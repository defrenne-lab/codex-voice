import SwiftUI

struct VoiceRemotePopoverView: View {
  @ObservedObject var model: VoiceRemoteViewModel

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      readingSection
      Divider()
      voiceSection
      Divider()
      volumeSection
      Divider()
      stopSection
      if !model.optionMonitoringAuthorized {
        Divider()
        optionPermissionSection
      }
    }
    .frame(width: 340)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Codex Voice 3")
        .font(.system(size: 16, weight: .semibold))
      Text(model.deviceStatus)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      if let error = model.lastError, model.connectionPhase == .disconnected {
        Text(error)
          .font(.system(size: 11))
          .foregroundStyle(.orange)
          .lineLimit(2)
          .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 18)
    .padding(.vertical, 15)
  }

  private var readingSection: some View {
    HStack(spacing: 14) {
      Image(systemName: "waveform")
        .font(.system(size: 22, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(model.isReading ? Color.accentColor : Color.secondary)
        .frame(width: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text(model.isReading ? "Lecture en cours" : "En attente")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(model.isReading ? Color.accentColor : Color.secondary)
        Text(model.readingTitle)
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 17)
  }

  private var voiceSection: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(model.voiceEnabled ? Color.accentColor : Color.secondary.opacity(0.25))
        Image(systemName: "waveform")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(model.voiceEnabled ? Color.white : Color.secondary)
      }
      .frame(width: 36, height: 36)

      Text("Voix active")
        .font(.system(size: 15, weight: .medium))
      Spacer()
      Toggle(
        "Voix active",
        isOn: Binding(
          get: { model.voiceEnabled },
          set: { model.setVoiceEnabled($0) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .disabled(!model.controlsEnabled)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 13)
  }

  private var volumeSection: some View {
    HStack(spacing: 12) {
      Image(systemName: volumeSymbol)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 24)
      Text("Volume \(Int((model.volume * 100).rounded())) %")
        .font(.system(size: 14, weight: .medium))
        .monospacedDigit()
        .frame(width: 92, alignment: .leading)
      Slider(
        value: Binding(
          get: { model.volume },
          set: { model.setVolume($0) }
        ),
        in: 0...1
      )
      .disabled(!model.controlsEnabled)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 15)
  }

  private var stopSection: some View {
    Button(action: model.interruptAudio) {
      HStack(spacing: 14) {
        ZStack {
          Circle().fill(Color.secondary.opacity(0.18))
          Image(systemName: "stop.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(model.canStop ? Color.primary : Color.secondary)
        }
        .frame(width: 34, height: 34)
        Text("Arrêter la lecture")
          .font(.system(size: 15, weight: .medium))
        Spacer()
        Text("⌥")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!model.canStop)
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
  }

  private var optionPermissionSection: some View {
    Button(action: model.requestOptionMonitoringAuthorization) {
      HStack(spacing: 10) {
        Image(systemName: "option")
          .font(.system(size: 15, weight: .semibold))
        VStack(alignment: .leading, spacing: 2) {
          Text("Autoriser la touche Option")
            .font(.system(size: 13, weight: .medium))
          Text("Pour couper la lecture depuis Codex")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 18)
    .padding(.vertical, 11)
  }

  private var volumeSymbol: String {
    if model.volume == 0 || model.muted { return "speaker.slash.fill" }
    if model.volume < 0.35 { return "speaker.wave.1.fill" }
    if model.volume < 0.7 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }
}

struct VoiceHaloIcon: View {
  let state: VoiceRemoteViewModel.HaloState

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(state == .active ? 0.24 : 0.12))
        .frame(width: 28, height: 28)
        .blur(radius: 3.5)
      Circle()
        .fill(color.opacity(state == .active ? 0.28 : 0.14))
        .frame(width: 21, height: 21)
      Circle()
        .fill(color)
        .frame(width: 16, height: 16)
        .shadow(color: color.opacity(state == .active ? 0.9 : 0.25), radius: 4)
      Circle()
        .fill(Color.white.opacity(state == .active ? 0.65 : 0.3))
        .frame(width: 4, height: 4)
        .offset(x: -3, y: -3)
    }
    .frame(width: 30, height: 22)
    .fixedSize()
    .accessibilityLabel(accessibilityLabel)
  }

  private var color: Color {
    switch state {
    case .active: return Color(red: 0.13, green: 0.49, blue: 1)
    case .inactive: return .secondary
    case .disconnected: return .orange
    }
  }

  private var accessibilityLabel: String {
    switch state {
    case .active: return "Codex Voice actif"
    case .inactive: return "Codex Voice silencieux"
    case .disconnected: return "Codex Voice déconnecté"
    }
  }
}
