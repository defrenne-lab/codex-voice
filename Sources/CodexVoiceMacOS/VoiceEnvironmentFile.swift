import Foundation

public enum VoiceEnvironmentFileError: LocalizedError, Equatable {
  case fileTooLarge
  case invalidLine(Int)

  public var errorDescription: String? {
    switch self {
    case .fileTooLarge:
      return "Le fichier .env de Codex Voice est trop volumineux."
    case .invalidLine(let line):
      return "La ligne \(line) du fichier .env de Codex Voice est invalide."
    }
  }
}

public enum VoiceEnvironmentFile {
  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex-voice", isDirectory: true)
      .appendingPathComponent(".env", isDirectory: false)
  }

  public static func load(from url: URL = defaultURL) throws -> [String: String] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    guard data.count <= 64 * 1_024 else { throw VoiceEnvironmentFileError.fileTooLarge }
    guard let contents = String(data: data, encoding: .utf8) else {
      throw VoiceEnvironmentFileError.invalidLine(1)
    }

    var values: [String: String] = [:]
    for (offset, rawLine) in contents.split(
      omittingEmptySubsequences: false,
      whereSeparator: { $0.isNewline }
    ).enumerated() {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      if line.hasPrefix("export ") {
        line.removeFirst("export ".count)
        line = line.trimmingCharacters(in: .whitespaces)
      }
      guard let separator = line.firstIndex(of: "=") else {
        throw VoiceEnvironmentFileError.invalidLine(offset + 1)
      }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      var value = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)
      guard isValidKey(key) else {
        throw VoiceEnvironmentFileError.invalidLine(offset + 1)
      }
      if value.count >= 2,
        let first = value.first,
        let last = value.last,
        (first == "\"" && last == "\"") || (first == "'" && last == "'")
      {
        value.removeFirst()
        value.removeLast()
      }
      values[key] = value
    }
    return values
  }

  private static func isValidKey(_ key: String) -> Bool {
    guard let first = key.unicodeScalars.first,
      CharacterSet.letters.contains(first) || first == "_"
    else { return false }
    return key.unicodeScalars.dropFirst().allSatisfy {
      CharacterSet.alphanumerics.contains($0) || $0 == "_"
    }
  }
}
