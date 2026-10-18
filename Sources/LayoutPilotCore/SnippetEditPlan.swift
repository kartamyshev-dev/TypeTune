import Foundation

/// A snippet expansion (or its undo) as steps sent to the focused application
/// (docs/SNIPPETS_PLAN.md, S4): optional → presses, Backspaces, the text typed as Unicode
/// or pasted with ⌘V, optional ← presses to the `{{курсор}}` position. Pure: posting,
/// the clipboard and verification are the caller's.
public struct SnippetEditPlan: Equatable, Sendable {
    public enum Insertion: Equatable, Sendable {
        /// Unicode keyboard events, as layout corrections.
        case keystrokes
        /// Through the clipboard with ⌘V: long text, line breaks and tabs. Return is never
        /// typed for a line break (DECISIONS п. 28).
        case paste
    }
    /// Longer insertions are pasted (DECISIONS п. 28).
    public static let pasteThreshold = 100

    public let snippetID: UUID
    /// Text that must end at the caret before the first step.
    public let expectedBefore: String
    /// Text that ends at the caret after the last step.
    public let expectedAfter: String
    public let moveRight: Int
    public let deleteCount: Int
    public let insertText: String
    public let insertion: Insertion
    public let moveLeft: Int
    /// True for the undo: the caret ends after text the user typed.
    public let restoresTyped: Bool

    /// Abbreviation text as typed (with boundary) and the text that replaces it.
    private let typed: String
    private let inserted: String
    private let caretLeft: Int

    /// The expansion of `match`. nil when nothing would change.
    public init?(match: SnippetMatch, expansion: SnippetTemplate.Expansion) {
        guard !expansion.text.isEmpty else { return nil }
        let typed = match.typed + match.boundary
        let inserted = expansion.text + match.suffix + match.boundary
        guard typed != inserted else { return nil }
        self.init(snippetID: match.snippet.id, from: typed, to: inserted, caretRightFirst: 0,
                  // Without a cursor the caret stays after the Space; with one it goes back
                  // over the rest of the expansion, the punctuation and the Space.
                  caretLeftAfter: expansion.caretOffset.map { $0 + match.suffix.count + match.boundary.count } ?? 0,
                  restoresTyped: false, typed: typed, inserted: inserted)
    }

    private init(snippetID: UUID, from old: String, to new: String, caretRightFirst: Int, caretLeftAfter: Int,
                 restoresTyped: Bool, typed: String, inserted: String) {
        // Characters shared at the start stay; only the changed tail is replaced.
        let shared = zip(old, new).prefix(while: { $0 == $1 }).count
        self.snippetID = snippetID
        self.moveRight = caretRightFirst
        self.expectedBefore = String(old.dropLast(caretRightFirst))
        self.deleteCount = old.count - shared
        self.insertText = String(new.dropFirst(shared))
        self.insertion = Self.insertion(for: insertText)
        self.moveLeft = caretLeftAfter
        self.expectedAfter = String(new.dropLast(caretLeftAfter))
        self.restoresTyped = restoresTyped
        self.typed = typed; self.inserted = inserted; self.caretLeft = caretLeftAfter
    }

    /// The undo: from the caret at `{{курсор}}` (if any) back to the end of the insertion,
    /// then the abbreviation as it was typed, with the caret after it.
    public var inverse: SnippetEditPlan {
        SnippetEditPlan(snippetID: snippetID, from: inserted, to: typed, caretRightFirst: caretLeft, caretLeftAfter: 0,
                        restoresTyped: true, typed: typed, inserted: inserted)
    }

    public static func insertion(for text: String) -> Insertion {
        text.count > pasteThreshold || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            ? .paste : .keystrokes
    }

    /// Whether text ending at the caret is the state the first step expects. With
    /// `anchored` a word boundary (or the start of the text) must precede the abbreviation:
    /// use it when the typed buffer itself does not prove one.
    public func expects(textBeforeCaret text: String, anchored: Bool = false, application: String = "") -> Bool {
        let expected = fieldText(expectedBefore, application: application)
        guard text.hasSuffix(expected) else { return false }
        guard anchored else { return true }
        return text.dropLast(expected.count).last.map { $0.isWhitespace } ?? true
    }

    /// Whether text ending at the caret shows the edit done.
    public func confirms(textBeforeCaret text: String, application: String = "") -> Bool {
        text.hasSuffix(fieldText(expectedAfter, application: application))
    }

    public func textAfterDeletion(from text: String, application: String) -> String? {
        guard moveRight == 0, expects(textBeforeCaret: text, application: application), text.count >= deleteCount else { return nil }
        return String(text.dropLast(deleteCount))
    }

    private func fieldText(_ text: String, application: String) -> String {
        // Telegram's AX value represents pasted line breaks as U+2028, including before undo.
        application == "com.tdesktop.Telegram" ? text.replacingOccurrences(of: "\n", with: "\u{2028}") : text
    }

    /// `insertText` as keyboard-event chunks (only for `.keystrokes`).
    public func unicodeChunks(limit: Int = 16) -> [[UInt16]] {
        KeystrokeEditPlan.unicodeChunks(of: insertText, limit: limit)
    }

    /// The typed buffer after this plan was confirmed. Inserted text is never treated as
    /// typed, so its words are not corrected; the undo restores the typed abbreviation.
    public func update(_ buffer: inout TypedWordBuffer) {
        if restoresTyped {
            buffer.reset(.explicit)
            buffer.insert(expectedAfter)
        } else {
            buffer.resetAfterInsertion(endingWith: expectedAfter)
        }
    }
}
