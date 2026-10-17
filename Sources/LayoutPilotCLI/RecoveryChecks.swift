import LayoutPilotCore

func recoveryChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    for completion: InputRecovery.Completion in [.notApplied, .verified] {
        var state = InputRecovery(); state.observe(completion)
        checks.append((state.action(pending: 0, outstanding: 0, contextMatches: false) == .resume, "empty completed mutation resumes without a stale field"))
        checks.append((state.action(pending: 2, outstanding: 0, contextMatches: false) == .retain, "changed field retains pending keys"))
        checks.append((state.action(pending: 2, outstanding: 0, contextMatches: true) == .replay, "only confirmed target authorizes pending replay"))
        checks.append((state.action(pending: 0, outstanding: 1, contextMatches: true) == .retain, "empty pending is not drained delivery"))
    }
    var state = InputRecovery(); state.observe(.uncertain)
    checks.append((state.action(pending: 0, outstanding: 0, contextMatches: true) == .review, "uncertain mutation cannot auto resume even in matching field"))
    state.observe(.notApplied)
    checks.append((state.requiresReview, "read-only recovery cannot erase an uncertain mutation"))
    state.confirmTextReviewed()
    checks.append((state.action(pending: 2, outstanding: 0, contextMatches: false) == .retain, "review confirmation does not discard real pending input"))
    var queue = InputReplayQueue<Int>(); queue.append(1)
    let batch = queue.takeBatch()!
    state.deliveryTimedOut(queue.cancelOutstanding())
    checks.append((!state.mayDetachTap(activeMutation: false, outstanding: 0), "unknown delivery keeps late-token filter installed"))
    checks.append((queue.isDrained && state.uncertainDeliveries == 1 && state.requiresReview, "timeout preserves uncertainty independently of queue count"))
    checks.append((queue.receive(token: batch.token, routingAllowed: true) == .suppress, "late delivery remains suppressed"))
    state.confirmTextReviewed()
    checks.append((state.mayDetachTap(activeMutation: false, outstanding: 0), "reviewed drained input permits tap teardown"))
    checks.append((!state.mayDetachTap(activeMutation: true, outstanding: 0) && !state.mayDetachTap(activeMutation: false, outstanding: 1), "active mutation and delivery keep tap installed"))
    checks.append((state.action(pending: 0, outstanding: 0, contextMatches: false) == .resume, "review resumes without replay or rollback"))
    checks.append((queue.receive(token: batch.token, routingAllowed: true) == .suppress, "review never revives expired tokens"))
    var tap = TapRecovery()
    checks.append((tap.next(safe: false) == .wait, "active mutation never spends recovery attempt"))
    checks.append((tap.next(safe: true) == .enable, "tap first retries enable"))
    checks.append((tap.next(safe: true) == .recreate, "tap then recreates once"))
    checks.append((tap.next(safe: true) == .failed && tap.next(safe: true) == .failed, "tap failure is bounded across refreshes"))
    tap.reset()
    checks.append((tap.next(safe: true) == .enable, "explicit retry or received hardware starts new incident"))
    return checks
}
