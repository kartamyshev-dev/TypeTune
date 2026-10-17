import AppKit
import ApplicationServices
import Carbon

private let fixtureURL = "http://127.0.0.1:18763/?fixture=LP-CODEX-001"
private let probeTag: Int64 = 0x4c504f52
private let modifierKeys: [CGKeyCode] = [54, 55, 56, 60, 58, 61, 59, 62, 57, 63]
private let modifierMask: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]
private struct ProbeFailure: Error { let reason: String }
private func require(_ value: @autoclosure () -> Bool, _ reason: String) throws {
    if !value() { throw ProbeFailure(reason: reason) }
}
private func pause(_ value: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: value)) }
private func neutralModifiers() -> Bool {
    [.hidSystemState, .combinedSessionState].allSatisfy { state in
        CGEventSource.flagsState(state).intersection(modifierMask).isEmpty &&
            CGEventSource.flagsState(state).rawValue & 0x207f == 0 &&
            modifierKeys.allSatisfy { !CGEventSource.keyState(state, key: $0) }
    }
}
private func sourceIdentifier(_ source: TISInputSource) -> String? {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}
private func currentIdentifier() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return sourceIdentifier(source)
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

// Both taps are passive. Foreign events are discarded before any keycode or
// Unicode read; even aggregate foreign input counts are deliberately absent.
private final class Trace {
    let ownPID = Int64(ProcessInfo.processInfo.processIdentifier)
    var records: [[String: Any]] = []
    var disabled = false
    var overflow = false
}
private final class TapContext {
    let trace: Trace
    let location: String
    init(trace: Trace, location: String) { self.trace = trace; self.location = location }
}
private let passiveCallback: CGEventTapCallBack = { _, type, event, raw in
    guard let raw else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(raw).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.trace.disabled = true
        return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUnixProcessID) == context.trace.ownPID,
          event.getIntegerValueField(.eventSourceUserData) == probeTag else {
        return Unmanaged.passUnretained(event)
    }
    guard context.trace.records.count < 64 else {
        context.trace.overflow = true
        return Unmanaged.passUnretained(event)
    }
    context.trace.records.append(["location": context.location, "type": type.rawValue,
        "keyCode": event.getIntegerValueField(.keyboardEventKeycode),
        "sourceStateID": event.getIntegerValueField(.eventSourceStateID), "flags": event.flags.rawValue,
        "timestampNanoseconds": event.timestamp])
    return Unmanaged.passUnretained(event)
}

