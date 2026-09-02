import Foundation

@MainActor
public protocol VoiceSystemVolumeControlling: AnyObject {
  var volume: Float { get }

  @discardableResult
  func setVolume(_ volume: Float) -> Bool
}
