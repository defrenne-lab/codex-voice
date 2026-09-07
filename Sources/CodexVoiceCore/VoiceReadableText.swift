import Foundation

/// Local, deterministic preparation shared by live speech, history and summaries.
/// It never sends conversation content to an external service.
public enum VoiceReadableText {
  public static func blocks(_ rawText: String) -> [String] {
    parsedBlocks(rawText).map(\.text)
  }

  public static func notificationSummary(_ text: String) -> String {
    let candidates = parsedBlocks(text).filter { $0.kind == .prose }.map(\.text)
    // Extract, do not invent a completion/result that the assistant did not say.
    let source =
      candidates.first(where: { $0.split(whereSeparator: \.isWhitespace).count >= 3 })
      ?? candidates.first ?? "Une réponse est disponible à l’écran."
    let sentence = source.components(separatedBy: ". ").first ?? source
    let words = sentence.split(whereSeparator: \.isWhitespace)
    var selected: [Substring] = []
    var length = 0
    for word in words.prefix(30) {
      guard length + word.count + 1 <= 180 else { break }
      selected.append(word)
      length += word.count + 1
    }
    guard !selected.isEmpty else { return "Une réponse est disponible à l’écran." }
    let result = selected.joined(separator: " ")
    return selected.count < words.count ? result + "…" : result
  }

  public static func shortTitle(_ title: String?) -> String {
    let title = clean(String((title ?? "Conversation Codex").prefix(512)))
    let result = title.split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ")
    return result.isEmpty ? "Conversation Codex" : String(result.prefix(80))
  }

  private enum BlockKind { case prose, technical }

  private struct ParsedBlock {
    let text: String
    let kind: BlockKind
  }

  private static func parsedBlocks(_ rawText: String) -> [ParsedBlock] {
    let text = String(rawText.prefix(65_536)).replacingOccurrences(of: "\r\n", with: "\n")
    var result: [ParsedBlock] = []
    var paragraph: [String] = []
    var fence: Character?
    func flush() {
      let block = clean(paragraph.joined(separator: " "))
      if !block.isEmpty { result.append(ParsedBlock(text: block, kind: .prose)) }
      paragraph.removeAll(keepingCapacity: true)
    }
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        flush()
        if fence == nil {
          fence = trimmed.first
        } else if fence == trimmed.first {
          fence = nil
        }
        continue
      }
      if fence != nil {
        let codeLine = clean(trimmed)
        if !codeLine.isEmpty { result.append(ParsedBlock(text: codeLine, kind: .technical)) }
        continue
      }
      if let cells = tableCells(from: trimmed) {
        flush()
        if !cells.allSatisfy(isTableSeparator) {
          result.append(ParsedBlock(text: cells.joined(separator: " : "), kind: .technical))
        }
        continue
      }
      if trimmed.isEmpty { flush() } else { paragraph.append(trimmed) }
    }
    flush()
    return Array(result.prefix(128))
  }

  private static func clean(_ text: String) -> String {
    text
      .replacingOccurrences(
        of: #"!?\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression
      )
      .replacingOccurrences(of: #"https?://\S+"#, with: "lien", options: .regularExpression)
      .replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"^\s*(?:[-*+] |\d+[.)] )"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: "**", with: "")
      .replacingOccurrences(of: "__", with: "")
      .replacingOccurrences(of: "`", with: "")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func tableCells(from line: String) -> [String]? {
    guard line.contains("|") else { return nil }
    var cells = line.split(separator: "|", omittingEmptySubsequences: false).map {
      clean(String($0))
    }
    if line.hasPrefix("|") { cells.removeFirst() }
    if line.hasSuffix("|") { cells.removeLast() }
    guard cells.count >= 2, cells.contains(where: { !$0.isEmpty }) else { return nil }
    return cells
  }

  private static func isTableSeparator(_ cell: String) -> Bool {
    let normalized = cell.replacingOccurrences(of: ":", with: "")
      .trimmingCharacters(in: .whitespaces)
    return normalized.count >= 3 && normalized.allSatisfy { $0 == "-" }
  }
}
