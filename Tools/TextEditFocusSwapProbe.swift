import AppKit
import ApplicationServices
import Carbon

// Separate negative routing candidate. Default preflight never opens a document.
// --run uses ONLY two new UUID-owned TextEdit files, never existing user documents.
private struct Failure: Error { let reason: String }
private func need(_ ok: Bool, _ reason: String) throws { if !ok { throw Failure(reason: reason) } }
private func attribute(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(e, 0.15)
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}
private func element(_ v: CFTypeRef?) -> AXUIElement? {
    guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}
private func wait(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
private func modifiersNeutral() -> Bool {
    let mask: UInt64 = (0x1f << 16) | (1 << 23) | 0x20ff
    return [CGEventSourceStateID.hidSystemState, .combinedSessionState].allSatisfy {
        CGEventSource.flagsState($0).rawValue & mask == 0
    }
}
private func keyboardNeutral(except owned: CGKeyCode? = nil) -> Bool {
    modifiersNeutral() && (0..<128).allSatisfy { value in
        let key = CGKeyCode(value)
        return key == owned || (!CGEventSource.keyState(.hidSystemState, key: key) && !CGEventSource.keyState(.combinedSessionState, key: key))
    }
}
private struct OwnedDocument {
    let app: AXUIElement
    let window: AXUIElement
    let field: AXUIElement
    let pid: pid_t
    let url: URL
    let document: String
    func verify(focused: Bool) throws {
        try need(AXIsProcessTrusted() && !IsSecureEventInputEnabled(), "access_or_secure_input")
        guard let host = NSRunningApplication(processIdentifier: pid), host.bundleIdentifier == "com.apple.TextEdit" else { throw Failure(reason: "textedit_identity_changed") }
        try need((attribute(window, kAXDocumentAttribute) as? String) == document, "owned_document_identity_changed")
        try need(URL(string: document)?.standardizedFileURL == url.standardizedFileURL, "not_exact_owned_file_url")
        guard let fieldWindow = element(attribute(field, kAXWindowAttribute)) else { throw Failure(reason: "owned_field_window_missing") }
        try need(CFEqual(fieldWindow, window) && (attribute(field, kAXRoleAttribute) as? String) == kAXTextAreaRole && (attribute(field, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole, "owned_field_identity_changed")
        if focused {
            try need(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "textedit_not_frontmost")
            guard let current = element(attribute(app, kAXFocusedUIElementAttribute)), let win = element(attribute(app, kAXFocusedWindowAttribute)) else { throw Failure(reason: "focused_identity_missing") }
            try need(CFEqual(current, field) && CFEqual(win, window), "focus_changed_outside_expected_target")
        }
    }
    func read(focused: Bool) throws -> (String, CFRange) {
        try verify(focused: focused)
        guard let text = attribute(field, kAXValueAttribute) as? String, text.utf16.count <= 64,
              let raw = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { throw Failure(reason: "owned_text_or_range_unavailable") }
        var range = CFRange()
        try need(AXValueGetValue(raw as! AXValue, .cfRange, &range) && range.location >= 0 && range.length >= 0 && range.location <= text.utf16.count && range.length <= text.utf16.count - range.location, "owned_range_invalid")
        try need(Range(NSRange(location: range.location, length: range.length), in: text) != nil, "owned_range_splits_unicode")
        try verify(focused: focused)
        return (text, range)
    }
    func focus() throws {
        try verify(focused: false)
        try need(keyboardNeutral(), "focus_requires_neutral_keyboard")
        guard let host = NSRunningApplication(processIdentifier: pid) else { throw Failure(reason: "host_disappeared") }
        try need(host.activate(options: []), "own_window_activation_rejected")
        try verify(focused: false)
        try need(keyboardNeutral(), "raise_requires_neutral_keyboard")
        try need(AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success, "own_window_raise_failed")
        try verify(focused: false)
        try need(keyboardNeutral(), "field_focus_requires_neutral_keyboard")
        try need(AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success, "own_field_focus_failed")
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while true {
            try verify(focused: false)
            if (try? verify(focused: true)) != nil { return }
            try need(ProcessInfo.processInfo.systemUptime < deadline, "own_focus_ack_timeout")
            wait(0.01)
        }
    }
}
private func openOwned(_ url: URL) throws -> OwnedDocument {
    guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { throw Failure(reason: "textedit_unavailable") }
    let config = NSWorkspace.OpenConfiguration(); config.activates = true
    var host: NSRunningApplication?, failed = false
    NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: config) { app, error in host = app; failed = error != nil }
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while host == nil && !failed && ProcessInfo.processInfo.systemUptime < deadline { wait(0.02) }
    guard let host, host.bundleIdentifier == "com.apple.TextEdit" else { throw Failure(reason: "own_document_open_failed") }
    let app = AXUIElementCreateApplication(host.processIdentifier)
    while ProcessInfo.processInfo.systemUptime < deadline {
        if let field = element(attribute(app, kAXFocusedUIElementAttribute)), let window = element(attribute(field, kAXWindowAttribute)),
           let document = attribute(window, kAXDocumentAttribute) as? String,
           URL(string: document)?.standardizedFileURL == url.standardizedFileURL {
            let result = OwnedDocument(app: app, window: window, field: field, pid: host.processIdentifier, url: url, document: document)
            let state = try result.read(focused: true)
            try need(state.0.isEmpty && state.1.location == 0 && state.1.length == 0, "new_document_not_empty")
            return result
        }
        wait(0.02)
    }
    throw Failure(reason: "own_document_pin_timeout")
}
private func englishSource() -> Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
    return ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String)
}
@main private struct TextEditFocusSwapProbe {
    static func main() {
        var report: [String: Any] = ["schemaVersion": 1, "eventsPosted": 0, "postSwitchEvents": 0,
            "eventCap": 18, "switchAttempted": false, "raceProven": false, "fullAcceptance": false,
            "clipboardUsed": false, "returnEvents": 0, "permissionRequests": 0,
            "prototypePendingCount": NSNull(), "pendingCountReason": "Not publicly exposed; no defaults or user data read"]
        var frames = 0, switched = false
        var ownedDown: CGKeyCode?
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try need(args.isEmpty || args == ["--preflight"] || args == ["--run"], "usage_preflight_or_explicit_run")
            let run = args == ["--run"]
            report["mode"] = run ? "run" : "preflight"
            report["accessibilityTrusted"] = AXIsProcessTrusted()
            report["postEventAccess"] = CGPreflightPostEventAccess()
            report["secureInput"] = IsSecureEventInputEnabled()
            report["keyboardNeutral"] = keyboardNeutral()
            report["preflightReady"] = AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled() && keyboardNeutral() && englishSource()
            if run {
                try need(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled() && keyboardNeutral() && englishSource(), "initial_permissions_keyboard_or_source")
                let switchers = NSWorkspace.shared.runningApplications.filter { ["LayoutPilot", "Caramba Switcher Pro", "Lang Switcher", "TypeTune"].contains($0.localizedName ?? "") }
                try need(switchers.count == 1 && switchers[0].localizedName == "LayoutPilot", "exactly_one_layoutpilot_required")
                let prototype = switchers[0]
                let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                let expectedPrototype = project.appendingPathComponent("dist/LayoutPilot.app/Contents/MacOS/LayoutPilot")
                try need(prototype.executableURL?.standardizedFileURL == expectedPrototype.standardizedFileURL, "prototype_executable_not_project_dist")
                report["prototypeExecutable"] = expectedPrototype.path
                report["prototypePID"] = Int(prototype.processIdentifier)
                let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("research/private/probes", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try need(base.resolvingSymlinksInPath() == base.standardizedFileURL, "probe_directory_must_not_be_symlinked")
                let token = UUID().uuidString.lowercased()
                let aURL = base.appendingPathComponent("focus-A-" + token + ".txt")
                let bURL = base.appendingPathComponent("focus-B-" + token + ".txt")
                for url in [aURL,bURL] {
                    try Data().write(to: url, options: .withoutOverwriting)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                report["documentA"] = aURL.path; report["documentB"] = bURL.path
                let a = try openOwned(aURL), b = try openOwned(bURL)
                try need(a.pid == b.pid && !CFEqual(a.window, b.window) && !CFEqual(a.field, b.field), "two_independent_owned_windows_required")
                // Rehearse B→A before any key: fail closed if the chosen focus API
                // cannot prove both owned fields and the exact selected window.
                try b.focus(); try a.focus()
                let aInitial = try a.read(focused: true), bInitial = try b.read(focused: false)
                try need(aInitial.0.isEmpty && bInitial.0.isEmpty && aInitial.1.location == 0 && aInitial.1.length == 0 && bInitial.1.location == 0 && bInitial.1.length == 0, "owned_initial_state_changed")
                guard let source = CGEventSource(stateID: .privateState) else { throw Failure(reason: "source_unavailable") }
                let phrases = ["ghbdtn", "привет"].flatMap { word in ["ab", "aи", "фb", "фи"].map { word + " " + $0 } }
                let allowed = Set(phrases.flatMap { phrase in (0...phrase.count).map { String(phrase.prefix($0)) } })
                let began = ProcessInfo.processInfo.systemUptime
                for key: CGKeyCode in [5,4,11,2,17,45,49,0,11] {
                    for down in [true,false] {
                        try need(!switched && frames < 18 && keyboardNeutral(except: ownedDown) && CGPreflightPostEventAccess(), "frame_keyboard_permission_or_cap")
                        try a.verify(focused: true); try b.verify(focused: false)
                        let current = try a.read(focused: true), untouched = try b.read(focused: false)
                        try need(allowed.contains(current.0) && untouched.0.isEmpty && untouched.1.location == 0 && untouched.1.length == 0, "non_synthetic_or_B_changed_before_switch")
                        try need(down ? ownedDown == nil : ownedDown == key, "unbalanced_owned_frame")
                        try need(!prototype.isTerminated && NSWorkspace.shared.runningApplications.filter { ["LayoutPilot", "Caramba Switcher Pro", "Lang Switcher", "TypeTune"].contains($0.localizedName ?? "") }.count == 1, "prototype_or_conflict_changed")
                        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw Failure(reason: "event_creation_failed") }
                        event.flags = []
                        try a.verify(focused: true)
                        try need(keyboardNeutral(except: ownedDown) && CGPreflightPostEventAccess(), "last_frame_guard")
                        event.post(tap: .cghidEventTap)
                        frames += 1; ownedDown = down ? key : nil
                        wait(0.005)
                    }
                }
                try need(ownedDown == nil && keyboardNeutral(), "keyboard_not_neutral_before_swap")
                try a.verify(focused: true); try b.verify(focused: false)
                report["switchAttempted"] = true
                report["switchAfterSeconds"] = ProcessInfo.processInfo.systemUptime - began
                switched = true // No event path is permitted after the first swap attempt.
                try b.focus()
                let deadline = ProcessInfo.processInfo.systemUptime + 1.5
                while ProcessInfo.processInfo.systemUptime < deadline {
                    try b.verify(focused: true); try a.verify(focused: false)
                    wait(0.02)
                }
                let finalA = try a.read(focused: false), finalB = try b.read(focused: true)
                report["documentAState"] = ["text": finalA.0, "location": finalA.1.location, "length": finalA.1.length]
                report["documentBState"] = ["text": finalB.0, "location": finalB.1.location, "length": finalB.1.length]
                report["noLeakToBObserved"] = finalB.0.isEmpty && finalB.1.location == 0 && finalB.1.length == 0
                report["postSwitchReadOnly"] = true
                report["notice"] = "Negative routing candidate only. Timing does not prove an active mutation/replay overlap; correlate with independent target trace. No pending count inference."
                try need(allowed.contains(finalA.0) && finalB.0.isEmpty && finalB.1.location == 0 && finalB.1.length == 0, "unexpected_text_or_replay_leak_to_B")
            }
            report["success"] = true
        } catch {
            report["success"] = false
            report["failure"] = (error as? Failure)?.reason ?? String(describing: error)
        }
        report["eventsPosted"] = frames
        report["ownedKeyReleasePending"] = ownedDown != nil
        report["focusSwapAttemptedNoFurtherEvents"] = switched
        print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
        if report["success"] as? Bool != true { exit(2) }
    }
}
