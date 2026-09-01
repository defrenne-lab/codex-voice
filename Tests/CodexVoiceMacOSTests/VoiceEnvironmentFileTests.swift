import Foundation
import XCTest

@testable import CodexVoiceMacOS

final class VoiceEnvironmentFileTests: XCTestCase {
  func testLoadsCommentsExportsQuotesAndEmbeddedEquals() throws {
    let url = temporaryFile()
    try """
      # MacBook local configuration
      export CODEX_VOICE_SSH_TARGET="voice@mini.local"
      CODEX_VOICE_DEVICE_NAME='Mac mini salon'
      VALUE_WITH_EQUALS=left=right

      """.write(to: url, atomically: true, encoding: .utf8)

    let values = try VoiceEnvironmentFile.load(from: url)

    XCTAssertEqual(values["CODEX_VOICE_SSH_TARGET"], "voice@mini.local")
    XCTAssertEqual(values["CODEX_VOICE_DEVICE_NAME"], "Mac mini salon")
    XCTAssertEqual(values["VALUE_WITH_EQUALS"], "left=right")
  }

  func testMissingFileProducesEmptyConfiguration() throws {
    XCTAssertEqual(try VoiceEnvironmentFile.load(from: temporaryFile()), [:])
  }

  func testRejectsInvalidLinesAndKeys() throws {
    let invalidLine = temporaryFile()
    try "MISSING_SEPARATOR\n".write(to: invalidLine, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try VoiceEnvironmentFile.load(from: invalidLine))

    let invalidKey = temporaryFile()
    try "BAD-KEY=value\n".write(to: invalidKey, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try VoiceEnvironmentFile.load(from: invalidKey))
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-voice-env-\(UUID().uuidString)")
  }
}
