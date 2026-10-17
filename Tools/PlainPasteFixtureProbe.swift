import AppKit
import ApplicationServices
import Carbon

// Deliberately restricted to the already-open isolated LP-CODEX-001 Chrome page.
// No conversation controls, Return events, arbitrary payloads, or clipboard logging.
private struct ProbeFailure: Error { let reason: String }
private func require(_ value: @autoclosure () -> Bool, _ reason: String) throws {
    if !value() { throw ProbeFailure(reason: reason) }
}
private func pause(_ value: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: value)) }
private let fixtureURL = "http://127.0.0.1:18763/?fixture=LP-CODEX-001"
private let syntheticText = "первая\nвторая\tстрока"
private let modifierKeys: [CGKeyCode] = [54, 55, 56, 60, 58, 61, 59, 62, 57, 63]
private let modifierMask: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]
private func modifiersNeutral() -> Bool {
    [.hidSystemState, .combinedSessionState].allSatisfy { state in
        CGEventSource.flagsState(state).intersection(modifierMask).isEmpty &&
            CGEventSource.flagsState(state).rawValue & 0x207f == 0 &&
            modifierKeys.allSatisfy { !CGEventSource.keyState(state, key: $0) }
    }
}
private var axErrors: [String: Int] = [:]
private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.15)
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    if status != .success { axErrors["\(key):\(status.rawValue)", default: 0] += 1 }
    return status == .success ? value : nil
}
private func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

// Exact item/type/data snapshots remain in RAM. No values, hashes, or type names
// from the original clipboard enter the report, diagnostics, or filesystem.
private struct ClipboardSnapshot: Equatable {
    struct Item: Equatable { var types: [NSPasteboard.PasteboardType]; var data: [Data] }
    var items: [Item]
    var generation: Int
    static func == (left: ClipboardSnapshot, right: ClipboardSnapshot) -> Bool { left.items == right.items }
    static func capture(_ pasteboard: NSPasteboard) throws -> ClipboardSnapshot {
        let generation = pasteboard.changeCount
        var total = 0
        var result: [Item] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var bytes: [Data] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { throw ProbeFailure(reason: "clipboard_representation_unavailable") }
                total += data.count
                try require(total <= 64 * 1024 * 1024, "clipboard_snapshot_memory_bound")
                bytes.append(data)
            }
            result.append(Item(types: item.types, data: bytes))
        }
        try require(pasteboard.changeCount == generation, "clipboard_changed_during_snapshot")
        return ClipboardSnapshot(items: result, generation: generation)
    }
    func write(to pasteboard: NSPasteboard) -> Bool {
        let copies = items.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for (type, data) in zip(item.types, item.data) { copy.setData(data, forType: type) }
            return copy
        }
        pasteboard.clearContents()
        return copies.isEmpty || pasteboard.writeObjects(copies)
    }
}

