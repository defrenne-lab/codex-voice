/// Bounded FIFO deduplication with amortized constant-time insertion/eviction.
struct BoundedIdentitySet {
  private var values: Set<String> = []
  private var order: [String] = []
  private var head = 0
  private let capacity: Int

  init(capacity: Int = 8_192) { self.capacity = max(1, capacity) }

  func contains(_ value: String) -> Bool { values.contains(value) }

  @discardableResult
  mutating func insert(_ value: String) -> (inserted: Bool, evicted: String?) {
    guard values.insert(value).inserted else { return (false, nil) }
    order.append(value)
    var evicted: String?
    if values.count > capacity {
      evicted = order[head]
      values.remove(order[head])
      head += 1
    }
    if head >= capacity {
      order.removeFirst(head)
      head = 0
    }
    return (true, evicted)
  }

  mutating func formUnion(_ values: [String]) {
    for value in values { insert(value) }
  }
}
