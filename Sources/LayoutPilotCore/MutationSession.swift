import Foundation

/// The input barrier and recovery state machine shared by the runtime and offline checks.
/// It owns the mutation gate, the FIFO of intercepted events, the recovery target and the
/// replay delivery tokens. It performs no AX, event posting, TIS or UI work: callers do
/// those and report the observed facts (completion, matching context, routing permission).
/// Target is the pinned editor identity; Event is an intercepted input event.
public struct MutationSession<Target, Event> {
    public enum ReplayStart: Equatable, Sendable {
        /// Uncertain text or an unacknowledged delivery: nothing is replayed.
        case blocked
        /// No pending input: the gate is released and recovery is cleared.
        case empty
        /// The gate is held for the target and replay delivery may begin.
        case started
    }
    public enum DrainStep {
        /// Replay is idle, a delivery is outstanding or an identity check is running.
        case wait
        /// Every event was delivered; replay and the gate are released. Carries the old gate.
        case drained(Target?)
        /// Deliver the next event to this gate after a fresh identity proof.
        case next(Target)
    }
    public struct Interception: Equatable, Sendable {
        /// The pending FIFO just reached its limit: cancel further AX writes.
        public let cancelWrites: Bool
        /// Replay cannot keep up: suspend it and keep everything for recovery.
        public let suspendReplay: Bool
    }

    // State changes only through the transitions below.
    public private(set) var gate: Target?
    public private(set) var deadline: Double?
    public private(set) var mutationNonce: UUID?
    public private(set) var replaying = false
    public private(set) var queue = InputReplayQueue<Event>()
    public private(set) var recovery = InputRecovery()
    public private(set) var recoveryTarget: Target?
    public private(set) var recoverySourceID: String?
    public private(set) var identityNonce: UUID?
    public private(set) var routeLease: ReplayDeliveryLease?
    public private(set) var batchNonce = UUID()

    public init() {}

    // MARK: Queries

    public var hasPendingInput: Bool { gate != nil || !queue.isDrained || recovery.requiresReview }
    public var recoveryRequired: Bool { recoveryTarget != nil || recovery.requiresReview }
    /// The mutation gate may be acquired only with no gate, recovery, review or pending input.
    public var permitsMutation: Bool { gate == nil && recoveryTarget == nil && !recovery.requiresReview && queue.isEmpty }
    public var mayDetachTap: Bool { recovery.mayDetachTap(activeMutation: gate != nil, outstanding: queue.outstanding) }
    /// The saved target an explicit recovery may verify, when nothing else is in flight.
    public var recoveryCandidate: Target? {
        guard !recovery.requiresReview, queue.outstanding == 0, gate == nil else { return nil }
        return recoveryTarget
    }
    public var mayConfirmReview: Bool { gate == nil && queue.outstanding == 0 && recovery.requiresReview }
    public var mayDiscardPending: Bool { gate == nil && queue.outstanding == 0 && queue.count > 0 }

    // MARK: Mutation

    /// Holds the gate for one AX mutation. Returns the nonce of its soft deadline.
    @discardableResult
    public mutating func beginMutation(_ target: Target, deadline: Double?) -> UUID {
        gate = target; self.deadline = deadline
        let nonce = UUID(); mutationNonce = nonce
        return nonce
    }

    /// Retains an event that arrived for the gated application while it is held.
    public mutating func intercept(_ event: Event) -> Interception {
        queue.append(event)
        return Interception(cancelWrites: queue.count == InputReplayQueue<Event>.pendingLimit,
                            suspendReplay: replaying && queue.reachedPendingLimit)
    }

    /// Releases the gate after a mutation and chooses what happens to retained input.
    /// expected is the target the text must now match; contextMatches is the caller's
    /// fresh observation of that exact target, text and caret.
    public mutating func finish(_ completion: InputRecovery.Completion, expected: Target,
                                sourceID: String, contextMatches: Bool) -> InputRecovery.Action {
        gate = nil; mutationNonce = nil; deadline = nil
        recovery.observe(completion)
        recoveryTarget = expected; recoverySourceID = sourceID
        let action = recovery.action(pending: queue.count, outstanding: queue.outstanding, contextMatches: contextMatches)
        if action == .resume { recoveryTarget = nil; recoverySourceID = nil }
        return action
    }

    // MARK: Replay

    public mutating func startReplay(target: Target) -> ReplayStart {
        guard !recovery.requiresReview, queue.outstanding == 0 else { return .blocked }
        recoveryTarget = nil; recoverySourceID = nil
        guard !queue.isEmpty else { gate = nil; deadline = nil; return .empty }
        identityNonce = nil; routeLease = nil
        gate = target; deadline = nil; replaying = true
        return .started
    }

