import Foundation
import Testing
import WoiceCore

struct ProcessingTaskProjectionTests {
  @Test("活动转写任务优先于数组末尾的排队片段")
  func runningMainTaskWinsOverQueuedSegment() {
    let now = Date()
    let tasks = [
      ProcessingTask(
        kind: .transcription, idempotencyKey: "main", status: .running,
        updatedAt: now.addingTimeInterval(-10)),
      ProcessingTask(
        kind: .segmentTranscription, idempotencyKey: "segment", status: .queued,
        updatedAt: now),
    ]

    #expect(ProcessingTaskProjection.activeTranscriptionTask(in: tasks)?.idempotencyKey == "main")
  }

  @Test("等待模型优先于更新的失败任务")
  func waitingModelWinsOverFailure() {
    let now = Date()
    let tasks = [
      ProcessingTask(
        kind: .transcription, idempotencyKey: "failed", status: .failed,
        updatedAt: now.addingTimeInterval(30)),
      ProcessingTask(
        kind: .transcription, idempotencyKey: "model", status: .waitingForModel,
        updatedAt: now),
    ]

    #expect(ProcessingTaskProjection.activeTranscriptionTask(in: tasks)?.idempotencyKey == "model")
  }

  @Test("任务列表在转写完成后可投影正在运行的 Markdown 任务")
  func allTaskProjectionIncludesLanguageModelWork() {
    let now = Date()
    let tasks = [
      ProcessingTask(
        kind: .transcription, idempotencyKey: "transcription", status: .completed,
        updatedAt: now),
      ProcessingTask(
        kind: .languageModel, idempotencyKey: "markdown", status: .running,
        updatedAt: now.addingTimeInterval(-5)),
    ]

    #expect(ProcessingTaskProjection.activeTask(in: tasks)?.idempotencyKey == "markdown")
  }

  @Test("运行中任务会隐藏旧失败任务的继续入口")
  func runningTaskSuppressesStaleResume() {
    let now = Date()
    let tasks = [
      ProcessingTask(
        kind: .transcription, idempotencyKey: "old-failure", status: .failed,
        updatedAt: now),
      ProcessingTask(
        kind: .transcription, idempotencyKey: "current", status: .running,
        updatedAt: now.addingTimeInterval(-1)),
    ]

    #expect(ProcessingTaskProjection.resumableTask(in: tasks) == nil)
  }

  @Test("活动排队任务仍显示为可继续")
  func queuedTaskRemainsResumable() {
    let task = ProcessingTask(
      kind: .transcription, idempotencyKey: "queued", status: .queued)

    #expect(ProcessingTaskProjection.resumableTask(in: [task])?.idempotencyKey == "queued")
  }
}
