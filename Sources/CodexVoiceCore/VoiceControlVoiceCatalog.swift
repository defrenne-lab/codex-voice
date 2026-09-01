import Foundation

public enum VoiceControlVoiceCatalog {
  public static func recommendedFrenchVoice(
    named expectedName: String,
    from voices: [VoiceControlVoice]
  ) -> VoiceControlVoice? {
    let expectedName = normalized(expectedName)
    return voices
      .filter {
        normalized($0.language).hasPrefix("fr-fr")
          && normalized($0.name).contains(expectedName)
          && qualityRank($0) > 0
      }
      .max { qualityRank($0) < qualityRank($1) }
  }

  private static func qualityRank(_ voice: VoiceControlVoice) -> Int {
    let description = normalized("\(voice.name) \(voice.identifier)")
    if description.contains("premium") { return 2 }
    if description.contains("enhanced") { return 1 }
    return 0
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }
}
