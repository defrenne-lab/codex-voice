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
  /// Optional hierarchical fields keep clients compatible with older services.
  public let canGoPreviousResponse: Bool?
  public let canGoNextResponse: Bool?
  public let responseCount: Int?
  public let selectedResponse: Int?
  public let responsePreview: String?
  public let canGoPreviousBlockInResponse: Bool?
  public let canGoNextBlockInResponse: Bool?
  public let responseBlockCount: Int?
  public let selectedResponseBlock: Int?

  public init(
    canGoPrevious: Bool, canGoNext: Bool, blockCount: Int, selectedBlock: Int?,
    canGoPreviousResponse: Bool? = nil, canGoNextResponse: Bool? = nil,
    responseCount: Int? = nil, selectedResponse: Int? = nil, responsePreview: String? = nil,
    canGoPreviousBlockInResponse: Bool? = nil, canGoNextBlockInResponse: Bool? = nil,
    responseBlockCount: Int? = nil, selectedResponseBlock: Int? = nil
  ) {
    self.canGoPrevious = canGoPrevious
    self.canGoNext = canGoNext
    self.blockCount = blockCount
    self.selectedBlock = selectedBlock
    self.canGoPreviousResponse = canGoPreviousResponse
    self.canGoNextResponse = canGoNextResponse
    self.responseCount = responseCount
    self.selectedResponse = selectedResponse
    self.responsePreview = responsePreview
    self.canGoPreviousBlockInResponse = canGoPreviousBlockInResponse
    self.canGoNextBlockInResponse = canGoNextBlockInResponse
    self.responseBlockCount = responseBlockCount
    self.selectedResponseBlock = selectedResponseBlock
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

  public func selectBlock(threadID: String, blockID: String) {
    guard blocks(for: threadID).contains(where: { $0.id == blockID }) else { return }
    positions[threadID] = blockID
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
        canGoPrevious: false, canGoNext: false, blockCount: 0, selectedBlock: nil,
        canGoPreviousResponse: false, canGoNextResponse: false, responseCount: 0,
        canGoPreviousBlockInResponse: false, canGoNextBlockInResponse: false,
        responseBlockCount: 0)
    }
    let blocks = blocks(for: threadID)
    let selectedID = liveBlockID ?? positions[threadID]
    let index = blocks.firstIndex { $0.id == selectedID }
    let entries = responseEntries(for: threadID)
    let responseIndex = entries.firstIndex { entry in
      entry.blocks.contains(where: { $0.id == selectedID })
    }
    let responseBlockIndex = responseIndex.flatMap { index in
      entries[index].blocks.firstIndex(where: { $0.id == selectedID })
    }
    let response = responseIndex.map { entries[$0] }
    return VoiceHistoryNavigationState(
      canGoPrevious: index.map { $0 > 0 } ?? !blocks.isEmpty,
      canGoNext: index.map { $0 + 1 < blocks.count } ?? false,
      blockCount: blocks.count, selectedBlock: index.map { $0 + 1 },
      canGoPreviousResponse: responseIndex.map {
        (responseBlockIndex ?? 0) > 0 || $0 > 0
      } ?? !entries.isEmpty,
      canGoNextResponse: responseIndex.map { $0 + 1 < entries.count } ?? false,
      responseCount: entries.count,
      selectedResponse: responseIndex.map { $0 + 1 },
      responsePreview: response.flatMap(preview),
      canGoPreviousBlockInResponse: responseBlockIndex.map { $0 > 0 } ?? false,
      canGoNextBlockInResponse: responseIndex.flatMap { responseIndex in
        responseBlockIndex.map { $0 + 1 < entries[responseIndex].blocks.count }
      } ?? false,
      responseBlockCount: response?.blocks.count ?? 0,
      selectedResponseBlock: responseBlockIndex.map { $0 + 1 })
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

  public func navigateResponse(
    threadID: String, forward: Bool, liveBlockID: String? = nil
  ) -> [VoiceHistoryBlock]? {
    let entries = responseEntries(for: threadID)
    guard !entries.isEmpty else { return nil }
    let selectedID = liveBlockID ?? positions[threadID]
    let responseIndex = entries.firstIndex { entry in
      entry.blocks.contains(where: { $0.id == selectedID })
    }
    let blockIndex = responseIndex.flatMap { index in
      entries[index].blocks.firstIndex(where: { $0.id == selectedID })
    }
    let target: Int
    if forward {
      target = responseIndex.map { $0 + 1 } ?? entries.count
    } else if let responseIndex {
      target = (blockIndex ?? 0) > 0 ? responseIndex : responseIndex - 1
    } else {
      target = entries.count - 1
    }
    guard entries.indices.contains(target), let first = entries[target].blocks.first else {
      return nil
    }
    positions[threadID] = first.id
    return entries[target].blocks
  }

  public func navigateBlockInResponse(
    threadID: String, forward: Bool, liveBlockID: String? = nil
  ) -> VoiceHistoryBlock? {
    let entries = responseEntries(for: threadID)
    let selectedID = liveBlockID ?? positions[threadID]
    guard let response = entries.first(where: { entry in
      entry.blocks.contains(where: { $0.id == selectedID })
    }), let index = response.blocks.firstIndex(where: { $0.id == selectedID })
    else { return nil }
    let target = index + (forward ? 1 : -1)
    guard response.blocks.indices.contains(target) else { return nil }
    positions[threadID] = response.blocks[target].id
    return response.blocks[target]
  }

  private func responseEntries(for threadID: String) -> [Message] {
    (messages[threadID] ?? []).filter { !$0.blocks.isEmpty }
  }

  private func preview(_ message: Message) -> String? {
    guard let text = message.blocks.first?.text else { return nil }
    let words = text.split(whereSeparator: \.isWhitespace)
    let short = words.prefix(8).joined(separator: " ")
    guard !short.isEmpty else { return nil }
    return words.count > 8 ? String(short.prefix(80)) + "…" : String(short.prefix(80))
  }
}
