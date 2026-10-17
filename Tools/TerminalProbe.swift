import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

private struct Failure: Error { let message: String }
private func require(_ ok: @autoclosure () -> Bool, _ message: String) throws {
    if !ok() { throw Failure(message: message) }
}
private func pause(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

@main struct TerminalProbe {
    static func main() {
        var frames = 0
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try require(args.count == 3, "report_host_mode_required")
            let reportURL = URL(fileURLWithPath: args[0]).standardizedFileURL
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            try require(reportURL.deletingLastPathComponent() == root.appendingPathComponent("research/private/probes"), "outside_fixture_directory")
            try require(reportURL.lastPathComponent.hasPrefix("TerminalFixture-") && reportURL.pathExtension == "json" && reportURL.resolvingSymlinksInPath() == reportURL, "not_fixture_file")
            let host = args[1], mode = args[2]
            try require(EditorSupport.permitsTerminalIntegration(applicationID: host) && ["auto", "correct", "manual"].contains(mode), "unsupported_host_or_mode")
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_or_secure_input")
            func state() throws -> [String: Any] {
                let data = try Data(contentsOf: reportURL)
                try require(data.count <= 4096, "oversize_fixture_report")
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: "invalid_fixture_report") }
                return value
            }
            let initial = try state()
            guard let nonce = initial["nonce"] as? String, UUID(uuidString: nonce) != nil,
                  let fixturePID = initial["pid"] as? Int, fixturePID > 0,
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == host }) else { throw Failure(message: "fixture_or_host_absent") }
            try require(initial["text"] as? String == "" && initial["host"] as? String == host, "fresh_empty_fixture_required")
            _ = app.activate(options: []); pause(0.5)
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var pinnedField: AXUIElement?, pinnedWindow: AXUIElement?
            var ownsShift = false
            func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
                var value: CFTypeRef?
                return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
            }
            func guardTarget() throws {
                try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_changed")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "focus_changed")
                let current = try state()
                try require(current["nonce"] as? String == nonce && current["pid"] as? Int == fixturePID && current["host"] as? String == host && current["active"] as? Bool == true, "fixture_identity_changed")
                try require(kill(pid_t(fixturePID), 0) == 0 && current["text"] as? String != "redacted", "fixture_stopped_or_foreign_input")
                guard let raw = attribute(ax, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw Failure(message: "no_focused_field") }
                let field = raw as! AXUIElement
                guard let win = attribute(field, kAXWindowAttribute), CFGetTypeID(win) == AXUIElementGetTypeID() else { throw Failure(message: "no_fixture_window") }
                let window = win as! AXUIElement
                try require(attribute(field, kAXRoleAttribute) as? String == kAXTextAreaRole &&
                    (attribute(window, kAXTitleAttribute) as? String)?.contains("[LP:" + nonce + "]") == true, "not_fixture_editor")
                if let pinnedField, let pinnedWindow { try require(CFEqual(pinnedField, field) && CFEqual(pinnedWindow, window), "field_or_window_changed") }
                pinnedField = field; pinnedWindow = window
                let mask: UInt64 = CGEventFlags([.maskShift, .maskAlternate, .maskControl, .maskCommand, .maskAlphaShift, .maskSecondaryFn]).rawValue | 0x20ff
                let allowed: UInt64 = ownsShift ? CGEventFlags.maskShift.rawValue | 0x2 : 0
                for source: CGEventSourceStateID in [.hidSystemState, .combinedSessionState] {
                    try require(CGEventSource.flagsState(source).rawValue & mask & ~allowed == 0, "foreign_modifier")
                    for key: CGKeyCode in [54,55,56,60,58,61,59,62,57,63] where !(ownsShift && key == 56) {
                        try require(!CGEventSource.keyState(source, key: key), "foreign_modifier_key")
                    }
                }
            }
            try guardTarget()
            let originalSource = InputSources.identifier
            defer { _ = InputSources.restore(identifier: originalSource) }
            try require(InputSources.select(.english), "english_source_unavailable")
            pause(0.2)
            let source = CGEventSource(stateID: .privateState)!
            func emit(_ key: CGKeyCode, down: Bool, shift: Bool = false) throws {
                try guardTarget()
                try require((shift && key == 56) || (!shift && [5,4,11,2,17,45,49,14,37,31].contains(key)), "unapproved_key")
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
                if shift { event.type = .flagsChanged }
                event.flags = shift && down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2) : []
                event.post(tap: .cghidEventTap); frames += 1
                if shift { ownsShift = down }
                pause(shift ? 0.08 : 0.04)
            }
            for key: CGKeyCode in mode == "correct" ? [4,14,37,37,31] : [5,4,11,2,17,45] {
                try emit(key, down: true); try emit(key, down: false)
            }
            if mode == "manual" {
                for _ in 0..<2 { try emit(56, down: true, shift: true); try emit(56, down: false, shift: true) }
            } else { try emit(49, down: true); try emit(49, down: false) }
            pause(0.7); try guardTarget()
            let after = try state()
            let expected = mode == "correct" ? "hello " : mode == "manual" ? "привет" : "привет "
            let passed = after["text"] as? String == expected && after["cursor"] as? Int == expected.count
            let result: [String: Any] = ["mode": mode, "host": host, "fixturePID": fixturePID, "nonce": nonce,
                "after": after, "expected": expected, "passed": passed, "frames": frames, "returnEvents": 0,
                "clipboardUsed": false, "finalModifiersNeutral": !ownsShift]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
            if !passed { exit(2) }
        } catch {
            let reason = (error as? Failure)?.message ?? "fixture_read_failed"
            print("{\"error\":\"\(reason)\",\"frames\":\(frames),\"returnEvents\":0}")
            exit(2)
        }
    }
}
