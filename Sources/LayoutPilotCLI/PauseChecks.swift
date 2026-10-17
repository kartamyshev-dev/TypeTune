import Foundation
import LayoutPilotCore

func pauseChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "pause: " + name)) }
    let app = "com.apple.TextEdit"
    let context = InputContext(application: app)
    // Each automatic kind with the input that triggers it when everything is enabled.
    let kinds: [(name: String, input: String, reason: Decision.Reason)] = [
        ("layout", "ghbdtn", .layout), ("typo", "превет", .typo), ("yo", "еще", .yo),
        ("double capital", "ПРивет", .typo), ("rule", "lpfixture", .userRule)]
    for paused in [false, true] {
        for appPolicy: Bool? in [nil, true, false] {
            for automatic in [false, true] {
                for typos in [false, true] {
                    for yo in [false, true] {
                        var settings = Settings()
                        settings.paused = paused; settings.automatic = automatic
                        settings.typos = typos; settings.yo = yo
                        settings.appAutomatic = appPolicy.map { [app: $0] } ?? [:]
                        settings.rules = [UserRule(source: "lpfixture", replacement: "проверка")]
                        let engine = Engine(settings: settings)
                        let stopped = paused || appPolicy == false
                        let label = "paused=\(paused) app=\(appPolicy.map(String.init) ?? "nil") auto=\(automatic) typos=\(typos) yo=\(yo)"
                        for kind in kinds {
                            let enabled: Bool
                            switch kind.name {
                            case "layout", "rule": enabled = automatic
                            case "yo": enabled = yo
                            default: enabled = typos
                            }
                            let decision = engine.decide(kind.input, context: context)
                            if stopped || !enabled { check(decision == nil, "\(kind.name) suppressed, \(label)") }
                            else { check(decision?.reason == kind.reason, "\(kind.name) applies, \(label)") }
                        }
                        let token = engine.completedTokenDecision("ghbdtn/", decide: { engine.decide($0, context: context) })
                        check((token != nil) == (!stopped && automatic), "converted punctuation follows the pause, \(label)")
                        let partial = engine.decidePartial("ghbd", context: context)
                        check((partial != nil) == (!stopped && automatic), "early correction follows the pause, \(label)")
                        check(engine.manual("ghbdtn", context: context)?.replacement == "привет", "manual conversion survives, \(label)")
                    }
                }
            }
        }
    }
    var excluded = Settings(); excluded.excludedApps = [app]
    check(Engine(settings: excluded).manual("ghbdtn", context: context) == nil, "full exclusion still stops manual conversion")
    var other = Settings(); other.appAutomatic = ["com.google.Chrome": false]
    check(Engine(settings: other).decide("превет", context: context)?.reason == .typo, "another application's pause does not apply here")
    let legacy = #"{"automatic":false,"typos":true}"#
    let migrated = try? JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
    check(migrated?.paused == false && migrated?.automatic == false, "old settings without paused keep automatic=false as layout-only off")
    var roundtrip = Settings(); roundtrip.paused = true
    check((try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(roundtrip)))?.paused == true, "paused survives save and load")
    return checks
}
