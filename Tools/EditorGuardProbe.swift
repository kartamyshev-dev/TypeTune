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
        let report: [String: Any] = ["cases": blocked.count + supported.count + 5, "failures": failures,
            "notice": "Production replace entry point; current-check sentinel always denies all AX work. No live Codex reproduction or native TextEdit acceptance."]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
