import Foundation

@MainActor
public protocol VoicePronunciationDictionaryManaging {
  func loadContent() throws -> String
  func replaceContent(_ content: String) throws
}
