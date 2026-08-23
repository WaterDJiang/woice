import Foundation
import Testing
import WoiceCore

@Test("本机 ASR 预设只包含 loopback OpenAI-compatible 起点")
func localASRServicePresetsAreUniqueAndSafe() throws {
  let presets = ASRServicePreset.builtIns
  #expect(presets.count == 4)
  #expect(Set(presets.map(\.id)).count == presets.count)
  for preset in presets {
    #expect(preset.isSafeLocalEndpoint)
    #expect(ASRServiceDiscoveryPolicy.allows(preset.endpoint))
    #expect(URL(string: preset.endpoint)?.user == nil)
    #expect(URL(string: preset.endpoint)?.password == nil)
    #expect(URL(string: preset.endpoint)?.query == nil)
    #expect(URL(string: preset.endpoint)?.fragment == nil)
    #expect(!preset.model.isEmpty)
    #expect(preset.description.contains("OpenAI-compatible"))
  }
}

@Test("自定义公网或带凭据预设不会被标记为安全")
func customASRServicePresetFailsClosed() {
  let publicPreset = ASRServicePreset(
    id: "public", displayName: "公网", description: "OpenAI-compatible",
    endpoint:
      "https://user:password@example.com/v1?token=secret", model: "whisper-1")
  #expect(!publicPreset.isSafeLocalEndpoint)
  #expect(!ASRServiceDiscoveryPolicy.allows(publicPreset.endpoint))
}

@Test("套用预设只修改 ASR 草稿字段并保留密钥和其他设置")
func applyingPresetPreservesIndependentSettings() {
  var settings = AppSettings.default
  settings.asrAPIKey = "existing-asr-key"
  settings.llmEndpoint = "http://127.0.0.1:9000/v1"
  settings.llmAPIKey = "existing-llm-key"
  settings.language = "en"
  let updated = ASRServicePreset.builtIns[0].applying(to: settings)

  #expect(updated.asrProviderSelection == .external)
  #expect(updated.asrEndpoint == ASRServicePreset.builtIns[0].endpoint)
  #expect(updated.asrModel == ASRServicePreset.builtIns[0].model)
  #expect(updated.asrAPIKey == "existing-asr-key")
  #expect(updated.llmEndpoint == "http://127.0.0.1:9000/v1")
  #expect(updated.llmAPIKey == "existing-llm-key")
  #expect(updated.language == "en")
}
