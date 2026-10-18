import AppKit
import ApplicationServices
import Carbon
import Foundation

struct ProbeFailure: Error {
    let message: String
    var initiallyMissing = false
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeFailure(message: message) }
}
func output(_ values: [String: Any]) {
    var record = values
    record["axReadErrors"] = axReadErrors
    record["axReadTiming"] = axReadTiming
    if CommandLine.arguments.contains("--validate-cases") {
        // Argument errors in the offline decoder must not query WindowServer either.
        record["events"] = 0; record["pureFixtureValidation"] = true; record["nativeAcceptance"] = false
    } else {
        record["finalModifierFlags"] = CGEventSource.flagsState(.hidSystemState).rawValue
    }
    if traceTagsRequested {
        record["tagTrace"] = activeTagTrace?.summary ?? ["started": false, "taggedSamples": 0]
    }
    let data = try! JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
func settle(_ seconds: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
func modifiersNeutral() -> Bool {
    [CGEventSourceStateID.hidSystemState, .combinedSessionState].allSatisfy {
        CGEventSource.flagsState($0).rawValue & 0x9f207f == 0
    }
}
// Counts only failed AX attribute names/status codes for the authenticated test
// workflow. No values, user text, keycodes or cross-application reads are added.
var axReadErrors: [String: Int] = [:]
// Aggregated IPC durations only. Attribute names/statuses have fixed bounded
// cardinality; no attribute values or event/document identifiers are retained.
var axReadTiming: [String: [String: Double]] = [:]
func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let started = ProcessInfo.processInfo.systemUptime
    let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
    let timingKey = "\(key):\(status.rawValue)"
    var timing = axReadTiming[timingKey] ?? ["count": 0, "totalMilliseconds": 0, "maxMilliseconds": 0]
    timing["count", default: 0] += 1
    timing["totalMilliseconds", default: 0] += elapsed
    timing["maxMilliseconds"] = max(timing["maxMilliseconds", default: 0], elapsed)
    axReadTiming[timingKey] = timing
    guard status == .success else {
        axReadErrors["\(key):\(status.rawValue)", default: 0] += 1
        return nil
    }
    return value
}
func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func sourceID(_ source: TISInputSource?) -> String {
    guard let source, let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}
func currentSource() -> TISInputSource? { TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() }

struct ProbeCase: Decodable {
    var id: String
    var text: String
    var source: String
    var gesture: String?
    var boundary: Bool?
    var selectAllBeforeGesture: Bool?
    var pasteText: String?
    var firstWordAfterFocus: Bool? = nil
    var preGestureDelayMilliseconds: Int? = nil
    var scrollAfterCharacters: Int? = nil
}
func validateText(_ text: String) throws {
    try require(text.count <= 128 && text.unicodeScalars.allSatisfy { (32...126).contains($0.value) }, "bounded_printable_ascii_required")
}
func validateCase(_ item: ProbeCase) throws {
    try validateText(item.text)
    try require(!item.id.isEmpty && item.id.count <= 80 && item.id.unicodeScalars.allSatisfy { (32...126).contains($0.value) }, "invalid_case_id")
    try require(["ABC", "RussianWin", "Russian"].contains(item.source), "unsupported_source")
    let gesture = item.gesture ?? "none"
    if let count = item.scrollAfterCharacters {
        try require(count > 0 && count < item.text.count && item.firstWordAfterFocus != true,
                    "scroll_requires_internal_word_position")
    }
    try require(["none", "manual", "cmdoptspace", "undo", "cmdoptz", "recover", "interruptRecover", "doubleShift", "dragDoubleShift", "singleShift", "chord", "plainPaste", "optionTap", "nativeUndo", "manualUndo", "backspace", "doubleBackspace"].contains(gesture), "unsupported_gesture")
    if gesture == "dragDoubleShift" {
        try require(item.boundary == false && item.selectAllBeforeGesture != true && item.text == "ghbdtn",
                    "drag_requires_single_test_word")
    }
    if let text = item.pasteText { try validateText(text); try require(gesture == "plainPaste", "paste_text_requires_plainPaste") }
    if gesture == "plainPaste" { try require(item.pasteText != nil, "plainPaste_requires_synthetic_paste_text") }
    if item.firstWordAfterFocus == true {
        try require(item.text == "ghbdtn" && item.source == "ABC" && gesture == "none" && (item.boundary ?? true) &&
                    item.selectAllBeforeGesture != true && item.pasteText == nil, "first_word_requires_plain_ghbdtn_fixture")
    }
    if gesture == "interruptRecover" {
        try require(item.text == "ghbdtn he" && item.source == "ABC" && item.boundary == false &&
                    item.preGestureDelayMilliseconds == 0 && item.selectAllBeforeGesture != true &&
                    item.pasteText == nil, "interrupted_recovery_requires_exact_fixture")
    }
    if let delay = item.preGestureDelayMilliseconds {
        try require((0...1000).contains(delay) && (gesture == "doubleShift" || gesture == "interruptRecover") && item.boundary == false &&
                    item.selectAllBeforeGesture != true && item.pasteText == nil, "gesture_delay_requires_unselected_double_shift_fixture")
    }
}
struct Arguments {
    var cases: [ProbeCase] = []
    var interval: TimeInterval = 0.080
    var settleTime: TimeInterval = 1
    var status = false
    var traceTags = false
    var referenceSelectionClipboard = false
    var batch = false
    var validateOnly = false
    var idleAfterBatch = false
    var initialText = ""
    init() throws {
        var text: String?, source = "ABC", gesture = "none", boundary = true
        var selectAll = false, pasteText: String?, batchPath: String?
        var hasInitialText = false
        let args = Array(CommandLine.arguments.dropFirst()); var index = 0
        while index < args.count {
            let flag = args[index]
            if flag == "--status" { status = true; index += 1; continue }
            if flag == "--validate-cases" { validateOnly = true; index += 1; continue }
            if flag == "--idle-after-batch" { idleAfterBatch = true; index += 1; continue }
            if flag == "--trace-tags" { traceTags = true; index += 1; continue }
            if flag == "--reference-selection-clipboard" { referenceSelectionClipboard = true; index += 1; continue }
            if flag == "--no-boundary" { boundary = false; index += 1; continue }
            if flag == "--select-all-before-gesture" { selectAll = true; index += 1; continue }
            try require(index + 1 < args.count, "missing_argument_value")
            let value = args[index + 1]
            switch flag {
            case "--text": text = value
            case "--initial-text": initialText = value; hasInitialText = true
            case "--source": source = value
            case "--gesture": gesture = value
            case "--paste-text": pasteText = value
            case "--batch": batchPath = value; batch = true
            case "--interval-ms":
                guard let ms = Double(value), ms.isFinite, (10...1000).contains(ms) else { throw ProbeFailure(message: "interval_requires_10_to_1000_ms") }
                interval = ms / 1000
            case "--settle-ms":
                guard let ms = Double(value), ms.isFinite, (100...3000).contains(ms) else { throw ProbeFailure(message: "settle_requires_100_to_3000_ms") }
                settleTime = ms / 1000
            default: throw ProbeFailure(message: "unknown_argument")
            }
            index += 2
        }
        try require(!status || (!validateOnly && !idleAfterBatch), "status_cannot_mix_workload_modes")
        if status { return }
        try require(initialText.count <= 128 && initialText.unicodeScalars.count <= 512 && initialText.utf16.count <= 1024 && !initialText.contains("\0"), "bounded_unicode_initial_text_required")
        if let path = batchPath {
            try require(!hasInitialText, "initial_text_single_case_only")
            try require(text == nil && pasteText == nil && !selectAll && source == "ABC" && gesture == "none" && boundary, "batch_cases_cannot_mix_single_case_options")
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            try require(data.count <= 1_048_576, "batch_file_too_large")
            cases = try JSONDecoder().decode([ProbeCase].self, from: data)
            try require((1...200).contains(cases.count), "batch_requires_1_to_200_cases")
        } else {
            guard let text else { throw ProbeFailure(message: "text_required") }
            cases = [ProbeCase(id: "single", text: text, source: source, gesture: gesture, boundary: boundary, selectAllBeforeGesture: selectAll, pasteText: pasteText)]
        }
        try require(Set(cases.map(\.id)).count == cases.count, "duplicate_case_id")
        try require(!idleAfterBatch || batch, "idle_requires_batch")
        try require(!validateOnly || batch, "validation_requires_batch")
        for (caseIndex, item) in cases.enumerated() {
            try validateCase(item)
            try require(item.firstWordAfterFocus != true || (batch && caseIndex == 0), "first_word_requires_first_case_of_new_document")
            if referenceSelectionClipboard {
                try require(item.selectAllBeforeGesture == true && item.gesture == "doubleShift" && item.pasteText == nil, "reference_clipboard_requires_selected_double_shift_only")
            }
        }
    }
}

/// Diagnostic listener: stores only nonzero 64-bit tags and event-type counts.
/// No keycodes, Unicode, flags, text, event ordering, or timestamps are retained.
final class TagTrace {
    private let pid: pid_t
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var histogram: [String: [String: Int]] = [:]
    private var modifierFrames: [[String: Any]] = []
    private var typeCounts: [String: Int] = [:]
    private var samples = 0
    private var started = false
    private var state = "not_started"
    init(pid: pid_t) { self.pid = pid }
    func start() throws {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) |
                               (1 << CGEventType.keyUp.rawValue) |
                               (1 << CGEventType.flagsChanged.rawValue))
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, info in
            if let info {
                Unmanaged<TagTrace>.fromOpaque(info).takeUnretainedValue().observe(type, event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { state = "unavailable"; throw ProbeFailure(message: "trace_tap_unavailable") }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop(reason: "unavailable")
            throw ProbeFailure(message: "trace_run_loop_source_unavailable")
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        started = true
        state = "listening"
    }
    private func observe(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(reason: "tap_disabled")
            return
        }
        guard samples < 512 else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            stop(reason: "target_not_frontmost")
            return
        }
        let name: String
        switch type {
        case .keyDown: name = "keyDown"
        case .keyUp: name = "keyUp"
        case .flagsChanged: name = "flagsChanged"
        default: return
        }
        let tag = event.getIntegerValueField(.eventSourceUserData)
        guard tag != 0 else { return }
        let key = String(format: "0x%016llx", UInt64(bitPattern: tag))
        histogram[key, default: [:]][name, default: 0] += 1
        typeCounts[name, default: 0] += 1
        samples += 1
        // Only tagged test modifier frames; no ordinary keycodes or text.
        let modifierNames: [Int64: String] = [54:"rightCommand",55:"leftCommand",56:"leftShift",57:"capsLock",58:"leftOption",59:"leftControl",60:"rightShift",61:"rightOption",62:"rightControl"]
        if type == .flagsChanged, tag == Probe.eventTag,
           let modifier = modifierNames[event.getIntegerValueField(.keyboardEventKeycode)], modifierFrames.count < 128 {
            modifierFrames.append(["modifier": modifier, "rawFlags": event.flags.rawValue,
                "eventTimestampNanoseconds": event.timestamp,
                "observedUptime": ProcessInfo.processInfo.systemUptime])
        }
        if samples == 512 { stop(reason: "sample_limit") }
    }
    func stop(reason: String = "stopped") {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        runLoopSource = nil
        if state == "listening" || state == "not_started" { state = reason }
    }
    var summary: [String: Any] {
        ["started": started, "state": state, "maxTaggedSamples": 512, "taggedSamples": samples,
         "nonzeroTagTypeHistogram": histogram, "taggedTypeCounts": typeCounts,
         "modifierFrames": modifierFrames, "modifierFrameCap": 128,
         "ordinaryKeycodesOrTextLogged": false]
    }
    deinit { stop() }
}
var traceTagsRequested = false
var activeTagTrace: TagTrace?

