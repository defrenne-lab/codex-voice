import AppKit
import CoreGraphics

@MainActor
final class GlobalOptionMonitor {
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var optionIsPressed = false
  private var action: (() -> Void)?

  var isAuthorized: Bool {
    CGPreflightListenEventAccess()
  }

  func start(action: @escaping () -> Void) {
    guard globalMonitor == nil, localMonitor == nil else { return }
    self.action = action

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      DispatchQueue.main.async { self?.handle(event) }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      self?.handle(event)
      return event
    }
  }

  func requestAuthorization() -> Bool {
    let granted = CGRequestListenEventAccess()
    optionIsPressed = false
    return granted
  }

  func stop() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
    action = nil
    optionIsPressed = false
  }

  private func handle(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isPressed = flags.contains(.option)
    if isPressed, !optionIsPressed { action?() }
    optionIsPressed = isPressed
  }
}
