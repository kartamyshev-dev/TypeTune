import AppKit
import Foundation
import LayoutPilotCore

/// Fixed synthetic diagnostics. Does not activate apps, post events, or open spell UI.
@main
struct SpellProbe {
    @MainActor static func main() throws {
        let provider = SystemVocabulary()
        // Authored before first execution; these are challenge expectations, not original observations.
        let fixtures: [(String, String, String)] = [
            ("ru-natural-outside-bundle", "телескоп", "телескоп"),
            ("ru-wrong-layout-outside-bundle", "ntktcrjg", "телескоп"),
            ("en-natural-outside-bundle", "microscope", "microscope"),
            ("en-wrong-layout-outside-bundle", "ьшскщысщзу", "microscope"),
            ("ru-physical-punctuation-outside-bundle", ";jyukbhjdfybt", "жонглирование"),
            ("en-generic-one-edit-typo", "microscoppe", "microscope"),
            ("ru-generic-one-edit-typo", "телесккоп", "телескоп"),
            ("digits-guard", "ntktcrjg42", "ntktcrjg42"),
            ("url-guard", "https://ntktcrjg.test", "https://ntktcrjg.test"),
            ("mixed-guard", "helloЁ", "helloЁ"),
            ("proper-name-typo-guard", "Microscoppe", "Microscoppe"),
            ("acronym-guard", "HTTP", "HTTP"),
            ("ambiguous-yo-guard", "сестры", "сестры")
        ]
        var results: [[String: Any]] = []
        var settings = Settings()
        let started = ProcessInfo.processInfo.systemUptime
        for (id, input, expected) in fixtures {
            let base = Engine(settings: settings).decide(input)?.replacement ?? input
            let time = ProcessInfo.processInfo.systemUptime
            let actual = provider.decision(input, settings: settings)?.replacement ?? input
            results.append(["id": id, "input": input, "expected": expected, "actual": actual, "base": base,
                            "passed": actual == expected, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - time])
        }
        let queriesBeforeGuards = provider.spellQueries + provider.guessQueries
        let guarded = "ntktcrjg"
        var guardChecks: [String: Bool] = [:]
        guardChecks["secure"] = provider.decision(guarded, settings: settings, context: .init(secure: true)) == nil
        guardChecks["unreliable"] = provider.decision(guarded, settings: settings, context: .init(reliable: false)) == nil
        settings.excludedWords = [guarded]
        guardChecks["excludedWord"] = provider.decision(guarded, settings: settings) == nil
        settings.excludedWords = []; settings.excludedApps = ["synthetic.app"]
        guardChecks["excludedApp"] = provider.decision(guarded, settings: settings, context: .init(application: "synthetic.app")) == nil
        settings.excludedApps = []; settings.learnedWords = [guarded]
        guardChecks["learned"] = provider.decision(guarded, settings: settings) == nil
        settings.learnedWords = []; settings.automatic = false; settings.typos = false; settings.yo = false
        guardChecks["allOff"] = provider.decision(guarded, settings: settings) == nil
        guardChecks["noProviderQueriesForGuards"] = queriesBeforeGuards == provider.spellQueries + provider.guessQueries
        settings = Settings()
        guardChecks["basePriority"] = provider.decision("ghbdtn", settings: settings) == Engine(settings: settings).decide("ghbdtn")
        let cachedBefore = provider.spellQueries + provider.guessQueries
        for (_, input, _) in fixtures { _ = provider.decision(input, settings: settings) }
        guardChecks["secondPassUsesCache"] = cachedBefore == provider.spellQueries + provider.guessQueries
        let report: [String: Any] = ["providerAvailable": provider.isAvailable, "status": provider.statusInfo,
            "results": results, "guardChecks": guardChecks, "spellQueries": provider.spellQueries,
            "guessQueries": provider.guessQueries, "totalElapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
            "notice": "Sparse independent synthetic diagnostics only; NSSpellChecker correctness/provider availability varies by system. Not Caramba parity or corpus quality."]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        let success = guardChecks.values.allSatisfy { $0 } && (!provider.isAvailable || results.allSatisfy { $0["passed"] as? Bool == true })
        if !success { exit(1) }
    }
}