/// Retains every pasteboard representation only in memory. Never prints its values.
final class ClipboardLease {
    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]
    private var saved: Snapshot = []
    private var syntheticItems: Snapshot = []
    private var ownedChange: Int?
    private var completed: String?
    // Only the explicitly requested original-selection experiment may adopt the
    // original's round-trip of our nonce. No private pasteboard data is logged.
    private let referenceContext: (() throws -> Void)?
    private static func snapshot(_ board: NSPasteboard) throws -> Snapshot {
        let items = board.pasteboardItems
        try require(items != nil || (board.types ?? []).isEmpty, "clipboard_items_cannot_be_preserved")
        var result: Snapshot = [], bytes = 0, representations = 0
        try require((items?.count ?? 0) <= 1024, "clipboard_item_limit")
        for item in items ?? [] {
            var values: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                representations += 1
                try require(representations <= 4096, "clipboard_representation_limit")
                guard let data = item.data(forType: type) else { throw ProbeFailure(message: "clipboard_representation_cannot_be_preserved") }
                try require(data.count <= 64 * 1024 * 1024 - bytes, "clipboard_snapshot_exceeds_64_mib")
                bytes += data.count
                values.append((type, data))
            }
            result.append(values)
        }
        return result
    }
    private static func equal(_ left: Snapshot, _ right: Snapshot) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.count == b.count && Set(a.map { $0.0 }) == Set(b.map { $0.0 }) &&
            a.allSatisfy { type, data in b.contains { $0.0 == type && $0.1 == data } }
        }
    }
    init(synthetic: String, referenceContext: (() throws -> Void)? = nil) throws {
        self.referenceContext = referenceContext
        let board = NSPasteboard.general
        let initial = board.changeCount
        saved = try Self.snapshot(board)
        try require(board.changeCount == initial, "clipboard_changed_before_test_write")
        try referenceContext?()
        try require(board.changeCount == initial, "clipboard_changed_before_test_write")
        board.clearContents()
        ownedChange = board.changeCount
        if !board.writeObjects([synthetic as NSString]) {
            ownedChange = board.changeCount
            _ = restore()
            throw ProbeFailure(message: "synthetic_clipboard_write_failed")
        }
        ownedChange = board.changeCount
        // Keep only a RAM copy of representations generated by our own write.
        // A failed readback never authorizes adopting a later pasteboard owner.
        do {
            syntheticItems = try Self.snapshot(board)
            try require(board.changeCount == ownedChange, "synthetic_clipboard_changed_during_readback")
        } catch {
            _ = restore()
            throw error
        }
    }
    @discardableResult func restore() -> String {
        if let completed { return completed }
        let board = NSPasteboard.general
        if let referenceContext {
            do { try referenceContext() }
            catch { completed = "skipped_unverified_reference_context"; return completed! }
        }
        guard var ownedChange else { completed = "skipped_newer_clipboard"; return completed! }
        if board.changeCount != ownedChange {
            guard let referenceContext, !syntheticItems.isEmpty else {
                completed = "skipped_newer_clipboard"; return completed!
            }
            // Stable, exact all-item nonce round-trip is the sole exception to
            // the usual generation ownership rule. Never adopt arbitrary text.
            let returnedChange = board.changeCount
            do {
                try referenceContext()
                let returned = try Self.snapshot(board)
                guard board.changeCount == returnedChange, Self.equal(returned, syntheticItems) else {
                    completed = "skipped_newer_clipboard"; return completed!
                }
                try referenceContext()
                guard board.changeCount == returnedChange else {
                    completed = "skipped_newer_clipboard"; return completed!
                }
            } catch { completed = "skipped_unverified_reference_context"; return completed! }
            self.ownedChange = returnedChange
            ownedChange = returnedChange
        }
        // Reauthenticate immediately before a restore, including after adoption.
        if let referenceContext {
            do { try referenceContext() }
            catch { completed = "skipped_unverified_reference_context"; return completed! }
        }
        guard board.changeCount == ownedChange else { completed = "skipped_newer_clipboard"; return completed! }
        let items = saved.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        guard items.isEmpty || board.writeObjects(items) else { completed = "restore_failed"; return completed! }
        let restoredChange = board.changeCount
        do {
            let restored = try Self.snapshot(board)
            if board.changeCount != restoredChange { completed = "changed_during_restore_readback" }
            else { completed = Self.equal(restored, saved) ? "restored_all_representations" : "restore_readback_failed" }
        } catch { completed = "restore_readback_failed" }
        return completed!
    }
    deinit { _ = restore() }
}

