import Foundation

/// Local, deterministic preparation shared by live speech, history and summaries.
/// It never sends conversation content to an external service.
public enum VoiceReadableText {
  public static func blocks(_ rawText: String) -> [String] {
    let text = String(rawText.prefix(65_536)).replacingOccurrences(of: "\r\n", with: "\n")
    var result: [String] = []
    var paragraph: [String] = []
    var fence: Character?
    var inTable = false
    func flush() {
      let block = clean(paragraph.joined(separator: " "))
      if !block.isEmpty { result.append(block) }
      paragraph.removeAll(keepingCapacity: true)
    }
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        flush()
        if fence == nil {
          fence = trimmed.first
          result.append("Bloc de code disponible à l’écran.")
        } else if fence == trimmed.first {
          fence = nil
        }
        continue
      }
      guard fence == nil else { continue }
      if trimmed.hasPrefix("|") && trimmed.dropFirst().contains("|") {
        flush()
        if !inTable { result.append("Tableau disponible à l’écran.") }
        inTable = true
        continue
      }
      inTable = false
      if trimmed.isEmpty { flush() } else { paragraph.append(trimmed) }
    }
    flush()
    return Array(result.prefix(128))
  }

  public static func notificationSummary(_ text: String) -> String {
    let candidates = blocks(text).filter {
      $0 != "Bloc de code disponible à l’écran." && $0 != "Tableau disponible à l’écran."
    }
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
}
