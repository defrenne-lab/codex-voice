import Combine
import CryptoKit
import Foundation
import SwiftUI
import XCTest

@testable import CodexVoiceMenu

final class ApplicationUpdateConfigurationTests: XCTestCase {
  func testInstalledAppHasNoRestriction() {
    XCTAssertNil(configuration().unavailabilityReason)
  }

  func testPreviewAndCommandLineNeverStartUpdater() {
    XCTAssertNotNil(configuration(preview: true).unavailabilityReason)
    XCTAssertNotNil(configuration(path: "/tmp/codex-voice-menu").unavailabilityReason)
  }

  func testMountedReadOnlyAndTranslocatedCopiesRequireInstallation() {
    for path in [
      "/Volumes/Codex Voice 3/Codex Voice 3.app",
      "/private/var/folders/x/AppTranslocation/UUID/d/Codex Voice 3.app",
    ] {
      XCTAssertNotNil(configuration(path: path).unavailabilityReason)
    }
    XCTAssertNotNil(configuration(readOnly: true).unavailabilityReason)
  }

  func testRejectsMissingInsecureOrCredentialedFeed() {
    for feed in [nil, "http://example.com/appcast.xml", "file:///tmp/appcast.xml",
                 "https://user:password@example.com/appcast.xml", "https:///appcast.xml"] {
      XCTAssertNotNil(configuration(feed: feed).unavailabilityReason, "\(feed ?? "nil")")
    }
  }

  func testRequiresBase64Encoded32BytePublicKey() {
    for key in [nil, "placeholder", Data(repeating: 0, count: 31).base64EncodedString()] {
      XCTAssertNotNil(configuration(key: key).unavailabilityReason)
    }
  }

  func testShippingDefaultsAreManualAndRequireSignatures() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/CodexVoiceRemote-Info.plist"))
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
                "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling"] {
      XCTAssertEqual(plist[key] as? Bool, false, key)
    }
    for key in ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
      XCTAssertEqual(plist[key] as? Bool, true, key)
    }
    XCTAssertEqual(plist["SUSignedFeedFailureExpirationInterval"] as? Int, 0)
    XCTAssertNil(configuration(
      feed: plist["SUFeedURL"] as? String, key: plist["SUPublicEDKey"] as? String
    ).unavailabilityReason)
  }

  func testFeedSignatureMatchesEmbeddedKeyAndRejectsChangedContent() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let plistData = try Data(contentsOf: root.appendingPathComponent("Resources/CodexVoiceRemote-Info.plist"))
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    )
    let encodedKey = try XCTUnwrap(plist["SUPublicEDKey"] as? String)
    let key = try Curve25519.Signing.PublicKey(
      rawRepresentation: XCTUnwrap(Data(base64Encoded: encodedKey))
    )
    let feed = try Data(contentsOf: root.appendingPathComponent("Updates/appcast.xml"))
    // Sparkle 2.9's signed-feed format appends this comment after the signed
    // bytes. This CI check uses only the public key, never the login Keychain.
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    let signatureStart = try XCTUnwrap(feed.range(of: prefix, options: .backwards))
    let signatureEnd = try XCTUnwrap(feed.range(
      of: Data("-->".utf8), in: signatureStart.upperBound..<feed.endIndex
    ))
    let fields = try XCTUnwrap(String(
      data: feed[signatureStart.upperBound..<signatureEnd.lowerBound], encoding: .utf8
    )).split(separator: "\n")
    let encodedSignature = try XCTUnwrap(fields.first { $0.hasPrefix("edSignature:") })
      .dropFirst("edSignature:".count).trimmingCharacters(in: .whitespaces)
    let signature = try XCTUnwrap(Data(base64Encoded: encodedSignature))
    let declaredLength = try XCTUnwrap(fields.first { $0.hasPrefix("length:") })
      .dropFirst("length:".count).trimmingCharacters(in: .whitespaces)
    let content = Data(feed[..<signatureStart.lowerBound])
    XCTAssertEqual(Int(declaredLength), content.count)
    XCTAssertTrue(key.isValidSignature(signature, for: content))
    var changed = content
    changed.append(0)
    XCTAssertFalse(key.isValidSignature(signature, for: changed))
  }
}

