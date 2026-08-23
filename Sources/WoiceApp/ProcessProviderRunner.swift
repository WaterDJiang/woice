@preconcurrency import Foundation
import WoiceCore

enum ProcessProviderRunnerError: LocalizedError, Equatable {
  case rejectedTrust
  case signatureVerificationFailed
  case executableMissing
  case timedOut
  case outputLimitExceeded
  case nonZeroExit(Int32, String)

  var errorDescription: String? {
    switch self {
    case .rejectedTrust: return "Provider 信任状态不允许启动。"
    case .signatureVerificationFailed: return "Provider 代码签名验证失败，已拒绝启动。"
    case .executableMissing: return "Provider 可执行文件不存在或不可执行。"
    case .timedOut: return "Provider 处理超时，进程已终止。"
    case .outputLimitExceeded: return "Provider 输出超过安全上限，进程已终止。"
    case .nonZeroExit(let code, let stderr):
      let prefix = "Provider 以状态码 " + String(code) + " 退出。"
      return stderr.isEmpty ? prefix : prefix + "：" + stderr
    }
  }
}

struct ProcessProviderRunnerConfiguration: Sendable {
  var timeout: TimeInterval = 10
  var maxOutputBytes = 1_048_576
  var allowUnsigned = false
  var verifySignature = true
  var expectedTeamIdentifier: String?
}

/// 受控进程调用器。调用方应在 Runtime 的后台执行上下文运行，不能阻塞 UI 主线程。
final class ProcessProviderRunner: @unchecked Sendable {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func run(
    manifest: ProcessProviderManifest,
    request: Data,
    configuration: ProcessProviderRunnerConfiguration = .init()
  ) throws -> Data {
    _ = try manifest.validated()
    guard manifest.trust != .rejected, manifest.trust != .unknown,
      configuration.allowUnsigned || manifest.trust != .unsigned
    else { throw ProcessProviderRunnerError.rejectedTrust }

    let executableURL = URL(fileURLWithPath: manifest.executablePath)
    guard fileManager.isExecutableFile(atPath: executableURL.path) else {
      throw ProcessProviderRunnerError.executableMissing
    }
    if configuration.verifySignature, manifest.trust != .unsigned {
      let report = ProviderTrustVerifier.verify(
        manifest: manifest, expectedTeamIdentifier: configuration.expectedTeamIdentifier)
      guard report.isTrusted else {
        throw ProcessProviderRunnerError.signatureVerificationFailed
      }
    }
    let workDirectory = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-provider-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: workDirectory) }

    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = executableURL
    process.arguments = manifest.arguments
    process.currentDirectoryURL = workDirectory
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    process.environment = ["PATH": "/usr/bin:/bin"]

    try process.run()
    input.fileHandleForWriting.write(request)
    input.fileHandleForWriting.closeFile()

    let timeout = max(0.1, configuration.timeout)
    let deadline = DispatchTime.now() + timeout
    while process.isRunning, DispatchTime.now() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
      throw ProcessProviderRunnerError.timedOut
    }

    let response = output.fileHandleForReading.readDataToEndOfFile()
    guard response.count <= max(1, configuration.maxOutputBytes) else {
      throw ProcessProviderRunnerError.outputLimitExceeded
    }
    let stderrData = error.fileHandleForReading.readDataToEndOfFile()
    let stderr = String(data: stderrData.prefix(4_096), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw ProcessProviderRunnerError.nonZeroExit(process.terminationStatus, stderr)
    }
    return response
  }
}
