import AppKit
import Carbon
import Foundation
import LayoutPilotCore

/// Only the diagnostics adapter is stubbed; KeyboardService, Store and queue policy are production code.
final class InputDiagnostics {
    static let shared = InputDiagnostics()
    let enabled = true
    private(set) var faultReasons: [String] = []
    func record(_ phase: String, revision: Int, checks: [String: Bool] = [:], elapsed: TimeInterval? = nil,
                counts: [String: Int] = [:], reason: String? = nil) {}
    func fault(reason: String, revision: Int, checks: [String: Bool] = [:], counts: [String: Int] = [:]) {
        faultReasons.append(reason)
    }
    func flush() {}
    func exportReport(completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.failure(CocoaError(.featureUnsupported)))
    }
    func saveReport(_ data: Data, to destination: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(CocoaError(.featureUnsupported)))
    }
}

/// Test-mode hooks suppress platform reads, AX work, timers and event-tap creation.
@main private struct RuntimeRecoveryProbe {
    static func main() throws {
        let suite = "dev.layoutpilot.runtime-recovery-probe." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = try JSONEncoder().encode(Settings())
        defaults.set(settings, forKey: "settings.v1")
        var checks: [String: Bool] = [:]
        let expectsPrefix: (String) -> Bool = { $0 == "ghbdtn " }
        checks["transient_unreadable_retries_before_blind_fallback"] = AccessibilityEditor.FieldObservation.unreadable.needsAnotherRead(expects: expectsPrefix)
        checks["matching_prefix_stops_observation_retry"] = !AccessibilityEditor.FieldObservation.textBeforeCaret("ghbdtn ").needsAnotherRead(expects: expectsPrefix)
        checks["stale_prefix_still_retries"] = AccessibilityEditor.FieldObservation.textBeforeCaret("ghbdtn").needsAnotherRead(expects: expectsPrefix)
        checks["selected_prefix_never_retries_as_unreadable"] = !AccessibilityEditor.FieldObservation.selection(textBeforeSelection: "ghbdtn ").needsAnotherRead(expects: expectsPrefix)
        checks["secure_observation_never_retries"] = !AccessibilityEditor.FieldObservation.secure.needsAnotherRead(expects: expectsPrefix)
        let expiredProof = ["identity": true, "revision": true, "allowed": true, "trusted": true,
            "posting": true, "frontmost": true, "source": true, "leaseFresh": false, "replaySource": true]
        checks["expired_replay_proof_rechecks_instead_of_posting"] = KeyboardService.shouldRetryReplayIdentity(expiredProof, retries: 0)
        checks["expired_replay_proof_retry_is_bounded"] = !KeyboardService.shouldRetryReplayIdentity(expiredProof, retries: 2)
        checks["fresh_replay_proof_needs_no_retry"] = !KeyboardService.shouldRetryReplayIdentity(expiredProof.merging(["leaseFresh": true]) { _, new in new }, retries: 0)
        checks["other_replay_failures_never_retry"] = expiredProof.keys.filter { $0 != "leaseFresh" }.allSatisfy { key in
            !KeyboardService.shouldRetryReplayIdentity(expiredProof.merging([key: false]) { _, new in new }, retries: 0)
        }
        func service() -> KeyboardService {
            let store = Store(defaults: defaults)
            store.trusted = true; store.listening = true; store.posting = true; store.secure = false
            let service = KeyboardService(store: store, startAutomatically: false)
            service.testingRefreshStatus()
            return service
        }
        do {
            let keyboard = service()
            checks["route_and_event_rechecks_share_one_budget"] = keyboard.testingRetryReplayIdentity(expiredProof) &&
                keyboard.testingRetryReplayIdentity(expiredProof) && !keyboard.testingRetryReplayIdentity(expiredProof)
        }
        do {
            let keyboard = service()
            keyboard.testingFinish(.verified)
            checks["verified_empty_missing_readback_resumes"] = keyboard.store.serviceStatus == .ready && keyboard.store.running
            checks["verified_empty_has_no_phantom_recovery"] = !keyboard.store.recoveryRequired && !keyboard.hasPendingInput
            checks["verified_empty_no_review"] = !keyboard.store.textReviewRequired && keyboard.store.uncertainInput == 0
        }
        do {
            let keyboard = service()
            keyboard.testingFinish(.notApplied)
            checks["not_applied_empty_missing_readback_resumes"] = keyboard.store.serviceStatus == .ready && !keyboard.hasPendingInput
        }
        do {
            let keyboard = service()
            keyboard.testingFinish(.uncertain)
            checks["uncertain_empty_requires_review"] = keyboard.store.textReviewRequired && keyboard.store.serviceStatus == .uncertainResult
            checks["uncertain_empty_blocks_new_mutation_and_exit"] = !keyboard.store.running && keyboard.store.recoveryRequired && keyboard.hasPendingInput
            checks["uncertain_empty_does_not_invent_pending_keys"] = keyboard.store.pendingInput == 0 && keyboard.store.outstandingInput == 0
            checks["uncertain_fault_identified"] = InputDiagnostics.shared.faultReasons.last == "mutation-uncertain"
            let faultCount = InputDiagnostics.shared.faultReasons.count
            keyboard.testingSnapshotFailure(.deadlineExceeded)
            checks["snapshot_failure_does_not_rotate_away_recovery_cause"] = InputDiagnostics.shared.faultReasons.count == faultCount
            keyboard.testingFinish(.verified)
            checks["later_verified_does_not_clear_uncertainty"] = keyboard.store.textReviewRequired && keyboard.store.serviceStatus == .uncertainResult
            keyboard.confirmTextReviewed()
            checks["review_confirmation_resumes_empty_queue"] = keyboard.store.serviceStatus == .ready && !keyboard.hasPendingInput && !keyboard.store.recoveryRequired
        }
        do {
            let keyboard = service()
            keyboard.testingFinish(.uncertain, pending: 2)
            keyboard.confirmTextReviewed()
            checks["confirmation_preserves_pending_input"] = keyboard.store.pendingInput == 2 && keyboard.hasPendingInput
            checks["confirmation_keeps_exact_recovery_required"] = keyboard.store.recoveryRequired && keyboard.store.serviceStatus == .recoveryPending && !keyboard.store.textReviewRequired
        }
        do {
            let keyboard = service()
            keyboard.testingFinish(.verified, pending: 2)
            checks["verified_pending_without_context_is_retained"] = keyboard.store.pendingInput == 2 && keyboard.store.recoveryRequired && !keyboard.store.textReviewRequired
            keyboard.confirmTextReviewed()
            checks["confirmation_without_review_does_not_discard_pending"] = keyboard.store.pendingInput == 2 && keyboard.store.serviceStatus == .recoveryPending
        }
        do {
            let keyboard = service()
            keyboard.testingStartOutstanding()
            keyboard.testingRefreshStatus()
            checks["pending_zero_still_counts_inflight_for_exit"] = keyboard.store.pendingInput == 0 && keyboard.store.outstandingInput == 1 && keyboard.hasPendingInput
            keyboard.confirmTextReviewed()
            checks["confirmation_never_clears_inflight"] = keyboard.store.outstandingInput == 1 && keyboard.hasPendingInput
            keyboard.testingDeliveryTimeout()
            checks["timeout_zero_pending_preserves_unknown_delivery"] = keyboard.store.pendingInput == 0 && keyboard.store.outstandingInput == 0 && keyboard.store.uncertainInput == 1
            checks["timeout_zero_pending_requires_review"] = keyboard.store.textReviewRequired && keyboard.store.serviceStatus == .uncertainResult && keyboard.hasPendingInput
            checks["delivery_timeout_fault_identified"] = InputDiagnostics.shared.faultReasons.last == "delivery-timeout"
            keyboard.confirmTextReviewed()
            checks["review_confirmation_clears_unknown_without_replay"] = keyboard.store.uncertainInput == 0 && keyboard.store.serviceStatus == .ready && !keyboard.hasPendingInput
        }
        do {
            let keyboard = service()
            keyboard.testingStartOutstanding(pendingAfter: 2)
            keyboard.testingDeliveryTimeout()
            keyboard.confirmTextReviewed()
            checks["timeout_confirmation_preserves_pending_suffix"] = keyboard.store.pendingInput == 2 && keyboard.store.uncertainInput == 0 && keyboard.store.outstandingInput == 0
            checks["timeout_suffix_still_needs_exact_recovery"] = keyboard.store.recoveryRequired && keyboard.store.serviceStatus == .recoveryPending && keyboard.hasPendingInput
        }
        do {
            let keyboard = service()
            keyboard.store.lastStatus = "Защищённый ввод: обработка приостановлена"
            keyboard.store.secure = true
            keyboard.testingRefreshStatus()
            checks["secure_input_pauses_status"] = keyboard.store.serviceStatus == .secureInput && !keyboard.store.running
            keyboard.store.secure = false
            keyboard.testingRefreshStatus()
            checks["secure_input_off_restores_current_status"] = keyboard.store.serviceStatus == .ready && keyboard.store.running
            checks["current_status_is_independent_of_historical_message"] = keyboard.store.serviceStatus.message != keyboard.store.lastStatus
            keyboard.testingFinish(.uncertain)
            keyboard.store.secure = true
            keyboard.testingRefreshStatus()
            keyboard.store.secure = false
            keyboard.testingRefreshStatus()
            checks["secure_input_off_preserves_unresolved_recovery"] = keyboard.store.serviceStatus == .uncertainResult && keyboard.store.textReviewRequired
        }
        do {
            let keyboard = service()
            checks["unsafe_tap_repair_waits"] = keyboard.testingNextTapAction(safe: false) == .wait
            checks["first_safe_attempt_enables"] = keyboard.testingNextTapAction(safe: true) == .enable
            checks["unsafe_attempt_does_not_consume_budget"] = keyboard.testingNextTapAction(safe: false) == .wait && keyboard.testingNextTapAction(safe: true) == .recreate
            checks["third_attempt_is_bounded_failure"] = keyboard.testingNextTapAction(safe: true) == .failed
            checks["subsequent_attempt_stays_failed"] = keyboard.testingNextTapAction(safe: true) == .failed
            keyboard.retryConnection()
            checks["explicit_retry_resets_attempt_budget"] = keyboard.testingNextTapAction(safe: true) == .enable
        }
        do {
            let keyboard = service()
            checks["terminal_ready_allows_decision_and_ack_effects"] = keyboard.testingTerminalPolicy()
            keyboard.store.tapActive = false
            checks["terminal_tap_failure_blocks_new_decisions"] = !keyboard.testingTerminalPolicy()
            keyboard.store.tapActive = true
            keyboard.store.secure = true
            checks["terminal_pause_after_decision_blocks_ack_effects"] = !keyboard.testingTerminalPolicy()
            keyboard.store.secure = false
            keyboard.testingFinish(.uncertain)
            checks["terminal_recovery_blocks_commands_and_ack_effects"] = !keyboard.testingTerminalPolicy()
        }
        do {
            let keyboard = service()
            keyboard.testingSnapshotFailure(.axCannotComplete)
            checks["exhausted_snapshot_failure_is_saved"] = InputDiagnostics.shared.faultReasons.last == "snapshot-axCannotComplete"
            let saved = InputDiagnostics.shared.faultReasons.count
            keyboard.testingSnapshotFailure(.axCannotComplete)
            checks["unchanged_snapshot_failure_does_not_flood_reports"] = InputDiagnostics.shared.faultReasons.count == saved
            keyboard.testingSnapshotFailure(.staleContext)
            checks["expected_context_cancellation_is_not_a_fault"] = InputDiagnostics.shared.faultReasons.count == saved
        }
        do {
            let keyboard = service()
            keyboard.testingEnableContextCapture()
            keyboard.testingPrepareKeyRead(deadline: .greatestFiniteMagnitude)
            keyboard.testingMarkPrimaryCapture()
            keyboard.testingReleaseKey()
            checks["keyup_does_not_queue_duplicate_of_primary_capture"] = keyboard.testingRequestedContextRevisions.isEmpty
            keyboard.testingCompleteContextCapture(revision: 0, failure: .deadlineExceeded)
            checks["failed_primary_capture_releases_slot"] = !keyboard.testingContextCapturePending
            keyboard.testingReleaseKey()
            checks["release_can_retry_after_primary_finished_within_original_budget"] = keyboard.testingRequestedContextRevisions.count == 1
        }
        do {
            let keyboard = service()
            keyboard.testingEnableContextCapture()
            keyboard.testingPrepareKeyRead(deadline: .greatestFiniteMagnitude)
            keyboard.testingReleaseKey()
            let first = keyboard.testingRequestedContextRevisions.first ?? -1
            checks["key_release_requests_missing_baseline"] = keyboard.testingRequestedContextRevisions.count == 1 &&
                keyboard.testingContextCapturePending && !keyboard.testingHasCurrentContext
            keyboard.testingReleaseKey()
            checks["repeated_releases_coalesce_while_capture_is_pending"] = keyboard.testingRequestedContextRevisions.count == 1
            keyboard.testingCompleteContextCapture(revision: first)
            checks["release_readback_bootstraps_current_anchor"] = keyboard.testingHasCurrentContext && !keyboard.testingContextCapturePending
            checks["baseline_capture_never_starts_mutation_or_replay"] = !keyboard.hasPendingInput &&
                keyboard.store.pendingInput == 0 && keyboard.store.outstandingInput == 0
            keyboard.testingReleaseKey()
            checks["release_preserves_existing_anchor_without_another_read"] = keyboard.testingRequestedContextRevisions.count == 1 && keyboard.testingHasCurrentContext
            keyboard.testingCompleteContextCapture(revision: first, failure: .deadlineExceeded)
            checks["failed_refresh_invalidates_previous_anchor"] = !keyboard.testingHasCurrentContext
            checks["transient_refresh_keeps_only_manual_proposal"] = keyboard.testingHasManualProposal && !keyboard.hasPendingInput
            keyboard.testingCompleteContextCapture(revision: first, failure: .deadlineExceeded)
            checks["repeated_timeout_keeps_manual_proposal"] = keyboard.testingHasManualProposal
            keyboard.testingInvalidateContext()
            checks["revision_change_invalidates_manual_proposal"] = !keyboard.testingHasManualProposal
            keyboard.testingPrepareKeyRead(deadline: .greatestFiniteMagnitude)
            keyboard.testingReleaseKey()
            let next = keyboard.testingRequestedContextRevisions.last ?? -1
            keyboard.testingCompleteContextCapture(revision: first)
            checks["old_capture_cannot_publish_after_revision_change"] = !keyboard.testingHasCurrentContext
            checks["old_completion_cannot_cancel_new_capture"] = keyboard.testingContextCapturePending && next != first
            keyboard.testingCompleteContextCapture(revision: next, contextMatches: false)
            checks["changed_pid_source_or_permissions_rejects_baseline"] = !keyboard.testingHasCurrentContext && !keyboard.testingContextCapturePending
            keyboard.testingReleaseKey()
            keyboard.testingCompleteContextCapture(revision: next, failure: .deadlineExceeded)
            checks["expired_capture_releases_coalescing_slot"] = !keyboard.testingHasCurrentContext && !keyboard.testingContextCapturePending
            keyboard.testingReleaseKey()
            keyboard.testingCompleteContextCapture(revision: next)
            checks["later_release_recovers_from_expired_baseline_capture"] = keyboard.testingHasCurrentContext &&
                keyboard.testingRequestedContextRevisions.count == 4
        }
        do {
            let keyboard = service()
            keyboard.testingEnableContextCapture()
            keyboard.testingReleaseKey()
            checks["release_without_matching_keydown_does_not_bootstrap"] = keyboard.testingRequestedContextRevisions.isEmpty
            keyboard.testingPrepareKeyRead(inserted: "n", keyCode: 0, deadline: .greatestFiniteMagnitude)
            keyboard.testingReleaseKey(keyCode: 1)
            checks["different_key_release_does_not_bootstrap"] = keyboard.testingRequestedContextRevisions.isEmpty
            keyboard.testingReleaseKey()
            let revision = keyboard.testingRequestedContextRevisions.first ?? -1
            keyboard.testingCompleteContextCapture(revision: revision, text: "ghbdt")
            checks["pre_insertion_readback_never_becomes_anchor"] = !keyboard.testingHasCurrentContext && keyboard.testingContextCapturePending
            keyboard.testingCompleteContextCapture(revision: revision, text: "ghbdtn", selection: NSRange(location: 5, length: 0))
            checks["text_without_matching_caret_never_becomes_anchor"] = !keyboard.testingHasCurrentContext && keyboard.testingContextCapturePending
            keyboard.testingCompleteContextCapture(revision: revision, text: "ghbdtn")
            checks["ready_readback_after_stale_values_becomes_anchor"] = keyboard.testingHasCurrentContext && !keyboard.testingContextCapturePending
            checks["readiness_baseline_does_not_authorize_a_write"] = !keyboard.hasPendingInput && keyboard.store.pendingInput == 0 && keyboard.store.outstandingInput == 0
            keyboard.testingInvalidateContext()
            keyboard.testingPrepareKeyRead(deadline: ProcessInfo.processInfo.systemUptime - 1)
            keyboard.testingReleaseKey()
            checks["release_never_renews_expired_keydown_budget"] = keyboard.testingRequestedContextRevisions.count == 1
            let deadline: TimeInterval = .greatestFiniteMagnitude / 2
            keyboard.testingPrepareKeyRead(deadline: deadline)
            keyboard.testingReleaseKey()
            let next = keyboard.testingRequestedContextRevisions.last ?? -1
            let requestedBeforeExpiry = keyboard.testingContextCapturePending
            keyboard.testingCompleteContextCapture(revision: next, now: .greatestFiniteMagnitude)
            checks["late_ready_readback_cannot_publish_anchor"] = requestedBeforeExpiry &&
                !keyboard.testingHasCurrentContext && !keyboard.testingContextCapturePending
        }
        do {
            // Universal mode U3: the typed buffer follows delivered events through handle().
            let keyboard = service()
            func key(_ code: Int, _ flags: CGEventFlags = []) {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
                event.flags = flags
                keyboard.testingHandle(.keyDown, event)
            }
            if IsSecureEventInputEnabled() {
                key(5)
                checks["typed_secure_input_resets"] = keyboard.testingTyped.lastReset == .secureInput
            } else {
                key(5) // G key: a letter in ABC/US and Russian layouts
                checks["typed_letter_follows_current_layout"] = InputSources.language != nil ?
                    keyboard.testingTyped.text.count == 1 : keyboard.testingTyped.lastReset == .untrackedKey
                key(51)
                checks["typed_backspace_removes_letter"] = keyboard.testingTyped.text.isEmpty
                key(5); key(36)
                checks["typed_return_resets_and_anchors"] = keyboard.testingTyped.text.isEmpty &&
                    keyboard.testingTyped.anchoredStart && keyboard.testingTyped.lastReset == .newline
                key(5); key(123)
                checks["typed_arrow_resets"] = keyboard.testingTyped.text.isEmpty && keyboard.testingTyped.lastReset == .navigation
                key(5); key(9, .maskCommand)
                checks["typed_shortcut_resets"] = keyboard.testingTyped.lastReset == .shortcut
                key(5)
                keyboard.testingHandle(.leftMouseDown, CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                    mouseCursorPosition: .zero, mouseButton: .left)!)
                checks["typed_click_resets"] = keyboard.testingTyped.lastReset == .pointer
                key(5)
                let before = keyboard.testingTyped
                keyboard.testingHandle(.keyUp, CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: false)!)
                keyboard.testingHandle(.scrollWheel, CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                    wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!)
                checks["typed_key_up_and_scroll_keep_buffer"] = keyboard.testingTyped == before
            }
        }
        do {
            // Universal mode U4: keystroke targets are identified by process only.
            let first = EditorSnapshot.keystrokeTarget(pid: 4242, application: "dev.example")
            let second = EditorSnapshot.keystrokeTarget(pid: 4242, application: "dev.example")
            checks["keystroke_targets_same_process_match"] = AccessibilityEditor.sameTarget(first, second)
            checks["keystroke_targets_other_process_differ"] =
                !AccessibilityEditor.sameTarget(first, .keystrokeTarget(pid: 4243, application: "dev.example"))
            var pinned = first; pinned.keystrokes = false
            checks["keystroke_target_never_matches_pinned_field"] = !AccessibilityEditor.sameTarget(first, pinned)
            let keyboard = service()
            checks["universal_mode_on_by_default"] = keyboard.store.universalInput
        }
        do {
            let keyboard = service()
            keyboard.testingEnableContextCapture()
            keyboard.testingCaptureAfterEvent()
            checks["universal_without_plain_paste_does_not_capture_legacy_context"] = keyboard.testingRequestedContextRevisions.isEmpty
            keyboard.store.universalInput = false
            keyboard.testingCaptureAfterEvent()
            checks["legacy_mode_keeps_event_context_capture"] = keyboard.testingRequestedContextRevisions.count == 1
            keyboard.store.universalInput = true
        }
        do {
            let after = EditorSnapshot(element: AXUIElementCreateApplication(-1), window: nil,
                document: nil, pid: -1, application: "com.apple.TextEdit", text: "привет ",
                selection: NSRange(location: 7, length: 0))
            var reads = 0
            let result = AccessibilityEditor.ReplacementResult.verified(after).settledSnapshot {
                reads += 1; return nil // The old operation's read budget is exhausted.
            }
            checks["verified_readback_survives_exhausted_second_read_budget"] = reads == 0 &&
                result.map { after.matchesContent($0) && AccessibilityEditor.sameTarget(after, $0) } == true
            let missing = AccessibilityEditor.ReplacementResult.notApplied.settledSnapshot { reads += 1; return nil }
            checks["unverified_result_still_requires_fresh_read"] = reads == 1 && missing == nil
        }
        do {
            let keyboard = service()
            keyboard.testingPrepareKeyRead(deadline: .greatestFiniteMagnitude)
            keyboard.testingCompleteContextCapture(revision: 0)
            keyboard.testingCompleteContextCapture(revision: 0, failure: .deadlineExceeded)
            checks["manual_timeout_proposal_present"] = keyboard.testingHasManualProposal
            keyboard.testingCompleteContextCapture(revision: 0, failure: .secureInput)
            checks["secure_failure_removes_manual_proposal"] = !keyboard.testingHasManualProposal
        }
        do {
            // Snippets (S7): migration of former rules, derived rules, persistence, damaged file.
            let suite = "dev.layoutpilot.snippets-probe.\(UUID().uuidString)"
            guard let isolated = UserDefaults(suiteName: suite) else { exit(2) }
            defer { isolated.removePersistentDomain(forName: suite) }
            var withRule = Settings(); withRule.rules = [UserRule(source: "спс", replacement: "спасибо")]
            isolated.set(try JSONEncoder().encode(withRule), forKey: "settings.v1")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("typetune-probe-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let store = Store(defaults: isolated, snippetsURL: file)
            let ruleID = withRule.rules[0].id
            checks["snippets_rules_migrated_with_ids"] = store.snippets.snippets.map(\.abbreviation) == ["спс"] &&
                store.snippets.snippets.first?.id == ruleID && FileManager.default.fileExists(atPath: file.path)
            checks["snippets_derived_rules_match_migrated"] = store.settings.rules.map(\.id) == [ruleID] &&
                store.settings.rules.first?.replacement == "спасибо"
            let address = Snippet(abbreviation: ";адр", text: "г. Москва\nул. Тверская")
            checks["snippets_saved_and_usable"] = store.saveSnippet(address).isEmpty && store.usableSnippets.count == 2
            checks["snippets_immediate_multiline_not_a_rule"] = store.settings.rules.map(\.id) == [ruleID]
            checks["snippets_duplicate_refused"] = store.saveSnippet(Snippet(abbreviation: "СПС", text: "x")) == [.duplicate(of: ruleID)] &&
                store.snippets.snippets.count == 2
            store.deleteSnippet(ruleID)
            checks["snippets_delete_removes_derived_rule"] = store.settings.rules.isEmpty && store.usableSnippets.map(\.id) == [address.id]
            checks["snippets_persist_across_launch"] = Store(defaults: isolated, snippetsURL: file).snippets.snippets == [address]
            try Data("{".utf8).write(to: file)
            let broken = Store(defaults: isolated, snippetsURL: file)
            _ = broken.saveSnippet(Snippet(abbreviation: ";x", text: "y"))
            checks["snippets_damaged_file_never_overwritten"] = !broken.snippetsStorageAvailable &&
                (try? Data(contentsOf: file)) == Data("{".utf8)
        }
        if let source = CGEventSource(stateID: .privateState), let events = SnippetEditor.pasteEvents(source: source) {
            checks["snippet_paste_complete_modifier_frame"] = events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged] &&
                events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [55, 9, 9, 55] &&
                events.prefix(3).allSatisfy { $0.flags.rawValue == CGEventFlags.maskCommand.rawValue | 0x8 } &&
                events.last?.flags.rawValue == 0
        } else { checks["snippet_paste_complete_modifier_frame"] = false }
        checks["settings_bytes_preserved"] = defaults.data(forKey: "settings.v1") == settings
        let passed = checks.values.allSatisfy { $0 }
        let output: [String: Any] = ["passed": passed, "checks": checks,
            "productionControllerUsed": true, "diagnosticsAdapterStubbed": true, "platformInputsStubbed": true,
            "nativeEventsPosted": false, "eventTapCreated": false, "realFieldsRead": false,
            "standardDefaultsUsed": false, "nativeAcceptance": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if !passed { exit(1) }
    }
}
