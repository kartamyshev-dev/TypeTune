import Foundation

/// Text typed with the keyboard immediately before the caret since the last reset.
/// It is the universal-mode replacement for reading the editor: every claim it makes
/// is about characters this process saw being typed, in order, with nothing in between.
/// Anything it cannot account for (pointer, navigation, shortcuts, focus, IME, paste…)
/// must reset it; what lies left of the caret after a reset is unknown.
public struct TypedWordBuffer: Equatable, Sendable {
    public enum ResetReason: String, Equatable, Sendable {
        /// Return or Tab was typed: the caret now follows a known boundary.
        case newline, tab
        /// The caret or content may have changed in a way the buffer cannot follow.
        case pointer, navigation, shortcut, focus, secureInput, sourceChange, escape, untrackedKey, explicit
        /// This process inserted text (a snippet). The inserted words are not typed and
        /// must never be corrected; while this stays the last reset nothing was typed since.
        case inserted
    }
    /// Longest retained text. Older characters are dropped from the front.
    public static let capacity = 128

    public private(set) var text = ""
    /// True when the character before `text` is known to be a word boundary
    /// (after Return/Tab, or when the retained text begins after whitespace).
    public private(set) var anchoredStart = false
    public private(set) var lastReset: ResetReason? = .explicit

    public init() {}

    /// Appends characters typed by one key. Control characters cannot be tracked.
    public mutating func insert(_ characters: String) {
        guard !characters.isEmpty else { return }
        guard !Self.containsControl(characters) else { reset(.untrackedKey); return }
        text += characters
        lastReset = nil
        if text.count > Self.capacity {
            let dropped = text.count - Self.capacity
            let removed = text.prefix(dropped)
            text.removeFirst(dropped)
            // The new first character follows the last dropped one.
            anchoredStart = removed.last?.isWhitespace == true
        }
    }

    /// Backspace removes the character before the caret. With nothing retained it
    /// deletes unknown text, which leaves the buffer empty and unanchored.
    public mutating func backspace() {
        if text.isEmpty { anchoredStart = false; return }
        text.removeLast()
    }

    public mutating func reset(_ reason: ResetReason) {
        text = ""
        anchoredStart = reason == .newline || reason == .tab
        lastReset = reason
    }

    /// After this process inserted text that now ends at the caret: the buffer forgets
    /// it, and the next typed token is anchored only when that text ends in whitespace.
    public mutating func resetAfterInsertion(endingWith textBeforeCaret: String) {
        text = ""
        anchoredStart = textBeforeCaret.last?.isWhitespace == true
        lastReset = .inserted
    }

    /// The unfinished token at the caret (characters after the last whitespace).
    public var currentToken: String {
        String(text.reversed().prefix(while: { !$0.isWhitespace }).reversed())
    }

    /// The token that the trailing whitespace just completed, with that whitespace.
    /// nil when the text does not end with whitespace or the token is empty.
    public var completedToken: (token: String, boundary: String)? {
        let boundary = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        guard !boundary.isEmpty else { return nil }
        let rest = text.dropLast(boundary.count)
        let token = String(rest.reversed().prefix(while: { !$0.isWhitespace }).reversed())
        guard !token.isEmpty else { return nil }
        return (token, boundary)
    }

    /// Whether a token ending `boundaryLength` characters before the caret is known to
    /// start at a word boundary: whitespace precedes it inside the buffer, or the buffer
    /// itself starts at a known boundary.
    public func tokenIsAnchored(boundaryLength: Int = 0) -> Bool {
        let body = text.dropLast(boundaryLength)
        let tokenLength = body.reversed().prefix(while: { !$0.isWhitespace }).count
        if tokenLength < body.count { return true }
        return anchoredStart
    }

    /// Records an edit the process made itself, such as a correction that replaced
    /// `old` before the caret with `new`. Returns false (and resets) when the buffer
    /// does not end with `old`, because the field and the buffer would disagree.
    @discardableResult
    public mutating func replaceSuffix(_ old: String, with new: String) -> Bool {
        guard text.hasSuffix(old), !Self.containsControl(new) else { reset(.untrackedKey); return false }
        text.removeLast(old.count)
        insert(new)
        return true
    }

    private static func containsControl(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