    public mutating func drainStep() -> DrainStep {
        guard replaying, queue.outstanding == 0, identityNonce == nil else { return .wait }
        if queue.isEmpty {
            let anchor = gate
            replaying = false; gate = nil; mutationNonce = nil; deadline = nil
            return .drained(anchor)
        }
        guard let gate else { return .wait }
        return .next(gate)
    }

    /// Marks an identity query in flight; a newer one or any reset makes it stale.
    public mutating func beginIdentityCheck() -> UUID {
        let nonce = UUID(); identityNonce = nonce
        return nonce
    }

    /// The gate an identity result applies to, or nil when the result is stale.
    public func identityCheckTarget(_ nonce: UUID) -> Target? {
        guard identityNonce == nonce, replaying else { return nil }
        return gate
    }

    public mutating func clearIdentityCheck() { identityNonce = nil }

    /// A context reset invalidates an in-flight identity query and the routing lease;
    /// pending and outstanding input are untouched.
    public mutating func resetDeliveryProof() { identityNonce = nil; routeLease = nil }

    /// Takes one event for delivery and binds it to a short routing lease.
    public mutating func dispatchNext(revision: Int, sourceID: String, issuedAt: Double,
                                      leaseDuration: Double) -> (batch: InputReplayQueue<Event>.Batch, batchNonce: UUID)? {
        guard let batch = queue.takeBatch(limit: 1), !batch.events.isEmpty else { return nil }
        routeLease = ReplayDeliveryLease(token: batch.token, revision: revision, sourceID: sourceID,
                                         issuedAt: issuedAt, deadline: issuedAt + leaseDuration)
        let nonce = UUID(); batchNonce = nonce
        return (batch, nonce)
    }

    /// A replay-tagged event reached the tap. Without an active replay it is suppressed.
    public mutating func receiveReplay(token: UInt32, routingAllowed: Bool) -> InputReplayQueue<Event>.DeliveryDisposition {
        guard replaying, gate != nil else { return .suppress }
        let disposition = queue.receive(token: token, routingAllowed: routingAllowed)
        if disposition == .forward { routeLease = nil }
        return disposition
    }

    /// The posted event was never acknowledged: delivery is uncertain and needs review.
    /// recoveryTarget is the predicted target after acknowledged events (defaults to the gate).
    @discardableResult
    public mutating func timeOutDelivery(recoveryTarget predicted: Target?, sourceID: String?) -> Bool {
        guard replaying, queue.outstanding > 0 else { return false }
        replaying = false
        recovery.deliveryTimedOut(queue.cancelOutstanding())
        identityNonce = nil; routeLease = nil
        recoveryTarget = predicted ?? gate; recoverySourceID = sourceID
        gate = nil; deadline = nil
        return true
    }

    /// Stops delivery (focus, permission, identity or limit), keeping pending input.
    public mutating func suspendReplay(recoveryTarget predicted: Target, sourceID: String?) {
        identityNonce = nil; routeLease = nil
        replaying = false; batchNonce = UUID()
        recovery.deliveryTimedOut(queue.cancelOutstanding())
        gate = nil; mutationNonce = nil; deadline = nil
        recoveryTarget = predicted; recoverySourceID = sourceID
        if queue.isDrained && !recovery.requiresReview { recoveryTarget = nil; recoverySourceID = nil }
    }

    // MARK: Recovery

    /// Holds the gate while the saved target is verified read-only; finish() follows.
    public mutating func beginRecovery(_ expected: Target) {
        gate = expected; mutationNonce = UUID(); deadline = nil
    }

    /// The user confirmed the text. Returns false when confirmation is not applicable.
    @discardableResult
    public mutating func confirmReviewed() -> Bool {
        guard mayConfirmReview else { return false }
        recovery.confirmTextReviewed()
        if queue.isDrained { recoveryTarget = nil; recoverySourceID = nil }
        return true
    }

    /// User-authorized discard of pending input; posted events are never touched.
    @discardableResult
    public mutating func discardPending() -> Bool {
        guard mayDiscardPending else { return false }
        queue.discardPending()
        if !recovery.requiresReview { recoveryTarget = nil; recoverySourceID = nil }
        return true
    }
}

extension MutationSession: Sendable where Target: Sendable, Event: Sendable {}
extension MutationSession.DrainStep: Sendable where Target: Sendable {}
