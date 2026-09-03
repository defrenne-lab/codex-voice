import AppKit
import Foundation

@MainActor
enum ApplicationInstaller {
  private static let applicationsDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)
  private static let applicationName = "Codex Voice 3.app"

  private(set) static var isInstalling = false

  static func offerInstallationIfNeeded() -> Bool {
    let source = Bundle.main.bundleURL.standardizedFileURL
    guard isRunningFromDiskImage(source) else { return false }

    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Installer Codex Voice 3 \(displayVersion) ?"
    alert.informativeText =
      "Codex Voice 3 va remplacer la version présente dans Applications, puis relancer la bonne copie."
    alert.addButton(withTitle: "Installer et remplacer")
    alert.addButton(withTitle: "Utiliser sans installer")

    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    isInstalling = true
    installAndRelaunch(from: source)
    return true
  }

  static func isRunningFromDiskImage(_ bundleURL: URL) -> Bool {
    let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true).standardizedFileURL.path
    return bundleURL.standardizedFileURL.path.hasPrefix(volumes + "/")
  }

  private static var displayVersion: String {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String,
      !version.isEmpty
    else { return "" }
    return "v\(version)"
  }

  private static func installAndRelaunch(from source: URL) {
    let destination = applicationsDirectory.appendingPathComponent(
      applicationName,
      isDirectory: true
    )

    do {
      try replaceApplication(from: source, at: destination)
      relaunch(destination)
    } catch {
      isInstalling = false
      showInstallationError(error)
    }
  }

  static func replaceApplication(
    from source: URL,
    at destination: URL,
    fileManager: FileManager = .default
  ) throws {
    let staging = destination.deletingLastPathComponent().appendingPathComponent(
      ".codex-voice-3-install-\(UUID().uuidString).app",
      isDirectory: true
    )
    do {
      try fileManager.copyItem(at: source, to: staging)
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(
          destination,
          withItemAt: staging,
          backupItemName: nil,
          options: []
        )
      } else {
        try fileManager.moveItem(at: staging, to: destination)
      }
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
  }

  private static func relaunch(_ applicationURL: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) {
      _, error in
      Task { @MainActor in
        if let error {
          isInstalling = false
          showInstallationError(error)
        } else {
          NSApplication.shared.terminate(nil)
        }
      }
    }
  }

  private static func showInstallationError(_ error: Error) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Installation impossible"
    alert.informativeText =
      "Codex Voice 3 n’a pas pu remplacer l’application dans Applications. Tu peux encore la glisser manuellement depuis le DMG.\n\n\(error.localizedDescription)"
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
