import AudioToolbox
import CodexVoiceCore
import CoreAudio
import Foundation

@MainActor
public final class MacOSSystemVolumeController: VoiceSystemVolumeControlling {
  private var lastKnownVolume: Float = 0.8

  public init() {
    if let current = Self.readDefaultOutputVolume() {
      lastKnownVolume = current
    }
  }

  public var volume: Float {
    if let current = Self.readDefaultOutputVolume() {
      lastKnownVolume = current
    }
    return lastKnownVolume
  }

  @discardableResult
  public func setVolume(_ volume: Float) -> Bool {
    let clamped = min(1, max(0, volume))
    guard let deviceID = Self.defaultOutputDeviceID() else { return false }

    if Self.set(clamped, on: deviceID, address: Self.virtualMainVolumeAddress) {
      lastKnownVolume = clamped
      return true
    }
    if Self.set(clamped, on: deviceID, address: Self.mainVolumeAddress) {
      lastKnownVolume = clamped
      return true
    }

    let changedLeft = Self.set(clamped, on: deviceID, address: Self.channelVolumeAddress(1))
    let changedRight = Self.set(clamped, on: deviceID, address: Self.channelVolumeAddress(2))
    guard changedLeft || changedRight else { return false }
    lastKnownVolume = clamped
    return true
  }

  private static var virtualMainVolumeAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static var mainVolumeAddress: AudioObjectPropertyAddress {
    channelVolumeAddress(kAudioObjectPropertyElementMain)
  }

  private static func channelVolumeAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: channel
    )
  }

  private static func defaultOutputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private static func readDefaultOutputVolume() -> Float? {
    guard let deviceID = defaultOutputDeviceID() else { return nil }
    if let value = read(from: deviceID, address: virtualMainVolumeAddress) { return value }
    if let value = read(from: deviceID, address: mainVolumeAddress) { return value }

    let channels = [1, 2].compactMap {
      read(from: deviceID, address: channelVolumeAddress(UInt32($0)))
    }
    guard !channels.isEmpty else { return nil }
    return channels.reduce(0, +) / Float(channels.count)
  }

  private static func read(
    from deviceID: AudioDeviceID,
    address: AudioObjectPropertyAddress
  ) -> Float? {
    var address = address
    guard AudioObjectHasProperty(deviceID, &address) else { return nil }
    var value = Float32.zero
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    guard status == noErr, value.isFinite else { return nil }
    return min(1, max(0, value))
  }

  private static func set(
    _ value: Float,
    on deviceID: AudioDeviceID,
    address: AudioObjectPropertyAddress
  ) -> Bool {
    var address = address
    guard AudioObjectHasProperty(deviceID, &address) else { return false }
    var isSettable = DarwinBoolean(false)
    guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
      isSettable.boolValue
    else { return false }

    var value = Float32(value)
    let size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
  }
}
