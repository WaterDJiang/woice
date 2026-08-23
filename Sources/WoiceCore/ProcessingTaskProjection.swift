import Foundation

/// Deterministic presentation projection for durable processing tasks.
///
/// The array order is an implementation detail of persistence and must not
/// decide what the user sees as the current task. This projection is read-only
/// and never changes the persisted RecordingRecord or Job state.
public enum ProcessingTaskProjection {
  public static func activeTranscriptionTask(in tasks: [ProcessingTask]) -> ProcessingTask? {
    activeTask(
      in: tasks,
      where: { $0.kind == .transcription || $0.kind == .segmentTranscription })
  }

  public static func activeTask(in tasks: [ProcessingTask]) -> ProcessingTask? {
    activeTask(in: tasks, where: { _ in true })
  }

  public static func resumableTask(in tasks: [ProcessingTask]) -> ProcessingTask? {
    guard let task = activeTask(in: tasks) else {
      return nil
    }
    guard task.status == .queued || task.status == .failed || task.status == .interrupted else {
      return nil
    }
    return task
  }

  private static func activeTask(
    in tasks: [ProcessingTask],
    where predicate: (ProcessingTask) -> Bool
  ) -> ProcessingTask? {
    var selected: (offset: Int, task: ProcessingTask)?
    for (offset, task) in tasks.enumerated() where predicate(task) {
      guard let current = selected else {
        selected = (offset, task)
        continue
      }
      if isHigherPriority(task, offset: offset, than: current.task, offset: current.offset) {
        selected = (offset, task)
      }
    }
    return selected?.task
  }

  private static func isHigherPriority(
    _ candidate: ProcessingTask,
    offset candidateOffset: Int,
    than current: ProcessingTask,
    offset currentOffset: Int
  ) -> Bool {
    let candidateStatusRank = statusRank(candidate.status)
    let currentStatusRank = statusRank(current.status)
    if candidateStatusRank != currentStatusRank {
      return candidateStatusRank > currentStatusRank
    }
    if candidate.updatedAt != current.updatedAt {
      return candidate.updatedAt > current.updatedAt
    }
    let candidateKindRank = kindRank(candidate.kind)
    let currentKindRank = kindRank(current.kind)
    if candidateKindRank != currentKindRank {
      return candidateKindRank > currentKindRank
    }
    return candidateOffset > currentOffset
  }

  private static func statusRank(_ status: ProcessingTaskStatus) -> Int {
    switch status {
    case .running: 6
    case .awaitingAuthorization: 5
    case .waitingForModel: 4
    case .queued: 3
    case .failed, .interrupted, .cancelled: 2
    case .completed: 1
    }
  }

  private static func kindRank(_ kind: ProcessingTaskKind) -> Int {
    switch kind {
    case .transcription: 3
    case .segmentTranscription: 2
    case .languageModel: 1
    }
  }
}
