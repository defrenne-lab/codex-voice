import AppKit
import Combine
import SwiftUI

@MainActor
final class CodexVoiceAppDelegate: NSObject, NSApplicationDelegate {
  static var launchHandler: (() -> Void)?
  static var terminationHandler: (() -> Void)?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    if ApplicationInstaller.offerInstallationIfNeeded() {
      Self.launchHandler = nil
      return
    }
    Self.launchHandler?()
    Self.launchHandler = nil
  }

  func applicationWillTerminate(_ notification: Notification) {
    Self.terminationHandler?()
    Self.terminationHandler = nil
  }
}

@MainActor
private final class VoiceRemoteStatusItemController: NSObject, NSPopoverDelegate {
  static let shared = VoiceRemoteStatusItemController()

  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var outsideClickMonitor: Any?
  private var previouslyActiveApplication: NSRunningApplication?
  private var updater: ApplicationUpdateController?
  private var cancellables: Set<AnyCancellable> = []

  func install(model: VoiceRemoteViewModel, updater: ApplicationUpdateController) {
    guard statusItem == nil else { return }
    self.updater = updater

    let statusItem = NSStatusBar.system.statusItem(withLength: 30)
    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(togglePopover)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown

    let hostingController = NSHostingController(
      rootView: VoiceRemotePopoverView(model: model, updater: updater) { [weak self] in
        self?.checkForUpdates()
      }
      .tint(Color(red: 0.12, green: 0.48, blue: 1))
    )
    hostingController.view.frame.size.width = 340
    hostingController.view.layoutSubtreeIfNeeded()

    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    popover.contentViewController = hostingController
    let fittingSize = hostingController.view.fittingSize
    popover.contentSize = NSSize(width: 340, height: max(1, fittingSize.height))

    self.statusItem = statusItem
    self.popover = popover
    model.optionPressedHandler = { [weak self] in self?.dismissForPushToTalk() }
    updateIcon(model.haloState)

    Publishers.CombineLatest3(
      model.$connectionPhase,
      model.$voiceEnabled,
      model.$muted
    )
    .receive(on: RunLoop.main)
    .sink { [weak self, weak model] _, _, _ in
      guard let model else { return }
      self?.updateIcon(model.haloState)
    }
    .store(in: &cancellables)

    if model.configuration.isPreview {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.showPopover()
      }
    }
  }

  @objc private func togglePopover() {
    guard let button = statusItem?.button, let popover else { return }
    if let event = NSApplication.shared.currentEvent, event.type == .rightMouseUp {
      showContextMenu(for: button, event: event)
      return
    }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover(relativeTo: button)
    }
  }

  private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let updateItem = NSMenuItem(
      title: "Rechercher une mise à jour…",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    updateItem.target = self
    updateItem.isEnabled = updater?.canCheckForUpdates == true
    updateItem.toolTip = updater?.unavailabilityReason
    menu.addItem(updateItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "Quitter Codex Voice 3",
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }

  @objc private func checkForUpdates() {
    guard let updater, updater.canCheckForUpdates else { return }
    popover?.performClose(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    updater.checkForUpdates()
  }

  @objc private func quitApplication() {
    NSApplication.shared.terminate(nil)
  }

  private func showPopover() {
    guard let button = statusItem?.button, popover?.isShown == false else { return }
    showPopover(relativeTo: button)
  }

  private func showPopover(relativeTo button: NSStatusBarButton) {
    guard let popover else { return }
    let currentApplication = NSWorkspace.shared.frontmostApplication
    if currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previouslyActiveApplication = currentApplication
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  private func dismissForPushToTalk() {
    if popover?.isShown == true { popover?.performClose(nil) }
    DispatchQueue.main.async { [weak self] in
      self?.restorePreviousApplicationIfNeeded()
    }
  }

  func popoverDidShow(_ notification: Notification) {
    guard outsideClickMonitor == nil else { return }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard self?.popover?.isShown == true else { return }
        self?.popover?.performClose(nil)
      }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    guard let outsideClickMonitor else { return }
    NSEvent.removeMonitor(outsideClickMonitor)
    self.outsideClickMonitor = nil
  }

  private func restorePreviousApplicationIfNeeded() {
    defer { previouslyActiveApplication = nil }
    guard NSApp.isActive, let previouslyActiveApplication else { return }
    previouslyActiveApplication.activate(options: [.activateIgnoringOtherApps])
  }

  private func updateIcon(_ state: VoiceRemoteViewModel.HaloState) {
    guard let button = statusItem?.button else { return }
    let renderer = ImageRenderer(content: VoiceHaloIcon(state: state))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let image = renderer.nsImage else { return }
    image.size = NSSize(width: 28, height: 22)
    image.isTemplate = false
    button.image = image
    switch state {
    case .active:
      button.toolTip = "Codex Voice 3 — voix active"
    case .inactive:
      button.toolTip = "Codex Voice 3 — voix silencieuse"
    case .disconnected:
      button.toolTip = "Codex Voice 3 — hors ligne"
    }
  }
}

@main
@MainActor
struct CodexVoiceMenuApp: App {
  @NSApplicationDelegateAdaptor(CodexVoiceAppDelegate.self) private var appDelegate
  @StateObject private var model: VoiceRemoteViewModel
  @StateObject private var updater: ApplicationUpdateController

  init() {
    let model = VoiceRemoteViewModel()
    let updater = ApplicationUpdateController(
      configuration: .current(isPreview: model.configuration.isPreview)
    )
    _model = StateObject(wrappedValue: model)
    _updater = StateObject(wrappedValue: updater)
    CodexVoiceAppDelegate.launchHandler = {
      VoiceRemoteStatusItemController.shared.install(model: model, updater: updater)
      model.start()
      updater.start()
    }
    CodexVoiceAppDelegate.terminationHandler = {
      model.shutdown()
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !ApplicationInstaller.isInstalling else { return }
      VoiceRemoteStatusItemController.shared.install(model: model, updater: updater)
      model.start()
      updater.start()
    }
  }

  var body: some Scene {
    Settings { EmptyView() }
  }
}
