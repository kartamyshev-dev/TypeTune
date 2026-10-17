import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

// Only the omnibox of the isolated LP-CODEX-001 window. Never posts Enter or uses the clipboard.
enum OmniboxProbe {
    static func run(_ mode: String, reportPath: String) throws {
        let report = URL(fileURLWithPath: reportPath).standardizedFileURL
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        try require(report.deletingLastPathComponent().path == root.appendingPathComponent("research/private/probes").path &&
            report.lastPathComponent.hasPrefix("Omnibox-") && report.pathExtension == "json" &&
            report.resolvingSymlinksInPath().path == report.path && !FileManager.default.fileExists(atPath: report.path), "invalid_new_report")
        var frames = 0
        func write(_ values: [String: Any]) throws {
            var result = values; result["mode"] = mode; result["frames"] = frames
            result["returnEvents"] = 0; result["clipboardUsed"] = false
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: report, options: .withoutOverwriting)
        }
        do {
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_or_secure_input")
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { throw Failure(reason: "chrome_absent") }
            _ = app.activate(options: []); pause(0.5)
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            guard let field = element(attr(ax, kAXFocusedUIElementAttribute)), let window = element(attr(field, kAXWindowAttribute)) else { throw Failure(reason: "no_focused_editor") }
            func guardTarget(shiftHeld: Bool = false) throws {
                try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_changed")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "focus_changed")
                guard let current = element(attr(ax, kAXFocusedUIElementAttribute)), let currentWindow = element(attr(ax, kAXFocusedWindowAttribute)) else { throw Failure(reason: "focus_unavailable") }
                try require(CFEqual(current, field) && CFEqual(currentWindow, window), "field_or_window_changed")
                try require((attr(window, kAXTitleAttribute) as? String)?.contains("LayoutPilot isolated input LP-CODEX-001") == true &&
                    attr(field, kAXRoleAttribute) as? String == kAXTextFieldRole && attr(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole, "not_fixture_omnibox")
                let allowed = shiftHeld ? CGEventFlags.maskShift.rawValue | 0x2 : 0
                let mask: UInt64 = CGEventFlags([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift,.maskSecondaryFn]).rawValue | 0x20ff
                for source: CGEventSourceStateID in [.hidSystemState, .combinedSessionState] {
                    try require(CGEventSource.flagsState(source).rawValue & mask & ~allowed == 0, "foreign_modifier")
                    for key: CGKeyCode in [54,55,56,60,58,61,59,62,57,63] where !(shiftHeld && key == 56) {
                        try require(!CGEventSource.keyState(source, key: key), "foreign_modifier_key")
                    }
                }
            }
            func state() throws -> (String, CFRange) {
                try guardTarget()
                guard let text = attr(field, kAXValueAttribute) as? String, text.utf16.count < 1024,
                      let value = attr(field, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { throw Failure(reason: "no_text_or_range") }
                var range = CFRange()
                try require(AXValueGetValue(value as! AXValue, .cfRange, &range), "no_selected_range")
                return (text, range)
            }
            let initial = try state()
            guard let recognized = AccessibilityEditor.snapshot(), recognized.addressBar,
                  CFEqual(recognized.element, field), CFEqual(recognized.window, window) else { throw Failure(reason: "unrecognized_omnibox") }
            let ownURL = "http://127.0.0.1:18763/?fixture=LP-CODEX-001"
            try require(initial.0 == ownURL || initial.0 == String(ownURL.dropFirst(7)), "requires_own_fixture_url")
            if mode == "omnibox-profile" {
                var attributes = CFArray?.none
                _ = AXUIElementCopyAttributeNames(field, &attributes)
                try write(["profile": ["role": attr(field,kAXRoleAttribute) as? String ?? "", "description": attr(field,kAXDescriptionAttribute) as? String ?? "", "identifier": attr(field,kAXIdentifierAttribute) as? String ?? "", "attributes": attributes as? [String] ?? []], "productionRecognized": AccessibilityEditor.snapshot()?.addressBar == true])
                return
            }
            let urls = ["https://example.com/ghbdtn", "ghbdtn.ru", "user@example.com", "localhost", "127.0.0.1:18763", "chrome://settings", "file:///tmp/ghbdtn", "https://пример.рф/ghbdtn", "https://example.com ghbdtn"]
            let urlIndex = Int(mode.replacingOccurrences(of: "omnibox-url-", with: ""))
            try require(["omnibox-auto", "omnibox-correct", "omnibox-manual", "omnibox-query"].contains(mode) || mode.hasPrefix("omnibox-url-") && urlIndex.map(urls.indices.contains) == true, "unsupported_case")
            let seed = mode == "omnibox-manual" ? "ghbdtn" : mode == "omnibox-query" ? "hello " : urlIndex.map { urls[$0] } ?? ""
            try guardTarget()
            try require(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, seed as CFString) == .success, "seed_failed")
            var caret = CFRange(location: seed.utf16.count, length: 0)
            try require(AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &caret)!) == .success, "seed_caret_failed")
            pause(0.2)
            let seeded = try state()
            try require(seeded.0.utf16.elementsEqual(seed.utf16) && seeded.1.location == caret.location && seeded.1.length == 0, "seed_not_verified")
            let originalSource = InputSources.identifier
            defer { _ = InputSources.restore(identifier: originalSource) }
            try require(InputSources.select(.english), "english_unavailable"); pause(0.2)
            let source = CGEventSource(stateID: .privateState)!
            var ownsShift = false
            func emit(_ key: CGKeyCode, down: Bool, shift: Bool = false) throws {
                try guardTarget(shiftHeld: ownsShift)
                try require(shift && key == 56 || !shift && [5,4,11,2,17,45,49,14,37,31].contains(key), "unapproved_key")
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
                if shift { event.type = .flagsChanged }
                event.flags = shift && down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2) : []
                event.post(tap: .cghidEventTap); frames += 1
                if shift { ownsShift = down }
                pause(shift ? 0.08 : 0.09)
            }
            if mode == "omnibox-manual" || urlIndex != nil {
                for _ in 0..<2 { try emit(56, down: true, shift: true); try emit(56, down: false, shift: true) }
            } else {
                let keys: [CGKeyCode] = mode == "omnibox-correct" ? [4,14,37,37,31] : [5,4,11,2,17,45]
                for key in keys { try emit(key, down: true); try emit(key, down: false) }
            }
            if urlIndex != nil {
                let unchanged = try state()
                try require(unchanged.0.utf16.elementsEqual(seed.utf16) && unchanged.1.location == seed.utf16.count && unchanged.1.length == 0, "url_changed_by_double_shift")
            }
            if mode != "omnibox-manual" { try emit(49, down: true); try emit(49, down: false) }
            pause(0.9)
            let after = try state()
            let expected = mode == "omnibox-manual" ? "привет" : urlIndex != nil ? seed + " " : mode == "omnibox-correct" ? "hello " : mode == "omnibox-query" ? "hello привет " : "привет "
            let passed = after.0.utf16.elementsEqual(expected.utf16) && after.1.location == expected.utf16.count && after.1.length == 0
            try write(["after": after.0, "expected": expected, "location": after.1.location, "length": after.1.length, "passed": passed, "finalModifiersNeutral": !ownsShift, "sourceAfter": InputSources.identifier])
            try require(passed, "unexpected_omnibox_result")
        } catch {
            if !FileManager.default.fileExists(atPath: report.path) { try? write(["error": (error as? Failure)?.reason ?? "probe_failed"]) }
            throw error
        }
    }
}
