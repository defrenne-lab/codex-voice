import Foundation
import XCTest

@testable import CodexVoiceMacOS

@MainActor
final class PronunciationDictionaryTests: XCTestCase {
  func testAppliesWholeWordsCaseInsensitivelyAndPreservesInitialCapital() throws {
    let fileURL = temporaryDictionaryURL()
    try "source,replacement\nGitHub,Guit-Heub\n".write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )
    let dictionary = PronunciationDictionary(fileURL: fileURL)

    XCTAssertEqual(
      dictionary.applying(to: "GitHub et github, pas GitHubActions."),
      "Guit-Heub et Guit-Heub, pas GitHubActions."
    )
  }

  func testLastDuplicateEntryWins() throws {
    let fileURL = temporaryDictionaryURL()
    try "source,replacement\nBacklog,back-lo-gue\nBacklog,back-logue\n".write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )

    XCTAssertEqual(
      PronunciationDictionary(fileURL: fileURL).applying(to: "Backlog"),
      "Back-logue"
    )
  }

  func testReplaceContentPersistsAValidDictionary() throws {
    let fileURL = temporaryDictionaryURL()
    try "source,replacement\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let dictionary = PronunciationDictionary(fileURL: fileURL)
    let content = "source,replacement\nShopify,shopifaille\n"

    try dictionary.replaceContent(content)

    XCTAssertEqual(try dictionary.loadContent(), content)
  }

  func testReplaceContentRejectsMissingHeader() throws {
    let fileURL = temporaryDictionaryURL()
    try "source,replacement\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let dictionary = PronunciationDictionary(fileURL: fileURL)

    XCTAssertThrowsError(try dictionary.replaceContent("GitHub,Guit-Heub\n"))
    XCTAssertEqual(try dictionary.loadContent(), "source,replacement\n")
  }

  private func temporaryDictionaryURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("pronunciations.csv")
  }
}
