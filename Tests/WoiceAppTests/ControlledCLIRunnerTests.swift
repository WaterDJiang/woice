import Foundation
import Testing
import WoiceCore

#if !WOICE_APP_STORE
  @testable import WoiceApp

  struct ControlledCLIRunnerTests {
    private func bundle() throws -> ContextPackageBundle {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "woice-cli-bundle-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let recordingID = UUID()
      let item = ContextPackageBuildItem(
        reference: ContextArtifactReference(
          artifactID: "recording:\(recordingID.uuidString):transcript",
          recordingID: recordingID,
          kind: .transcript),
        text: "这是给 CLI 的原文。")
      let package = try ContextPackageBuilder().build(
        items: [item], instruction: "提取待办", packageID: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000), rootURL: root)
      // The test owns the bundle root and can remove it after the runner returns.
      return package
    }

    private func unsignedManifest(
      executablePath: String, arguments: [String] = [], timeout: TimeInterval = 2
    ) -> AgentCLIAdapterManifest {
      AgentCLIAdapterManifest(
        id: "com.example.fixture",
        displayName: "Fixture CLI",
        version: "1.0.0",
        executablePath: executablePath,
        versionProbeArguments: ["--version"],
        argumentTemplate: arguments,
        inputTransport: .contextPackageFile,
        outputTransport: .text,
        workingDirectoryPolicy: .none,
        timeout: timeout,
        source: .external,
        trust: .unsigned)
    }

    @Test("Controlled CLI Runner 使用固定参数读取 Context Package")
    func runnerReadsContextPackageWithoutShell() throws {
      let bundle = try bundle()
      defer { try? FileManager.default.removeItem(at: bundle.directoryURL) }
      let manifest = unsignedManifest(executablePath: "/bin/cat", arguments: ["{context_file}"])
      let result = try ControlledCLIRunner().run(
        manifest: manifest,
        package: bundle,
        configuration: ControlledCLIRunConfiguration(
          maxOutputBytes: 64 * 1024, allowUnsigned: true, verifySignature: false))
      let output = String(decoding: result.stdout, as: UTF8.self)
      #expect(output.contains("schemaVersion"))
      #expect(output.contains(bundle.package.id.uuidString))
      #expect(result.terminationStatus == 0)
    }

    @Test("Controlled CLI Runner 版本探针和环境白名单 fail-closed")
    func runnerProbesVersionAndRejectsUnknownEnvironment() throws {
      let bundle = try bundle()
      defer { try? FileManager.default.removeItem(at: bundle.directoryURL) }
      let manifest = unsignedManifest(executablePath: "/bin/echo", arguments: ["{context_file}"])
      let version = try ControlledCLIRunner().probeVersion(
        manifest: manifest,
        configuration: ControlledCLIRunConfiguration(
          maxOutputBytes: 1024, allowUnsigned: true, verifySignature: false))
      #expect(version == "--version")
      #expect(throws: ControlledCLIRunnerError.invalidEnvironment) {
        try ControlledCLIRunner().run(
          manifest: manifest,
          package: bundle,
          configuration: ControlledCLIRunConfiguration(
            environment: ["SECRET": "should-not-pass"], allowUnsigned: true, verifySignature: false)
        )
      }
    }

    @Test("Controlled CLI Runner 超时、取消、非零退出和输出超限均不成功")
    func runnerFailureMatrix() async throws {
      let bundle = try bundle()
      defer { try? FileManager.default.removeItem(at: bundle.directoryURL) }
      let runner = ControlledCLIRunner()
      let sleepManifest = unsignedManifest(
        executablePath: "/bin/sleep", arguments: ["2"], timeout: 1)
      #expect(throws: ControlledCLIRunnerError.timedOut) {
        try runner.run(
          manifest: sleepManifest,
          package: bundle,
          configuration: ControlledCLIRunConfiguration(
            timeout: 0.1, allowUnsigned: true, verifySignature: false))
      }

      let cancellation = ControlledCLICancellation()
      let task = Task.detached {
        try runner.run(
          manifest: sleepManifest,
          package: bundle,
          configuration: ControlledCLIRunConfiguration(
            timeout: 2, allowUnsigned: true, verifySignature: false),
          cancellation: cancellation)
      }
      try await Task.sleep(for: .milliseconds(100))
      cancellation.cancel()
      do {
        _ = try await task.value
        Issue.record("取消后的 CLI 不应返回成功。")
      } catch let error as ControlledCLIRunnerError {
        #expect(error == .cancelled)
      }

      let failed = unsignedManifest(executablePath: "/usr/bin/false", arguments: [])
      #expect(throws: ControlledCLIRunnerError.nonZeroExit(1, "")) {
        try runner.run(
          manifest: failed,
          package: bundle,
          configuration: ControlledCLIRunConfiguration(
            allowUnsigned: true, verifySignature: false))
      }

      let output = unsignedManifest(
        executablePath: "/bin/echo", arguments: [String(repeating: "x", count: 256)])
      #expect(throws: ControlledCLIRunnerError.outputLimitExceeded) {
        try runner.run(
          manifest: output,
          package: bundle,
          configuration: ControlledCLIRunConfiguration(
            maxOutputBytes: 16, allowUnsigned: true, verifySignature: false))
      }
    }
  }
#endif
