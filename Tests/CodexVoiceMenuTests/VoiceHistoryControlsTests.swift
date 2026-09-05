import Foundation
import XCTest

@testable import CodexVoiceMenu

@MainActor
final class VoiceHistoryControlsTests: XCTestCase {
  func testStopActionKeepsHistoryVoiceAndMainConversationWithoutDismissingPopover() {
    let model = makePreview()
    model.start() // No network, SSH, real audio or Option monitoring.
    let conversation = model.mainConversation
    let history = model.historyState
    var dismissalCount = 0
    model.optionPressedHandler = { dismissalCount += 1 }

    XCTAssertTrue(model.canStop)
    model.interruptAudio() // Same action as the small Stop button, not an Option event.

    XCTAssertNil(model.currentAudio)
    XCTAssertFalse(model.canStop)
    XCTAssertTrue(model.voiceEnabled)
    XCTAssertFalse(model.muted)
    XCTAssertEqual(model.mainConversation, conversation)
    XCTAssertEqual(model.historyState, history)
    XCTAssertTrue(model.canGoPrevious)
    XCTAssertTrue(model.canGoNext)
    XCTAssertEqual(dismissalCount, 0)
  }

  func testStopIsUnavailableBeforeConnectionAndRepeatedStopLeavesNavigationIntact() {
    let model = makePreview()
    XCTAssertFalse(model.canStop)
    model.interruptAudio()
    XCTAssertFalse(model.voiceEnabled)
    XCTAssertNil(model.currentAudio)

    model.start()
    let history = model.historyState
    model.interruptAudio()
    model.interruptAudio()
    XCTAssertNil(model.currentAudio)
    XCTAssertEqual(model.historyState, history)
    XCTAssertTrue(model.voiceEnabled)
  }

  private func makePreview() -> VoiceRemoteViewModel {
    VoiceRemoteViewModel(configuration: VoiceRemoteConfiguration(
      url: URL(string: "ws://127.0.0.1:48731/control")!,
      tokenFile: URL(fileURLWithPath: "/unused-preview-token"),
      deviceName: "Mac mini", clientID: "history-controls-test", isPreview: true,
      initialSSHTarget: nil
    ))
  }
}
