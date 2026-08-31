import AVFoundation
import CodexVoiceCore
import Foundation

public struct MacOSVoiceDescriptor: Equatable, Sendable {
  public let identifier: String
  public let name: String
  public let language: String

  public init(identifier: String, name: String, language: String) {
    self.identifier = identifier
    self.name = name
    self.language = language
  }
}

@MainActor
public final class MacOSSpeechDriver: NSObject, VoiceSpeechDriver,
  @preconcurrency AVSpeechSynthesizerDelegate
{
  private let synthesizer = AVSpeechSynthesizer()
  private var activeUnitID: String?
  private var activeUtterance: AVSpeechUtterance?

  public var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)?

  public override init() {
    super.init()
    synthesizer.delegate = self
  }

  public func speak(_ request: VoiceSpeechDriverRequest) {
    stop()
    let utterance = AVSpeechUtterance(string: request.text)
    utterance.rate = request.rate
    utterance.pitchMultiplier = 1
    utterance.volume = request.volume
    if let identifier = request.voiceIdentifier,
      let voice = AVSpeechSynthesisVoice(identifier: identifier)
    {
      utterance.voice = voice
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
    }
    activeUnitID = request.unitID
    activeUtterance = utterance
    synthesizer.speak(utterance)
  }

  public func stop() {
    activeUnitID = nil
    activeUtterance = nil
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    complete(utterance, outcome: .finished)
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    complete(utterance, outcome: .cancelled)
  }

  public static func availableFrenchVoices() -> [MacOSVoiceDescriptor] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.lowercased().hasPrefix("fr") }
      .map {
        MacOSVoiceDescriptor(identifier: $0.identifier, name: $0.name, language: $0.language)
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  private func complete(
    _ utterance: AVSpeechUtterance,
    outcome: VoiceSpeechDriverOutcome
  ) {
    guard let activeUtterance, utterance === activeUtterance, let activeUnitID else { return }
    self.activeUtterance = nil
    self.activeUnitID = nil
    completionHandler?(activeUnitID, outcome)
  }
}
