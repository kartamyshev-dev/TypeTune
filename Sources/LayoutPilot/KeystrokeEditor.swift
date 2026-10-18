import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

/// Universal mode: performs a KeystrokeEditPlan as synthetic keyboard input sent to one
/// process. Events carry the synthetic tag, so the tap neither tracks nor intercepts them.
/// Posting is not proof of an edit; callers verify with Accessibility when it is readable.
enum KeystrokeEditor {
    static let backspaceKey: CGKeyCode = 51
    /// Returns false before posting anything when posting is not allowed. A false
    /// return after some events were posted is reported as `partial`.
    static func perform(_ plan: KeystrokeEditPlan, pid: pid_t) -> (posted: Bool, partial: Bool) {
        guard CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(), pid > 0,
              EditorSupport.permitsKeyboardText(plan.insertText) || plan.insertText.isEmpty,
              let source = CGEventSource(stateID: .privateState) else { return (false, false) }
        var postedAny = false
        func post(_ event: CGEvent?) -> Bool {
            guard let event else { return false }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: EditorSupport.syntheticEventTag)
            event.postToPid(pid)
            postedAny = true
            return true
        }
        for _ in 0..<plan.deleteCount {
            guard post(CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: true)),
                  post(CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: false)) else {
                return (false, postedAny)
            }
        }
        for chunk in plan.unicodeChunks() {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                    return (false, postedAny)
                }
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                }
                _ = post(event)
            }
        }
        return (true, false)
    }
}
