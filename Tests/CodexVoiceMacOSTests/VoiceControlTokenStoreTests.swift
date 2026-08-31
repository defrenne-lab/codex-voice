import Foundation
import XCTest

@testable import CodexVoiceMacOS

final class VoiceControlTokenStoreTests: XCTestCase {
  func testEndpointPolicyAllowsOnlyLocalPlainWebSocketsOrTLS() {
    XCTAssertTrue(VoiceControlEndpointPolicy.isAllowed(URL(string: "ws://127.0.0.1:48731/control")!))
    XCTAssertTrue(VoiceControlEndpointPolicy.isAllowed(URL(string: "ws://localhost:48731/control")!))
    XCTAssertTrue(VoiceControlEndpointPolicy.isAllowed(URL(string: "wss://voice.example.test/control")!))
    XCTAssertFalse(VoiceControlEndpointPolicy.isAllowed(URL(string: "ws://192.168.1.10:48731/control")!))
    XCTAssertFalse(VoiceControlEndpointPolicy.isAllowed(URL(string: "https://example.test/control")!))
  }

  func testTokenIsStableAndStoredWithPrivatePermissions() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-voice-token-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("control-token")

    let first = try VoiceControlTokenStore.loadOrCreate(at: url)
    let second = try VoiceControlTokenStore.loadOrCreate(at: url)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.utf8.count, 64)
    XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
  }

  func testInvalidTokenFileIsRejected() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-voice-invalid-token-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("trop-court\n".utf8).write(to: url)

    XCTAssertThrowsError(try VoiceControlTokenStore.load(from: url))
  }
}
