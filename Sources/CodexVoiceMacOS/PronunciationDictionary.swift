import CodexVoiceCore
import Foundation

public enum PronunciationDictionaryError: LocalizedError {
  case invalidFormat
  case unreadableFile

  public var errorDescription: String? {
    switch self {
    case .invalidFormat:
      return "Le dictionnaire doit contenir l’en-tête source,replacement."
    case .unreadableFile:
      return "Le dictionnaire de prononciation ne peut pas être lu."
    }
  }
}

public struct PronunciationDictionary: VoicePronunciationDictionaryManaging {
  public static let fileName = "pronunciations.csv"
  public static let environmentKey = "CODEX_VOICE_PRONUNCIATION_FILE"

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var userFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Codex Voice 3", isDirectory: true)
      .appendingPathComponent(fileName)
  }

  public static var legacyUserFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Codex Voice 2", isDirectory: true)
      .appendingPathComponent(fileName)
  }

  public static func current(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> PronunciationDictionary
  {
    if let override = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      return PronunciationDictionary(fileURL: URL(fileURLWithPath: override).standardizedFileURL)
    }
    return PronunciationDictionary(fileURL: ensureUserFileExists())
  }

  @discardableResult
  public static func ensureUserFileExists() -> URL {
    let destination = userFileURL
    guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }

    try? FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: legacyUserFileURL.path) {
      try? FileManager.default.copyItem(at: legacyUserFileURL, to: destination)
    } else {
      try? "source,replacement\n".write(to: destination, atomically: true, encoding: .utf8)
    }
    return destination
  }

  public func applying(to text: String) -> String {
    var output = text
    for (word, replacement) in entries().sorted(by: { $0.key.count > $1.key.count }) {
      output = Self.replaceWholeWord(word, with: replacement, in: output)
    }
    return output
  }

  public func loadContent() throws -> String {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      throw PronunciationDictionaryError.unreadableFile
    }
    return content
  }

  public func replaceContent(_ content: String) throws {
    try Self.validate(content)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  public static func validate(_ content: String) throws {
    guard content.utf8.count <= VoiceControlProtocol.maximumPronunciationDictionaryBytes,
      content.components(separatedBy: .newlines).contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          == "source,replacement"
      })
    else {
      throw PronunciationDictionaryError.invalidFormat
    }
  }

  private func entries() -> [String: String] {
    guard let content = try? loadContent() else { return [:] }
    var entries: [String: String] = [:]
    for line in content.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
      let cells = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
      guard cells.count == 2 else { continue }

      let source = cells[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let replacement = cells[1].trimmingCharacters(in: .whitespacesAndNewlines)
      guard source != "source", !source.isEmpty, !replacement.isEmpty else { continue }
      entries[source] = replacement
    }
    return entries
  }

  private static func replaceWholeWord(
    _ word: String,
    with replacement: String,
    in text: String
  ) -> String {
    let escapedWord = NSRegularExpression.escapedPattern(for: word)
    let pattern = "(?<![\\p{L}\\p{N}_])\(escapedWord)(?![\\p{L}\\p{N}_])"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return text
    }

    var output = text
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, range: range).reversed() {
      guard let matchRange = Range(match.range, in: output) else { continue }
      let matchedWord = String(output[matchRange])
      output.replaceSubrange(matchRange, with: replacement.matchingCapitalization(of: matchedWord))
    }
    return output
  }
}

private extension String {
  func matchingCapitalization(of source: String) -> String {
    guard source.first?.isUppercase == true, let replacementFirst = first else { return self }
    return replacementFirst.uppercased() + dropFirst()
  }
}
