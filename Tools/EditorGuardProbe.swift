import AppKit
import ApplicationServices
import LayoutPilotCore

/// Calls the production replacement entry point, but never authorizes AX work:
/// isCurrent always returns false. No input, field reads or mutations occur.
@main
struct EditorGuardProbe {
    static func main() {
        var failures: [String] = []
        let original = EditorSnapshot(element: AXUIElementCreateApplication(getpid()), window: nil,
            document: nil, pid: getpid(), application: "com.google.Chrome", text: "e\u{0301} ghbdtn abc",
            selection: NSRange(location: 10, length: 0))
        var changed = original
        changed.text = original.text.precomposedStringWithCanonicalMapping
        if original.matchesContent(changed) { failures.append("normalization must invalidate stale UTF16 range") }
        if !original.matchesContent(original) { failures.append("identical decomposed text must remain usable") }
        changed = original; changed.selection.location -= 1
        if original.matchesContent(changed) { failures.append("changed caret must invalidate context") }
        changed = original; changed.selection.length = 1
        if original.matchesContent(changed) { failures.append("changed selection must invalidate context") }
        var sameSize = original
        sameSize.text = "e\u{0301} ghbdtn é"
        changed = sameSize; changed.text = "é ghbdtn e\u{0301}"
        if sameSize.matchesContent(changed) { failures.append("equal UTF16 length is not exact content") }
        let range = NSRange(location: 3, length: 6)
        let edit = TextEdit(text: original.text, selection: range, replacement: "привет")!
        var pending = original; pending.selection = range
        var inserted = original; inserted.text = edit.expectedText
        inserted.selection = NSRange(location: edit.cursor, length: 0)
        var reads = 0
        let observed = AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: {
                reads += 1; return reads < 3 ? pending : inserted
            })
        if observed == nil || reads != 3 { failures.append("delayed AX acknowledgement must settle") }
        var caretAhead = pending; caretAhead.selection = inserted.selection
        reads = 0
        let settledCaretAhead = AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: {
                reads += 1; return reads == 1 ? caretAhead : inserted
            })
        if settledCaretAhead == nil || reads != 2 { failures.append("Chrome caret ahead of text must wait for exact text") }
        reads = 0
        let unconfirmedCaret = AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.012, isCurrent: { true }, read: { reads += 1; return caretAhead })
        if unconfirmedCaret != nil || reads < 2 { failures.append("caret alone must never confirm insertion and must expire") }
        var wrongCaret = caretAhead; wrongCaret.selection = NSRange(location: 1, length: 0)
        reads = 0
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: { reads += 1; return wrongCaret }) != nil || reads != 1 {
            failures.append("unrelated caret must stop immediately")
        }
        var wrongTarget = caretAhead; wrongTarget.pid += 1
        reads = 0
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: { reads += 1; return wrongTarget }) != nil || reads != 1 {
            failures.append("caret ahead in another target must stop immediately")
        }
        var nonChrome = original; nonChrome.application = "com.apple.TextEdit"
        reads = 0
        if AccessibilityEditor.awaitInsertion(in: nonChrome, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: { reads += 1; return caretAhead }) != nil || reads != 1 {
            failures.append("caret ahead policy must stay Chrome only")
        }
        var textAhead = inserted; textAhead.selection = range
        reads = 0
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: {
                reads += 1; return reads == 1 ? textAhead : inserted
            }) == nil || reads != 2 { failures.append("text alone must wait for exact caret") }
        var other = inserted; other.pid += 1
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: { other }) != nil {
            failures.append("same text in another target must fail")
        }
        var normalized = inserted; normalized.text = inserted.text.precomposedStringWithCanonicalMapping
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { true }, read: { normalized }) != nil {
            failures.append("normalized readback must not confirm UTF16 mutation")
        }
        var expiredReads = 0
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime - 1, isCurrent: { true }, read: { expiredReads += 1; return inserted }) != nil || expiredReads != 0 {
            failures.append("expired observation must not read AX")
        }
        var staleReads = 0
        if AccessibilityEditor.awaitInsertion(in: original, range: range, edit: edit,
            deadline: ProcessInfo.processInfo.systemUptime + 0.15, isCurrent: { false }, read: { staleReads += 1; return inserted }) != nil || staleReads != 0 {
            failures.append("stale observation must not read AX")
        }
        let blocked = ["com.openai.chat", "com.apple.Safari", "com.example.UnknownEditor", ""]
        let supported = ["com.apple.TextEdit", "com.openai.codex", "com.google.Chrome"]
        for application in blocked + supported {
            let before = EditorSnapshot(element: AXUIElementCreateApplication(getpid()), window: nil,
                document: nil, pid: getpid(), application: application, text: "ghbdtn ",
                selection: NSRange(location: 7, length: 0))
            var reachedCurrentCheck = false
            let result = AccessibilityEditor.replace(before, range: NSRange(location: 0, length: 6),
                replacement: "привет", isCurrent: { reachedCurrentCheck = true; return false })
            if case .notApplied = result {} else { failures.append(application + ": unexpected mutation result") }
            if reachedCurrentCheck != supported.contains(application) {
                failures.append(application + ": host guard order")
            }
        }
        let report: [String: Any] = ["cases": blocked.count + supported.count + 16, "failures": failures,
            "notice": "Production replace entry point; current-check sentinel always denies all AX work. No live Codex reproduction or native TextEdit acceptance."]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
