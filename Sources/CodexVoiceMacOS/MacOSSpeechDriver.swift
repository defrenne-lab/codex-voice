import AVFoundation
import AppKit
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
  private let pronunciationDictionary: PronunciationDictionary
  private var activeUnitID: String?
  private var activeUtterance: AVSpeechUtterance?
  private var cueTask: Task<Void, Never>?
  private var notificationSound: NSSound?

  public var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)?

  public init(pronunciationDictionary: PronunciationDictionary) {
    self.pronunciationDictionary = pronunciationDictionary
    super.init()
    synthesizer.delegate = self
  }

  public func speak(_ request: VoiceSpeechDriverRequest) {
    stop()
    let utterance = AVSpeechUtterance(string: pronunciationDictionary.applying(to: request.text))
    utterance.rate = request.rate
    utterance.pitchMultiplier = 1
    utterance.volume = 1
    if let identifier = request.voiceIdentifier,
      let voice = AVSpeechSynthesisVoice(identifier: identifier)
    {
      utterance.voice = voice
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
    }
    activeUnitID = request.unitID
    activeUtterance = utterance
    if request.notificationCue {
      notificationSound = NSSound(named: NSSound.Name("Glass"))
      notificationSound?.volume = 0.18
      notificationSound?.play()
      cueTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled, let self, activeUnitID == request.unitID else { return }
        synthesizer.speak(utterance)
      }
    } else {
      synthesizer.speak(utterance)
    }
  }

  public func stop() {
    cueTask?.cancel()
    cueTask = nil
    notificationSound?.stop()
    notificationSound = nil
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
