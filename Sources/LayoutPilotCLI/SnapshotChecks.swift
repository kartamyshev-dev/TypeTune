import LayoutPilotCore

func snapshotChecks() -> [(String, Bool)] {
    var checks: [(String, Bool)] = []
    func check(_ label: String, _ value: Bool) { checks.append(("snapshot: " + label, value)) }
    func failure(_ budget: EditorSnapshotBudget, now: Double, current: Bool = true) -> EditorSnapshotFailure? {
        do { _ = try budget.timeout(now: now, isCurrent: current); return nil }
        catch let error as EditorSnapshotFailure { return error }
        catch { return nil }
    }
    let budget = EditorSnapshotBudget(deadline: 10.15)
    let first = try? budget.timeout(now: 10)
    let last = try? budget.timeout(now: 10.14)
    check("per-call timeout never exceeds 150ms", first.map { $0 > 0 && Double($0) <= 0.15 } == true)
    check("later IPC uses the remaining shared budget", last.map { $0 > 0 && Double($0) <= 10.15 - 10.14 } == true)
    check("deadline is inclusive", failure(budget, now: 10.15) == .deadlineExceeded)
    check("expired observation cannot begin another IPC", failure(budget, now: 10.2) == .deadlineExceeded)
    check("cancellation prevents an IPC before its deadline", failure(budget, now: 10, current: false) == .staleContext)
    check("cancellation remains permanent after timeout", failure(budget, now: 11, current: false) == .staleContext)
    check("invalid deadline fails closed", failure(.init(deadline: .infinity), now: 10) == .deadlineExceeded)
    check("invalid clock fails closed", failure(budget, now: .nan) == .deadlineExceeded)
    check("temporary editor failures can retry", [EditorSnapshotFailure.targetUnavailable, .axCannotComplete, .deadlineExceeded].allSatisfy(\.retryable))
    check("permission and context failures cannot retry", [EditorSnapshotFailure.accessibilityDenied, .secureInput, .staleContext,
        .unsupportedApplication, .unsupportedField, .invalidAttribute, .invalidSelection, .oversizedText, .axError(-1)].allSatisfy { !$0.retryable })
    let operation = EditorSnapshotBudget(deadline: 20.2)
    check("stage never extends the operation deadline", operation.stage(now: 20.1).deadline == 20.2)
    check("initial stage retains its 150ms ceiling", operation.stage(now: 20).deadline == 20.15)
    var clock = 20.0, calls = 0, supplied: [Float] = []
    let firstResult = try? operation.perform(now: { clock }, isCurrent: { true }) { timeout in
        calls += 1; supplied.append(timeout); clock = 20.12; return 7
    }
    let secondResult = try? operation.perform(now: { clock }, isCurrent: { true }) { timeout in
        calls += 1; supplied.append(timeout); clock = 20.19; return 8
    }
    check("sequential production calls share remaining budget", firstResult == 7 && secondResult == 8 && calls == 2 &&
        supplied.count == 2 && Double(supplied[0]) <= 0.15 && Double(supplied[1]) <= 20.2 - 20.12)
    clock = 20.2
    _ = try? operation.perform(now: { clock }, isCurrent: { true }) { _ in calls += 1 }
    check("expired operation never invokes the next AX closure", calls == 2)
    clock = 20
    _ = try? operation.perform(now: { clock }, isCurrent: { false }) { _ in calls += 1 }
    check("stale operation never invokes the AX closure", calls == 2)
    let expiredResult = try? operation.perform(now: { clock }, isCurrent: { true }) { _ in
        calls += 1; clock = 20.21; return 9
    }
    check("an IPC finishing after the deadline is not accepted", expiredResult == nil && calls == 3)
    clock = 20
    var current = true
    let cancelledResult = try? operation.perform(now: { clock }, isCurrent: { current }) { _ in
        calls += 1; current = false; return 10
    }
    check("an IPC cannot publish after cancellation", cancelledResult == nil && calls == 4)
    clock = 20
    _ = try? operation.perform(now: { clock }, isCurrent: { clock = 20.21; return true }) { _ in calls += 1 }
    check("time spent validating context consumes the same budget", calls == 4)
    let retryBudget = EditorSnapshotBudget(deadline: 30.06)
    clock = 30; calls = 0
    var pauses: [Double] = []
    let recovered: Result<Int, EditorSnapshotFailure> = retryBudget.retry(now: { clock }, isCurrent: { true },
        pause: { pauses.append($0); clock += $0 }) {
            calls += 1; clock += 0.01
            return calls == 1 ? .failure(.axCannotComplete) : .success(42)
        }
    check("production retry recovers from cannotComplete within the original budget",
        recovered == .success(42) && calls == 2 && pauses == [0.005] && clock < retryBudget.deadline)
    clock = 30; calls = 0; pauses = []
    let permanent: Result<Int, EditorSnapshotFailure> = retryBudget.retry(now: { clock }, isCurrent: { true },
        pause: { pauses.append($0); clock += $0 }) {
            calls += 1; return .failure(.unsupportedField)
        }
    check("production retry does not retry a permanent editor failure",
        permanent == .failure(.unsupportedField) && calls == 1 && pauses.isEmpty)
    clock = 30; calls = 0; pauses = []
    let exhausted: Result<Int, EditorSnapshotFailure> = retryBudget.retry(now: { clock }, isCurrent: { true },
        pause: { pauses.append($0); clock += $0 }) {
            calls += 1; clock += 0.03; return .failure(.axCannotComplete)
        }
    check("production retry cannot start a third read after two slow failures",
        exhausted == .failure(.deadlineExceeded) && calls == 2 && pauses == [0.005])
    clock = 30; calls = 0; current = true
    let abandoned: Result<Int, EditorSnapshotFailure> = retryBudget.retry(now: { clock }, isCurrent: { current },
        pause: { clock += $0; current = false }) {
            calls += 1; return .failure(.axCannotComplete)
        }
    check("production retry cancels before another read when the context changes",
        abandoned == .failure(.staleContext) && calls == 1)
    clock = 30; calls = 0
    let lateSuccess: Result<Int, EditorSnapshotFailure> = retryBudget.retry(now: { clock }, isCurrent: { true },
        pause: { clock += $0 }) {
            calls += 1; clock = 30.07; return .success(42)
        }
    check("production retry rejects success received after its deadline",
        lateSuccess == .failure(.deadlineExceeded) && calls == 1)
    return checks
}
