import XCTest

@testable import CodexVoiceMacOS

final class SSHTunnelSpecificationTests: XCTestCase {
  func testBuildsARestrictedPersistentForward() throws {
    let specification = try SSHTunnelSpecification(
      target: "voice-user@mac-mini.local",
      localPort: 48_731,
      remotePort: 48_731
    )

    XCTAssertEqual(specification.target, "voice-user@mac-mini.local")
    XCTAssertTrue(specification.arguments.contains("BatchMode=yes"))
    XCTAssertTrue(specification.arguments.contains("PreferredAuthentications=publickey"))
    XCTAssertTrue(specification.arguments.contains("PasswordAuthentication=no"))
    XCTAssertTrue(specification.arguments.contains("KbdInteractiveAuthentication=no"))
    XCTAssertTrue(specification.arguments.contains("ExitOnForwardFailure=yes"))
    XCTAssertTrue(specification.arguments.contains("ClearAllForwardings=no"))
    XCTAssertTrue(specification.arguments.contains("127.0.0.1:48731:127.0.0.1:48731"))
    XCTAssertEqual(specification.arguments.last, "voice-user@mac-mini.local")
  }

  func testTrimsTargetBeforePersistingIt() throws {
    let specification = try SSHTunnelSpecification(target: "  voice@mini.local\n")

    XCTAssertEqual(specification.target, "voice@mini.local")
  }

  func testRejectsTargetsThatCouldBecomeSSHArguments() {
    for target in [
      "-oProxyCommand=bad",
      "voice@mini.local extra",
      "voice@@mini.local",
      "voice@",
      "voice@mini.local:22",
    ] {
      XCTAssertThrowsError(try SSHTunnelSpecification(target: target), target)
    }
  }

  func testRejectsInvalidPorts() {
    XCTAssertThrowsError(try SSHTunnelSpecification(target: "mini", localPort: 0))
    XCTAssertThrowsError(try SSHTunnelSpecification(target: "mini", remotePort: 70_000))
  }
}
