import Foundation
import LayoutPilotCore

/// Exercises the queue and lease types used by the runtime. No AX or input events.
func replayRoutingChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ passed: Bool, _ label: String) { checks.append((passed, "replay routing: " + label)) }
    var limited = InputReplayQueue<Int>()
    for value in 0..<(InputReplayQueue<Int>.pendingLimit - 1) { limited.append(value) }
    check(!limited.reachedPendingLimit, "below the pending limit replay may continue")
    limited.append(511)
    check(limited.reachedPendingLimit && limited.count == 512, "the limit is reached at 512 pending events")
    limited.append(512)
    check(limited.reachedPendingLimit && limited.count == 513, "the limit signal never discards further input")
    _ = limited.takeBatch(limit: 2)
    check(!limited.reachedPendingLimit && limited.outstanding == 2, "posted events leave the pending count")
    var queue = InputReplayQueue<String>()
    for item in ["keyDown-A", "keyUp-A", "shiftDown", "shiftUp"] { queue.append(item) }
    check(queue.takeBatch(limit: 0) == nil && queue.count == 4, "invalid limit cannot remove pending input")
    check(queue.takeBatch(limit: -1) == nil && queue.count == 4, "negative limit cannot remove pending input")
    let first = queue.takeBatch(limit: 1)!
    check(first.events == ["keyDown-A"] && queue.count == 3 && queue.outstanding == 1,
          "identity proof posts only one event, including for key-down/up pairs")
    check(queue.takeBatch(limit: 1) == nil, "cannot post a second event before first ACK")
    queue.append("new-B")
    check(queue.receive(token: first.token, routingAllowed: true) == .forward, "verified first key reaches original field once")
    let release = queue.takeBatch(limit: 1)!
    check(release.events == ["keyUp-A"], "release needs its own identity proof")
    check(queue.receive(token: release.token, routingAllowed: false) == .retain,
          "field change blocks release rather than sending it to the other field")
    check(queue.count == 4 && queue.outstanding == 0 && !queue.isDrained,
          "denied release and all later input remain available for explicit recovery")
    check(queue.receive(token: release.token, routingAllowed: true) == .suppress && queue.count == 4,
          "late stale copy cannot bypass recovery or consume a pending release")
    let recovered = queue.takeBatch(limit: 1)!
    check(recovered.events == ["keyUp-A"] && recovered.token != release.token,
          "recovery keeps release before modifiers and newer hardware input")
    check(queue.receive(token: release.token, routingAllowed: true) == .suppress && queue.outstanding == 1,
          "old ACK cannot authorize recovered event")
    check(queue.receive(token: recovered.token, routingAllowed: true) == .forward, "new proof delivers saved release once")
    var delivered = ["keyDown-A", "keyUp-A"]
    while !queue.isDrained {
        let batch = queue.takeBatch(limit: 1)!
        delivered.append(contentsOf: batch.events)
        _ = queue.receive(token: batch.token, routingAllowed: true)
    }
    check(delivered == ["keyDown-A", "keyUp-A", "shiftDown", "shiftUp", "new-B"],
          "focus interruption neither drops nor reorders modifier release and subsequent typing")

    // Identity-query failure occurs before takeBatch: inspecting an untouched
    // production queue must leave the entire input pending, not in-flight.
    var unposted = InputReplayQueue<Int>()
    for value in 0..<20 { unposted.append(value) }
    check(unposted.count == 20 && unposted.outstanding == 0 && unposted.activeToken == nil,
          "input awaiting successful identity proof remains pending")
    let bounded = unposted.takeBatch(limit: 3)!
    check(bounded.events == [0, 1, 2] && unposted.count == 17,
          "bounded take leaves unposted suffix intact")
    _ = unposted.receive(token: bounded.token, routingAllowed: true)
    _ = unposted.receive(token: bounded.token, routingAllowed: false)
    let retained = unposted.takeBatch()!
    check(retained.events == Array(1..<20), "denial restores only undelivered suffix ahead of remaining pending input")

    let lease = ReplayDeliveryLease(token: 42, revision: 7, sourceID: "ABC", issuedAt: 10, deadline: 10.05)
    check(lease.permits(token: 42, revision: 7, sourceID: "ABC", now: 10), "lease is valid at identity-read completion")
    check(lease.permits(token: 42, revision: 7, sourceID: "ABC", now: 10.05), "lease includes exact deadline")
    check(!lease.permits(token: 42, revision: 7, sourceID: "ABC", now: 10.051), "expired identity proof cannot route a posted event")
    check(!lease.permits(token: 41, revision: 7, sourceID: "ABC", now: 10.01), "stale batch token cannot reuse identity proof")
    check(!lease.permits(token: 42, revision: 8, sourceID: "ABC", now: 10.01), "changed revision invalidates delivery lease")
    check(!lease.permits(token: 42, revision: 7, sourceID: "RussianWin", now: 10.01), "changed exact source invalidates delivery lease")
    for time in [9.99, Double.infinity, -Double.infinity, Double.nan] {
        check(!lease.permits(token: 42, revision: 7, sourceID: "ABC", now: time), "nonmonotonic/nonfinite time cannot authorize routing")
    }
    let zero = ReplayDeliveryLease(token: 0, revision: 7, sourceID: "ABC", issuedAt: 10, deadline: 11)
    check(!zero.permits(token: 0, revision: 7, sourceID: "ABC", now: 10.1), "reserved empty batch never grants delivery")
    let inverted = ReplayDeliveryLease(token: 42, revision: 7, sourceID: "ABC", issuedAt: 11, deadline: 10)
    check(!inverted.permits(token: 42, revision: 7, sourceID: "ABC", now: 10.5), "invalid lease interval fails closed")
    for (issued, deadline) in [(Double.nan, 11.0), (10.0, Double.infinity)] {
        let malformed = ReplayDeliveryLease(token: 42, revision: 7, sourceID: "ABC", issuedAt: issued, deadline: deadline)
        check(!malformed.permits(token: 42, revision: 7, sourceID: "ABC", now: 10.01), "nonfinite lease metadata fails closed")
    }
    // Actual production queue and projection: ACKed prefix is the recovery
    // expectation even when automatic correction is disabled or manual was used.
    var recoveryFIFO = InputReplayQueue<String>()
    var recovery = ReplayInsertionProjection(anchorText: "prefix", selection: NSRange(location: 6, length: 0))!
    for event in ["a", "keyUp", "b"] { recoveryFIFO.append(event) }
    let ackA = recoveryFIFO.takeBatch(limit: 1)!
    if recoveryFIFO.receive(token: ackA.token, routingAllowed: true) == .forward { recovery.consume(.insertion(ackA.events[0])) }
    let deniedRelease = recoveryFIFO.takeBatch(limit: 1)!
    check(recoveryFIFO.receive(token: deniedRelease.token, routingAllowed: false) == .retain, "recovery interruption retains unforwarded release")
    check(recovery.expectedText == "prefixa" && recovery.expectedSelection == NSRange(location: 7, length: 0), "recovery target includes acknowledged printable prefix, not stale anchor")
    check(recovery.matchesObserved(text: "prefixa", selection: NSRange(location: 7, length: 0), ownsAnchor: true), "exact acknowledged prefix is recoverable in its owned field")
    check(!recovery.matchesObserved(text: "prefix", selection: NSRange(location: 6, length: 0), ownsAnchor: true), "stale pre-FIFO text cannot authorize recovery")
    check(!recovery.matchesObserved(text: "prefixa", selection: NSRange(location: 6, length: 0), ownsAnchor: true), "recovery cannot silently reposition a changed caret")
    check(!recovery.matchesObserved(text: "prefixa", selection: NSRange(location: 7, length: 0), ownsAnchor: false), "same text in another field cannot authorize recovery")
    check(recoveryFIFO.receive(token: ackA.token, routingAllowed: true) == .suppress && recovery.expectedText == "prefixa", "late duplicate ACK cannot duplicate the predicted prefix")
    let recoveredRelease = recoveryFIFO.takeBatch(limit: 1)!
    if recoveryFIFO.receive(token: recoveredRelease.token, routingAllowed: true) == .forward { recovery.consume(.keyUp) }
    check(recovery.expectedText == "prefixa" && recoveryFIFO.count == 1, "recovered keyUp adds no printable text and does not consume following b")
    let ackB = recoveryFIFO.takeBatch(limit: 1)!
    if recoveryFIFO.receive(token: ackB.token, routingAllowed: true) == .forward { recovery.consume(.insertion(ackB.events[0])) }
    check(recovery.expectedText == "prefixab" && recoveryFIFO.isDrained, "recovered FIFO completes remaining prefix exactly once")
    check(recovery.completedTokenRanges.isEmpty, "recovery prediction does not invent a completed correction or learning token")

    var timeoutFIFO = InputReplayQueue<String>()
    var acknowledged = ReplayInsertionProjection(anchorText: "prefix", selection: NSRange(location: 6, length: 0))!
    timeoutFIFO.append("a"); timeoutFIFO.append("b")
    let known = timeoutFIFO.takeBatch(limit: 1)!
    if timeoutFIFO.receive(token: known.token, routingAllowed: true) == .forward { acknowledged.consume(.insertion("a")) }
    let uncertain = timeoutFIFO.takeBatch(limit: 1)!
    check(timeoutFIFO.cancelOutstanding() == 1 && acknowledged.expectedText == "prefixa", "timeout never predicts unacknowledged b as delivered")
    check(!acknowledged.matchesObserved(text: "prefixab", selection: NSRange(location: 8, length: 0), ownsAnchor: true), "actual extra uncertain delivery must fail exact recovery readback")
    check(timeoutFIFO.receive(token: uncertain.token, routingAllowed: true) == .suppress, "late timed-out ACK cannot reapply uncertain insertion")
    var unknown = acknowledged
    unknown.invalidate()
    check(!unknown.matchesObserved(text: "prefixa", selection: NSRange(location: 7, length: 0), ownsAnchor: true), "unknown commands invalidate projected recovery instead of guessing their effect")
    var changedSource = acknowledged
    changedSource.invalidate(reason: .sourceChanged)
    check(!changedSource.matchesObserved(text: "prefixa", selection: NSRange(location: 7, length: 0), ownsAnchor: true), "source mismatch invalidates any later insertion prediction")
    var boundedRecovery = ReplayInsertionProjection(anchorText: "prefix", selection: NSRange(location: 6, length: 0), maxInsertedUTF16: 1)!
    boundedRecovery.consume(.insertion("ab"))
    check(!boundedRecovery.isValid, "recovery projection uses the same explicit capacity bounds")
    return checks
}
