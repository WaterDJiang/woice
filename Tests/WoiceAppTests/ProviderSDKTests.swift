import Foundation
import Testing
import WoiceCore

#if !WOICE_APP_STORE
  @testable import WoiceApp

  struct ProviderSDKTests {
    @Test("合法 Provider Manifest 可验证并保持来源与信任状态")
    func validManifestRoundTrips() throws {
      let manifest = ProcessProviderManifest(
        id: "com.example.woice.asr",
        displayName: "Example ASR",
        version: "1.2.3",
        kind: .asr,
        executablePath: "/Library/Application Support/Woice/Providers/example-asr",
        capabilities: ["transcribe", "timestamps"],
        source: .userInstalled,
        trust: .signatureVerified
      )
      #expect(try manifest.validated() == manifest)
      let data = try JSONEncoder().encode(manifest)
      let decoded = try JSONDecoder().decode(ProcessProviderManifest.self, from: data)
      #expect(decoded == manifest)
    }

    @Test("Provider Manifest 拒绝相对路径和路径穿越")
    func manifestRejectsUnsafePaths() {
      let relative = ProcessProviderManifest(
        id: "example.asr",
        displayName: "ASR",
        version: "1.0.0",
        kind: .asr,
        executablePath: "Providers/asr",
        source: .external,
        trust: .unknown
      )
      #expect(throws: ProcessProviderManifestError.relativeExecutablePath) {
        try relative.validated()
      }
      let traversal = ProcessProviderManifest(
        id: "example.asr",
        displayName: "ASR",
        version: "1.0.0",
        kind: .asr,
        executablePath: "/tmp/../Providers/asr",
        source: .external,
        trust: .unknown
      )
      #expect(throws: ProcessProviderManifestError.executablePathTraversal) {
        try traversal.validated()
      }
    }

    @Test("Provider Manifest 拒绝非法标识、版本和信任组合")
    func manifestRejectsInvalidMetadata() {
      let invalidID = ProcessProviderManifest(
        id: "bad id",
        displayName: "ASR",
        version: "1.0.0",
        kind: .asr,
        executablePath: "/tmp/asr",
        source: .external,
        trust: .unknown
      )
      #expect(throws: ProcessProviderManifestError.invalidIdentifier) {
        try invalidID.validated()
      }
      let invalidVersion = ProcessProviderManifest(
        id: "example.asr",
        displayName: "ASR",
        version: "1.0",
        kind: .asr,
        executablePath: "/tmp/asr",
        source: .external,
        trust: .unknown
      )
      #expect(throws: ProcessProviderManifestError.invalidVersion) {
        try invalidVersion.validated()
      }
      let mismatchedTrust = ProcessProviderManifest(
        id: "example.asr",
        displayName: "ASR",
        version: "1.0.0",
        kind: .asr,
        executablePath: "/tmp/asr",
        source: .bundled,
        trust: .unsigned
      )
      #expect(throws: ProcessProviderManifestError.invalidTrustState) {
        try mismatchedTrust.validated()
      }
    }

    @Test("受控 Provider Runner 使用固定环境完成 stdin/stdout 往返")
    func processRunnerRoundTripsData() throws {
      let manifest = ProcessProviderManifest(
        id: "com.example.echo",
        displayName: "Echo Provider",
        version: "1.0.0",
        kind: .languageModel,
        executablePath: "/bin/cat",
        source: .external,
        trust: .signatureVerified
      )
      let request = Data(#"{"ok":true}"#.utf8)
      let response = try ProcessProviderRunner().run(
        manifest: manifest,
        request: request,
        configuration: ProcessProviderRunnerConfiguration(timeout: 2, maxOutputBytes: 128)
      )
      #expect(response == request)
    }

    @Test("受控 Provider Runner 拒绝未授权信任状态和缺失文件")
    func processRunnerFailsClosed() {
      let unsigned = ProcessProviderManifest(
        id: "com.example.unsigned",
        displayName: "Unsigned",
        version: "1.0.0",
        kind: .tts,
        executablePath: "/bin/cat",
        source: .external,
        trust: .unsigned
      )
      #expect(throws: ProcessProviderRunnerError.rejectedTrust) {
        try ProcessProviderRunner().run(manifest: unsigned, request: Data())
      }
      let missing = ProcessProviderManifest(
        id: "com.example.missing",
        displayName: "Missing",
        version: "1.0.0",
        kind: .asr,
        executablePath: "/tmp/woice-provider-does-not-exist",
        source: .external,
        trust: .signatureVerified
      )
      #expect(throws: ProcessProviderRunnerError.executableMissing) {
        try ProcessProviderRunner().run(manifest: missing, request: Data())
      }

      let slow = ProcessProviderManifest(
        id: "com.example.slow",
        displayName: "Slow",
        version: "1.0.0",
        kind: .tts,
        executablePath: "/bin/sleep",
        arguments: ["2"],
        source: .external,
        trust: .signatureVerified
      )
      #expect(throws: ProcessProviderRunnerError.timedOut) {
        try ProcessProviderRunner().run(
          manifest: slow,
          request: Data(),
          configuration: ProcessProviderRunnerConfiguration(timeout: 0.1)
        )
      }

      let echo = ProcessProviderManifest(
        id: "com.example.limit",
        displayName: "Limit",
        version: "1.0.0",
        kind: .languageModel,
        executablePath: "/bin/cat",
        source: .external,
        trust: .signatureVerified
      )
      #expect(throws: ProcessProviderRunnerError.outputLimitExceeded) {
        try ProcessProviderRunner().run(
          manifest: echo,
          request: Data(repeating: 65, count: 129),
          configuration: ProcessProviderRunnerConfiguration(timeout: 2, maxOutputBytes: 128)
        )
      }
    }

    @Test("Provider 代码签名验证拒绝未签名可执行文件")
    func providerTrustVerifierRejectsUnsignedExecutable() throws {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "woice-unsigned-provider-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: url) }
      try Data("#!/bin/sh\ncat\n".utf8).write(to: url)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
      let manifest = ProcessProviderManifest(
        id: "com.example.unsigned-fixture",
        displayName: "Unsigned Fixture",
        version: "1.0.0",
        kind: .languageModel,
        executablePath: url.path,
        source: .external,
        trust: .signatureVerified
      )
      let report = ProviderTrustVerifier.verify(manifest: manifest)
      #expect(report.state == .rejected)
      #expect(!report.isTrusted)
      #expect(throws: ProcessProviderRunnerError.signatureVerificationFailed) {
        try ProcessProviderRunner().run(manifest: manifest, request: Data())
      }
    }
  }
#endif
