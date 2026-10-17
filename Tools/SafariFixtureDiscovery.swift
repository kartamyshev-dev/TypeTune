import AppKit
import ApplicationServices
import Carbon

// Read-only by default. Explicit bounded typing is prepared for separate approval.
// Activation only with explicit native-only flag after own fixture authentication.
// AX writes only in explicit own-fixture probe; never switches sources, reads clipboard or requests access.
private struct ProbeFailure: Error { let reason: String }
private func check(_ ok: Bool, _ reason: String) throws { if !ok { throw ProbeFailure(reason: reason) } }
private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.15)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
private func ax(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
private func neutral() -> Bool {
    let mask: UInt64 = (0x1f << 16) | (1 << 23) | 0x20ff
    let keys: [CGKeyCode] = [54,55,56,57,58,59,60,61,62,63]
    return [CGEventSourceStateID.hidSystemState, .combinedSessionState].allSatisfy { state in
        CGEventSource.flagsState(state).rawValue & mask == 0 &&
        keys.allSatisfy { !CGEventSource.keyState(state, key: $0) }
    }
}
private struct FixtureIdentity {
    let pid: pid_t
    let url: String
    let token: String
    let label: String
    let app: AXUIElement
    let field: AXUIElement
    let window: AXUIElement
    let document: String?
    var requiresFrontmost: Bool

    func verify() throws {
        try check(AXIsProcessTrusted(), "accessibility_not_granted")
        try check(!IsSecureEventInputEnabled() && neutral(), "secure_input_or_active_modifiers")
        guard let target = NSRunningApplication(processIdentifier: pid), target.bundleIdentifier == "com.apple.Safari" else { throw ProbeFailure(reason: "wrong_running_app_identity") }
        if requiresFrontmost {
            guard let front = NSWorkspace.shared.frontmostApplication else { throw ProbeFailure(reason: "no_frontmost") }
            try check(front.processIdentifier == pid && front.bundleIdentifier == "com.apple.Safari", "wrong_frontmost_identity")
        }
        guard let current = ax(attribute(app, kAXFocusedUIElementAttribute)),
              let currentWindow = ax(attribute(current, kAXWindowAttribute)),
              let focusedWindow = ax(attribute(app, kAXFocusedWindowAttribute)) else { throw ProbeFailure(reason: "focused_identity_unavailable") }
        try check(CFEqual(current, field) && CFEqual(currentWindow, window) && CFEqual(focusedWindow, window), "field_or_window_changed")
        try check((attribute(window, kAXDocumentAttribute) as? String) == document, "document_changed")
        let labels = [kAXDescriptionAttribute, kAXTitleAttribute, "AXHelp"]
        try check(labels.contains { (attribute(field, $0) as? String) == label }, "not_own_fixture_field")
        try check((attribute(window, kAXTitleAttribute) as? String)?.contains(token) == true, "window_token_missing")
        var ancestor: AXUIElement? = field
        var seen: [AXUIElement] = []
        var matchedURL = false
        for _ in 0..<24 {
            guard let node = ancestor, !seen.contains(where: { CFEqual($0, node) }) else { break }
            seen.append(node)
            if let raw = attribute(node, kAXURLAttribute) {
                let actual = (raw as? URL)?.absoluteString ?? (raw as? String) ?? ""
                if actual == url { matchedURL = true; break }
            }
            ancestor = ax(attribute(node, kAXParentAttribute))
        }
        try check(matchedURL, "exact_local_fixture_url_unverified")
    }
}
@main private struct SafariFixtureDiscovery {
    static func main() {
        var report: [String: Any] = ["schemaVersion": 1, "eventsPosted": 0,
            "axWrites": 0, "activations": 0, "permissionRequests": 0,
            "clipboardUsed": false, "productionAdapterEnabled": false, "eventCap": 0]
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try check([6,7,8].contains(args.count) && args[0] == "--token" && args[2] == "--pid" && args[4] == "--field", "usage_token_uuid_pid_number_field_plain_or_rich")
            guard let uuid = UUID(uuidString: args[1]), let pid = pid_t(args[3]), pid > 0,
                  ["plain", "rich"].contains(args[5]) else { throw ProbeFailure(reason: "invalid_arguments") }
            let mode = args.count >= 7 ? args[6] : "--read"
            try check(["--read", "--read-background", "--type-wrong", "--type-correct", "--type-seed", "--probe-selected-text"].contains(mode), "invalid_explicit_mode")
            let activateOwn = args.count == 8
            try check(!activateOwn || (args[7] == "--activate-own-fixture" && ["--type-wrong", "--type-correct", "--type-seed", "--probe-selected-text"].contains(mode)), "activation_only_explicit_native_mode")
            report["mode"] = mode
            let token = "LP-SAFARI-" + uuid.uuidString.lowercased()
            let url = "http://127.0.0.1:18764/?fixture=" + token
            try check(AXIsProcessTrusted() && !IsSecureEventInputEnabled() && neutral(), "permission_secure_or_modifiers")
            guard let target = NSRunningApplication(processIdentifier: pid), target.bundleIdentifier == "com.apple.Safari" else { throw ProbeFailure(reason: "safari_not_requested_running_pid") }
            if mode != "--read-background" && !activateOwn {
                guard let front = NSWorkspace.shared.frontmostApplication,
                      front.processIdentifier == pid, front.bundleIdentifier == "com.apple.Safari" else { throw ProbeFailure(reason: "safari_not_requested_frontmost_pid") }
            }
            let app = AXUIElementCreateApplication(pid)
            guard let field = ax(attribute(app, kAXFocusedUIElementAttribute)),
                  let window = ax(attribute(field, kAXWindowAttribute)) else { throw ProbeFailure(reason: "no_focused_field_window") }
            var identity = FixtureIdentity(pid: pid, url: url, token: token, label: token + " " + args[5],
                app: app, field: field, window: window, document: attribute(window, kAXDocumentAttribute) as? String, requiresFrontmost: mode != "--read-background" && !activateOwn)
            try identity.verify()
            if activateOwn {
                // Authenticate the pinned own background field/window before the
                // only activation attempt. Never activates an arbitrary Safari tab.
                try check(CGPreflightPostEventAccess(), "activation_requires_existing_post_access")
                try identity.verify()
                try check((0..<128).allSatisfy { raw in
                    let key = CGKeyCode(raw)
                    return !CGEventSource.keyState(.hidSystemState, key: key) && !CGEventSource.keyState(.combinedSessionState, key: key)
                }, "activation_requires_neutral_keyboard")
                report["activationAttempts"] = 1
                try check(target.activate(options: []), "own_fixture_activation_rejected")
                let deadline = ProcessInfo.processInfo.systemUptime + 1.0
                while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                    try identity.verify() // still pinned; no retry for changed field/window/URL
                    try check(ProcessInfo.processInfo.systemUptime < deadline, "own_fixture_activation_ack_timeout")
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: min(0.02, max(0, deadline - ProcessInfo.processInfo.systemUptime))))
                }
                try check(ProcessInfo.processInfo.systemUptime <= deadline, "own_fixture_activation_ack_timeout")
                identity.requiresFrontmost = true
                try identity.verify()
                report["activations"] = 1
            }
            let role = attribute(field, kAXRoleAttribute) as? String ?? "unavailable"
            let subrole = attribute(field, kAXSubroleAttribute) as? String ?? ""
            try check(subrole != kAXSecureTextFieldSubrole, "secure_field")
            // No text read until URL/token/PID/window/field ownership is established.
            try identity.verify()
            guard let text = attribute(field, kAXValueAttribute) as? String, text.utf16.count <= 4096 else { throw ProbeFailure(reason: "bounded_value_unavailable") }
            let allowed = ["", "\n", "ghbdtn", "привет", "ghbdtn ", "привет ", "hello ", "первая🙂вторая"]
            try check(allowed.contains(text), "not_whitelisted_synthetic_fixture_text")
            guard let rawRange = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { throw ProbeFailure(reason: "range_unavailable") }
            var range = CFRange()
            try check(AXValueGetValue(rawRange as! AXValue, .cfRange, &range) && range.location >= 0 && range.length >= 0 && range.location <= text.utf16.count && range.length <= text.utf16.count - range.location, "invalid_range")
            if mode == "--type-wrong" || mode == "--type-correct" || mode == "--type-seed" {
                // Empty field only: no clear, selection write, delete, paste or command.
                try check(role == kAXTextAreaRole && text.isEmpty && range.location == 0 && range.length == 0, "typing_requires_empty_textarea_caret_zero")
                try check(CGPreflightPostEventAccess(), "post_access_not_previously_granted")
                guard let source = CGEventSource(stateID: .privateState) else { throw ProbeFailure(reason: "event_source_unavailable") }
                let keys: [CGKeyCode] = mode == "--type-seed" ? [5,4,11,2,17,45] : (mode == "--type-wrong" ? [5,4,11,2,17,45,49] : [4,14,37,37,31,49])
                try check(keys.count * 2 <= 14 && keys.allSatisfy { [5,4,11,2,17,45,49,14,37,31].contains($0) }, "event_plan_not_whitelisted")
                report["eventCap"] = 14
                var frames = 0
                var ownedDown: CGKeyCode?
                defer { report["eventsPosted"] = frames; report["ownedKeyReleasePending"] = ownedDown != nil }
                let syntheticStates: Set<String> = Set(["ghbdtn ", "привет ", "hello "].flatMap { word in
                    (0...word.count).map { String(word.prefix($0)) }
                })
                func keyboardNeutralExceptOwned() -> Bool {
                    neutral() && (0..<128).allSatisfy { raw in
                        let key = CGKeyCode(raw)
                        return key == ownedDown || (!CGEventSource.keyState(.hidSystemState, key: key) && !CGEventSource.keyState(.combinedSessionState, key: key))
                    }
                }
                func sourceIsEnglish() -> Bool {
                    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                          let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
                    let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
                    return ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(identifier)
                }
                func syntheticState() throws -> (String, CFRange) {
                    try identity.verify()
                    guard let value = attribute(field, kAXValueAttribute) as? String,
                          syntheticStates.contains(value), let raw = attribute(field, kAXSelectedTextRangeAttribute),
                          CFGetTypeID(raw) == AXValueGetTypeID() else { throw ProbeFailure(reason: "typing_state_not_own_synthetic") }
                    var selected = CFRange()
                    try check(AXValueGetValue(raw as! AXValue, .cfRange, &selected) && selected.location >= 0 && selected.length >= 0 && selected.location <= value.utf16.count && selected.length <= value.utf16.count - selected.location, "typing_range_invalid")
                    try identity.verify()
                    return (value, selected)
                }
                for key in keys {
                    for down in [true, false] {
                        try check(frames < 14 && CGPreflightPostEventAccess() && keyboardNeutralExceptOwned(), "typing_access_keyboard_or_cap_changed")
                        let state = try syntheticState()
                        if down {
                            try check(ownedDown == nil && sourceIsEnglish(), "typing_requires_neutral_english_source")
                            try check(state.1.length == 0 && state.1.location == state.0.utf16.count, "typing_requires_end_caret")
                        } else { try check(ownedDown == key, "unowned_key_release") }
                        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw ProbeFailure(reason: "event_creation_failed") }
                        event.flags = []
                        // Last identity/security barrier immediately before each single post.
                        try identity.verify()
                        try check(CGPreflightPostEventAccess() && keyboardNeutralExceptOwned(), "typing_last_barrier_failed")
                        event.post(tap: .cghidEventTap)
                        frames += 1
                        ownedDown = down ? key : nil
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
                    }
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
                let final = try syntheticState()
                try check(keyboardNeutralExceptOwned() && ownedDown == nil, "typing_final_keyboard_not_neutral")
                report.merge(["success": true, "fixtureURL": url, "pid": Int(pid), "field": args[5],
                    "deliveryFramesPosted": frames, "finalSyntheticText": final.0,
                    "selectionLocation": final.1.location, "selectionLength": final.1.length,
                    "functionalAcceptance": false, "returnAllowed": false,
                    "writeCapabilityVerified": false], uniquingKeysWith: { _, b in b })
            } else if mode == "--probe-selected-text" {
                func guarded() throws {
                    try identity.verify()
                    try check((0..<128).allSatisfy { raw in
                        let key = CGKeyCode(raw)
                        return !CGEventSource.keyState(.hidSystemState, key: key) && !CGEventSource.keyState(.combinedSessionState, key: key)
                    }, "ax_probe_requires_neutral_keyboard")
                }
                func readState() throws -> (String, CFRange) {
                    try guarded()
                    guard let value = attribute(field, kAXValueAttribute) as? String,
                          ["ghbdtn", "привет"].contains(value),
                          let raw = attribute(field, kAXSelectedTextRangeAttribute),
                          CFGetTypeID(raw) == AXValueGetTypeID() else { throw ProbeFailure(reason: "ax_probe_state_unverified") }
                    var selection = CFRange()
                    try check(AXValueGetValue(raw as! AXValue, .cfRange, &selection), "ax_probe_range_unavailable")
                    try guarded()
                    return (value, selection)
                }
                func matches(_ range: CFRange, _ location: Int, _ length: Int) -> Bool {
                    range.location == location && range.length == length
                }
                try guarded()
                try check(role == kAXTextAreaRole && text == "ghbdtn" && matches(range, 6, 0), "ax_probe_wrong_baseline_zero_writes")
                var selectionOwned = false
                var writes = 0
                func writeSelection(_ location: Int, _ length: Int) -> Bool {
                    var selection = CFRange(location: location, length: length)
                    guard let value = AXValueCreate(.cfRange, &selection) else { return false }
                    writes += 1
                    return AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success
                }
                defer {
                    // Never rewrite value to rollback. Restore only our unchanged
                    // baseline selection while the exact target is still owned.
                    if selectionOwned, let state = try? readState(), state.0 == "ghbdtn", matches(state.1, 0, 6) {
                        if (try? guarded()) != nil {
                            report["selectionRollbackAttempted"] = true
                            let restored = writeSelection(6, 0)
                            if let final = try? readState() {
                                report["selectionRollbackVerified"] = restored && final.0 == "ghbdtn" && matches(final.1, 6, 0)
                            }
                        }
                    }
                    report["axWrites"] = writes // attempted setters, never text rollback
                }
                let before = try readState()
                try check(before.0 == "ghbdtn" && matches(before.1, 6, 0), "ax_probe_baseline_changed_zero_writes")
                var writable = DarwinBoolean(false)
                try check(AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &writable) == .success && writable.boolValue, "ax_probe_selected_text_not_settable")
                try guarded()
                selectionOwned = true // setter failure may still have changed selection
                try check(writeSelection(0, 6), "ax_probe_selection_set_failed")
                let selectionDeadline = ProcessInfo.processInfo.systemUptime + 0.15
                while true {
                    let selected = try readState()
                    try check(ProcessInfo.processInfo.systemUptime <= selectionDeadline, "ax_probe_selection_ack_timeout")
                    try check(selected.0 == "ghbdtn", "ax_probe_text_changed_during_selection")
                    if matches(selected.1, 0, 6) { break }
                    try check(matches(selected.1, 6, 0), "ax_probe_unexpected_selection")
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.003))
                }
                try guarded()
                try check((attribute(field, kAXSelectedTextAttribute) as? String) == "ghbdtn", "ax_probe_selected_text_mismatch")
                let selected = try readState()
                try check(selected.0 == "ghbdtn" && matches(selected.1, 0, 6), "ax_probe_lost_owned_selection")
                try guarded()
                writes += 1
                try check(AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, "привет" as CFString) == .success, "ax_probe_replacement_set_failed")
                let replacementDeadline = ProcessInfo.processInfo.systemUptime + 0.15
                while true {
                    let final = try readState()
                    try check(ProcessInfo.processInfo.systemUptime <= replacementDeadline, "ax_probe_replacement_ack_timeout")
                    if final.0 == "привет" && matches(final.1, 6, 0) { break }
                    try check((final.0 == "ghbdtn" && matches(final.1, 0, 6)) || (final.0 == "привет" && matches(final.1, 0, 6)), "ax_probe_unexpected_replacement_state")
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.003))
                }
                selectionOwned = false
                report.merge(["success": true, "pid": Int(pid), "fixtureURL": url, "field": args[5],
                    "eventCap": 0, "selectedTextReplacementVerified": true,
                    "writeCapabilityVerified": true, "selectionLocation": 6, "selectionLength": 0,
                    "functionalAcceptance": false], uniquingKeysWith: { _, b in b })
            } else {
            var selectedTextWritable = DarwinBoolean(false), selectionWritable = DarwinBoolean(false)
            let stStatus = AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &selectedTextWritable)
            let rangeStatus = AXUIElementIsAttributeSettable(field, kAXSelectedTextRangeAttribute as CFString, &selectionWritable)
            try identity.verify()
            report.merge(["success": true, "pid": Int(pid), "fixtureURL": url, "field": args[5],
                "role": role, "subrole": subrole, "syntheticValueVerified": true,
                "utf16Count": text.utf16.count, "selectionLocation": range.location, "selectionLength": range.length,
                "selectedTextSettable": stStatus == .success && selectedTextWritable.boolValue,
                "selectionSettable": rangeStatus == .success && selectionWritable.boolValue,
                "postPermissionAlreadyGranted": CGPreflightPostEventAccess(),
                "writeCapabilityVerified": false, "eventCap": 0,
                "futureWrongWordFrameCap": 14, "returnAllowed": false], uniquingKeysWith: { _, b in b })
            }
        } catch {
            report["success"] = false
            report["failure"] = (error as? ProbeFailure)?.reason ?? "unexpected_error"
        }
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if report["success"] as? Bool != true { exit(2) }
    }
}
