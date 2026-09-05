import Foundation

public enum CompositeDisposition: String, Sendable {
  case inserted
  case upgraded
  case corrected
  case duplicate
  case ignoredLowerAuthority
}

public struct CompositeIngestion: Sendable {
  public let observation: CodexSourceEvent
  public let event: CodexSourceEvent
  public let disposition: CompositeDisposition
  public let stateChanged: Bool
  public let isNewTimelineEvent: Bool

  public init(
    observation: CodexSourceEvent,
    event: CodexSourceEvent,
    disposition: CompositeDisposition,
    stateChanged: Bool,
    isNewTimelineEvent: Bool
  ) {
    self.observation = observation
    self.event = event
    self.disposition = disposition
    self.stateChanged = stateChanged
    self.isNewTimelineEvent = isNewTimelineEvent
  }
}

public final class CompositeCodexEventSource {
  private var eventsByIdentity: [String: CodexSourceEvent] = [:]
  private var identities: BoundedIdentitySet

  public init(maximumEvents: Int = 2_048) {
    identities = BoundedIdentitySet(capacity: maximumEvents)
  }

  public var knownEventCount: Int { eventsByIdentity.count }

  public func event(for identityKey: String) -> CodexSourceEvent? {
    eventsByIdentity[identityKey]
  }

  @discardableResult
  public func ingest(_ event: CodexSourceEvent) -> CompositeIngestion {
    guard let previous = eventsByIdentity[event.identityKey] else {
      if let evicted = identities.insert(event.identityKey).evicted {
        eventsByIdentity[evicted] = nil
      }
      eventsByIdentity[event.identityKey] = event
      return CompositeIngestion(
        observation: event,
        event: event,
        disposition: .inserted,
        stateChanged: true,
        isNewTimelineEvent: true
      )
    }

    if previous.payload == event.payload {
      guard event.authority > previous.authority else {
        return CompositeIngestion(
          observation: event,
          event: previous,
          disposition: .duplicate,
          stateChanged: false,
          isNewTimelineEvent: false
        )
      }

      eventsByIdentity[event.identityKey] = event
      return CompositeIngestion(
        observation: event,
        event: event,
        disposition: .upgraded,
        stateChanged: true,
        isNewTimelineEvent: false
      )
    }

    guard event.authority >= previous.authority else {
      return CompositeIngestion(
        observation: event,
        event: previous,
        disposition: .ignoredLowerAuthority,
        stateChanged: false,
        isNewTimelineEvent: false
      )
    }

    eventsByIdentity[event.identityKey] = event
    return CompositeIngestion(
      observation: event,
      event: event,
      disposition: .corrected,
      stateChanged: true,
      isNewTimelineEvent: false
    )
  }

  public func ingest(_ events: [CodexSourceEvent]) -> [CompositeIngestion] {
    events.map(ingest)
  }
}