@main private struct InputOriginFixtureProbe {
    static func main() {
        var report: [String: Any] = ["fixtureURL": fixtureURL, "tag": probeTag,
            "correctionExpected": NSNull(), "notProofOfOriginalCodeFilter": true,
            "foreignInputLogged": false, "unicodeReadByTaps": false]
        let trace = Trace()
        var oldSource: TISInputSource?
        var oldIdentifier: String?
        var sourceTouched = false
        var passed = false
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try require(args == ["--source", "private"] || args == ["--source", "hid"], "usage_source_private_or_hid_required")
            let sourceName = args[1]
            let sourceState: CGEventSourceStateID = sourceName == "private" ? .privateState : .hidSystemState
            report["requestedSource"] = sourceName
            report["requestedSourceStateID"] = sourceState.rawValue
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_or_secure_input")
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { throw ProbeFailure(reason: "chrome_not_running") }
            _ = app.activate(options: []); pause(0.5)
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "fixture_host_not_frontmost")
            let application = AXUIElementCreateApplication(app.processIdentifier)
            guard let field = element(attribute(application, kAXFocusedUIElementAttribute)),
                  let window = element(attribute(field, kAXWindowAttribute)) else { throw ProbeFailure(reason: "no_focused_field") }
            var guards = 0
            func authenticated() throws {
                try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_changed")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && app.bundleIdentifier == "com.google.Chrome", "focus_changed")
                guard let focused = element(attribute(application, kAXFocusedUIElementAttribute)),
                      let focusedWindow = element(attribute(focused, kAXWindowAttribute)) else { throw ProbeFailure(reason: "focus_unavailable") }
                try require(CFEqual(field, focused) && CFEqual(window, focusedWindow), "field_or_window_changed")
                let label = attribute(field, kAXDescriptionAttribute) as? String
                try require(label == "LP-CODEX-001 plain" || label == "LP-CODEX-001 rich", "not_fixture_field")
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
                guards += 1
            }
            func snapshot() throws -> (String, CFRange) {
                try authenticated()
                guard let text = attribute(field, kAXValueAttribute) as? String, text.utf16.count < 256 else { throw ProbeFailure(reason: "fixture_value_unavailable") }
                var selection = CFRange()
                guard let raw = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID(),
                      AXValueGetValue(raw as! AXValue, .cfRange, &selection) else { throw ProbeFailure(reason: "fixture_selection_unavailable") }
                return (text, selection)
            }
            let before = try snapshot()
            let syntheticValues = ["", "\n", "ghbdtn ", "ghbdtn  ", "привет ", "привет  ", "hello ", "hello  ",
                String(repeating: "привет ", count: 20), String(repeating: "привет ", count: 20) + " "]
            try require(syntheticValues.contains(before.0), "requires_empty_or_exact_synthetic_fixture")
            try require(neutralModifiers(), "active_modifiers")
            // First g replaces only a verified known synthetic selection. No
            // Backspace or Return is needed to reset the test field.
            var selectedRange = CFRange(location: 0, length: before.0 == "\n" ? 0 : before.0.utf16.count)
            try authenticated()
            guard let value = AXValueCreate(.cfRange, &selectedRange) else { throw ProbeFailure(reason: "selection_create_failed") }
            try require(AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success, "selection_write_failed")
            pause(0.05)
            let selected = try snapshot()
            try require(selected.0 == before.0 && selected.1.location == selectedRange.location && selected.1.length == selectedRange.length, "selection_not_verified")
            guard let savedSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let savedID = sourceIdentifier(savedSource),
                  let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
                  let abc = sources.first(where: { sourceIdentifier($0) == "com.apple.keylayout.ABC" }) else { throw ProbeFailure(reason: "input_sources_unavailable") }
            oldSource = savedSource; oldIdentifier = savedID
            try authenticated()
            sourceTouched = true
            try require(TISSelectInputSource(abc) == noErr, "abc_selection_failed")
            pause(0.2)
            try require(currentIdentifier() == "com.apple.keylayout.ABC", "abc_selection_not_verified")
            report["initialInputSource"] = savedID
            report["selectedInputSource"] = currentIdentifier()

