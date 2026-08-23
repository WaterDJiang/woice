import Foundation

public struct MarkdownNoteSections: Equatable, Sendable {
  public let summary: [String]
  public let todos: [String]
  public let hasTodoSection: Bool

  public init(summary: [String], todos: [String], hasTodoSection: Bool = false) {
    self.summary = summary
    self.todos = todos
    self.hasTodoSection = hasTodoSection
  }

  public var hasStructuredContent: Bool {
    !summary.isEmpty || !todos.isEmpty || hasTodoSection
  }
}

public enum MarkdownRenderer {
  public static func render(title: String, transcript: String, generatedMarkdown: String?) -> String
  {
    var sections = ["# \(title)", "## 原文", TranscriptTextNormalizer.normalize(transcript)]
    if let generatedMarkdown, !generatedMarkdown.isEmpty {
      sections.append("## AI 笔记")
      sections.append(generatedMarkdown)
    }
    return sections.joined(separator: "\n\n") + "\n"
  }

  /// Parses only the small, deterministic subset needed by the detail view.
  /// The original Markdown remains the durable source; this is a read-only UI
  /// projection and must never be used to rewrite the generated artifact.
  public static func sections(from markdown: String) -> MarkdownNoteSections {
    enum Bucket { case summary, todos }

    var bucket: Bucket = .summary
    var summary: [String] = []
    var todos: [String] = []
    var hasTodoSection = false
    for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }

      if line.first == "#" {
        let heading = line.drop { $0 == "#" || $0 == " " }
        let normalized = heading.lowercased()
        if containsAny(normalized, values: ["待办", "行动项", "todo", "action item", "follow-up"]) {
          bucket = .todos
          hasTodoSection = true
        } else if containsAny(normalized, values: ["摘要", "要点", "重点", "总结", "summary"]) {
          bucket = .summary
        }
        continue
      }

      guard var item = listItem(from: line) else { continue }
      item =
        item
        .replacingOccurrences(of: "[ ]", with: "")
        .replacingOccurrences(of: "[x]", with: "")
        .replacingOccurrences(of: "[X]", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let explicitTodo = containsAny(item.lowercased(), values: ["待办：", "待办:", "todo:", "todo："])
      if explicitTodo {
        bucket = .todos
        hasTodoSection = true
      }
      item = cleanTodoPrefix(item)
      guard !item.isEmpty else { continue }
      if case .todos = bucket, isNoTodo(item) { continue }

      switch bucket {
      case .summary:
        if explicitTodo { todos.append(item) } else { summary.append(item) }
      case .todos:
        todos.append(item)
      }
    }
    return MarkdownNoteSections(
      summary: summary, todos: todos, hasTodoSection: hasTodoSection)
  }

  private static func listItem(from line: String) -> String? {
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
      return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let dot = line.firstIndex(of: ".") else { return nil }
    let prefix = line[..<dot]
    guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
    return String(line[line.index(after: dot)...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func cleanTodoPrefix(_ value: String) -> String {
    var item = value.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["待办：", "待办:", "TODO：", "TODO:", "todo：", "todo:"] {
      if item.hasPrefix(prefix) {
        item = String(item.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        break
      }
    }
    return item
  }

  private static func containsAny(_ value: String, values: [String]) -> Bool {
    values.contains(where: value.contains)
  }

  private static func isNoTodo(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["暂无", "暂无待办", "无", "无待办", "none", "n/a"].contains(normalized)
  }
}
