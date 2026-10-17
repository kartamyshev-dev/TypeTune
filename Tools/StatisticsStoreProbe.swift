import AppKit
import Foundation
import LayoutPilotCore

/// Actual Store implementation, isolated named defaults only. No UI/AX/keyboard/sound.
@main private struct StatisticsStoreProbe {
    static func main() throws {
        let suite = "dev.layoutpilot.statistics-probe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks: [[String: Any]] = []
        func check(_ value: Bool, _ id: String) { checks.append(["id": id, "passed": value]) }
        let settings = try JSONEncoder().encode(Settings())
        defaults.set(settings, forKey: "settings.v1")
        defaults.set(41, forKey: "corrected")
        let first = Store(defaults: defaults)
        check(first.corrected == 41 && first.statistics.unclassifiedHistorical == 41, "legacy_total_migrated")
        check(first.statistics.estimatedSeconds == 0, "history_no_time_estimate")
        check(defaults.integer(forKey: "corrected") == 41, "old_key_preserved_at_migration")
        check(defaults.data(forKey: "statistics.v1") != nil, "new_counts_record_persisted")
        first.recordCorrection(category: .typo)
        first.recordCorrection(category: .manual)
        first.recordSingleShift()
        check(first.corrected == 43 && first.statistics[.typo] == 1 && first.statistics[.manual] == 1,
              "verified_corrections_classified")
        check(first.statistics[.singleShift] == 1 && first.corrected == 43, "verified_source_change_not_correction")
        check(first.statistics[.sound] == 0, "no_sound_start_no_sound_count")
        check(first.statistics.estimatedSeconds == 19, "known_action_weights_only")
        first.recordCorrection(category: .sound)
        first.recordCorrection(category: .singleShift)
        check(first.corrected == 43 && first.statistics[.sound] == 0 && first.statistics[.singleShift] == 1,
              "correction_api_rejects_noncorrection_categories")
        let second = Store(defaults: defaults)
        check(second.statistics == first.statistics && second.corrected == 43, "restart_preserves_migration_and_categories")
        defaults.set(48, forKey: "corrected")
        let newerLegacy = Store(defaults: defaults)
        check(newerLegacy.corrected == 48 && newerLegacy.statistics.unclassifiedHistorical == 46 &&
              newerLegacy.statistics[.typo] == 1, "older_build_increment_preserved_as_history")
        defaults.set(2, forKey: "corrected")
        let oldLegacy = Store(defaults: defaults)
        check(oldLegacy.corrected == 48 && oldLegacy.statistics == newerLegacy.statistics, "older_legacy_value_no_reset")
        let malformed = Data("{\"version\":1,\"counts\":{\"manual\":-1},\"unclassifiedHistorical\":3}".utf8)
        defaults.set(malformed, forKey: "statistics.v1")
        defaults.set(48, forKey: "corrected")
        let broken = Store(defaults: defaults)
        check(!broken.statisticsStorageAvailable && broken.corrected == 48, "malformed_record_preserves_legacy_total")
        broken.recordCorrection(category: .yo)
        check(defaults.data(forKey: "statistics.v1") == malformed, "malformed_saved_record_never_overwritten")
        check(defaults.integer(forKey: "corrected") == 49, "legacy_total_still_saved_when_category_record_unavailable")
        let brokenRestart = Store(defaults: defaults)
        check(!brokenRestart.statisticsStorageAvailable && brokenRestart.corrected == 49 &&
              brokenRestart.statistics.unclassifiedHistorical == 49, "unavailable_record_restart_preserves_new_total_as_history")
        let full = Data("{\"version\":1,\"counts\":{\"automatic\":9223372036854775807},\"unclassifiedHistorical\":0}".utf8)
        defaults.set(full, forKey: "statistics.v1")
        let saturated = Store(defaults: defaults)
        saturated.recordCorrection(category: .automatic)
        check(saturated.corrected == Int.max && saturated.statistics[.automatic] == Int64.max,
              "store_corrected_and_count_saturate")
        check(saturated.statistics.estimatedSeconds == Int64.max, "store_estimate_saturates")
        defaults.removeObject(forKey: "statistics.v1")
        defaults.set(-9, forKey: "corrected")
        let negative = Store(defaults: defaults)
        check(negative.corrected == 0 && negative.statistics.unclassifiedHistorical == 0 &&
              defaults.integer(forKey: "corrected") == -9, "negative_legacy_not_imported_or_silently_rewritten")
        defaults.removeObject(forKey: "statistics.v1")
        defaults.set(true, forKey: "corrected")
        let boolean = Store(defaults: defaults)
        check(boolean.corrected == 0 && boolean.statistics.unclassifiedHistorical == 0,
              "boolean_legacy_is_not_a_count")
        check(defaults.data(forKey: "settings.v1") == settings, "ordinary_settings_bytes_untouched")
        for raw: Any in [Data("not JSON".utf8),
                         Data(#"{"automatic":"invalid","excludedApps":["com.google.Chrome"],"learnedWords":["protected"]}"#.utf8),
                         "not Data"] {
            defaults.set(raw, forKey: "settings.v1")
            let unavailable = Store(defaults: defaults)
            check(!unavailable.settingsStorageAvailable, "malformed_settings_stop_processing")
            unavailable.settings.sound.toggle()
            unavailable.learn("new-word")
            check((defaults.object(forKey: "settings.v1") as? NSObject)?.isEqual(raw) == true,
                  "settings_edits_and_learning_preserve_unreadable_record")
            check(!Store(defaults: defaults).settingsStorageAvailable, "restart_preserves_unreadable_settings")
        }
        defaults.removeObject(forKey: "settings.v1")
        let fresh = Store(defaults: defaults)
        check(fresh.settingsStorageAvailable, "absent_settings_allow_first_launch")
        fresh.settings.excludedWords = ["protected"]
        check(Store(defaults: defaults).settings.excludedWords == ["protected"], "healthy_settings_still_persist")
        defaults.set(settings, forKey: "settings.v1")
        check(Store(defaults: defaults).settingsStorageAvailable, "explicitly_restored_settings_recover_after_restart")
        defaults.removePersistentDomain(forName: suite)
        check((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty, "own_suite_cleaned")
        let failures = checks.filter { $0["passed"] as? Bool != true }.count
        let report: [String: Any] = ["kind":"isolated-actual-Store-statistics", "checks":checks,
            "total":checks.count,"failed":failures,"standardDefaultsUsed":false,"uiUsed":false,
            "nativeEventsPosted":false,"soundPlayed":false,"originalAccessed":false,"nativeAcceptance":false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if failures > 0 { exit(1) }
    }
}