/// Exact installed reference only. This mode must never expose a user's original
/// pasteboard to Caramba's string-only selected-text clipboard round-trip.
func verifyReferenceSelectionSwitcher() throws {
    let applications = NSWorkspace.shared.runningApplications
    let expected = URL(fileURLWithPath: "/Applications/Caramba Switcher Pro.app/Contents/MacOS/Caramba Switcher Pro").standardizedFileURL
    let originals = applications.filter { $0.executableURL?.standardizedFileURL == expected }
    try require(originals.count == 1 && !originals[0].isTerminated, "reference_switcher_exact_original_required")
    let competitors = applications.filter { app in
        let name = app.localizedName ?? ""
        let executable = app.executableURL?.lastPathComponent ?? ""
        return ["LayoutPilot", "Lang Switcher", "LangSwitcher", "TypeTune"].contains(name) ||
            ["LayoutPilot", "Lang Switcher", "LangSwitcher", "TypeTune"].contains(executable) ||
            (name == "Caramba Switcher Pro" && app.executableURL?.standardizedFileURL != expected)
    }
    try require(competitors.isEmpty, "reference_switcher_conflict")
}

final class Probe {
    let target: URL
    let pid: pid_t
    let source: CGEventSource
    var events = 0
    var gestureIntermediate: [String: Any] = [:]
    var firstEventUptime: TimeInterval?
    var lastEventUptime: TimeInterval?
    private var authenticatedField: AXUIElement?
    private var authenticatedWindow: AXUIElement?
    static let eventTag: Int64 = 0x4c505052 // LPPR; deliberately different from LayoutPilot syntheticTag.
    init(target: URL, pid: pid_t) throws {
        self.target = target.standardizedFileURL.resolvingSymlinksInPath(); self.pid = pid
        guard let source = CGEventSource(stateID: .hidSystemState) else { throw ProbeFailure(message: "no_hid_event_source") }
        self.source = source
    }
    /// Do not read AXValue until the exact newly created document is authenticated.
    func verifiedField() throws -> AXUIElement {
        let retryDeadline = ProcessInfo.processInfo.systemUptime + 0.300
        var retryFailure = "focused_window_document_unverified"
        // Wait for a positive AX response within the same overall 300ms gate.
        // Every attribute is still checked; a slow success after the deadline
        // cannot authorize emission. Missing pinned identities still fail closed.
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            let remaining = retryDeadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.150, remaining)))
            return attr(element, key)
        }
        func retryMissing(_ reason: String) throws {
            try require(authenticatedField != nil && authenticatedWindow != nil, reason)
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "target_not_frontmost")
            try require(ProcessInfo.processInfo.systemUptime + 0.020 <= retryDeadline, reason)
            retryFailure = reason
            settle(0.020)
        }
        while true {
            try require(ProcessInfo.processInfo.systemUptime < retryDeadline, retryFailure)
            try require(AXIsProcessTrusted(), "accessibility_not_trusted")
            try require(CGPreflightPostEventAccess(), "post_event_access_not_granted")
            try require(!IsSecureEventInputEnabled(), "secure_input_enabled")
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "target_not_frontmost")
            let app = AXUIElementCreateApplication(pid)

            let rawWindow = read(app, kAXFocusedWindowAttribute)
            if rawWindow == nil {
                if authenticatedField == nil && authenticatedWindow == nil {
                    throw ProbeFailure(message: "focused_window_unverified", initiallyMissing: true)
                }
                // A missing focused-window attribute may retry only while the focused
                // field still proves both previously authenticated object identities.
                guard let pinnedField = authenticatedField, let pinnedWindow = authenticatedWindow,
                      let field = axElement(read(app, kAXFocusedUIElementAttribute)) else {
                    throw ProbeFailure(message: "focused_window_unverified")
                }

                try require(CFEqual(pinnedField, field), "focused_document_field_changed")
                guard let fieldWindow = axElement(read(field, kAXWindowAttribute)) else {
                    throw ProbeFailure(message: "focused_field_window_unverified")
                }
                try require(CFEqual(pinnedWindow, fieldWindow), "focused_document_window_changed")
                try retryMissing("focused_window_unverified")
                continue
            }
            guard let window = axElement(rawWindow) else { throw ProbeFailure(message: "focused_window_unverified") }

            if let authenticatedWindow { try require(CFEqual(authenticatedWindow, window), "focused_document_window_changed") }
            let rawField = read(app, kAXFocusedUIElementAttribute)
            if rawField == nil {
                if authenticatedField == nil && authenticatedWindow == nil {
                    throw ProbeFailure(message: "focused_field_window_unverified", initiallyMissing: true)
                }
                // The pinned focused window is proven above; still do not read AXValue
                // or emit until the same focused field and document return together.
                try retryMissing("focused_field_window_unverified")
                continue
            }
            guard let field = axElement(rawField) else { throw ProbeFailure(message: "focused_field_window_unverified") }

            guard let fieldWindow = axElement(read(field, kAXWindowAttribute)) else { throw ProbeFailure(message: "focused_field_window_unverified") }
            try require(CFEqual(window, fieldWindow), "focused_field_not_in_probe_window")
            try require((read(field, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole, "secure_field")
            try require((read(field, kAXRoleAttribute) as? String) == kAXTextAreaRole, "focused_field_is_not_document_text_area")
            if let authenticatedField { try require(CFEqual(authenticatedField, field), "focused_document_field_changed") }
            let rawDocument = read(window, kAXDocumentAttribute)
            if rawDocument == nil {
                // Only a temporary missing AXDocument may retry. No event or AXValue read occurs here.
                // The original authenticated window AND field must still be exactly the same objects.
                try retryMissing("focused_window_document_unverified")
                continue
            }
            guard let document = rawDocument as? String,
                  let url = URL(string: document), url.isFileURL else { throw ProbeFailure(message: "focused_window_document_unverified") }
            try require(url.standardizedFileURL.resolvingSymlinksInPath() == target, "focused_window_is_not_fresh_probe_document")
            // Recheck these cheap gates after readonly IPC, before allowing the caller to emit.
            try require(!IsSecureEventInputEnabled(), "secure_input_enabled")
            try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "target_not_frontmost")
            try require(ProcessInfo.processInfo.systemUptime <= retryDeadline, retryFailure)
            if authenticatedField == nil { authenticatedField = field; authenticatedWindow = window }
            return field
        }
    }

    /// Readonly startup barrier; never relaxes the gates used before each event.
    func awaitInitialVerification() throws {
        try require(events == 0 && authenticatedField == nil && authenticatedWindow == nil, "initial_verification_already_started")
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        while true {
            try require(ProcessInfo.processInfo.systemUptime < deadline, "initial_verification_timeout")
            // Activation is asynchronous. During this readonly startup barrier
            // wait for its positive result, without activating again or emitting.
            // Per-event verifiedField remains unchanged and fails immediately
            // if the user changes focus after the session has started.
            try require(AXIsProcessTrusted(), "accessibility_not_trusted")
            try require(CGPreflightPostEventAccess(), "post_event_access_not_granted")
            try require(!IsSecureEventInputEnabled(), "secure_input_enabled")
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                try require(ProcessInfo.processInfo.systemUptime + 0.020 <= deadline, "initial_target_not_frontmost")
                settle(0.020)
                continue
            }
            do {
                _ = try verifiedField()
                try require(ProcessInfo.processInfo.systemUptime <= deadline, "initial_verification_timeout")
                return
            } catch let failure as ProbeFailure where failure.initiallyMissing {
                try require(events == 0 && authenticatedField == nil && authenticatedWindow == nil, "initial_verification_already_started")
                try require(AXIsProcessTrusted(), "accessibility_not_trusted")
                try require(CGPreflightPostEventAccess(), "post_event_access_not_granted")
                try require(!IsSecureEventInputEnabled(), "secure_input_enabled")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "target_not_frontmost")
                try require(ProcessInfo.processInfo.systemUptime + 0.020 <= deadline, "initial_verification_timeout")
                settle(0.020)
            }
        }
    }

    func snapshot() throws -> (String, [String: Int]) {
        let field = try verifiedField()
        guard let text = attr(field, kAXValueAttribute) as? String, text.utf16.count <= 65536,
              let value = attr(field, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            throw ProbeFailure(message: "probe_text_or_selection_unavailable")
        }
        var selection = CFRange()
        try require(AXValueGetValue(value as! AXValue, .cfRange, &selection), "invalid_probe_selection")
        return (text, ["location": selection.location, "length": selection.length])
    }
    func emit(_ key: CGKeyCode, down: Bool, flags: CGEventFlags = [], modifier: Bool = false) throws {
        try require(events < 600, "event_limit")
        _ = try verifiedField()
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { throw ProbeFailure(message: "event_creation_failed") }
        if modifier { event.type = .flagsChanged }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        event.post(tap: .cghidEventTap)
        let postedAt = ProcessInfo.processInfo.systemUptime
        if firstEventUptime == nil { firstEventUptime = postedAt }
        lastEventUptime = postedAt
        events += 1
        settle(0.012)
    }
    func tap(_ key: CGKeyCode, flags: CGEventFlags = []) throws {
        // Model the actual modifier frame, rather than leaving aggregate flags
        // set while no corresponding device key has been pressed/released.
        let modifiers: [(CGEventFlags, CGKeyCode, UInt64)] = [
            (.maskCommand, 55, 0x8), (.maskControl, 59, 0x1),
            (.maskAlternate, 58, 0x20), (.maskShift, 56, 0x2)]
        var held = CGEventFlags()
        for (mask, code, side) in modifiers where flags.contains(mask) {
            held = CGEventFlags(rawValue: held.rawValue | mask.rawValue | side)
            try emit(code, down: true, flags: held, modifier: true)
        }
        try emit(key, down: true, flags: held.union(flags))
        try emit(key, down: false, flags: held.union(flags))
        for (mask, code, side) in modifiers.reversed() where flags.contains(mask) {
            held = CGEventFlags(rawValue: held.rawValue & ~(mask.rawValue | side))
            try emit(code, down: false, flags: held, modifier: true)
        }
    }
    func scroll() throws {
        try require(events < 600, "event_limit")
        let bounds = try characterBounds(0)
        _ = try verifiedField()
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line,
                                  wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            throw ProbeFailure(message: "scroll_event_creation_failed")
        }
        event.location = CGPoint(x: bounds.midX, y: bounds.midY)
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        event.post(tap: .cghidEventTap)
        events += 1
        settle(0.012)
    }
    func characterBounds(_ location: Int) throws -> CGRect {
            let field = try verifiedField()
            var range = CFRange(location: location, length: 1)
            let parameter = AXValueCreate(.cfRange, &range)!
            var value: CFTypeRef?
            try require(AXUIElementCopyParameterizedAttributeValue(field,
                kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
                "drag_range_bounds_unavailable")
            guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
                throw ProbeFailure(message: "drag_range_bounds_invalid")
            }
            var rect = CGRect.zero
            try require(AXValueGetValue(value as! AXValue, .cgRect, &rect) && !rect.isEmpty,
                        "drag_range_bounds_invalid")
            return rect
    }
    func dragTestWord() throws {
        let initial = try snapshot()
        try require(initial.0 == "ghbdtn", "drag_test_word_mismatch")
        let first = try characterBounds(0), last = try characterBounds(5)
        try require(abs(first.midY - last.midY) < 1 && last.maxX > first.minX,
                    "drag_requires_single_line")
        for (type, point) in [(CGEventType.leftMouseDown, CGPoint(x: first.minX, y: first.midY)),
                              (.leftMouseDragged, CGPoint(x: last.maxX, y: last.midY)),
                              (.leftMouseUp, CGPoint(x: last.maxX, y: last.midY))] {
            try require(events < 600, "event_limit")
            _ = try verifiedField()
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else {
                throw ProbeFailure(message: "drag_event_creation_failed")
            }
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
            event.post(tap: .cghidEventTap)
            events += 1
            settle(0.05)
        }
        let selected = try snapshot()
        try require(selected.0 == initial.0 && selected.1 == ["location": 0, "length": 6],
                    "drag_selection_not_verified")
    }
    func type(_ text: String, interval: TimeInterval, waitAfterLast: Bool = true) throws {
        let map: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50," ":49]
        let shifted = Dictionary(uniqueKeysWithValues: zip(Array("!@#$%^&*()_+{}|:\"<>?~"), Array("1234567890-= []\\;' ,./`".replacingOccurrences(of: " ", with: ""))))
        for (index, character) in text.enumerated() {
            let lower = Character(String(character).lowercased())
            let base = shifted[character] ?? lower
            guard let key = map[base] else { throw ProbeFailure(message: "unsupported_ascii_key") }
            let needsShift = shifted[character] != nil || character.isUppercase
            try tap(key, flags: needsShift ? .maskShift : [])
            if waitAfterLast || index < text.count - 1 { settle(interval) }
        }
    }
    func idle(seconds: TimeInterval) throws -> TimeInterval {
        try require(modifiersNeutral(), "idle_modifiers_not_neutral")
        let before = try snapshot(), source = sourceID(currentSource()), eventCount = events
        let began = ProcessInfo.processInfo.systemUptime
        while true {
            try require(modifiersNeutral(), "idle_modifiers_not_neutral")
            let current = try snapshot()
            try require(current.0.utf16.elementsEqual(before.0.utf16) && current.1 == before.1 &&
                        sourceID(currentSource()) == source && events == eventCount, "idle_context_changed")
            let remaining = seconds - (ProcessInfo.processInfo.systemUptime - began)
            if remaining <= 0 { break }
            settle(min(0.25, remaining))
        }
        try require(modifiersNeutral(), "idle_modifiers_not_neutral")
        return ProcessInfo.processInfo.systemUptime - began
    }
    func gesture(_ name: String) throws {
        switch name {
        case "none": return
        case "recover": try tap(15, flags: [.maskCommand, .maskAlternate])
        case "interruptRecover":
            guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
                  let abc = sources.first(where: { sourceID($0) == "com.apple.keylayout.ABC" }),
                  let russian = sources.first(where: { sourceID($0) == "com.apple.keylayout.RussianWin" }) else {
                throw ProbeFailure(message: "recovery_sources_unavailable")
            }
            _ = try verifiedField()
            try require(sourceID(currentSource()) == sourceID(abc), "recovery_initial_source_mismatch")
            defer { _ = TISSelectInputSource(abc) }
            try require(TISSelectInputSource(russian) == noErr, "source_selection_failed")
            settle(0.3)
            _ = try verifiedField()
            try require(TISSelectInputSource(abc) == noErr, "source_selection_failed")
            settle(0.1)
            let before = try snapshot()
            gestureIntermediate = ["beforeRecoveryText": before.0, "beforeRecoverySelection": before.1,
                "inputSource": sourceID(currentSource())]
            try require(before.0 == "ghbdtn " && before.1 == ["location": 7, "length": 0] &&
                        sourceID(currentSource()) == sourceID(abc), "recovery_prefix_not_confirmed")
            try tap(15, flags: [.maskCommand, .maskAlternate])
        case "dragDoubleShift":
            try dragTestWord()
            settle(0.15)
            try gesture("doubleShift")
        case "manual", "cmdoptspace": try tap(49, flags: [.maskCommand, .maskAlternate])
        case "undo", "cmdoptz": try tap(6, flags: [.maskCommand, .maskAlternate])
        case "nativeUndo": try tap(6, flags: .maskCommand)
        case "backspace": try tap(51, flags: [])
        case "doubleBackspace":
            try tap(51, flags: []); Thread.sleep(forTimeInterval: 0.12)
            try tap(51, flags: [])
        case "manualUndo":
            try gesture("doubleShift")
            settle(0.25)
            let intermediate = try snapshot()
            gestureIntermediate = ["text": intermediate.0, "selection": intermediate.1, "inputSource": sourceID(currentSource())]
            try tap(6, flags: [.maskCommand, .maskAlternate])
        case "plainPaste": try tap(9, flags: [.maskCommand, .maskShift])
        case "optionTap":
            try emit(58, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20), modifier: true)
            settle(0.04)
            try emit(58, down: false, modifier: true)
        case "singleShift", "doubleShift":
            let count = name == "doubleShift" ? 2 : 1
            for index in 0..<count {
                try emit(56, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2), modifier: true)
                settle(0.04)
                try emit(56, down: false, modifier: true)
                if index + 1 < count { settle(0.07) }
            }
        case "chord":
            try emit(56, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2), modifier: true)
            try emit(60, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x6), modifier: true)
            try emit(56, down: false, flags: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x4), modifier: true)
            try emit(60, down: false, modifier: true)
        default: throw ProbeFailure(message: "unsupported_gesture")
        }
    }
}

