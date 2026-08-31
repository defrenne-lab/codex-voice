import CodexVoiceCore
import Foundation

public final class UserDefaultsVoiceAudioSettingsStore: VoiceAudioSettingsStore {
  private let defaults: UserDefaults
  private let key: String

  public init(
    suiteName: String = "lab.defrenne.codexvoice3",
    key: String = "voiceAudioSettings"
  ) {
    defaults = UserDefaults(suiteName: suiteName) ?? .standard
    self.key = key
  }

  public func load() -> VoiceAudioSettings? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(VoiceAudioSettings.self, from: data)
  }

  public func save(_ settings: VoiceAudioSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: key)
  }
}
