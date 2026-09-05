import Foundation

public struct VoiceHistoryBlock: Equatable, Sendable {
  public let id: String
  public let threadID: String
  public let turnID: String
  public let itemID: String
  public let text: String
}

public struct VoiceHistoryNavigationState: Codable, Equatable, Sendable {
  public let canGoPrevious: Bool
  public let canGoNext: Bool
  public let blockCount: Int
  public let selectedBlock: Int?

  public init(canGoPrevious: Bool, canGoNext: Bool, blockCount: Int, selectedBlock: Int?) {
    self.canGoPrevious = canGoPrevious
    self.canGoNext = canGoNext
    self.blockCount = blockCount
    self.selectedBlock = selectedBlock
  }
}

public final class VoiceRecentHistory {
  private struct Message {
    let turnID: String
    let itemID: String
    let phase: CodexMessagePhase
    let blocks: [VoiceHistoryBlock]
  }
  private var messages: [String: [Message]] = [:]
  private var threadOrder: [String] = []
  private var positions: [String: String] = [:]
  public let maximumMessages: Int
  public let maximumThreads: Int

  public init(maximumMessages: Int = 5, maximumThreads: Int = 32) {
    self.maximumMessages = max(1, maximumMessages)
    self.maximumThreads = max(1, maximumThreads)
  }

  public func store(_ message: CodexAssistantMessage) {
    var entries = messages[message.threadID] ?? []
    // Final text supersedes progress paragraphs from this turn, just as the UI
    // can replace them. A correction replaces the existing item in place.
    if message.phase == .finalAnswer {
      entries.removeAll { $0.turnID == message.turnID && $0.phase == .commentary }
    } else if message.phase == .commentary,
      entries.contains(where: { $0.turnID == message.turnID && $0.phase == .finalAnswer })
    {
      return
    }
    let entry = Message(
      turnID: message.turnID, itemID: message.itemID, phase: message.phase,
      blocks: VoiceReadableText.blocks(message.text).enumerated().map { index, text in
        VoiceHistoryBlock(
          id: "\(message.turnID)|\(message.itemID)|\(index)",
          threadID: message.threadID, turnID: message.turnID, itemID: message.itemID, text: text)
      })
    if let index = entries.firstIndex(where: {
      $0.turnID == message.turnID && $0.itemID == message.itemID
    }) {
      entries[index] = entry
    } else {
      entries.append(entry)
    }
    messages[message.threadID] = Array(entries.suffix(maximumMessages))
    threadOrder.removeAll { $0 == message.threadID }
    threadOrder.append(message.threadID)
    while threadOrder.count > maximumThreads {
      let removed = threadOrder.removeFirst()
      messages[removed] = nil
      positions[removed] = nil
    }
    if let position = positions[message.threadID],
      !blocks(for: message.threadID).contains(where: { $0.id == position })
    {
      positions[message.threadID] = nil
    }
  }

  public func blocks(for threadID: String) -> [VoiceHistoryBlock] {
    (messages[threadID] ?? []).flatMap(\.blocks)
  }

  public func finishTurn(threadID: String, turnID: String) {
    guard var entries = messages[threadID],
      let final = entries.last(where: { entry in
        guard entry.turnID == turnID else { return false }
        if case .unknown = entry.phase { return true }
        return entry.phase == .finalAnswer
      })
    else { return }
    entries.removeAll { $0.turnID == turnID && $0.phase == .commentary }
    if let index = entries.firstIndex(where: { $0.turnID == turnID && $0.itemID == final.itemID }) {
      entries[index] = Message(
        turnID: turnID, itemID: final.itemID, phase: .finalAnswer, blocks: final.blocks)
    }
    messages[threadID] = entries
  }

  public func resetPosition(for threadID: String) { positions[threadID] = nil }

  public func state(for threadID: String?, liveBlockID: String? = nil)
    -> VoiceHistoryNavigationState
  {
    guard let threadID else {
      return VoiceHistoryNavigationState(
        canGoPrevious: false, canGoNext: false, blockCount: 0, selectedBlock: nil)
    }
    let blocks = blocks(for: threadID)
    let index = blocks.firstIndex { $0.id == (liveBlockID ?? positions[threadID]) }
    return VoiceHistoryNavigationState(
      canGoPrevious: index.map { $0 > 0 } ?? !blocks.isEmpty,
      canGoNext: index.map { $0 + 1 < blocks.count } ?? false,
      blockCount: blocks.count, selectedBlock: index.map { $0 + 1 })
  }

  public func navigate(threadID: String, forward: Bool, liveBlockID: String? = nil)
    -> VoiceHistoryBlock?
  {
    let blocks = blocks(for: threadID)
    let index = blocks.firstIndex { $0.id == (liveBlockID ?? positions[threadID]) }
    let next = index.map { $0 + (forward ? 1 : -1) } ?? (forward ? blocks.count : blocks.count - 1)
    guard blocks.indices.contains(next) else { return nil }
    positions[threadID] = blocks[next].id
    return blocks[next]
  }
}
