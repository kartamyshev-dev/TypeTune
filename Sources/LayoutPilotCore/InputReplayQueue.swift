/// FIFO storage shared by the runtime input barrier and offline regression checks.
/// It does not post events or choose recovery policy. The owner serializes access.
public struct InputReplayQueue<Event> {
    public enum DeliveryDisposition: Equatable { case forward, retain, suppress }
    public struct Batch {
        public let token: UInt32
        public let events: [Event]
    }
    private var pending: [Event] = []
    private var generation: UInt32 = 0
    private var inFlight: [Event] = []
    public private(set) var outstanding = 0
    public private(set) var activeToken: UInt32?
    public init() {}
    /// Pending items only; empty pending input may still have a batch in flight.
    public var count: Int { pending.count }
    public var isEmpty: Bool { pending.isEmpty }
    public var isDrained: Bool { pending.isEmpty && outstanding == 0 }
    /// Pending size at which the owner cancels further AX writes and suspends replay.
    /// It is a signal only: the queue never discards input on its own.
    public static var pendingLimit: Int { 512 }
    public var reachedPendingLimit: Bool { pending.count >= Self.pendingLimit }
    public mutating func append(_ event: Event) { pending.append(event) }
    /// Only events waiting for posting; an acknowledged/in-flight batch is separate.
    public func containsPending(where predicate: (Event) -> Bool) -> Bool {
        pending.contains(where: predicate)
    }
    /// nil means a batch is in flight or limit is invalid. Unposted items stay pending.
    /// Runtime uses limit 1 so each event requires a new identity proof.
    /// An empty batch has reserved token zero.
    /// Nonempty batches receive increasing nonzero UInt32 tokens, wrapping after UInt32.max.
    public mutating func takeBatch(limit: Int = Int.max) -> Batch? {
        guard outstanding == 0, limit > 0 else { return nil }
        guard !pending.isEmpty else { return Batch(token: 0, events: []) }
        generation &+= 1
        if generation == 0 { generation = 1 }
        let events = Array(pending.prefix(limit))
        inFlight = events
        pending.removeFirst(events.count)
        outstanding = events.count
        activeToken = generation
        return Batch(token: generation, events: events)
    }
    /// Extra ACKs and ACKs for canceled/previous batches never change the active count.
    @discardableResult public mutating func acknowledge(token: UInt32) -> Bool {
        guard outstanding > 0, activeToken == token else { return false }
        outstanding -= 1
        if outstanding == 0 { activeToken = nil; inFlight.removeAll(keepingCapacity: true) }
        return true
    }
    /// Called at the replay tap before forwarding. A denied route has not delivered
    /// this event: retain only the unacknowledged suffix before newer pending input.
    /// Late copies of the old batch are suppressed, including after recovery starts.
    public mutating func receive(token: UInt32, routingAllowed: Bool) -> DeliveryDisposition {
        guard outstanding > 0, activeToken == token else { return .suppress }
        guard routingAllowed else {
            pending.insert(contentsOf: inFlight.suffix(outstanding), at: 0)
            outstanding = 0; activeToken = nil
            inFlight.removeAll(keepingCapacity: true)
            return .retain
        }
        _ = acknowledge(token: token)
        return .forward
    }
    /// Explicit user-authorized discard affects pending input, never a posted batch.
    @discardableResult public mutating func discardPending() -> [Event] {
        let discarded = pending
        pending.removeAll(keepingCapacity: true)
        return discarded
    }
    /// Mark delivery as uncertain without replaying it or discarding pending input.
    /// A later ACK carrying this canceled batch's token will remain invalid.
    @discardableResult public mutating func cancelOutstanding() -> Int {
        let uncertain = outstanding
        outstanding = 0; activeToken = nil
        inFlight.removeAll(keepingCapacity: true)
        return uncertain
    }
}

extension InputReplayQueue: Sendable where Event: Sendable {}
extension InputReplayQueue.Batch: Sendable where Event: Sendable {}

/// A short-lived proof binding, not an AX identity proof itself. Runtime creates
/// this only after a successful identity query and separately checks permissions.
public struct ReplayDeliveryLease: Sendable {
    public let token: UInt32
    public let revision: Int
    public let sourceID: String
    public let issuedAt: Double
    public let deadline: Double
    public init(token: UInt32, revision: Int, sourceID: String, issuedAt: Double, deadline: Double) {
        self.token = token; self.revision = revision; self.sourceID = sourceID
        self.issuedAt = issuedAt; self.deadline = deadline
    }
    public func permits(token: UInt32, revision: Int, sourceID: String, now: Double) -> Bool {
        self.token != 0 && self.token == token && self.revision == revision && self.sourceID == sourceID &&
        issuedAt.isFinite && deadline.isFinite && now.isFinite &&
        deadline >= issuedAt && now >= issuedAt && now <= deadline
    }
}
