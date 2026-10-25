import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

struct EditorSnapshot {
    var element: AXUIElement
    var window: AXUIElement?
    var document: String?
    var pid: pid_t
    var application: String
    var text: String
    var selection: NSRange
    var addressBar = false
    /// Universal mode: the target is identified by its process only and is edited with
    /// keystrokes; `element` is the application element and the field is not pinned.
    var keystrokes = false
    /// The target was taken from the system-wide focused element, not from the frontmost
    /// application: a non-activating panel (Spotlight) owns keyboard focus while the previous
    /// application stays frontmost. Such a target is confirmed by the focused element's
    /// process, never by `frontmostApplication`.
    var focusTarget = false

    func matchesContent(_ other: EditorSnapshot) -> Bool {
        selection == other.selection && text.utf16.elementsEqual(other.text.utf16)
    }

    static func keystrokeTarget(pid: pid_t, application: String) -> EditorSnapshot {
        EditorSnapshot(element: AXUIElementCreateApplication(pid), window: nil, document: nil, pid: pid,
                       application: application, text: "", selection: NSRange(location: 0, length: 0), keystrokes: true)
    }
}

enum AccessibilityEditor {
    enum SnapshotResult {
        case success(EditorSnapshot)
        case failure(EditorSnapshotFailure)

        var snapshot: EditorSnapshot? {
            if case .success(let value) = self { return value }
            return nil
        }
        var failure: EditorSnapshotFailure? {
            if case .failure(let value) = self { return value }
            return nil
        }
    }
    enum ReplacementResult {
        case notApplied
        case verified(EditorSnapshot)
        case uncertain