@main private struct PlainPasteFixtureProbe {
    static func main() {
        var report: [String: Any] = ["fixtureURL": fixtureURL, "expected": syntheticText,
            "clipboardOriginalLogged": false, "postedReturn": false, "postedControlPayload": false]
        var board: NSPasteboard?
        var original: ClipboardSnapshot?
        var ownedGeneration: Int?
        var trials: [[String: Any]] = []
        func restoreClipboard() {
            guard let board, let original, let ownedGeneration else { return }
            let stillOurs = board.changeCount == ownedGeneration
            report["clipboardStillOwned"] = stillOurs
            guard stillOurs else {
                report["clipboardRestorationSkippedForNewerChange"] = true
                report["clipboardRestored"] = false
                return
            }
            let written = original.write(to: board)
            let matched = written && ((try? ClipboardSnapshot.capture(board)) == original)
            report["clipboardRestored"] = matched
            report["clipboardOriginalTypesAndDataVerified"] = matched
        }
        var failure: String?
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            var clipboardSettleMilliseconds = 0
            var settleMilliseconds = 800
            var repeatCount = 1
            var plainClipboardOnly = false
            var expectation = "plain", sourceName = "private", nativeMatchStyle = false, formattedControl = false, holdPastTimeout = false, neutralOnly = false
            var seen = Set<String>(), index = 0
            while index < args.count {
                let option = args[index]
                try require(seen.insert(option).inserted, "duplicate_argument")
                if option == "--neutral-only" { neutralOnly = true; index += 1; continue }
                if option == "--hold-past-timeout" { holdPastTimeout = true; index += 1; continue }
                if option == "--formatted-control" { formattedControl = true; index += 1; continue }
                if option == "--native-match-style" { nativeMatchStyle = true; index += 1; continue }
                if option == "--plain-clipboard-only" { plainClipboardOnly = true; index += 1; continue }
                try require(["--expect", "--source", "--settle-ms", "--clipboard-settle-ms", "--repeat"].contains(option) && index + 1 < args.count, "invalid_arguments")
                if option == "--expect" { expectation = args[index + 1] }
                else if option == "--repeat" {
                    guard let value = Int(args[index + 1]), (1...20).contains(value) else { throw ProbeFailure(reason: "invalid_repeat_count") }; repeatCount = value
                }
                else if option == "--clipboard-settle-ms" {
                    guard let value = Int(args[index + 1]), (0...1000).contains(value) else { throw ProbeFailure(reason: "invalid_clipboard_settle_interval") }; clipboardSettleMilliseconds = value
                } else if option == "--settle-ms" {
                    guard let value = Int(args[index + 1]), (800...5000).contains(value) else { throw ProbeFailure(reason: "invalid_settle_interval") }; settleMilliseconds = value
                } else { sourceName = args[index + 1] }
                index += 2
            }
            try require(["plain", "passthrough"].contains(expectation) && ["private", "hid"].contains(sourceName), "invalid_argument_value")
            try require(!(nativeMatchStyle && formattedControl) && !(holdPastTimeout && (nativeMatchStyle || formattedControl)), "conflicting_modes")
            report["holdPastTimeout"] = holdPastTimeout
            report["formattedControl"] = formattedControl
            report["expectation"] = expectation
            report["nativeMatchStyle"] = nativeMatchStyle
            report["eventSource"] = sourceName
            report["repeatRequested"] = repeatCount
            // passthrough describes the caller's intended setup; text equality
            // cannot by itself establish which application's handler ran.
            report["handlerIdentityProven"] = false
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_or_secure_input")
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
                throw ProbeFailure(reason: "chrome_not_running")
            }
            _ = app.activate(options: []); pause(0.5)
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "fixture_host_not_frontmost")
            let application = AXUIElementCreateApplication(app.processIdentifier)
            guard let field = element(attribute(application, kAXFocusedUIElementAttribute)),
                  let window = element(attribute(field, kAXWindowAttribute)) else { throw ProbeFailure(reason: "no_focused_field") }
            var guardChecks = 0
            func authenticated() throws {
                try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_changed")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && app.bundleIdentifier == "com.google.Chrome", "focus_changed")
                guard let current = element(attribute(application, kAXFocusedUIElementAttribute)),
                      let currentWindow = element(attribute(current, kAXWindowAttribute)) else { throw ProbeFailure(reason: "focus_unavailable") }
                try require(CFEqual(current, field) && CFEqual(currentWindow, window), "field_or_window_changed")
                let description = attribute(field, kAXDescriptionAttribute) as? String
                try require(description == "LP-CODEX-001 plain" || description == "LP-CODEX-001 rich", "not_fixture_field")
                var ancestor: AXUIElement? = field
                var matched = false
                for _ in 0..<20 {
                    guard let current = ancestor else { break }
                    if let raw = attribute(current, kAXURLAttribute) {
                        let url = (raw as? URL)?.absoluteString ?? (raw as? String) ?? ""
                        if url == fixtureURL { matched = true; break }
                    }
                    ancestor = element(attribute(current, kAXParentAttribute))
                }
                try require(matched, "not_isolated_fixture_url")
                guardChecks += 1
            }
            func snapshot() throws -> (text: String, selection: CFRange) {
                try authenticated()
                guard let text = attribute(field, kAXValueAttribute) as? String, text.utf16.count < 256 else {
                    throw ProbeFailure(reason: "fixture_value_unavailable")
                }
                var selection = CFRange()
                guard let raw = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID(),
                      AXValueGetValue(raw as! AXValue, .cfRange, &selection) else { throw ProbeFailure(reason: "fixture_selection_unavailable") }
                return (text, selection)
            }
            let before = try snapshot()
            if neutralOnly {
                let report:[String:Any] = ["mode":"neutral-only", "fixtureURL":fixtureURL,
                    "modifiersNeutral":modifiersNeutral(), "postedEvents":0,"clipboardTouched":false,
                    "hidModifierFlags": CGEventSource.flagsState(.hidSystemState).rawValue,
                    "sessionModifierFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
                    "heldModifierKeyCodes": modifierKeys.filter { CGEventSource.keyState(.hidSystemState,key:$0) || CGEventSource.keyState(.combinedSessionState,key:$0) }.map(Int.init)]
                print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self));return
            }
            try require(["", "\n", syntheticText, syntheticText + "\n"].contains(before.text), "requires_empty_or_exact_synthetic_fixture")
            try require(modifiersNeutral(), "active_modifiers")
            report["initialModifiersNeutral"] = true
            // Select only this authenticated, known synthetic field. Newline is
            // Chromium's empty-contenteditable sentinel, not user text.
            var replacementRange = CFRange(location: 0, length: before.text == "\n" ? 0 : before.text.utf16.count)
            try authenticated()
            guard let range = AXValueCreate(.cfRange, &replacementRange) else { throw ProbeFailure(reason: "selection_create_failed") }
            try require(AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range) == .success, "selection_write_failed")
            pause(0.05)
            let selected = try snapshot()
            try require(selected.text == before.text && selected.selection.location == replacementRange.location && selected.selection.length == replacementRange.length, "selection_not_verified")
            let pasteboard = NSPasteboard.general
            let saved = try ClipboardSnapshot.capture(pasteboard)
            let savedGeneration = saved.generation
            let styled = NSAttributedString(string: syntheticText, attributes: [.font: NSFont.boldSystemFont(ofSize: 19), .foregroundColor: NSColor.systemRed])
            let html = Data("<b style=\"font-size:19px;color:red\">первая<br>вторая\tстрока</b>".utf8)
            let rtf = try styled.data(from: NSRange(location: 0, length: styled.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            let item = NSPasteboardItem()
            try require(item.setString(syntheticText, forType: .string), "synthetic_clipboard_prepare_failed")
            if !plainClipboardOnly {
                try require(item.setData(rtf, forType: .rtf) && item.setData(html, forType: .html), "synthetic_clipboard_prepare_failed")
            }
            report["syntheticClipboardProfile"] = plainClipboardOnly ? "plain-only" : "plain-rtf-html"
            try authenticated()
            try require(pasteboard.changeCount == savedGeneration, "clipboard_changed_before_write")
            board = pasteboard; original = saved
            pasteboard.clearContents()
            ownedGeneration = pasteboard.changeCount
            let written = pasteboard.writeObjects([item])
            ownedGeneration = pasteboard.changeCount
            try require(written, "synthetic_clipboard_write_failed")
            report["clipboardSettleMilliseconds"] = clipboardSettleMilliseconds
            if clipboardSettleMilliseconds > 0 {
                pause(Double(clipboardSettleMilliseconds) / 1000)
                try authenticated()
                try require(pasteboard.changeCount == ownedGeneration, "clipboard_changed_during_settle")
            }
            var totalPostedEvents = 0
            for trialIndex in 1...repeatCount {
                var trialReport: [String: Any] = ["trial": trialIndex, "passed": false]
                do {
                    let trialBefore: (text: String, selection: CFRange)
                    let trialRange: CFRange
                    if trialIndex == 1 {
                        trialBefore = before
                        trialRange = replacementRange
                    } else {
                        try authenticated()
                        try require(pasteboard.changeCount == ownedGeneration, "clipboard_changed_between_trials")
                        try require(modifiersNeutral(), "active_modifiers_between_trials")
                        trialBefore = try snapshot()
                        try require(["", "\n", syntheticText, syntheticText + "\n"].contains(trialBefore.text), "requires_empty_or_exact_synthetic_fixture")
                        var nextRange = CFRange(location: 0, length: trialBefore.text == "\n" ? 0 : trialBefore.text.utf16.count)
                        try authenticated()
                        guard let range = AXValueCreate(.cfRange, &nextRange) else { throw ProbeFailure(reason: "selection_create_failed") }
                        try require(AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range) == .success, "selection_write_failed")
                        pause(0.05)
                        let selected = try snapshot()
                        try require(selected.text == trialBefore.text && selected.selection.location == nextRange.location && selected.selection.length == nextRange.length, "selection_not_verified")
                        trialRange = nextRange
                    }
                    let eventState: CGEventSourceStateID = sourceName == "hid" ? .hidSystemState : .privateState
                    guard let source = CGEventSource(stateID: eventState) else { throw ProbeFailure(reason: "event_source_unavailable") }
                    var posted = 0
                    var held = CGEventFlags()
                    var ownedModifiers = Set<CGKeyCode>()
                    func emit(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) throws {
                        try authenticated() // exact PID/window/field/URL/trust/Secure Input BEFORE EVERY event
                        try require(pasteboard.changeCount == ownedGeneration, "clipboard_changed_before_event")
                        try require(posted < (nativeMatchStyle ? 8 : (formattedControl ? 4 : 6)), "event_limit")
                        // Do not release or modify keys outside our own bounded frame.
                        // On a failed guard no cleanup events are sent to another field.
                        let foreignHeld = modifierKeys.filter { !ownedModifiers.contains($0) && $0 != key }.filter {
                            CGEventSource.keyState(.hidSystemState, key: $0) || CGEventSource.keyState(.combinedSessionState, key: $0)
                        }
                        if !foreignHeld.isEmpty {
                            trialReport["stoppedBeforeOwnFrame"] = ["keyCode": Int(key), "down": down, "postedEvents": posted]
                            trialReport["externalModifierKeyCodes"] = foreignHeld.map(Int.init)
                        }
                        try require(foreignHeld.isEmpty, "external_modifier_pressed")
                        if !modifier && down {
                            let ready = try snapshot()
                            try require(ready.text == trialBefore.text && ready.selection.location == trialRange.location && ready.selection.length == trialRange.length,
                                        "fixture_changed_before_paste")
                        }
                        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw ProbeFailure(reason: "event_create_failed") }
                        if modifier { event.type = .flagsChanged }
                        event.flags = flags
                        event.post(tap: .cghidEventTap)
                        posted += 1
                        trialReport["postedEvents"] = posted
                        pause(0.025)
                    }
                    // Same physical frame as NativeProbe.tap: side-specific bits and
                    // aggregate flags are added on press and removed in reverse order.
                    let modifiers: [(CGEventFlags, CGKeyCode, UInt64)] = nativeMatchStyle ?
                        [(.maskCommand, 55, 0x8), (.maskAlternate, 58, 0x20), (.maskShift, 56, 0x2)] :
                        (formattedControl ? [(.maskCommand, 55, 0x8)] : [(.maskCommand, 55, 0x8), (.maskShift, 56, 0x2)])
                    try require(modifiersNeutral(), "modifiers_changed_before_frame")
                    for (mask, key, side) in modifiers {
                        held = CGEventFlags(rawValue: held.rawValue | mask.rawValue | side)
                        try emit(key, down: true, flags: held, modifier: true)
                        ownedModifiers.insert(key)
                    }
                    try emit(9, down: true, flags: held)
                    try emit(9, down: false, flags: held)
                    if holdPastTimeout { pause(2.3) }
                    for (mask, key, side) in modifiers.reversed() {
                        held = CGEventFlags(rawValue: held.rawValue & ~(mask.rawValue | side))
                        try emit(key, down: false, flags: held, modifier: true)
                        ownedModifiers.remove(key)
                    }
                    trialReport["settleMilliseconds"] = settleMilliseconds
                    pause(Double(settleMilliseconds) / 1000)
                    try require(modifiersNeutral(), "final_modifiers_not_neutral")
                    trialReport["finalModifiersNeutral"] = true
                    let after = try snapshot()
                    // Log only after verifying the value is entirely synthetic. An
                    // unexpected value is never disclosed, even on the test page.
                    let allowed = ["", "\n", syntheticText, syntheticText + "\n"]
                    try require(allowed.contains(after.text), "unexpected_fixture_result_redacted")
                    trialReport["beforeText"] = trialBefore.text
                    trialReport["afterText"] = after.text
                    trialReport["afterLocation"] = after.selection.location
                    trialReport["afterLength"] = after.selection.length
                    trialReport["postedEvents"] = posted
                    trialReport["guardChecks"] = guardChecks
                    trialReport["targetGuardsPassed"] = true
                    trialReport["clipboardUnchangedByPaste"] = pasteboard.changeCount == ownedGeneration
                    trialReport["passed"] = holdPastTimeout ? (after.text == trialBefore.text && after.selection.location == trialRange.location && after.selection.length == trialRange.length) : (after.text == syntheticText && after.selection.location == syntheticText.utf16.count && after.selection.length == 0)
                    totalPostedEvents += trialReport["postedEvents"] as? Int ?? 0
                    trials.append(trialReport)
                    // Preserve the original single-trial summary keys.
                    for (key, value) in trialReport where key != "trial" { report[key] = value }
                    // Explicit repeat mode stops at the FIRST unsuccessful
                    // text/cursor result. It never retries that failed paste.
                    if trialReport["passed"] as? Bool != true { break }
                } catch {
                    trialReport["error"] = (error as? ProbeFailure)?.reason ?? "unexpected_helper_error"
                    totalPostedEvents += trialReport["postedEvents"] as? Int ?? 0
                    trials.append(trialReport)
                    for (key, value) in trialReport where key != "trial" { report[key] = value }
                    report["totalPostedEvents"] = totalPostedEvents
                    throw error
                }
            }
            report["totalPostedEvents"] = totalPostedEvents
            report["passed"] = trials.count == repeatCount && trials.allSatisfy { ($0["passed"] as? Bool) == true }

        } catch {
            failure = (error as? ProbeFailure)?.reason ?? "unexpected_helper_error"
            report["error"] = failure
            report["passed"] = false
        }
        report["trials"] = trials
        restoreClipboard()
        report["axErrors"] = axErrors
        report["finalModifiersNeutral"] = modifiersNeutral()
        let clipboardOK = (report["clipboardRestored"] as? Bool) == true
        let success = (report["passed"] as? Bool) == true && clipboardOK &&
            (report["clipboardUnchangedByPaste"] as? Bool) == true && (report["finalModifiersNeutral"] as? Bool) == true
        report["passed"] = success
        report["allPassed"] = success
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        exit(success ? 0 : (failure == nil ? 2 : 1))
    }
}
