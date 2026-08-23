import CryptoKit
import Darwin
@preconcurrency import Foundation
import WoiceCore

enum ControlledCLIRunnerError: LocalizedError, Equatable, Sendable {
  case rejectedTrust
  case signatureVerificationFailed
  case executableMissing
  case invalidEnvironment
  case timedOut
  case cancelled
  case outputLimitExceeded
  case nonZeroExit(Int32, String)

  var errorDescription: String? {
    switch self {
    case .rejectedTrust: return "Agent CLI 信任状态不允许启动。"
    case .signatureVerificationFailed: return "Agent CLI 代码签名验证失败，已拒绝启动。"
    case .executableMissing: return "Agent CLI 可执行文件不存在或不可执行。"
    case .invalidEnvironment: return "Agent CLI 请求了不在白名单中的环境变量。"
    case .timedOut: return "Agent CLI 处理超时，进程组已终止。"
    case .cancelled: return "Agent CLI 任务已取消，进程组已终止。"
    case .outputLimitExceeded: return "Agent CLI 输出超过安全上限，进程组已终止。"
    case .nonZeroExit(let code, let stderr):
      let prefix = "Agent CLI 以状态码 \(code) 退出。"
      return stderr.isEmpty ? prefix : prefix + "：" + stderr
    }
  }
}

struct ControlledCLIRunConfiguration: Sendable {
  var timeout: TimeInterval?
  var maxOutputBytes = 1_048_576
  var environment: [String: String] = [:]
  var allowUnsigned = false
  var verifySignature = true
  var expectedTeamIdentifier: String?

  init(
    timeout: TimeInterval? = nil,
    maxOutputBytes: Int = 1_048_576,
    environment: [String: String] = [:],
    allowUnsigned: Bool = false,
    verifySignature: Bool = true,
    expectedTeamIdentifier: String? = nil
  ) {
    self.timeout = timeout
    self.maxOutputBytes = maxOutputBytes
    self.environment = environment
    self.allowUnsigned = allowUnsigned
    self.verifySignature = verifySignature
    self.expectedTeamIdentifier = expectedTeamIdentifier
  }
}

final class ControlledCLICancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
}

struct ControlledCLIRunResult: Equatable, Sendable {
  let stdout: Data
  let stderr: String
  let terminationStatus: Int32
  let outputFileData: Data?
}

/// Starts only a validated, fixed CLI manifest. The runner owns temporary
/// diagnostics, while ContextPackageBuilder owns the immutable input bundle.
final class ControlledCLIRunner: @unchecked Sendable {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func run(
    manifest: AgentCLIAdapterManifest,
    package: ContextPackageBundle,
    configuration: ControlledCLIRunConfiguration = .init(),
    cancellation: ControlledCLICancellation = ControlledCLICancellation()
  ) throws -> ControlledCLIRunResult {
    _ = try manifest.validated()
    try validateLaunch(manifest: manifest, configuration: configuration)
    let input = try inputData(manifest: manifest, package: package)
    return try execute(
      manifest: manifest,
      arguments: nil,
      package: package,
      input: input,
      configuration: configuration,
      cancellation: cancellation,
      currentDirectoryURL: workingDirectory(manifest: manifest, package: package))
  }