        func settledSnapshot(read: () -> EditorSnapshot?) -> EditorSnapshot? {
            // A verified result already contains the exact final text/caret readback.
            if case .verified(let after) = self { return after }
            return read()
        }
    }
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        let (status, value) = readAttribute(element, key)
        return status == .success ? value : nil
    }
    private static func readAttribute(_ element: AXUIElement, _ key: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let began = ProcessInfo.processInfo.systemUptime
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        if InputDiagnostics.shared.enabled, status == .cannotComplete || elapsed > 0.030 {
            InputDiagnostics.shared.record("ax-read", revision: -1,
                checks: ["cannotComplete": status == .cannotComplete,
                    "success": status == .success,
                    "focusedField": key == kAXFocusedUIElementAttribute,
                    "window": key == kAXWindowAttribute,
                    "text": key == kAXValueAttribute,
                    "selection": key == kAXSelectedTextRangeAttribute], elapsed: elapsed)
        }
        return (status, value)
    }
    static func snapshot() -> EditorSnapshot? { capture().snapshot }

    /// Universal mode, read-only and for any application: the text before a collapsed
    /// caret in the focused field of `pid`, when Accessibility exposes it.
    enum FieldObservation: Equatable {
        /// No readable value or caret (many custom editors); the caller may type blind.
        case unreadable
        /// A password field: universal mode must not touch it.
        case secure
        case textBeforeCaret(String)
        /// The field is readable but text is selected (for example an inline autocompletion
        /// after the caret). The first Backspace would delete the selection, not a typed
        /// character, so this is never treated as unreadable or edited blind. Carries the
        /// text before the selection, which can still confirm an edit already made.
        case selection(textBeforeSelection: String)
        /// The field gives its whole text but no caret. Typing usually appends at the end, so a
        /// text ending with the expected state may stand in for the text before the caret; it can
        /// only allow an edit the blind rules would refuse, never refuse one they allow.
        case valueWithoutCaret(String)

        func needsAnotherRead(expects: (String) -> Bool) -> Bool {
            switch self {
            case .unreadable: return true
            case .textBeforeCaret(let text), .valueWithoutCaret(let text): return !expects(text)
            case .secure, .selection: return false
            }
        }
    }
    enum SelectionObservation: Equatable {
        case unreadable, secure
        /// Readable field with a collapsed caret.
        case none
        case text(String)
    }
    /// Universal mode, read-only: the selected text of the focused field of `pid`.
    static func observeSelection(pid: pid_t) -> SelectionObservation {
        guard AXIsProcessTrusted() else { return .unreadable }
        guard !IsSecureEventInputEnabled() else { return .secure }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.050)
        guard let raw = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return .unreadable
        }
        let field = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.050)
        if attribute(field, kAXSubroleAttribute) as? String == "AXSecureTextField" { return .secure }
        guard let selected = attribute(field, kAXSelectedTextAttribute) as? String else { return .unreadable }
        guard selected.utf16.count <= 65_536 else { return .unreadable }
        return selected.isEmpty ? .none : .text(selected)
    }
    /// Chromium and Electron build the accessibility tree of web content only on request.
    /// `AXManualAccessibility` asks for it without VoiceOver side effects; other
    /// applications answer with an error, which is harmless. Returns the AX status.
    static func requestWebAccessibility(pid: pid_t) -> AXError {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.050)
        return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
    /// The system-wide focused element, when Accessibility exposes it. Keystrokes go to the
    /// process owning it, which is not always the frontmost application: Spotlight and other
    /// non-activating panels keep the previous application frontmost while their own field
    /// receives keys (docs/SPOTLIGHT_FOCUS.md). No text is read here.
    struct FocusedElement {
        let pid: pid_t
        let application: String
        let role: String
        let isApplication: Bool
        let isTextInput: Bool
        let isSecure: Bool
    }
    private static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static func focusedElement() -> FocusedElement? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.050)
        guard let raw = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.050)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        let application = NSRunningApplication(processIdentifier: pid)
        return FocusedElement(pid: pid, application: application?.bundleIdentifier ?? "", role: role,
            isApplication: application != nil, isTextInput: textInputRoles.contains(role),
            isSecure: subrole == "AXSecureTextField")
    }
    /// What an unreadable focused element offers, without its text: the AX role and
    /// which text attributes answer. For reports only.
    static func describeFocused(pid: pid_t) -> (role: String?, checks: [String: Bool]) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.050)
        guard let raw = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return (nil, ["focusedField": false])
        }
        let field = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.050)
        func has(_ name: String) -> Bool { attribute(field, name) != nil }
        let children = (attribute(field, kAXChildrenAttribute) as? [AnyObject])?.count ?? 0
        return (attribute(field, kAXRoleAttribute) as? String, [
            "focusedField": true, "value": attribute(field, kAXValueAttribute) is String,
            "selectedRange": has(kAXSelectedTextRangeAttribute), "selectedText": has(kAXSelectedTextAttribute),
            "characterCount": has(kAXNumberOfCharactersAttribute), "textMarker": has("AXSelectedTextMarkerRange"),
            "editableAncestor": has("AXEditableAncestor"), "children": children > 0])
    }
    static func observeTextBeforeCaret(pid: pid_t) -> FieldObservation {
        guard AXIsProcessTrusted() else { return .unreadable }
        guard !IsSecureEventInputEnabled() else { return .secure }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.050)
        guard let raw = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return .unreadable
        }
        let field = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.050)
        if attribute(field, kAXSubroleAttribute) as? String == "AXSecureTextField" { return .secure }
        guard let text = attribute(field, kAXValueAttribute) as? String, text.utf16.count <= 65_536 else { return .unreadable }
        guard let rawRange = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else {
            // Some text areas give their text but no caret (AXTextArea in user reports).
            return .valueWithoutCaret(text)
        }
        var range = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range),
              let prefix = TextEdit.validatedRange(NSRange(location: 0, length: range.location), in: text) else {
            return .unreadable
        }
        return range.length == 0 ? .textBeforeCaret(String(text[prefix])) : .selection(textBeforeSelection: String(text[prefix]))
    }

    private static func checkedTimeout(_ budget: EditorSnapshotBudget, isCurrent: () -> Bool) throws -> Float {
        guard AXIsProcessTrusted() else { throw EditorSnapshotFailure.accessibilityDenied }
        guard !IsSecureEventInputEnabled() else { throw EditorSnapshotFailure.secureInput }
        let current = isCurrent()
        return try budget.timeout(now: ProcessInfo.processInfo.systemUptime, isCurrent: current)
    }
    private static func boundedAttribute(_ element: AXUIElement, _ key: String, budget: EditorSnapshotBudget,
                                         isCurrent: () -> Bool) throws -> (AXError, CFTypeRef?) {
        try boundedAXOperation(element, budget: budget, isCurrent: isCurrent) { readAttribute(element, key) }
    }
    private static func boundedAXOperation<Value>(_ element: AXUIElement, budget: EditorSnapshotBudget,
                                                  isCurrent: () -> Bool, operation: () -> Value) throws -> Value {
        guard AXIsProcessTrusted() else { throw EditorSnapshotFailure.accessibilityDenied }
        guard !IsSecureEventInputEnabled() else { throw EditorSnapshotFailure.secureInput }
        return try budget.perform(now: { ProcessInfo.processInfo.systemUptime }, isCurrent: isCurrent) { timeout in
            let configured = AXUIElementSetMessagingTimeout(element, timeout)
            guard configured == .success else { throw EditorSnapshotFailure.axError(configured.rawValue) }
            defer { AXUIElementSetMessagingTimeout(element, 0.15) }
            let result = operation()
            guard AXIsProcessTrusted() else { throw EditorSnapshotFailure.accessibilityDenied }
            guard !IsSecureEventInputEnabled() else { throw EditorSnapshotFailure.secureInput }
            return result
        }
    }
    static func capture(deadline: TimeInterval? = nil, isCurrent: () -> Bool = { true }) -> SnapshotResult {
        captureOnce(deadline: deadline ?? ProcessInfo.processInfo.systemUptime + 0.15,
            isCurrent: isCurrent, fieldObserved: { _ in true })
    }
    static func captureRetrying(deadline: TimeInterval, isCurrent: () -> Bool) -> SnapshotResult {
        var firstField: AXUIElement?
        let result: Result<EditorSnapshot, EditorSnapshotFailure> = EditorSnapshotBudget(deadline: deadline).retry(
            now: { ProcessInfo.processInfo.systemUptime }, isCurrent: isCurrent,
            pause: { Thread.sleep(forTimeInterval: $0) }) {
                let capture = captureOnce(deadline: deadline, isCurrent: isCurrent, fieldObserved: { field in
                    if let firstField { return CFEqual(firstField, field) }
                    firstField = field; return true
                })
                switch capture {
                case .success(let snapshot): return .success(snapshot)
                case .failure(let failure): return .failure(failure)
                }
            }
        switch result {
        case .success(let snapshot): return .success(snapshot)
        case .failure(let failure): return .failure(failure)
        }
    }
    private static func captureOnce(deadline: TimeInterval, isCurrent: () -> Bool,
                                    fieldObserved: (AXUIElement) -> Bool) -> SnapshotResult {
        let budget = EditorSnapshotBudget(deadline: deadline)
        func read(_ element: AXUIElement, _ key: String, optional: Bool = false) throws -> CFTypeRef? {
            let (status, value) = try boundedAttribute(element, key, budget: budget, isCurrent: isCurrent)
            switch status {
            case .success:
                if value == nil && !optional { throw EditorSnapshotFailure.invalidAttribute }
                return value
            case .noValue:
                if optional { return nil }
                throw EditorSnapshotFailure.targetUnavailable
            case .attributeUnsupported:
                if optional { return nil }
                throw EditorSnapshotFailure.unsupportedField
            case .cannotComplete: throw EditorSnapshotFailure.axCannotComplete
            case .apiDisabled: throw EditorSnapshotFailure.accessibilityDenied
            case .invalidUIElement: throw EditorSnapshotFailure.staleContext
            default: throw EditorSnapshotFailure.axError(status.rawValue)
            }
        }
        func element(_ raw: CFTypeRef?) throws -> AXUIElement {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw EditorSnapshotFailure.invalidAttribute }
            return raw as! AXUIElement
        }
        do {
            _ = try checkedTimeout(budget, isCurrent: isCurrent)
            guard let front = NSWorkspace.shared.frontmostApplication else { return .failure(.targetUnavailable) }
            guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  EditorSupport.permitsTextReplacement(applicationID: front.bundleIdentifier) else { return .failure(.unsupportedApplication) }
            let app = AXUIElementCreateApplication(front.processIdentifier)
            let field = try element(read(app, kAXFocusedUIElementAttribute))
            guard fieldObserved(field) else { return .failure(.staleContext) }
            guard let role = try read(field, kAXRoleAttribute) as? String else { return .failure(.invalidAttribute) }
            let subrole = try read(field, kAXSubroleAttribute, optional: true) as? String
            var container: String?
            if front.bundleIdentifier == "com.google.Chrome", role == kAXTextFieldRole {
                var ancestor = field
                for _ in 0..<16 {
                    ancestor = try element(read(ancestor, kAXParentAttribute))
                    let role = try read(ancestor, kAXRoleAttribute) as? String
                    if role == "AXWebArea" || role == kAXToolbarRole { container = role; break }
                }
            }
            let description = container == kAXToolbarRole ? try read(field, kAXDescriptionAttribute, optional: true) as? String : nil
            let addressBar = container == kAXToolbarRole && EditorSupport.isChromeAddressBar(applicationID: front.bundleIdentifier,
                role: role, subrole: subrole, description: description, inToolbar: true)
            guard EditorSupport.permitsEditableField(applicationID: front.bundleIdentifier, role: role,
                      subrole: subrole, webContent: container == "AXWebArea", addressBar: addressBar) else { return .failure(.unsupportedField) }
            let window = try element(read(field, kAXWindowAttribute))
            let document = try read(window, kAXDocumentAttribute, optional: true) as? String
            guard let text = try read(field, kAXValueAttribute) as? String else { return .failure(.invalidAttribute) }
            guard text.utf16.count <= 65_536 else { return .failure(.oversizedText) }
            guard let rawRange = try read(field, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else {
                return .failure(.invalidSelection)
            }
            var range = CFRange()
            guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range), range.location >= 0,
                  range.length >= 0, range.location <= text.utf16.count,
                  range.length <= text.utf16.count - range.location,
                  TextEdit.validatedRange(NSRange(location: range.location, length: range.length), in: text) != nil else {
                return .failure(.invalidSelection)
            }
            let focusedField = try element(read(app, kAXFocusedUIElementAttribute))
            guard CFEqual(field, focusedField) else { return .failure(.staleContext) }
            _ = try checkedTimeout(budget, isCurrent: isCurrent)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else { return .failure(.staleContext) }
            return .success(EditorSnapshot(element: field, window: window, document: document, pid: front.processIdentifier,
                application: front.bundleIdentifier ?? "", text: text,
                selection: NSRange(location: range.location, length: range.length), addressBar: addressBar))
        } catch let failure as EditorSnapshotFailure {
            return .failure(failure)
        } catch {
            return .failure(.invalidAttribute)
        }
    }
    static func sameTarget(_ a: EditorSnapshot, _ b: EditorSnapshot) -> Bool {
        guard a.pid == b.pid, a.keystrokes == b.keystrokes, a.addressBar == b.addressBar,
              CFEqual(a.element, b.element), a.document == b.document else { return false }
        switch (a.window, b.window) {
        case (nil, nil): return true
        case let (first?, second?): return CFEqual(first, second)
        default: return false
        }
    }
    static func setSelection(_ range: NSRange, on element: AXUIElement) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
    private static func awaitSelection(_ target: NSRange, in before: EditorSnapshot,
                                       pending: NSRange, deadline: TimeInterval? = nil,
                                       isCurrent: () -> Bool = { true }) -> EditorSnapshot? {
        let deadline = deadline ?? ProcessInfo.processInfo.systemUptime + 0.15
        repeat {
            guard let current = captureRetrying(deadline: deadline, isCurrent: isCurrent).snapshot,
                  sameTarget(before, current), current.text.utf16.elementsEqual(before.text.utf16) else { return nil }
            if current.selection == target { return current }
            guard current.selection == pending, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.003)
        } while true
    }
    @discardableResult
    private static func restoreSelectionIfOwned(_ before: EditorSnapshot, selectedRange: NSRange) -> Bool {
        let began = ProcessInfo.processInfo.systemUptime
        let budget = EditorSnapshotBudget(deadline: began + 0.15)
        var restored = false
        defer {
            InputDiagnostics.shared.record("selection-cleanup", revision: -1, checks: ["restored": restored,
                "deadlineExpired": ProcessInfo.processInfo.systemUptime >= budget.deadline],
                elapsed: ProcessInfo.processInfo.systemUptime - began)
        }
        guard let current = capture(deadline: budget.deadline).snapshot, sameTarget(before, current), current.text.utf16.elementsEqual(before.text.utf16),
              current.selection == selectedRange else { return false }
        if current.selection == before.selection { restored = true; return true }
        if (try? boundedAXOperation(current.element, budget: budget, isCurrent: { true },
            operation: { setSelection(before.selection, on: current.element) })) == true {
            restored = awaitSelection(before.selection, in: before, pending: selectedRange, deadline: budget.deadline) != nil
        }
        return restored
    }
    /// Native keyboard insertion reaches Chromium's editor input path; its
    /// AXSelectedText setter may acknowledge success without changing text.
    /// One Unicode packet replaces the selection, without a delete-then-insert
    /// sequence or clipboard changes. Never emit Return or control characters.
    private static func postKeyboardText(_ text: String, pid: pid_t) -> Bool {
        guard EditorSupport.permitsKeyboardText(text),
              CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: EditorSupport.syntheticEventTag)
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
        }
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
    /// Chromium's native command keeps multiline text inside its editor's paste
    /// path. Do not move AX selection, alter the clipboard, or emit text keys.
    static func pastePlainNative(_ before: EditorSnapshot, text: String,
                                 clipboardChangeCount: Int? = nil,
                                 deadline: TimeInterval? = nil,
                                 isCurrent: () -> Bool = { true }) -> ReplacementResult {
        let began = ProcessInfo.processInfo.systemUptime
        let budget = EditorSnapshotBudget(deadline: deadline ?? began + 0.2)
        func trace(_ phase: String, _ checks: [String: Bool]) {
            InputDiagnostics.shared.record("native-paste-" + phase, revision: -1, checks: checks,
                elapsed: ProcessInfo.processInfo.systemUptime - began)
        }
        var initialChecks: [String: Bool] = [:]
        func checked(_ name: String, _ predicate: @autoclosure () -> Bool) -> Bool {
            let value = predicate(); initialChecks[name] = value; return value
        }
        func initialSnapshot() -> EditorSnapshot? {
            let value = capture(deadline: budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline,
                isCurrent: isCurrent).snapshot; initialChecks["snapshotAvailable"] = value != nil; return value
        }
        func initialEdit(_ snapshot: EditorSnapshot) -> TextEdit? {
            let value = TextEdit(text: snapshot.text, selection: snapshot.selection, replacement: text)
            initialChecks["editValid"] = value != nil
            return value
        }
        func initialSource() -> CGEventSource? {
            let value = CGEventSource(stateID: .privateState)
            initialChecks["sourceCreated"] = value != nil
            return value
        }
        trace("enter", [:])
        guard checked("backend", EditorSupport.insertionBackend(applicationID: before.application) == .keyboardEvents),
              checked("payloadAllowed", EditorSupport.permitsPlainPasteInterception(applicationID: before.application, text: text)),
              checked("current", isCurrent()), let now = initialSnapshot(),
              checked("sameTarget", sameTarget(before, now)), checked("sameText", now.text.utf16.elementsEqual(before.text.utf16)),
              checked("sameSelection", now.selection == before.selection),
              let edit = initialEdit(now),
              checked("boundedEdit", edit.expectedText.utf16.count <= 65_536),
              checked("postAccess", CGPreflightPostEventAccess()), checked("secureInputClear", !IsSecureEventInputEnabled()),
              let source = initialSource() else {
            initialChecks["accepted"] = false
            trace("initial-snapshot", initialChecks)
            return .notApplied
        }
        initialChecks["accepted"] = true
        trace("initial-snapshot", initialChecks)
        let pasteboard = NSPasteboard.general
        let generation = clipboardChangeCount ?? pasteboard.changeCount
        guard pasteboard.changeCount == generation, pasteboard.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true,
              pasteboard.changeCount == generation else { trace("clipboard", ["matched": false]); return .notApplied }
        trace("clipboard", ["matched": true])
        let insertionCaret = NSRange(location: edit.cursor, length: 0)
        let modifiers: [(mask: CGEventFlags, key: CGKeyCode, side: UInt64)] = [
            (.maskCommand, 55, 0x8), (.maskAlternate, 58, 0x20), (.maskShift, 56, 0x2)]
        var held = CGEventFlags()
        var pressed: [(mask: CGEventFlags, key: CGKeyCode, side: UInt64)] = []
        var vDown = false
        var frameStarted = false
        func expectedPasteText(_ candidate: String) -> Bool {
            EditorSupport.nativePasteTextMatches(applicationID: now.application,
                beforeText: now.text, selection: now.selection, payload: text, actualText: candidate)
        }
        func ownedTarget(deadline: TimeInterval? = nil, isCurrent: () -> Bool = { true }) -> EditorSnapshot? {
            var checks: [String: Bool] = [:]
            func targetCheck(_ name: String, _ predicate: @autoclosure () -> Bool) -> Bool {
                let value = predicate(); checks[name] = value; return value
            }
            func targetSnapshot() -> EditorSnapshot? {
                let targetBudget = EditorSnapshotBudget(deadline: deadline ?? budget.deadline).stage(now: ProcessInfo.processInfo.systemUptime)
                let value = capture(deadline: targetBudget.deadline, isCurrent: isCurrent).snapshot; checks["snapshotAvailable"] = value != nil; return value
            }
            guard targetCheck("trusted", AXIsProcessTrusted()), targetCheck("postAccess", CGPreflightPostEventAccess()),
                  targetCheck("secureInputClear", !IsSecureEventInputEnabled()), let current = targetSnapshot(),
                  targetCheck("sameTarget", sameTarget(now, current)) else {
                trace("target-failed", checks); return nil
            }
            return current
        }
        func send(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool) -> Bool {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                trace("send-failed", ["modifier": modifier, "syntheticPress": down]); return false
            }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EditorSupport.syntheticEventTag)
            event.postToPid(now.pid)
            return true
        }
        func frameAllowed(afterPaste: Bool) -> Bool {
            let currentRevision = isCurrent()
            guard currentRevision, ProcessInfo.processInfo.systemUptime < budget.deadline else {
                trace("frame-refused", ["current": currentRevision, "afterPaste": afterPaste,
                    "deadlineExpired": ProcessInfo.processInfo.systemUptime >= budget.deadline]); return false
            }
            guard pasteboard.changeCount == generation else { trace("frame-refused", ["current": true, "clipboardMatched": false, "afterPaste": afterPaste]); return false }
            guard let current = ownedTarget(isCurrent: isCurrent) else { trace("frame-refused", ["current": true, "clipboardMatched": true, "target": false, "afterPaste": afterPaste]); return false }
            if current.matchesContent(now) { return true }
            let accepted = afterPaste && expectedPasteText(current.text) &&
                (current.selection == insertionCaret || current.selection == now.selection)
            if !accepted { trace("frame-refused", ["current": true, "clipboardMatched": true, "target": true, "context": false, "afterPaste": afterPaste]) }
            return accepted
        }
        defer {
            // Release only keys created by this private, PID-targeted frame.
            // A changed focus/window/field forbids even a synthetic cleanup.
            let cleanupBegan = ProcessInfo.processInfo.systemUptime
            let cleanupDeadline = cleanupBegan + 0.15
            if vDown, ownedTarget(deadline: cleanupDeadline) != nil,
               send(9, down: false, flags: held, modifier: false) { vDown = false }
            for modifier in pressed.reversed() {
                guard ownedTarget(deadline: cleanupDeadline) != nil else { break }
                held = CGEventFlags(rawValue: held.rawValue & ~(modifier.mask.rawValue | modifier.side))
                guard send(modifier.key, down: false, flags: held, modifier: true) else { break }
                pressed.removeLast()
            }
            if frameStarted {
                InputDiagnostics.shared.record("native-paste-cleanup", revision: -1,
                    checks: ["released": !vDown && pressed.isEmpty,
                        "deadlineExpired": ProcessInfo.processInfo.systemUptime >= cleanupDeadline],
                    elapsed: ProcessInfo.processInfo.systemUptime - cleanupBegan)
            }
        }
        for modifier in modifiers {
            guard frameAllowed(afterPaste: false) else { return frameStarted ? .uncertain : .notApplied }
            held = CGEventFlags(rawValue: held.rawValue | modifier.mask.rawValue | modifier.side)
            guard send(modifier.key, down: true, flags: held, modifier: true) else { return frameStarted ? .uncertain : .notApplied }
            pressed.append(modifier)
            if !frameStarted { frameStarted = true; trace("frame-started", ["posted": true]) }
        }
        guard frameAllowed(afterPaste: false), send(9, down: true, flags: held, modifier: false) else { return .uncertain }
        vDown = true
        trace("paste-sent", ["posted": true])
        guard frameAllowed(afterPaste: true), send(9, down: false, flags: held, modifier: false) else { return .uncertain }
        vDown = false
        while let modifier = pressed.last {
            guard frameAllowed(afterPaste: true) else { return .uncertain }
            held = CGEventFlags(rawValue: held.rawValue & ~(modifier.mask.rawValue | modifier.side))
            guard send(modifier.key, down: false, flags: held, modifier: true) else { return .uncertain }
            pressed.removeLast()
        }
        trace("frame-completed", ["posted": true])
        let deadline = budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline
        repeat {
            let currentRevision = isCurrent()
            guard currentRevision else { trace("ACK", ["verified": false, "current": false]); return .uncertain }
            guard pasteboard.changeCount == generation else { trace("ACK", ["verified": false, "current": true, "clipboardMatched": false]); return .uncertain }
            guard let after = ownedTarget(deadline: deadline, isCurrent: isCurrent) else { trace("ACK", ["verified": false, "current": true, "clipboardMatched": true, "target": false]); return .uncertain }
            if expectedPasteText(after.text) && after.selection == insertionCaret {
                trace("ACK", ["verified": true, "current": true, "clipboardMatched": true, "target": true]); return .verified(after)
            }
            let unchanged = after.matchesContent(now)
            let pendingSelection = expectedPasteText(after.text) && after.selection == now.selection
            guard unchanged || pendingSelection, ProcessInfo.processInfo.systemUptime < deadline else {
                trace("ACK", ["verified": false, "current": true, "clipboardMatched": true, "target": true,
                    "unchanged": unchanged, "pendingSelection": pendingSelection,
                    "deadlineExpired": ProcessInfo.processInfo.systemUptime >= deadline]); return .uncertain
            }
            Thread.sleep(forTimeInterval: 0.003)
        } while true
    }
    /// AX setters can acknowledge before their value and caret readbacks catch up.
    static func awaitInsertion(in before: EditorSnapshot, range: NSRange, edit: TextEdit,
                               deadline: TimeInterval, isCurrent: () -> Bool,
                               read: () -> EditorSnapshot?) -> EditorSnapshot? {
        let insertionCaret = NSRange(location: edit.cursor, length: 0)
        while isCurrent(), ProcessInfo.processInfo.systemUptime < deadline {
            guard let current = read(), isCurrent(), ProcessInfo.processInfo.systemUptime < deadline,
                  sameTarget(before, current) else { return nil }
            if current.text.utf16.elementsEqual(edit.expectedText.utf16), current.selection == insertionCaret { return current }
            // Chrome can publish the insertion caret before its AX text; this only permits a bounded reread.
            let pendingOriginal = current.text.utf16.elementsEqual(before.text.utf16) &&
                (current.selection == range || (before.application == "com.google.Chrome" && current.selection == insertionCaret))
            let pendingInsertion = current.text.utf16.elementsEqual(edit.expectedText.utf16) &&
                (current.selection == range || current.selection == before.selection)
            InputDiagnostics.shared.record("insertion-observation", revision: -1, checks: [
                "originalText": current.text.utf16.elementsEqual(before.text.utf16),
                "expectedText": current.text.utf16.elementsEqual(edit.expectedText.utf16),
                "insertionCaret": current.selection == insertionCaret,
                "originalSelection": current.selection == before.selection,
                "replacementSelection": current.selection == range,
                "pending": pendingOriginal || pendingInsertion])
            guard pendingOriginal || pendingInsertion else { return nil }
            Thread.sleep(forTimeInterval: min(0.003, max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        }
        return nil
    }

    static func replace(_ before: EditorSnapshot, range: NSRange, replacement: String,
                        keepSelection: Bool = false, testSelectionDelay: TimeInterval = 0,
                        testKeyboardInsertion: ((String, pid_t) -> Bool)? = nil,
                        deadline: TimeInterval? = nil,
                        isCurrent: () -> Bool = { true }) -> ReplacementResult {
        let budget = EditorSnapshotBudget(deadline: deadline ?? ProcessInfo.processInfo.systemUptime + 0.2)
        var stage = "preflight"
        defer { InputDiagnostics.shared.record("replacement-stage", revision: -1,
            checks: ["deadlineExpired": ProcessInfo.processInfo.systemUptime >= budget.deadline],
            reason: stage) }
        guard EditorSupport.permitsTextReplacement(applicationID: before.application), isCurrent() else { return .notApplied }
        let initial = capture(deadline: budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline, isCurrent: isCurrent)
        InputDiagnostics.shared.record("replacement-preflight", revision: -1, checks: [
            "snapshot": initial.snapshot != nil,
            "target": initial.snapshot.map { sameTarget(before, $0) } ?? false,
            "content": initial.snapshot.map { before.matchesContent($0) } ?? false], reason: initial.failure?.diagnosticCode)
        guard let now = initial.snapshot, sameTarget(before, now), before.matchesContent(now),
              let edit = TextEdit(text: now.text, selection: range, replacement: replacement),
              !now.addressBar || (EditorSupport.permitsAddressBarCorrection(now.text) &&
                  EditorSupport.permitsAddressBarCorrection(edit.expectedText)) else { return .notApplied }
        guard let backend = EditorSupport.insertionBackend(applicationID: now.application) else { return .notApplied }
        if backend == .selectedText {
            var writable: DarwinBoolean = false
            guard (try? boundedAXOperation(now.element, budget: budget, isCurrent: isCurrent, operation: {
                AXUIElementIsAttributeSettable(now.element, kAXSelectedTextAttribute as CFString, &writable)
            })) == .success,
                  writable.boolValue else { return .notApplied }
        } else {
            guard EditorSupport.permitsKeyboardText(replacement),
                  CGPreflightPostEventAccess() else { return .notApplied }
        }
        guard isCurrent() else { return .notApplied }
        stage = "selection-request"
        var selectionAttempted = false
        let selectionSet = try? boundedAXOperation(now.element, budget: budget, isCurrent: isCurrent) {
            selectionAttempted = true
            return setSelection(range, on: now.element)
        }
        guard selectionSet == true else {
            guard selectionAttempted else { return .notApplied }
            restoreSelectionIfOwned(now, selectedRange: range)
            return .uncertain
        }
        // Check focus and value again after moving the selection; never write into a new field.
        stage = "selection-readback"
        let selectionDeadline = budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline
        guard let selected = awaitSelection(range, in: now, pending: now.selection, deadline: selectionDeadline, isCurrent: isCurrent),
              let (selectionStatus, selectedText) = try? boundedAttribute(selected.element, kAXSelectedTextAttribute,
                  budget: .init(deadline: selectionDeadline), isCurrent: isCurrent), selectionStatus == .success,
              (selectedText as? String)?.utf16.elementsEqual(
                (now.text as NSString).substring(with: range).utf16) == true else {
            return restoreSelectionIfOwned(now, selectedRange: range) ? .notApplied : .uncertain
        }
        // Explicit diagnostic fault injection; zero in normal launches, bounded by caller.
        if testSelectionDelay > 0 {
            Thread.sleep(forTimeInterval: max(0, min(testSelectionDelay, 0.15, budget.deadline - ProcessInfo.processInfo.systemUptime)))
        }
        guard (try? checkedTimeout(budget, isCurrent: isCurrent)) != nil else {
            return restoreSelectionIfOwned(now, selectedRange: range) ? .notApplied : .uncertain
        }
        stage = "insertion-request"
        let inserted: Bool
        switch backend {
        case .selectedText:
            inserted = (try? boundedAXOperation(now.element, budget: budget, isCurrent: isCurrent) {
                AXUIElementSetAttributeValue(now.element, kAXSelectedTextAttribute as CFString, replacement as CFString)
            }) == .success
        case .keyboardEvents:
            if let testKeyboardInsertion { inserted = testKeyboardInsertion(replacement, now.pid) }
            else { inserted = postKeyboardText(replacement, pid: now.pid) }
        }
        guard inserted else {
            restoreSelectionIfOwned(now, selectedRange: range)
            return .uncertain
        }
        stage = "insertion-readback"
        let insertionCaret = NSRange(location: edit.cursor, length: 0)
        let deadline = budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline
        guard let after = awaitInsertion(in: now, range: range, edit: edit, deadline: deadline,
            isCurrent: isCurrent, read: { captureRetrying(deadline: deadline, isCurrent: isCurrent).snapshot }) else {
            // A no-op must not leave our temporary word selection behind: a
            // subsequent Space would otherwise erase that selected word.
            restoreSelectionIfOwned(now, selectedRange: range)
            return .uncertain
        }
        let finalSelection = edit.resultingSelection(from: now.selection, keepSelection: keepSelection)
        if after.selection == finalSelection { stage = "verified"; return .verified(after) }
        stage = "final-selection"
        let finalDeadline = budget.stage(now: ProcessInfo.processInfo.systemUptime).deadline
        guard isCurrent(), let owned = capture(deadline: finalDeadline, isCurrent: isCurrent).snapshot,
              sameTarget(now, owned), owned.text.utf16.elementsEqual(edit.expectedText.utf16),
              owned.selection == insertionCaret, isCurrent(),
              (try? boundedAXOperation(owned.element, budget: .init(deadline: finalDeadline), isCurrent: isCurrent,
                  operation: { setSelection(finalSelection, on: owned.element) })) == true,
              let final = awaitSelection(finalSelection, in: owned, pending: insertionCaret,
                  deadline: finalDeadline, isCurrent: isCurrent) else { return .uncertain }
        stage = "verified"
        return .verified(final)
    }
}
