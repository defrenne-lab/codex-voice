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
      speechSettingsSection
      Divider()
      volumeSection
      Divider()
      stopSection
      if model.canOpenScreenSharing {
        Divider()
        screenSharingSection
      }
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
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text("Codex Voice 3")
          .font(.system(size: 16, weight: .semibold))
        Text("v\(applicationVersion)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
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

  private var speechSettingsSection: some View {
    VStack(spacing: 0) {
      Menu {
        Button(action: { model.setVoiceIdentifier(nil) }) {
          if model.voiceIdentifier == nil {
            Label("Automatique", systemImage: "checkmark")
          } else {
            Text("Automatique")
          }
        }
        ForEach(model.preferredVoices) { voice in
          Button(action: { model.setVoiceIdentifier(voice.identifier) }) {
            if model.voiceIdentifier == voice.identifier {
              Label(voice.name, systemImage: "checkmark")
            } else {
              Text(voice.name)
            }
          }
        }
      } label: {
        settingMenuLabel(
          icon: "quote.bubble.fill",
          title: "Voix",
          value: model.selectedVoiceName
        )
      }
      .menuStyle(.borderlessButton)
      .disabled(!model.controlsEnabled || model.preferredVoices.isEmpty)

      Divider().padding(.leading, 54)

      Menu {
        ForEach(model.ratePresets) { preset in
          Button(action: { model.setRate(preset.value) }) {
            if abs(model.rate - preset.value) < 0.01 {
              Label(preset.label, systemImage: "checkmark")
            } else {
              Text(preset.label)
            }
          }
        }
      } label: {
        settingMenuLabel(
          icon: "speedometer",
          title: "Vitesse",
          value: model.selectedRateName
        )
      }
      .menuStyle(.borderlessButton)
      .disabled(!model.controlsEnabled)

      Divider().padding(.leading, 54)

      Button(action: model.openPronunciationDictionary) {
        HStack(spacing: 12) {
          Image(systemName: "text.book.closed.fill")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24)
          Text("Dictionnaire")
            .font(.system(size: 14, weight: .medium))
          Spacer(minLength: 8)
          Text(model.pronunciationDictionaryStatus)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Image(systemName: "arrow.up.forward.app")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
      }
      .buttonStyle(.plain)
      .disabled(!model.controlsEnabled)
    }
  }

  private func settingMenuLabel(icon: String, title: String, value: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 24)
      Text(title)
        .font(.system(size: 14, weight: .medium))
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
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

  private var screenSharingSection: some View {
    Button(action: model.openScreenSharing) {
      HStack(spacing: 14) {
        Image(systemName: "display")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 34)
        Text("Ouvrir le partage d’écran")
          .font(.system(size: 14, weight: .medium))
        Spacer()
        Image(systemName: "arrow.up.forward.app")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 18)
    .padding(.vertical, 13)
  }

  private var volumeSymbol: String {
    if model.volume == 0 || model.muted { return "speaker.slash.fill" }
    if model.volume < 0.35 { return "speaker.wave.1.fill" }
    if model.volume < 0.7 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }

  private var applicationVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "développement"
  }
}

struct VoiceHaloIcon: View {
  let state: VoiceRemoteViewModel.HaloState

  var body: some View {
    ZStack {
      if state == .active {
        Circle()
          .fill(accentColor.opacity(0.22))
          .frame(width: 22, height: 22)
      }

      Circle()
        .fill(coreColor)
        .frame(width: 18, height: 18)
        .overlay {
          Circle()
            .stroke(borderColor, lineWidth: state == .disconnected ? 1.5 : 0.7)
        }
        .shadow(
          color: accentColor.opacity(state == .active ? 0.85 : 0.2),
          radius: state == .active ? 2.5 : 1
        )

      Image(systemName: symbolName)
        .font(.system(size: 8.5, weight: .semibold))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(symbolColor)
        .offset(x: 0.25)
    }
    .frame(width: 30, height: 22)
    .fixedSize()
    .accessibilityLabel(accessibilityLabel)
  }

  private var accentColor: Color {
    switch state {
    case .active: return Color(red: 0.13, green: 0.49, blue: 1)
    case .inactive: return .secondary
    case .disconnected: return .orange
    }
  }

  private var coreColor: Color {
    switch state {
    case .active: return Color(red: 0.08, green: 0.39, blue: 0.92)
    case .inactive: return Color.secondary.opacity(0.62)
    case .disconnected: return Color.secondary.opacity(0.32)
    }
  }

  private var borderColor: Color {
    switch state {
    case .active: return Color.white.opacity(0.22)
    case .inactive: return Color.white.opacity(0.12)
    case .disconnected: return .orange
    }
  }

  private var symbolColor: Color {
    state == .disconnected ? .orange : Color.white.opacity(state == .active ? 1 : 0.74)
  }

  private var symbolName: String {
    state == .active ? "speaker.wave.2.fill" : "speaker.slash.fill"
  }

  private var accessibilityLabel: String {
    switch state {
    case .active: return "Codex Voice actif"
    case .inactive: return "Codex Voice silencieux"
    case .disconnected: return "Codex Voice déconnecté"
    }
  }
}
