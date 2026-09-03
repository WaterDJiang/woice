import Foundation
import Testing
import WoiceCore

@Test("识别语言选项把旧代码映射为可读名称并保留未知值")
func transcriptionLanguageOptionsPreserveLegacyCodes() {
  #expect(TranscriptionLanguageOption.forCode("") == .automatic)
  #expect(TranscriptionLanguageOption.forCode("zh").code == "zh")
  #expect(TranscriptionLanguageOption.forCode("zh-CN").displayName == "简体中文")
  #expect(TranscriptionLanguageOption.forCode("yue").displayName == "粤语")
  #expect(TranscriptionLanguageOption.forCode("Cantonese").code == "yue")
  #expect(TranscriptionLanguageOption.forCode("en-US").code == "en")

  let unknown = TranscriptionLanguageOption.forCode("x-private")
  #expect(unknown.displayName == "当前配置")
  #expect(unknown.code == "x-private")
  #expect(TranscriptionLanguageOption.pickerOptions(currentCode: "x-private").last == unknown)
  #expect(TranscriptionLanguageOption.providerLanguageCode(for: " en-US ") == "en-US")
  #expect(!TranscriptionLanguageOption.providerLanguageCode(for: "").isEmpty)
}

@Test("识别语言常用选项以自动检测作为首项且不重复未知项")
func transcriptionLanguageOptionsHaveStablePickerOrder() {
  let options = TranscriptionLanguageOption.pickerOptions(currentCode: "zh")
  #expect(options.first == .automatic)
  #expect(options.count == TranscriptionLanguageOption.common.count)
  #expect(Set(options).count == options.count)
}

@Test("新设置默认自动检测，旧设置缺失语言字段保持兼容")
func transcriptionLanguageDefaultAndLegacyDecode() throws {
  #expect(AppSettings.default.language.isEmpty)
  let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
  #expect(legacy.language == "zh")
}