  func probeVersion(
    manifest: AgentCLIAdapterManifest,
    configuration: ControlledCLIRunConfiguration = .init(),
    cancellation: ControlledCLICancellation = ControlledCLICancellation()
  ) throws -> String {
    _ = try manifest.validated()
    try validateLaunch(manifest: manifest, configuration: configuration)
    let result = try execute(
      manifest: manifest,
      arguments: manifest.versionProbeArguments,
      package: nil,
      input: nil,
      configuration: ControlledCLIRunConfiguration(
        timeout: min(configuration.timeout ?? 15, 15),
        maxOutputBytes: min(configuration.maxOutputBytes, 16 * 1024),
        environment: configuration.environment,
        allowUnsigned: configuration.allowUnsigned,
        verifySignature: configuration.verifySignature,
        expectedTeamIdentifier: configuration.expectedTeamIdentifier),
      cancellation: cancellation,
      currentDirectoryURL: nil)
    return String(decoding: result.stdout, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func validateLaunch(
    manifest: AgentCLIAdapterManifest, configuration: ControlledCLIRunConfiguration
  ) throws {
    guard manifest.trust != .rejected, manifest.trust != .unknown,
      configuration.allowUnsigned || manifest.trust != .unsigned
    else { throw ControlledCLIRunnerError.rejectedTrust }
    guard fileManager.isExecutableFile(atPath: manifest.executablePath) else {
      throw ControlledCLIRunnerError.executableMissing
    }
    guard configuration.environment.keys.allSatisfy(manifest.allowedEnvironmentKeys.contains) else {
      throw ControlledCLIRunnerError.invalidEnvironment
    }
    if configuration.verifySignature, manifest.trust != .unsigned {
      let providerManifest = ProcessProviderManifest(
        id: manifest.id,
        displayName: manifest.displayName,
        version: manifest.version,
        kind: .languageModel,
        executablePath: manifest.executablePath,
        source: manifest.source,
        trust: manifest.trust)
      guard
        ProviderTrustVerifier.verify(
          manifest: providerManifest, expectedTeamIdentifier: configuration.expectedTeamIdentifier
        ).isTrusted
      else {
        throw ControlledCLIRunnerError.signatureVerificationFailed
      }
    }
  }

  private func inputData(
    manifest: AgentCLIAdapterManifest, package: ContextPackageBundle
  ) throws -> Data? {
    switch manifest.inputTransport {
    case .contextPackageFile:
      return nil
    case .instructionFile:
      return Data(package.package.instruction.utf8)
    case .stdinJSON:
      struct Request: Codable {
        let packageID: UUID
        let contextFile: String
        let instruction: String
      }
      return try JSONEncoder.woice.encode(
        Request(
          packageID: package.package.id,
          contextFile: package.contextURL.path,
          instruction: package.package.instruction))
    }
  }

  private func workingDirectory(
    manifest: AgentCLIAdapterManifest, package: ContextPackageBundle
  ) -> URL? {
    switch manifest.workingDirectoryPolicy {
    case .readOnly: package.directoryURL
    case .none, .readWrite: nil
    }
  }

  private func execute(
    manifest: AgentCLIAdapterManifest,
    arguments: [String]?,
    package: ContextPackageBundle?,
    input: Data?,
    configuration: ControlledCLIRunConfiguration,
    cancellation: ControlledCLICancellation,
    currentDirectoryURL: URL?
  ) throws -> ControlledCLIRunResult {
    let runDirectory = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-cli-run-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: runDirectory) }
    let stdoutURL = runDirectory.appendingPathComponent("stdout.bin")
    let stderrURL = runDirectory.appendingPathComponent("stderr.log")
    let resultURL = package.map { _ in runDirectory.appendingPathComponent("result.out") }
    fileManager.createFile(atPath: stdoutURL.path, contents: nil)
    fileManager.createFile(atPath: stderrURL.path, contents: nil)
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    defer {
      try? stdoutHandle.close()
      try? stderrHandle.close()
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: manifest.executablePath)
    let instructionURL = runDirectory.appendingPathComponent("instruction.txt")
    if let package {
      try Data(package.package.instruction.utf8).write(to: instructionURL, options: .atomic)
      try fileManager.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o400))], ofItemAtPath: instructionURL.path)
    }
    process.arguments =
      arguments
      ?? manifest.argumentTemplate.map { argument in
        argument
          .replacingOccurrences(of: "{context_package}", with: package?.directoryURL.path ?? "")
          .replacingOccurrences(of: "{context_file}", with: package?.contextURL.path ?? "")
          .replacingOccurrences(of: "{instruction_file}", with: instructionURL.path)
          .replacingOccurrences(of: "{result_file}", with: resultURL?.path ?? "")
          .replacingOccurrences(of: "{instruction}", with: package?.package.instruction ?? "")
      }
    process.currentDirectoryURL = currentDirectoryURL ?? runDirectory
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    // Keep the process environment minimal, but preserve the user's HOME so
    // an explicitly selected CLI can read its own login/session state. Woice
    // never reads or copies that state. Homebrew-installed script CLIs (such
    // as Codex) need their fixed bin directory on PATH to resolve node.
    let baseEnvironment = [
      "HOME": fileManager.homeDirectoryForCurrentUser.path,
      "PATH": runtimePath(for: manifest),
    ]
    process.environment = baseEnvironment.merging(configuration.environment) { _, value in value }
    if let input {
      let inputPipe = Pipe()
      process.standardInput = inputPipe
      try process.run()
      inputPipe.fileHandleForWriting.write(input)
      inputPipe.fileHandleForWriting.closeFile()
    } else {
      process.standardInput = FileHandle.nullDevice
      try process.run()
    }

    let processID = process.processIdentifier
    let didCreateProcessGroup = processID > 0 && setpgid(processID, processID) == 0
    let timeout = max(1, configuration.timeout ?? manifest.timeout)
    let deadline = DispatchTime.now() + timeout
    while process.isRunning {
      if cancellation.isCancelled {
        terminate(process, processID: processID, processGroup: didCreateProcessGroup)
        throw ControlledCLIRunnerError.cancelled
      }
      if DispatchTime.now() >= deadline {
        terminate(process, processID: processID, processGroup: didCreateProcessGroup)
        throw ControlledCLIRunnerError.timedOut
      }
      if outputSize(stdoutURL) > Int64(max(1, configuration.maxOutputBytes)) {
        terminate(process, processID: processID, processGroup: didCreateProcessGroup)
        throw ControlledCLIRunnerError.outputLimitExceeded
      }
      if let resultURL, outputSize(resultURL) > Int64(max(1, configuration.maxOutputBytes)) {
        terminate(process, processID: processID, processGroup: didCreateProcessGroup)
        throw ControlledCLIRunnerError.outputLimitExceeded
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    process.waitUntilExit()
    try? stdoutHandle.synchronize()
    try? stderrHandle.synchronize()
    let stdoutByteCount = outputSize(stdoutURL)
    guard stdoutByteCount <= Int64(max(1, configuration.maxOutputBytes)) else {
      throw ControlledCLIRunnerError.outputLimitExceeded
    }
    if let resultURL,
      self.outputSize(resultURL) > Int64(max(1, configuration.maxOutputBytes))
    {
      throw ControlledCLIRunnerError.outputLimitExceeded
    }
    let stdout = try Data(contentsOf: stdoutURL)
    let stderrData = try Data(contentsOf: stderrURL)
    let stderr = String(data: stderrData.prefix(16 * 1024), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw ControlledCLIRunnerError.nonZeroExit(process.terminationStatus, stderr)
    }
    return ControlledCLIRunResult(
      stdout: stdout,
      stderr: stderr,
      terminationStatus: process.terminationStatus,
      outputFileData: resultURL.flatMap { try? Data(contentsOf: $0) }
    )
  }

  private func terminate(_ process: Process, processID: pid_t, processGroup: Bool) {
    guard process.isRunning else { return }
    if processGroup, processID > 0 {
      _ = kill(-processID, SIGTERM)
    } else {
      process.terminate()
    }
    let deadline = DispatchTime.now() + 0.2
    while process.isRunning, DispatchTime.now() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning {
      if processGroup, processID > 0 { _ = kill(-processID, SIGKILL) } else { process.terminate() }
      process.waitUntilExit()
    }
  }

  private func outputSize(_ url: URL) -> Int64 {
    (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func runtimePath(for manifest: AgentCLIAdapterManifest) -> String {
    let executableDirectory = URL(fileURLWithPath: manifest.executablePath)
      .deletingLastPathComponent()
      .standardizedFileURL
      .path
    let trustedUserToolDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    guard trustedUserToolDirectories.contains(executableDirectory) else {
      return "/usr/bin:/bin"
    }
    return ([executableDirectory, "/usr/bin", "/bin"]).joined(separator: ":")
  }
}