@MainActor
final class ApplicationUpdateControllerTests: XCTestCase {
  func testPopoverRendersWithManualUpdaterFooter() throws {
    let voice = VoiceRemoteViewModel(configuration: VoiceRemoteConfiguration(
      url: URL(string: "ws://127.0.0.1:48731/control")!,
      tokenFile: URL(fileURLWithPath: "/unused-preview-token"),
      deviceName: "Mac mini", clientID: "preview", isPreview: true,
      initialSSHTarget: "preview-mini.local"
    ))
    voice.start() // Preview only: no network, microphone, SSH or key monitor.
    let updater = ApplicationUpdateController(configuration: configuration()) { FakeUpdateDriver() }
    updater.start()
    // NSHostingView also renders AppKit-backed controls, unlike ImageRenderer.
    let host = NSHostingView(rootView:
      VoiceRemotePopoverView(model: voice, updater: updater, checkForUpdates: {})
        .environment(\.colorScheme, .dark)
        .tint(.blue)
    )
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.bounds.width, 340)
    XCTAssertGreaterThan(host.bounds.height, 400)
    if let output = ProcessInfo.processInfo.environment["CODEX_VOICE_PREVIEW_OUTPUT"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: output))
    }
  }

  func testStartIsIdempotentAndNeverChecksAutomatically() {
    let driver = FakeUpdateDriver()
    let updater = ApplicationUpdateController(configuration: configuration()) { driver }
    XCTAssertFalse(updater.canCheckForUpdates)
    updater.checkForUpdates()
    updater.start()
    updater.start()
    XCTAssertEqual(driver.startCount, 1)
    XCTAssertEqual(driver.checkCount, 0)
    XCTAssertTrue(updater.canCheckForUpdates)
  }

  func testUnavailableConfigurationDoesNotConstructSparkle() {
    let updater = ApplicationUpdateController(configuration: configuration(preview: true)) {
      XCTFail("Preview must not initialize Sparkle")
      return FakeUpdateDriver()
    }
    updater.start()
    updater.checkForUpdates()
    XCTAssertFalse(updater.canCheckForUpdates)
    XCTAssertNotNil(updater.unavailabilityReason)
  }

  func testExplicitCheckDisablesButtonAndIgnoresRepeatedClick() {
    let driver = FakeUpdateDriver()
    let updater = ApplicationUpdateController(configuration: configuration()) { driver }
    updater.start()
    updater.checkForUpdates()
    updater.checkForUpdates()
    XCTAssertEqual(driver.checkCount, 1)
    XCTAssertFalse(updater.canCheckForUpdates)
  }

  func testAvailabilityTracksDriverAndIgnoresStaleNotifications() async {
    let driver = FakeUpdateDriver()
    let updater = ApplicationUpdateController(configuration: configuration()) { driver }
    updater.start()
    updater.checkForUpdates()
    // The publisher's initial true value must not undo the disabled state.
    await drainMainQueue()
    XCTAssertFalse(updater.canCheckForUpdates)
    driver.available.send(true)
    await drainMainQueue()
    XCTAssertTrue(updater.canCheckForUpdates)
    updater.checkForUpdates()
    XCTAssertEqual(driver.checkCount, 2)
  }

  func testStartErrorDisablesButtonAndPreservesExplanation() async {
    let driver = FakeUpdateDriver()
    driver.startError = NSError(domain: "UpdateTest", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Test de configuration"])
    let updater = ApplicationUpdateController(configuration: configuration()) { driver }
    updater.start()
    driver.available.send(true)
    await drainMainQueue()
    updater.checkForUpdates()
    XCTAssertFalse(updater.canCheckForUpdates)
    XCTAssertEqual(driver.checkCount, 0)
    XCTAssertTrue(updater.unavailabilityReason?.contains("Test de configuration") == true)
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

@MainActor
private final class FakeUpdateDriver: ApplicationUpdateDriving {
  let available = CurrentValueSubject<Bool, Never>(true)
  var startCount = 0
  var checkCount = 0
  var startError: Error?
  var canCheckForUpdates: Bool { available.value }
  var availabilityPublisher: AnyPublisher<Bool, Never> { available.eraseToAnyPublisher() }
  func start() throws {
    startCount += 1
    if let startError { throw startError }
  }
  func checkForUpdates() {
    checkCount += 1
    available.send(false)
  }
}

private func configuration(
  path: String = "/Applications/Codex Voice 3.app",
  feed: String? = "https://example.com/appcast.xml",
  key: String? = Data(repeating: 1, count: 32).base64EncodedString(),
  preview: Bool = false,
  readOnly: Bool = false
) -> ApplicationUpdateConfiguration {
  ApplicationUpdateConfiguration(
    bundleURL: URL(fileURLWithPath: path), feedURL: feed.flatMap(URL.init(string:)),
    publicKey: key, isPreview: preview, isReadOnlyVolume: readOnly
  )
}
