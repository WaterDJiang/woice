import Foundation
import Testing
import WoiceCore

@Test("录音标题从原文生成且保持短")
func titleUsesTranscript() {
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "test.wav",
    duration: 3,
    transcript: "这是一个用于验证 Woice 历史记录标题的固定测试原文内容",
    generatedMarkdown: nil,
    processingError: nil
  )
  #expect(record.title == "这是一个用于验证 Woice 历史记录标题的固定测试原文内容")
}

@Test("空转写使用未命名录音")
func emptyTranscriptUsesFallbackTitle() {
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "test.wav",
    duration: 3,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil
  )
  #expect(record.title == "未命名录音")
}

@Test("Markdown 笔记解析要点和待办并保留顺序")
func markdownSectionsParseSummaryAndTodos() {
  let note = MarkdownRenderer.sections(
    from: """
      # 会议笔记

      ## 要点
      - 确认录音流程
      1. 保留原始 WAV

      ## 待办
      - [ ] 补充真实设备验收
      """
  )
  #expect(note.summary == ["确认录音流程", "保留原始 WAV"])
  #expect(note.todos == ["补充真实设备验收"])
  #expect(note.hasTodoSection)
}

@Test("旧式 Markdown 待办前缀和暂无不会伪造任务")
func markdownSectionsHandleLegacyTodoPrefix() {
  let note = MarkdownRenderer.sections(
    from: """
      - 讨论 API 配置
      - 待办：补充回归
      - 待办：暂无
      """
  )
  #expect(note.summary == ["讨论 API 配置"])
  #expect(note.todos == ["补充回归"])
  #expect(note.hasTodoSection)
}
