import Foundation
import LayoutPilotCore

func mutationSessionChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "mutation session: " + name)) }
    typealias Session = MutationSession<String, Int>

    // Gate and interception.
    var session = Session()
    check(session.permitsMutation && !session.hasPendingInput && session.mayDetachTap, "idle session permits a mutation")
    let nonce = session.beginMutation("field", deadline: 10)
    check(session.gate == "field" && session.deadline == 10 && session.mutationNonce == nonce, "begin holds gate, deadline and nonce")
    check(!session.permitsMutation && session.hasPendingInput && !session.mayDetachTap, "held gate blocks another mutation and tap teardown")
    let first = session.intercept(1)
    check(!first.cancelWrites && !first.suspendReplay && session.queue.count == 1, "intercepted event is retained")

    // finish → replay with matching context.
    check(session.finish(.verified, expected: "after", sourceID: "ru", contextMatches: true) == .replay,
          "verified mutation with matching context replays pending input")
    check(session.gate == nil && session.mutationNonce == nil && session.deadline == nil, "finish releases the gate")
    check(session.recoveryTarget == "after" && session.recoverySourceID == "ru", "finish records the expected target before replay")
    check(session.startReplay(target: "after") == .started, "replay starts")
    check(session.gate == "after" && session.replaying && session.recoveryTarget == nil, "replay holds gate and clears recovery")
    guard case .next(let target) = session.drainStep(), target == "after" else {
        check(false, "drain proposes the next event"); return checks
    }
    let identity = session.beginIdentityCheck()
    check(session.drainStep().isWait, "identity check in flight blocks another step")
    check(session.identityCheckTarget(UUID()) == nil, "a stale identity result has no target")
    check(session.identityCheckTarget(identity) == "after", "the current identity result applies to the gate")
    session.clearIdentityCheck()
    guard let delivery = session.dispatchNext(revision: 7, sourceID: "ru", issuedAt: 1, leaseDuration: 0.05) else {
        check(false, "dispatch takes one event"); return checks
    }
    check(delivery.batch.events == [1] && session.queue.outstanding == 1 && session.batchNonce == delivery.batchNonce,
          "dispatch takes one event and records its batch")
    check(session.routeLease?.permits(token: delivery.batch.token, revision: 7, sourceID: "ru", now: 1.01) == true,
          "lease permits the delivered token within its window")
    check(session.routeLease?.permits(token: delivery.batch.token, revision: 7, sourceID: "ru", now: 1.2) == false,
          "lease expires")
    check(session.drainStep().isWait, "outstanding delivery blocks the next step")
    check(session.receiveReplay(token: delivery.batch.token &+ 1, routingAllowed: true) == .suppress, "foreign token is suppressed")
    check(session.receiveReplay(token: delivery.batch.token, routingAllowed: true) == .forward && session.routeLease == nil,
          "acknowledged event is forwarded and its lease consumed")
    guard case .drained(let anchor) = session.drainStep() else { check(false, "empty queue drains"); return checks }
    check(anchor == "after" && !session.replaying && session.gate == nil && !session.hasPendingInput, "drain releases everything")
    check(session.receiveReplay(token: delivery.batch.token, routingAllowed: true) == .suppress, "late copy after drain is suppressed")

    // finish without pending input resumes and clears recovery.
    var empty = Session(); empty.beginMutation("f", deadline: nil)
    check(empty.finish(.notApplied, expected: "f", sourceID: "en", contextMatches: false) == .resume &&
          empty.recoveryTarget == nil && empty.recoverySourceID == nil, "empty completion resumes without recovery")
    check(empty.startReplay(target: "f") == .empty && empty.gate == nil, "replay of nothing releases the gate")

    // Changed context retains input for explicit recovery (testingFinish(.notApplied, pending:)).
    var retained = Session(); retained.beginMutation("f", deadline: nil); _ = retained.intercept(1); _ = retained.intercept(2)
    check(retained.finish(.notApplied, expected: "f", sourceID: "en", contextMatches: false) == .retain,
          "changed context retains pending input")
    check(retained.recoveryCandidate == "f" && retained.recoveryRequired && retained.permitsMutation == false,
          "retained input is offered for recovery and blocks new mutations")
    retained.beginRecovery("f")
    check(retained.gate == "f" && retained.recoveryCandidate == nil, "recovery verification holds the gate")
    check(retained.finish(.notApplied, expected: "f", sourceID: "en", contextMatches: true) == .replay,
          "verified recovery replays")
    check(retained.gate == nil && retained.recoveryTarget == "f", "recovery finish releases the gate before replay")
    var discard = Session(); discard.beginMutation("f", deadline: nil); _ = discard.intercept(1)
    _ = discard.finish(.notApplied, expected: "f", sourceID: "en", contextMatches: false)
    check(discard.mayDiscardPending && discard.discardPending() && discard.queue.isDrained && discard.recoveryTarget == nil,
          "user discard clears pending input and the recovery target")
    check(!discard.discardPending(), "nothing left to discard")

    // Uncertain mutation requires review; review confirmation clears it.
    var uncertain = Session(); uncertain.beginMutation("f", deadline: nil)
    check(uncertain.finish(.uncertain, expected: "f", sourceID: "en", contextMatches: true) == .review,
          "uncertain mutation requires review")
    check(uncertain.startReplay(target: "f") == .blocked && uncertain.hasPendingInput, "review blocks replay")
    check(uncertain.confirmReviewed() && !uncertain.recoveryRequired && !uncertain.hasPendingInput,
          "confirmed review clears recovery when nothing is pending")
    check(!uncertain.confirmReviewed(), "a second confirmation is not applicable")

    // Delivery timeout (testingStartOutstanding + testingDeliveryTimeout).
    var timeout = Session(); timeout.beginMutation("f", deadline: nil); _ = timeout.intercept(1); _ = timeout.intercept(2)
    _ = timeout.finish(.notApplied, expected: "f", sourceID: "en", contextMatches: true)
    _ = timeout.startReplay(target: "f")
    _ = timeout.beginIdentityCheck(); timeout.clearIdentityCheck()
    let late = timeout.dispatchNext(revision: 1, sourceID: "en", issuedAt: 0, leaseDuration: 0.05)
    check(timeout.timeOutDelivery(recoveryTarget: "predicted", sourceID: "en"), "outstanding delivery times out")
    check(!timeout.replaying && timeout.gate == nil && timeout.recoveryTarget == "predicted" &&
          timeout.recovery.uncertainDeliveries == 1 && timeout.queue.count == 1, "timeout keeps pending input and marks uncertainty")
    check(!timeout.mayDetachTap, "uncertain delivery keeps the late-token filter installed")
    check(timeout.receiveReplay(token: late?.batch.token ?? 0, routingAllowed: true) == .suppress, "late timed-out event is suppressed")
    check(!timeout.timeOutDelivery(recoveryTarget: nil, sourceID: nil), "a second timeout is ignored")
    var fallback = Session(); fallback.beginMutation("g", deadline: nil); _ = fallback.intercept(1)
    _ = fallback.finish(.notApplied, expected: "g", sourceID: "en", contextMatches: true); _ = fallback.startReplay(target: "g")
    _ = fallback.dispatchNext(revision: 1, sourceID: "en", issuedAt: 0, leaseDuration: 0.05)
    check(fallback.timeOutDelivery(recoveryTarget: nil, sourceID: nil) && fallback.recoveryTarget == "g",
          "timeout without a prediction keeps the gate as recovery target")

    // Routing refusal retains the event; suspension keeps it for recovery.
    var refused = Session(); refused.beginMutation("f", deadline: nil); _ = refused.intercept(1)
    _ = refused.finish(.verified, expected: "f", sourceID: "en", contextMatches: true); _ = refused.startReplay(target: "f")
    if let batch = refused.dispatchNext(revision: 1, sourceID: "en", issuedAt: 0, leaseDuration: 0.05)?.batch {
        check(refused.receiveReplay(token: batch.token, routingAllowed: false) == .retain && refused.queue.count == 1,
              "denied routing returns the event to the queue")
    }
    let batchBefore = refused.batchNonce
    refused.suspendReplay(recoveryTarget: "f", sourceID: "en")
    check(!refused.replaying && refused.gate == nil && refused.recoveryTarget == "f" && refused.batchNonce != batchBefore,
          "suspension keeps pending input for recovery and invalidates the delivery timer")
    var drainedSuspend = Session(); drainedSuspend.beginMutation("f", deadline: nil)
    _ = drainedSuspend.intercept(1)
    _ = drainedSuspend.finish(.verified, expected: "f", sourceID: "en", contextMatches: true)
    _ = drainedSuspend.startReplay(target: "f")
    if let batch = drainedSuspend.dispatchNext(revision: 1, sourceID: "en", issuedAt: 0, leaseDuration: 0.05)?.batch {
        _ = drainedSuspend.receiveReplay(token: batch.token, routingAllowed: true)
    }
    drainedSuspend.suspendReplay(recoveryTarget: "f", sourceID: "en")
    check(drainedSuspend.recoveryTarget == nil && !drainedSuspend.hasPendingInput, "suspending a drained replay needs no recovery")

    // A context reset invalidates the identity proof and lease, never the queue.
    var reset = Session(); reset.beginMutation("f", deadline: nil); _ = reset.intercept(1); _ = reset.intercept(2)
    _ = reset.finish(.verified, expected: "f", sourceID: "en", contextMatches: true); _ = reset.startReplay(target: "f")
    let staleIdentity = reset.beginIdentityCheck()
    reset.resetDeliveryProof()
    check(reset.identityCheckTarget(staleIdentity) == nil && reset.routeLease == nil && reset.queue.count == 2 && reset.replaying,
          "reset drops the identity proof but keeps replay and pending input")
    guard case .next = reset.drainStep() else { check(false, "replay continues after a reset"); return checks }
    // Pending limit while replaying.
    var limited = Session(); limited.beginMutation("f", deadline: nil); _ = limited.intercept(0)
    _ = limited.finish(.verified, expected: "f", sourceID: "en", contextMatches: true); _ = limited.startReplay(target: "f")
    var last = limited.intercept(1)
    for value in 2..<InputReplayQueue<Int>.pendingLimit { last = limited.intercept(value) }
    check(last.cancelWrites && last.suspendReplay && limited.queue.count == 512, "the 512th pending event cancels writes and suspends replay")
    var notReplaying = Session(); notReplaying.beginMutation("f", deadline: nil)
    for value in 1..<InputReplayQueue<Int>.pendingLimit { _ = notReplaying.intercept(value) }
    let atLimit = notReplaying.intercept(512)
    check(atLimit.cancelWrites && !atLimit.suspendReplay, "a mutation in flight is cancelled, never suspended as replay")
    check(!notReplaying.intercept(513).cancelWrites && notReplaying.queue.count == 513, "the limit signal fires once and nothing is dropped")
    return checks
}

private extension MutationSession.DrainStep {
    var isWait: Bool { if case .wait = self { return true }; return false }
}