/// Append-only in-memory completed cases; atomically persisted beside our fresh UUID document.
/// Failure reporting never consults Accessibility or another document.
final class ProbeCheckpoint {
    let url: URL
    let document: URL
    let requestedCases: Int
    let initialInputSource: String
    private(set) var results: [[String: Any]] = []
    private(set) var totalEvents = 0
    private(set) var persistedCompleted = 0
    var activeCase: String?
    var activeCaseIndex: Int?
    var caseEventCount: (() -> Int)?
    var initialReadback: [String: Any]?
    init(document: URL, requestedCases: Int, initialInputSource: String) throws {
        self.document = document; self.requestedCases = requestedCases; self.initialInputSource = initialInputSource
        self.url = document.deletingPathExtension().appendingPathExtension("results.json")
        try Data().write(to: url, options: .withoutOverwriting)
        try write(status: "created")
    }
    func write(status: String, error: String? = nil) throws {
        var record: [String: Any] = ["schemaVersion": 1, "document": document.path, "checkpoint": url.path,
            "status": status, "requestedCases": requestedCases, "completed": results.count,
            "results": results, "totalEventsCompletedCases": totalEvents,
            "initialInputSource": initialInputSource,
            "notice": "Only completed authenticated synthetic cases. Partial current case is not a result; never auto-resume."]
        if let activeCase { record["activeCase"] = activeCase }
        if let activeCaseIndex { record["activeCaseIndex"] = activeCaseIndex }
        if activeCase != nil, let count = caseEventCount?() { record["activeCaseEvents"] = count }
        if let error { record["error"] = error }
        if let initialReadback { record["initialReadback"] = initialReadback }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        persistedCompleted = results.count
    }
    func append(_ result: [String: Any], events: Int) throws {
        results.append(result); totalEvents += events
        activeCase = nil; activeCaseIndex = nil
        try write(status: "running")
    }
    func failure(_ error: String) -> [String: Any] {
        var failedWrite = false
        do { try write(status: "failed", error: error) } catch { failedWrite = true }
        var response: [String: Any] = ["error": error, "checkpoint": url.path, "document": document.path,
            "completed": results.count, "persistedCompleted": persistedCompleted,
            "requestedCases": requestedCases, "checkpointWriteFailed": failedWrite,
            "autoResume": false]
        if let activeCase { response["activeCase"] = activeCase }
        if let activeCaseIndex { response["activeCaseIndex"] = activeCaseIndex }
        if activeCase != nil, let count = caseEventCount?() { response["activeCaseEvents"] = count }
        if failedWrite { response["completedResults"] = results }
        return response
    }
}
var activeCheckpoint: ProbeCheckpoint?

