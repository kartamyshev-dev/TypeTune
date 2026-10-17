import Foundation

/// Text replacement must be enabled per host adapter, not inferred
/// from AXIsAttributeSettable: web editors may acknowledge a partial mutation.
public enum EditorSupport {
    public enum InsertionBackend { case selectedText, keyboardEvents }
    public static let syntheticEventTag: Int64 = 0x4c50544c
    public static func permitsTerminalIntegration(applicationID: String?) -> Bool {
        applicationID == "com.apple.Terminal" || applicationID == "com.mitchellh.ghostty"
    }
    public static func insertionBackend(applicationID: String?) -> InsertionBackend? {
        switch applicationID {
        case "com.apple.TextEdit": return .selectedText
        case "com.openai.codex", "com.google.Chrome": return .keyboardEvents
        default: return nil
        }
    }
    public static func permitsTextReplacement(applicationID: String?) -> Bool {
        insertionBackend(applicationID: applicationID) != nil
    }
    public static func permitsEditableField(applicationID: String?, role: String?, subrole: String?, webContent: Bool, addressBar: Bool = false) -> Bool {
        guard permitsTextReplacement(applicationID: applicationID), subrole != "AXSecureTextField" else { return false }
        if role == "AXTextArea" { return true }
        return applicationID == "com.google.Chrome" && role == "AXTextField" && (webContent || addressBar)
    }
    public static func isChromeAddressBar(applicationID: String?, role: String?, subrole: String?,
                                          description: String?, inToolbar: Bool) -> Bool {
        guard applicationID == "com.google.Chrome", role == "AXTextField",
              subrole != "AXSecureTextField", inToolbar else { return false }
        // shortcut: verified Russian/English Chrome labels only; add other locales after native profiling.
        return ["Адресная строка и строка поиска", "Address and search bar"].contains(description ?? "")
    }
    /// Only plain search words. Any address syntax protects the entire query, even a selected word.
    public static func permitsAddressBarCorrection(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard !words.isEmpty, text.allSatisfy({ $0.isLetter || $0 == " " }) else { return false }
        return !words.contains { ["localhost", "local", "intranet"].contains($0.lowercased()) }
    }
    public static func permitsKeyboardText(_ text: String) -> Bool {
        !text.isEmpty && text.utf16.count <= 4096 &&
            !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    /// Native paste is distinct from word replacement: Chromium receives its
    /// Paste and Match Style shortcut, so LF/TAB are clipboard data, not keys.
    public static func permitsPlainPasteInterception(applicationID: String?, text: String?) -> Bool {
        guard let text, !text.isEmpty, insertionBackend(applicationID: applicationID) != nil else { return false }
        return text.utf16.count <= 65_536 && !text.unicodeScalars.contains(where: { $0.value == 0 })
    }
    /// Starting a synthesized shortcut while the initiating V/modifiers remain
    /// held can overlap two frames. Ignore unrelated noncoalesced-event bits.
    public static func nativePasteKeysReleased(hidFlags: UInt64, sessionFlags: UInt64,
                                               anyWatchedKeyDown: Bool) -> Bool {
        let modifierBits: UInt64 = (0x1f << 16) | (1 << 23) | 0x207f
        return !anyWatchedKeyDown && (hidFlags | sessionFlags) & modifierBits == 0
    }
    /// Readback equivalence only: empty Chromium contenteditable may expose a
    /// structural LF at caret0 that disappears during native paste. Never strip
    /// LF from ordinary fields, nonzero carets, selections, or the payload.
    public static func nativePasteTextMatches(applicationID: String?, beforeText: String,
                                              selection: NSRange, payload: String, actualText: String) -> Bool {
        guard insertionBackend(applicationID: applicationID) == .keyboardEvents,
              permitsPlainPasteInterception(applicationID: applicationID, text: payload),
              let edit = TextEdit(text: beforeText, selection: selection, replacement: payload) else { return false }
        if actualText.utf16.elementsEqual(edit.expectedText.utf16) { return true }
        return beforeText == "\n" && selection == NSRange(location: 0, length: 0) && actualText.utf16.elementsEqual(payload.utf16)
    }
}

/// Per-shortcut delivery handshake, independent of potentially premature global
/// keyState snapshots. A new pending request always constructs a fresh value.
public struct NativePasteReleaseHandshake: Sendable {
    public enum Event { case keyDown, keyUp, flagsChanged, cancel }
    public private(set) var vReleased = false
    public private(set) var commandReleased = false
    public private(set) var shiftReleased = false
    public private(set) var neutralModifierReleaseSeen = false
    public private(set) var cancelled: Bool
    public init(originalFlags: UInt64) {
        let commandShift: UInt64 = (1 << 20) | (1 << 17)
        cancelled = originalFlags & commandShift != commandShift
    }
    public var ready: Bool {
        !cancelled && vReleased && commandReleased && shiftReleased && neutralModifierReleaseSeen
    }
    public mutating func observe(_ event: Event, keyCode: Int = -1, rawFlags: UInt64 = 0) {
        guard !cancelled else { return }
        switch event {
        case .keyDown, .cancel:
            cancelled = true
            vReleased = false; commandReleased = false; shiftReleased = false; neutralModifierReleaseSeen = false
        case .keyUp:
            if keyCode == 9 { vReleased = true }
        case .flagsChanged:
            let release = ModifierGesture.isRelease(keyCode: keyCode, rawFlags: rawFlags) ||
                (keyCode == 63 && rawFlags & (1 << 23) == 0) ||
                (keyCode == 57 && rawFlags & (1 << 16) == 0)
            guard release else { observe(.cancel); return }
            if [54, 55].contains(keyCode) { commandReleased = true }
            if [56, 60].contains(keyCode) { shiftReleased = true }
            if EditorSupport.nativePasteKeysReleased(hidFlags: rawFlags, sessionFlags: 0, anyWatchedKeyDown: false) {
                neutralModifierReleaseSeen = true
            }
        }
    }
}