            let hidContext = TapContext(trace: trace, location: "cghid")
            let sessionContext = TapContext(trace: trace, location: "cgSession")
            let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
            guard let hidTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: passiveCallback, userInfo: Unmanaged.passUnretained(hidContext).toOpaque()) else { throw ProbeFailure(reason: "hid_listen_tap_unavailable") }
            defer { CGEvent.tapEnable(tap: hidTap, enable: false); CFMachPortInvalidate(hidTap) }
            guard let sessionTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: passiveCallback, userInfo: Unmanaged.passUnretained(sessionContext).toOpaque()) else { throw ProbeFailure(reason: "session_listen_tap_unavailable") }
            defer { CGEvent.tapEnable(tap: sessionTap, enable: false); CFMachPortInvalidate(sessionTap) }
            guard let hidRunLoop = CFMachPortCreateRunLoopSource(nil, hidTap, 0),
                  let sessionRunLoop = CFMachPortCreateRunLoopSource(nil, sessionTap, 0) else { throw ProbeFailure(reason: "tap_runloop_source_unavailable") }
            CFRunLoopAddSource(CFRunLoopGetMain(), hidRunLoop, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetMain(), sessionRunLoop, .commonModes)
            defer {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), hidRunLoop, .commonModes)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), sessionRunLoop, .commonModes)
                withExtendedLifetime((hidContext, sessionContext)) {}
            }
            CGEvent.tapEnable(tap: hidTap, enable: true); CGEvent.tapEnable(tap: sessionTap, enable: true)
            try require(CGEvent.tapIsEnabled(tap: hidTap) && CGEvent.tapIsEnabled(tap: sessionTap), "passive_taps_not_enabled")
            guard let source = CGEventSource(stateID: sourceState) else { throw ProbeFailure(reason: "event_source_unavailable") }
            var created: [[String: Any]] = []
            for key: CGKeyCode in [5, 4, 11, 2, 17, 45, 49] {
                for down in [true, false] {
                    try authenticated()
                    try require(neutralModifiers(), "modifiers_changed")
                    try require(!trace.disabled && !trace.overflow && CGEvent.tapIsEnabled(tap: hidTap) && CGEvent.tapIsEnabled(tap: sessionTap), "passive_tap_interrupted")
                    if created.isEmpty {
                        let ready = try snapshot()
                        try require(ready.0 == before.0 && ready.1.location == selectedRange.location && ready.1.length == selectedRange.length, "fixture_changed_before_first_event")
                    }
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw ProbeFailure(reason: "event_create_failed") }
                    event.flags = []
                    event.setIntegerValueField(.eventSourceUserData, value: probeTag)
                    try require(event.getIntegerValueField(.eventSourceUnixProcessID) == trace.ownPID, "created_event_source_pid_mismatch")
                    created.append(["keyCode": key, "type": event.type.rawValue,
                        "sourceStateID": event.getIntegerValueField(.eventSourceStateID), "flags": event.flags.rawValue,
                        "timestampNanoseconds": event.timestamp])
                    event.post(tap: .cghidEventTap)
                    pause(0.025)
                }
            }
            pause(0.8)
            try require(!trace.disabled && !trace.overflow && CGEvent.tapIsEnabled(tap: hidTap) && CGEvent.tapIsEnabled(tap: sessionTap), "passive_tap_interrupted")
            let after = try snapshot()
            // The content may differ under either switcher. Unknown text is
            // redacted rather than expanding the authorized synthetic corpus.
            try require(["ghbdtn ", "привет ", "ghbdtn", "привет"].contains(after.0), "unexpected_fixture_result_redacted")
            report["before"] = ["text": before.0, "location": before.1.location, "length": before.1.length]
            report["afterFirstSpace"] = ["text": after.0, "location": after.1.location, "length": after.1.length]
            report["inputSourceAfterFirstSpace"] = currentIdentifier()
            report["createdEvents"] = created
            report["guardChecks"] = guards
            report["targetGuardsPassed"] = true
            passed = neutralModifiers()
        } catch {
            report["error"] = (error as? ProbeFailure)?.reason ?? "unexpected_helper_error"
        }
        if sourceTouched, let oldSource, let oldIdentifier {
            let selected = TISSelectInputSource(oldSource) == noErr
            pause(0.2)
            report["inputSourceRestored"] = selected && currentIdentifier() == oldIdentifier
        }
        report["finalInputSource"] = currentIdentifier()
        report["trace"] = trace.records
        report["traceCounts"] = ["cghid": trace.records.filter { ($0["location"] as? String) == "cghid" }.count,
            "cgSession": trace.records.filter { ($0["location"] as? String) == "cgSession" }.count]
        report["ownDeliveryObservedAtBothTaps"] = ["cghid", "cgSession"].allSatisfy { location in
            trace.records.contains { ($0["location"] as? String) == location }
        }
        report["traceDisabled"] = trace.disabled
        report["traceOverflow"] = trace.overflow
        report["finalModifiersNeutral"] = neutralModifiers()
        report["axErrors"] = axErrors
        let complete = passed && !trace.disabled && !trace.overflow && neutralModifiers() && (report["inputSourceRestored"] as? Bool) == true
        report["probeCompleted"] = complete
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { print(String(decoding: json, as: UTF8.self)) }
        exit(complete ? 0 : 1)
    }
}
