import AppKit
import ApplicationServices
import Carbon

// User-authorized matrix input. Pins an initially empty field and window; never sends Return.
struct MatrixCase: Decodable {
    let bundle: String
    let window: String
    let description: String
    let text: String
    let expected: String
    let source: String
    let expectedSource: String
    let gesture: String
    let clearAfter: Bool?
}
struct Failure: Error { let reason: String }
func require(_ value: @autoclosure () -> Bool, _ reason: String) throws {
    if !value() { throw Failure(reason: reason) }
}
func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.15)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func pause(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
func identifier(_ source: TISInputSource) -> String {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}
func currentSource() -> String { TISCopyCurrentKeyboardInputSource().map { identifier($0.takeRetainedValue()) } ?? "" }

@main struct MatrixInputProbe {
    static func main() {
        var result: [String: Any] = ["events": 0, "passed": false, "returnEvents": 0]
        var events = 0
        do {
            try require(CommandLine.arguments.count == 2, "one_case_file_required")
            let item = try JSONDecoder().decode(MatrixCase.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let allowed = ["com.google.Chrome", "com.apple.Safari", "com.tdesktop.Telegram", "com.tinyspeck.slackmacgap",
                "com.microsoft.VSCode", "com.apple.Notes", "com.microsoft.Word", "com.openai.codex", "com.apple.Terminal"]
            try require(allowed.contains(item.bundle) || item.bundle.hasPrefix("com.google.Chrome.app."), "bundle_not_in_matrix")
            let keys: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
                "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,
                "7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46," ":49]
            try require(!item.text.isEmpty && item.text.count <= 128 && item.text.allSatisfy { keys[$0] != nil }, "bounded_ascii_keys_required")
            try require(["none", "doubleShift"].contains(item.gesture), "unsupported_gesture")
            let applications = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == item.bundle }
            try require(applications.count == 1, "one_target_process_required")
            let app = applications[0]
            guard let appURL = app.bundleURL else { throw Failure(reason: "app_url_unavailable") }
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            var opened = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in opened = error == nil }
            let activationDeadline = ProcessInfo.processInfo.systemUptime + 5
            while !opened && ProcessInfo.processInfo.systemUptime < activationDeadline { pause(0.05) }
            _ = app.activate(options: [])
            pause(0.5)
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "wrong_frontmost_app")
            let pid = app.processIdentifier, ax = AXUIElementCreateApplication(pid)
            guard let field = element(read(ax, kAXFocusedUIElementAttribute)), let window = element(read(ax, kAXFocusedWindowAttribute)) else { throw Failure(reason: "no_focused_field_or_window") }
            func authenticate(shiftHeld: Bool = false) throws {
                try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(), "permissions_or_secure_input")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "frontmost_changed")
                guard let nowField = element(read(ax, kAXFocusedUIElementAttribute)), let nowWindow = element(read(ax, kAXFocusedWindowAttribute)) else { throw Failure(reason: "focus_unavailable") }
                try require(CFEqual(field, nowField) && CFEqual(window, nowWindow), "field_or_window_changed")
                let windowTitle = read(window, kAXTitleAttribute) as? String
                let fieldDescription = read(field, kAXDescriptionAttribute) as? String
                result["windowTitleLength"] = windowTitle?.utf16.count
                result["fieldDescriptionLength"] = fieldDescription?.utf16.count
                try require(windowTitle == item.window, "window_identity_changed")
                try require(fieldDescription == item.description, "field_description_changed")
                try require([kAXTextFieldRole, kAXTextAreaRole, "AXComboBox"].contains(read(field, kAXRoleAttribute) as? String ?? ""), "not_text_field")
                try require(read(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole, "secure_field")
                let allowedFlags: UInt64 = shiftHeld ? CGEventFlags.maskShift.rawValue | 0x2 : 0
                for state: CGEventSourceStateID in [.hidSystemState, .combinedSessionState] {
                    try require(CGEventSource.flagsState(state).rawValue & 0x9f207f & ~allowedFlags == 0, "foreign_modifier")
                    for key: CGKeyCode in [54,55,56,60,58,61,59,62,57,63] where !(shiftHeld && key == 56) {
                        try require(!CGEventSource.keyState(state, key: key), "foreign_modifier_key")
                    }
                }
                try require(events < 600, "event_limit")
            }
            func snapshot() throws -> (String, CFRange) {
                try authenticate()
                guard let text = read(field, kAXValueAttribute) as? String, text.utf16.count <= 4096,
                      let raw = read(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { throw Failure(reason: "text_or_caret_unavailable") }
                var range = CFRange()
                try require(AXValueGetValue(raw as! AXValue, .cfRange, &range), "invalid_caret")
                return (text, range)
            }
            let initial = try snapshot()
            try require(initial.0.isEmpty && initial.1.location == 0 && initial.1.length == 0, "initial_field_must_be_empty")
            guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
                  let chosen = sources.first(where: { identifier($0) == item.source }),
                  let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let source = CGEventSource(stateID: .hidSystemState) else { throw Failure(reason: "input_source_unavailable") }
            defer { result["inputSourceRestored"] = TISSelectInputSource(original) == noErr && currentSource() == identifier(original) }
            try authenticate()
            try require(TISSelectInputSource(chosen) == noErr, "source_selection_failed")
            pause(0.2)
            try require(currentSource() == item.source, "source_not_selected")
            func emit(_ key: CGKeyCode, down: Bool, modifier: Bool = false) throws {
                try authenticate(shiftHeld: modifier && !down)
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw Failure(reason: "event_creation_failed") }
                event.flags = modifier && down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2) : []
                if modifier { event.type = .flagsChanged }
                event.setIntegerValueField(.eventSourceUserData, value: 0x4c505052)
                event.post(tap: .cghidEventTap)
                events += 1
                pause(0.012)
            }
            let start = ProcessInfo.processInfo.systemUptime
            for character in item.text {
                try emit(keys[character]!, down: true)
                try emit(keys[character]!, down: false)
                pause(0.080)
            }
            if item.gesture == "doubleShift" {
                for _ in 0..<2 {
                    try emit(56, down: true, modifier: true); pause(0.04)
                    try emit(56, down: false, modifier: true); pause(0.07)
                }
            }
            pause(1)
            let final = try snapshot()
            let matches = final.0.utf16.elementsEqual(item.expected.utf16)
            let caret = final.1.location == item.expected.utf16.count && final.1.length == 0
            result.merge(["bundle": item.bundle, "pid": pid, "textMatches": matches, "caretMatches": caret,
                "sourceMatches": currentSource() == item.expectedSource, "observedLength": final.0.utf16.count,
                "inputSeconds": ProcessInfo.processInfo.systemUptime - start - 1,
                "passed": matches && caret && currentSource() == item.expectedSource]) { _, new in new }
            if item.clearAfter == true {
                try require(result["passed"] as? Bool == true, "mismatch_kept_for_diagnosis")
                var remaining = item.expected
                while !remaining.isEmpty {
                    let before = try snapshot()
                    try require(before.0.utf16.elementsEqual(remaining.utf16) && before.1.location == remaining.utf16.count && before.1.length == 0, "cleanup_text_changed")
                    try emit(51, down: true); try emit(51, down: false)
                    remaining.removeLast(); pause(0.08)
                }
                let empty = try snapshot()
                try require(empty.0.isEmpty && empty.1.location == 0 && empty.1.length == 0, "cleanup_not_empty")
                result["testTextCleared"] = true
            }
        } catch {
            result["passed"] = false
            result["error"] = (error as? Failure)?.reason ?? String(describing: error)
        }
        result["events"] = events
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
        print(String(decoding: data, as: UTF8.self))
        if result["passed"] as? Bool != true { exit(1) }
    }
}
