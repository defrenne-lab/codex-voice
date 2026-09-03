import Foundation
import XCTest

@testable import CodexVoiceMenu

@MainActor
final class ApplicationInstallerTests: XCTestCase {
  func testRecognizesOnlyApplicationsOpenedFromMountedVolumes() {
    XCTAssertTrue(
      ApplicationInstaller.isRunningFromDiskImage(
        URL(fileURLWithPath: "/Volumes/Codex Voice 3/Codex Voice 3.app")
      )
    )
    XCTAssertFalse(
      ApplicationInstaller.isRunningFromDiskImage(
        URL(fileURLWithPath: "/Applications/Codex Voice 3.app")
      )
    )
  }

  func testReplaceApplicationInstallsNewBundleOverExistingBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodexVoiceInstallerTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("Source.app", isDirectory: true)
    let destination = root.appendingPathComponent("Codex Voice 3.app", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("new-version".utf8).write(to: source.appendingPathComponent("version"))
    try Data("old-version".utf8).write(to: destination.appendingPathComponent("version"))

    try ApplicationInstaller.replaceApplication(from: source, at: destination)

    XCTAssertEqual(
      try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8),
      "new-version"
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
}
