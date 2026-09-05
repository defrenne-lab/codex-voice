import Combine
import Foundation
import Sparkle

@MainActor
protocol ApplicationUpdateDriving: AnyObject {
  var canCheckForUpdates: Bool { get }
  var availabilityPublisher: AnyPublisher<Bool, Never> { get }
  func start() throws
  func checkForUpdates()
}

@MainActor
private final class SparkleUpdateDriver: ApplicationUpdateDriving {
  private let controller = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

  var availabilityPublisher: AnyPublisher<Bool, Never> {
    controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
  }

  func start() throws {
    try controller.updater.start()
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}

/// Owns only updates of the menu app. It never sends commands to Voice Local.
@MainActor
final class ApplicationUpdateController: ObservableObject {
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var unavailabilityReason: String?

  private let configuration: ApplicationUpdateConfiguration
  private let makeDriver: @MainActor () -> any ApplicationUpdateDriving
  private var driver: (any ApplicationUpdateDriving)?
  private var availabilityObservation: AnyCancellable?
  private var hasStarted = false

  init(
    configuration: ApplicationUpdateConfiguration,
    makeDriver: @escaping @MainActor () -> any ApplicationUpdateDriving = { SparkleUpdateDriver() }
  ) {
    self.configuration = configuration
    self.makeDriver = makeDriver
    unavailabilityReason = configuration.unavailabilityReason
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    guard configuration.unavailabilityReason == nil else { return }
    let driver = makeDriver()
    self.driver = driver
    availabilityObservation = driver.availabilityPublisher
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, self.unavailabilityReason == nil else { return }
        // KVO is delivered on the next run-loop turn. Read the live value so
        // a queued notification cannot re-enable the button during a check.
        self.canCheckForUpdates = self.driver?.canCheckForUpdates == true
      }
    do {
      try driver.start()
      canCheckForUpdates = driver.canCheckForUpdates
    } catch {
      availabilityObservation = nil
      self.driver = nil
      canCheckForUpdates = false
      unavailabilityReason = "Mises à jour indisponibles : \(error.localizedDescription)"
    }
  }

  func checkForUpdates() {
    guard canCheckForUpdates, let driver, driver.canCheckForUpdates else { return }
    driver.checkForUpdates()
    canCheckForUpdates = driver.canCheckForUpdates
  }
}
