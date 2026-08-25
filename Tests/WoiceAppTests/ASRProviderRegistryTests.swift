import Testing
import WoiceCore

@Test("ASR Registry 注册、健康更新和快照保持稳定")
func asrProviderRegistryPublishesTrustedDescriptors() async throws {
  let registry = ASRProviderRegistry()
  let initial = await registry.snapshot()
  #expect(
    initial.map(\.providerID) == [
      "com.apple.speech.on-device",
      "com.woice.openai-compatible-asr",
      "com.woice.qwen3-asr",
      "com.woice.whisperkit",
    ])

  try await registry.updateHealth(
    providerID: "com.woice.whisperkit", health: .ready)
  let whisper = try #require(await registry.descriptor(for: "com.woice.whisperkit"))
  #expect(whisper.health == .ready)
  #expect(whisper.supports(.timestamps))
}

@Test("ASR Registry 按统一配置选择本机或外部 Provider，不加载模型")
func asrProviderRegistryResolvesConfiguration() async throws {
  let registry = ASRProviderRegistry()
  let local = try await registry.resolve(
    configuration: ASRProviderConfiguration(selection: .onDevice), localModelAvailable: true)
  #expect(local.providerID == "com.woice.whisperkit")
  #expect(local.dataLocation == .onDevice)
  #expect(local.health == .ready)

  let external = try await registry.resolve(
    configuration: ASRProviderConfiguration(
      selection: .external, endpoint: "http://127.0.0.1:9000/v1", modelID: "whisper"),
    localModelAvailable: true)
  #expect(external.providerID == "com.woice.openai-compatible-asr")
  #expect(external.health == .ready)
}

@Test("ASR Registry 拒绝重复注册和不支持的能力")
func asrProviderRegistryFailsClosed() async throws {
  let registry = ASRProviderRegistry()
  let duplicate = ASRProviderDescriptor.builtIns[0]
  await #expect(throws: ASRProviderRegistryError.duplicateProvider(duplicate.providerID)) {
    try await registry.register(duplicate)
  }

  let streamingOnly = ASRProviderDescriptor(
    providerID: "com.woice.whisperkit",
    displayName: "Fixture",
    transport: .controlledProcess,
    dataLocation: .onDevice,
    capabilities: [.streaming],
    health: .ready)
  let capabilityRegistry = ASRProviderRegistry(descriptors: [streamingOnly])
  await #expect(
    throws: ASRProviderRegistryError.capabilityUnavailable(
      streamingOnly.providerID, .transcription)
  ) {
    try await capabilityRegistry.resolve(
      configuration: ASRProviderConfiguration(selection: .onDevice),
      localModelAvailable: true)
  }
}
