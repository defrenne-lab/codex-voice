import XCTest

@testable import CodexVoiceCore

final class VoiceControlVoiceCatalogTests: XCTestCase {
  func testRecommendedVoicePrefersPremiumOverEnhancedAndCompact() {
    let selected = VoiceControlVoiceCatalog.recommendedFrenchVoice(
      named: "Thomas",
      from: [compactThomas, enhancedThomas, premiumThomas]
    )

    XCTAssertEqual(selected, premiumThomas)
  }

  func testRecommendedVoiceUsesEnhancedNameReportedForDownloadedPremiumVoice() {
    let selected = VoiceControlVoiceCatalog.recommendedFrenchVoice(
      named: "Thomas",
      from: [compactThomas, enhancedThomas]
    )

    XCTAssertEqual(selected, enhancedThomas)
  }

  func testCompactVoiceIsNeverPresentedAsRecommended() {
    let selected = VoiceControlVoiceCatalog.recommendedFrenchVoice(
      named: "Thomas",
      from: [compactThomas]
    )

    XCTAssertNil(selected)
  }

  func testRecommendedVoiceNameMatchingIgnoresDiacritics() {
    let aurelie = VoiceControlVoice(
      identifier: "com.apple.voice.enhanced.fr-FR.Aurelie",
      name: "Aurélie (Enhanced)",
      language: "fr-FR"
    )

    XCTAssertEqual(
      VoiceControlVoiceCatalog.recommendedFrenchVoice(named: "aurelie", from: [aurelie]),
      aurelie
    )
  }
}

private let compactThomas = VoiceControlVoice(
  identifier: "com.apple.voice.compact.fr-FR.Thomas",
  name: "Thomas",
  language: "fr-FR"
)

private let enhancedThomas = VoiceControlVoice(
  identifier: "com.apple.voice.enhanced.fr-FR.Thomas",
  name: "Thomas (Enhanced)",
  language: "fr-FR"
)

private let premiumThomas = VoiceControlVoice(
  identifier: "com.apple.voice.premium.fr-FR.Thomas",
  name: "Thomas (Premium)",
  language: "fr-FR"
)
