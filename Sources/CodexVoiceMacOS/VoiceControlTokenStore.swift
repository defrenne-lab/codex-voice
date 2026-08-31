import Foundation
import Security

public enum VoiceControlTokenStoreError: LocalizedError {
  case invalidTokenFile(String)
  case couldNotCreateTokenFile(String)
  case randomGenerationFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .invalidTokenFile(let path):
      return "Le fichier de jeton est absent ou invalide : \(path)"
    case .couldNotCreateTokenFile(let path):
      return "Impossible de créer le fichier de jeton : \(path)"
    case .randomGenerationFailed(let status):
      return "La génération sécurisée du jeton a échoué (\(status))."
    }
  }
}

public struct VoiceControlTokenStore {
  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex-voice", isDirectory: true)
      .appendingPathComponent("control-token", isDirectory: false)
  }

  public static func load(from url: URL) throws -> String {
    let value = try String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValid(value) else {
      throw VoiceControlTokenStoreError.invalidTokenFile(url.path)
    }
    return value
  }

  public static func loadOrCreate(
    at url: URL = defaultURL,
    fileManager: FileManager = .default
  ) throws -> String {
    if fileManager.fileExists(atPath: url.path) { return try load(from: url) }

    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let token = try generateToken()
    let created = fileManager.createFile(
      atPath: url.path,
      contents: Data((token + "\n").utf8),
      attributes: [.posixPermissions: 0o600]
    )
    guard created else {
      if fileManager.fileExists(atPath: url.path) { return try load(from: url) }
      throw VoiceControlTokenStoreError.couldNotCreateTokenFile(url.path)
    }
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return token
  }

  private static func generateToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw VoiceControlTokenStoreError.randomGenerationFailed(status)
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  private static func isValid(_ token: String) -> Bool {
    token.utf8.count == 64
      && token.unicodeScalars.allSatisfy { scalar in
        ("0"..."9").contains(Character(String(scalar)))
          || ("a"..."f").contains(Character(String(scalar)))
      }
  }
}
