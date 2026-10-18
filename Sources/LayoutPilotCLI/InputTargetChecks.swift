import LayoutPilotCore

func inputTargetChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "input target: " + name)) }
    typealias Target = InputTarget<String>
    let app = Target(pid: 10, applicationID: "org.telegram")
    let window = Target(pid: 10, applicationID: "org.telegram", window: 7)
    let field = Target(pid: 10, applicationID: "org.telegram", window: 7, field: "composer")

    check(app.proof == .application && window.proof == .window && field.proof == .field, "proof strength follows what is known")
    check(Target.Proof.application < .window && Target.Proof.window < .field, "proofs are ordered")

    // Process and application are always required.
    check(app.matches(app) && app.matches(window) && app.matches(field), "an application-only target accepts more detail")
    check(!app.matches(Target(pid: 11, applicationID: "org.telegram")), "another process does not match")
    check(!app.matches(Target(pid: 10, applicationID: "com.other")), "another application does not match")

    // A known window must be observed again.
    check(window.matches(field), "same window with a newly known field matches")
    check(!window.matches(Target(pid: 10, applicationID: "org.telegram", window: 8)), "another window does not match")
    check(!window.matches(app), "losing the window number fails closed")

    // A known field must be observed again and be equal.
    check(field.matches(field), "same field matches")
    check(!field.matches(Target(pid: 10, applicationID: "org.telegram", window: 7, field: "search")), "another field does not match")
    check(!field.matches(window), "losing the field fails closed")
    check(!field.matches(Target(pid: 10, applicationID: "org.telegram", window: 9, field: "composer")),
          "the same field identity in another window does not match")
    check(field.matches(Target(pid: 10, applicationID: "org.telegram", window: 7, field: "COMPOSER"),
                        sameField: { $0.lowercased() == $1.lowercased() }), "the platform decides field equality")

    // The barrier works unchanged with targets that have no field.
    var session = MutationSession<Target, Int>()
    session.beginMutation(window, deadline: nil)
    _ = session.intercept(1)
    check(session.finish(.verified, expected: window, sourceID: "ru",
                         contextMatches: window.matches(Target(pid: 10, applicationID: "org.telegram", window: 7))) == .replay,
          "a matching window authorizes replay without a field")
    check(session.startReplay(target: window) == .started, "replay holds a field-less target")
    guard case .next(let gate) = session.drainStep() else { check(false, "replay proposes delivery"); return checks }
    check(gate.matches(Target(pid: 10, applicationID: "org.telegram", window: 7)) && !gate.matches(app),
          "delivery requires the gated window to still be front")
    return checks
}
