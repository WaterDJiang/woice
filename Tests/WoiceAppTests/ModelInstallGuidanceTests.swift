import Testing

@testable import WoiceApp

@Test("模型下载卡覆盖三种模型的设备与质量取舍")
func modelInstallGuidanceCoversAllLocalModels() {
  let tiny = ModelInstallCardModel.whisperKit(.recommendedTiny).guidance
  #expect(tiny.resourceImpact == "低")
  #expect(tiny.qualityImpact == "基础")
  #expect(tiny.selectionHint.contains("响应速度"))

  let qwen = ModelInstallCardModel.qwen3ASR.guidance
  #expect(qwen.resourceImpact == "中")
  #expect(qwen.qualityImpact == "平衡（预览）")
  #expect(qwen.qualityDetail.contains("正式性能矩阵仍在收口"))

  let large = ModelInstallCardModel.whisperKit(.candidateLargeV3).guidance
  #expect(large.resourceImpact == "高")
  #expect(large.qualityImpact == "最高（已验证）")
  #expect(large.qualityDetail.contains("五类各 300 秒性能门禁"))
}

@Test("未知 WhisperKit 条目保守使用 Tiny 取舍说明")
func unknownWhisperKitEntryUsesConservativeGuidance() throws {
  let entry = WhisperKitModelCatalogEntry(
    packID: "com.woice.whisperkit.test",
    modelID: "test-model",
    displayName: "测试模型",
    modelFolderName: "test-model",
    modelRepository: "example/repository",
    modelRevision: "revision",
    tokenizerRepository: "example/tokenizer",
    tokenizerRevision: "tokenizer-revision",
    tokenizerFolderName: "tokenizer",
    estimatedBytes: 1_024)

  #expect(ModelInstallCardModel.whisperKit(entry).guidance == .tiny)
}