func main() throws {
    let args = try Arguments()
    if args.validateOnly {
        let report: [String: Any] = ["validatedCases": args.cases.count, "events": 0,
            "pureFixtureValidation": true, "nativeAcceptance": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
        return
    }
    traceTagsRequested = args.traceTags
    if args.status {
        output(["statusOnly": true, "accessibilityTrusted": AXIsProcessTrusted(), "postEventAccess": CGPreflightPostEventAccess(), "secureInput": IsSecureEventInputEnabled(), "inputSource": sourceID(currentSource()), "modifierFlags": CGEventSource.flagsState(.hidSystemState).rawValue, "events": 0])
        return
    }
    if args.referenceSelectionClipboard { try verifyReferenceSelectionSwitcher() }
    try require(AXIsProcessTrusted(), "accessibility_not_trusted")
    try require(CGPreflightPostEventAccess(), "post_event_access_not_granted")
    try require(!IsSecureEventInputEnabled(), "secure_input_enabled")
    try require(modifiersNeutral(), "initial_modifiers_not_neutral")
    guard let initial = currentSource() else { throw ProbeFailure(message: "initial_source_unavailable") }
    defer { _ = TISSelectInputSource(initial) }
    guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { throw ProbeFailure(message: "input_sources_unavailable") }
    for item in args.cases {
        try require(sources.contains(where: { sourceID($0) == "com.apple.keylayout." + item.source }), "requested_source_not_enabled")
    }
    let firstWordAfterFocus = args.cases.first?.firstWordAfterFocus == true
    if firstWordAfterFocus {
        guard let desired = sources.first(where: { sourceID($0) == "com.apple.keylayout.ABC" }) else { throw ProbeFailure(message: "requested_source_not_enabled") }
        try require(TISSelectInputSource(desired) == noErr, "source_selection_failed")
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while sourceID(currentSource()) != "com.apple.keylayout.ABC" {
            try require(ProcessInfo.processInfo.systemUptime < deadline && modifiersNeutral() && !IsSecureEventInputEnabled(), "source_selection_not_verified")
            settle(0.005)
        }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("research/private/probes", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let target = root.appendingPathComponent(UUID().uuidString + ".txt")
    try Data(args.initialText.utf8).write(to: target, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    let checkpoint = try ProbeCheckpoint(document: target, requestedCases: args.cases.count, initialInputSource: sourceID(initial))
    activeCheckpoint = checkpoint
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { throw ProbeFailure(message: "textedit_unavailable") }
    var opened: NSRunningApplication?
    var openFailed = false
    let config = NSWorkspace.OpenConfiguration(); config.activates = true
    NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: config) { app, error in opened = app; openFailed = error != nil }
    let deadline = Date(timeIntervalSinceNow: 10)
    while opened == nil && !openFailed && Date() < deadline { settle(0.1) }
    guard let opened else { throw ProbeFailure(message: "textedit_open_failed") }
    _ = opened.activate(options: [])
    if !firstWordAfterFocus { settle(0.5) }
    let probe = try Probe(target: target, pid: opened.processIdentifier)
    checkpoint.caseEventCount = { probe.events }
    try probe.awaitInitialVerification()
    let focusConfirmedAt = ProcessInfo.processInfo.systemUptime
    defer { activeTagTrace?.stop() }
    if args.traceTags {
        let trace = TagTrace(pid: opened.processIdentifier)
        activeTagTrace = trace
        try trace.start()
    }
    let initialSnapshot = try probe.snapshot()
    // Only the authenticated, newly created synthetic document may be recorded.
    checkpoint.initialReadback = ["text": initialSnapshot.0, "selection": initialSnapshot.1]
    try require(initialSnapshot.0.utf16.elementsEqual(args.initialText.utf16), "fresh_probe_initial_text_mismatch")
    let field = try probe.verifiedField()
    var endRange = CFRange(location: args.initialText.utf16.count, length: 0)
    guard let endValue = AXValueCreate(.cfRange, &endRange) else { throw ProbeFailure(message: "initial_cursor_value_failed") }
    try require(AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, endValue) == .success, "initial_cursor_set_failed")
    let positioned = try probe.snapshot()
    try require(positioned.0.utf16.elementsEqual(args.initialText.utf16) && positioned.1["location"] == args.initialText.utf16.count && positioned.1["length"] == 0, "initial_cursor_readback_failed")
    var results: [[String: Any]] = []
    var totalEvents = 0
    let inputSegmentStarted = ProcessInfo.processInfo.systemUptime
    for (index, item) in args.cases.enumerated() {
        probe.gestureIntermediate.removeAll()
        probe.firstEventUptime = nil; probe.lastEventUptime = nil
        probe.events = 0 // Explicit per-case bound, including clearing and all gesture events.
        checkpoint.activeCase = item.id; checkpoint.activeCaseIndex = index
        try checkpoint.write(status: "running")
        if index > 0 {
            try probe.tap(0, flags: .maskCommand)
            try probe.tap(51)
            settle(0.15)
            let cleared = try probe.snapshot()
            try require(cleared.0.isEmpty, "probe_clear_not_verified")
        }
        let wanted = "com.apple.keylayout." + item.source
        guard let desired = sources.first(where: { sourceID($0) == wanted }) else { throw ProbeFailure(message: "requested_source_not_enabled") }
        _ = try probe.verifiedField()
        if item.firstWordAfterFocus != true {
            try require(TISSelectInputSource(desired) == noErr, "source_selection_failed")
            settle(0.2)
        }
        try require(sourceID(currentSource()) == wanted, "source_selection_not_verified")
        let started = ProcessInfo.processInfo.systemUptime
        probe.firstEventUptime = nil
        if item.gesture == "interruptRecover" {
            // The exact bounded fixture must enter the 150 ms quiet-period mutation before its tail.
            try probe.type("ghbdtn ", interval: args.interval)
            settle(0.170)
            try probe.type("he", interval: args.interval, waitAfterLast: false)
        } else if let count = item.scrollAfterCharacters {
            try probe.type(String(item.text.prefix(count)), interval: args.interval)
            try probe.scroll()
            try probe.type(String(item.text.dropFirst(count)), interval: args.interval)
        } else {
            try probe.type(item.text, interval: args.interval, waitAfterLast: item.preGestureDelayMilliseconds != 0)
        }
        let firstTypingEvent = probe.firstEventUptime, lastTypingEvent = probe.lastEventUptime
        var observation: [String: Any] = ["performed": false]
        if item.boundary ?? true {
            let beforeBoundary = try probe.snapshot().0
            let boundaryTime = ProcessInfo.processInfo.systemUptime
            try probe.tap(49)
            var lastText = beforeBoundary
            var firstChange: TimeInterval?
            var lastChange = boundaryTime
            var changes = 0
            while ProcessInfo.processInfo.systemUptime - boundaryTime < 1 {
                let observed = try probe.snapshot().0
                let now = ProcessInfo.processInfo.systemUptime
                if observed != lastText {
                    if firstChange == nil { firstChange = now - boundaryTime }
                    changes += 1; lastChange = now; lastText = observed
                }
                if firstChange != nil && now - lastChange >= 0.1 { break }
                settle(0.015)
            }
            observation = ["performed": true, "textTransitionsObserved": changes,
                           "elapsedSeconds": ProcessInfo.processInfo.systemUptime - boundaryTime,
                           "firstChangeSeconds": firstChange.map { $0 as Any } ?? NSNull(),
                           "notice": "Includes delimiter insertion and AX readback; not correction-only latency or original p95."]
        }
        let gestureDelay = item.preGestureDelayMilliseconds.map { Double($0) / 1000 } ?? args.settleTime
        if gestureDelay > 0 { settle(gestureDelay) }
        // The reference gesture reducer rejects a first Shift within 100 ms
        // of a preceding reset (REA/Ghidra 0x1002516ec). Keep the synthetic
        // selection command outside that interval; target guards stay intact.
        if item.selectAllBeforeGesture ?? false { try probe.tap(0, flags: .maskCommand); settle(0.15) }
        var lease: ClipboardLease?
        if let text = item.pasteText { _ = try probe.verifiedField(); lease = try ClipboardLease(synthetic: text) }
        if args.referenceSelectionClipboard {
            _ = try probe.verifiedField()
            try verifyReferenceSelectionSwitcher()
            lease = try ClipboardLease(synthetic: UUID().uuidString, referenceContext: {
                _ = try probe.verifiedField()
                try verifyReferenceSelectionSwitcher()
            })
        }
        var clipboardState = "not_used"
        var beforeGesture: [String: Any] = [:]
        if (item.gesture ?? "none") != "none" {
            let before = try probe.snapshot()
            beforeGesture = ["text": before.0, "selection": before.1, "inputSource": sourceID(currentSource())]
        }
        do {
            defer { if let lease { clipboardState = lease.restore() } }
            probe.firstEventUptime = nil
            try probe.gesture(item.gesture ?? "none")
            settle(args.settleTime)
        }
        let snapshot = try probe.snapshot()
        totalEvents += probe.events
        var timing: [String: Any] = ["firstWordAfterFocus": item.firstWordAfterFocus == true,
            "preGestureDelayMilliseconds": gestureDelay * 1000]
        if item.firstWordAfterFocus == true, let firstTypingEvent { timing["firstInputAfterFocusMilliseconds"] = (firstTypingEvent - focusConfirmedAt) * 1000 }
        if let firstGestureEvent = probe.firstEventUptime, let lastTypingEvent { timing["gestureAfterTypingMilliseconds"] = (firstGestureEvent - lastTypingEvent) * 1000 }
        results.append(["id": item.id, "document": target.path, "text": snapshot.0, "selection": snapshot.1,
                        "inputSource": sourceID(currentSource()), "requestedSource": wanted,
                        "physicalASCII": item.text, "gesture": item.gesture ?? "none", "boundary": item.boundary ?? true,
                        "selectAllBeforeGesture": item.selectAllBeforeGesture ?? false, "clipboardRestore": clipboardState,
                        "events": probe.events, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                        "boundaryObservation": observation, "beforeGesture": beforeGesture, "gestureIntermediate": probe.gestureIntermediate,
                        "timing": timing])
        try checkpoint.append(results[results.count - 1], events: probe.events)
    }
    let inputSegmentSeconds = ProcessInfo.processInfo.systemUptime - inputSegmentStarted
    let idleSegmentSeconds = args.idleAfterBatch ? try probe.idle(seconds: 30) : 0
    try require(modifiersNeutral(), "final_modifiers_not_neutral")
    try checkpoint.write(status: "completed")
    activeTagTrace?.stop()
    let notice = "Bounded synthetic TextEdit probe only; not original parity or latency p95. Initial source restored by defer."
    if args.batch {
        output(["document": target.path, "results": results, "cases": results.count, "totalEvents": totalEvents,
                "initialInputSource": sourceID(initial), "eventTag": Probe.eventTag, "notice": notice,
                "checkpoint": checkpoint.url.path, "completed": results.count,
                "inputSegmentSeconds": inputSegmentSeconds, "idleSegmentSeconds": idleSegmentSeconds,
                "requiredIdleSeconds": args.idleAfterBatch ? 30 : 0, "idleEvents": 0])
    } else {
        var result = results[0]
        result["initialInputSource"] = sourceID(initial); result["eventTag"] = Probe.eventTag; result["notice"] = notice
        result["initialSyntheticText"] = args.initialText
        result["checkpoint"] = checkpoint.url.path; result["completed"] = results.count
        output(result)
    }

}
do { try main() }
catch let failure as ProbeFailure { output(activeCheckpoint?.failure(failure.message) ?? ["error": failure.message]); exit(2) }
catch {
    var response = activeCheckpoint?.failure("probe_operation_failed") ?? ["error": "probe_operation_failed"]
    response["kind"] = String(describing: type(of: error))
    output(response); exit(2)
}
