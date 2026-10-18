import Foundation

/// A correction expressed as keystrokes: `deleteCount` Backspaces, then `insertText`
/// typed as Unicode. It replaces `before` (the typed token and its boundary, ending at
/// the caret) with `after`. Characters shared at the start are kept, so only the
/// changed tail is deleted and retyped. Pure: posting and verification are the caller's.
public struct KeystrokeEditPlan: Equatable, Sendable {
    /// Text that must end at the caret before the edit (token + boundary).
    public let before: String
    /// Text that ends at the caret after the edit.
    public let after: String
    public let deleteCount: Int
    public let insertText: String
    public let decision: Decision
    /// The selected text this edit replaces by typing over it (selection conversion).
    public let selection: String?

    /// Builds the edit for a decision on `token`, the token typed just before `boundary`.
    /// The decision may cover the whole token or a prefix of it (literal trailing
    /// punctuation stays as typed). nil when nothing would change or text is untypable.
    public init?(token: String, boundary: String, decision: Decision) {
        guard !token.isEmpty, token.hasPrefix(decision.original), !decision.replacement.isEmpty,
              boundary.allSatisfy({ $0.isWhitespace }) else { return nil }
        let suffix = token.dropFirst(decision.original.count)
        let before = token + boundary
        let after = decision.replacement + suffix + boundary
        guard before != after, !Self.containsControl(before), !Self.containsControl(after) else { return nil }
        self.init(before: before, after: after, decision: decision)
    }

    /// Converts a selection by typing the replacement over it: nothing is deleted first.
    /// Multi-line selections are rejected (a line break cannot be typed as Unicode text).
    public init?(replacingSelection selected: String, decision: Decision) {
        guard !selected.isEmpty, decision.original == selected, !decision.replacement.isEmpty,
              decision.replacement != selected, !Self.containsControl(selected),
              !Self.containsControl(decision.replacement) else { return nil }
        self.before = ""; self.after = decision.replacement
        self.deleteCount = 0; self.insertText = decision.replacement
        self.decision = decision; self.selection = selected
    }

    private init(before: String, after: String, decision: Decision) {
        let shared = zip(before, after).prefix(while: { $0 == $1 }).count
        self.before = before; self.after = after
        self.deleteCount = before.count - shared
        self.insertText = String(after.dropFirst(shared))
        self.decision = decision; self.selection = nil
    }

    /// The undo of this edit: from `after` back to the original text. For a selection
    /// conversion the original is the selected text, now typed back at the caret.
    public var inverse: KeystrokeEditPlan {
        KeystrokeEditPlan(before: after, after: selection ?? before,
                          decision: Decision(original: decision.replacement, replacement: decision.original,
                                             reason: decision.reason, targetLanguage: nil, learnAs: decision.learnAs))
    }

    /// Whether text that ends at the caret is the state this edit expects.
    /// `anchored` additionally requires a word boundary (or the start of the text)
    /// before the token; use it when the typed buffer itself is not anchored.
    public func expects(textBeforeCaret text: String, anchored: Bool = false) -> Bool {
        guard text.hasSuffix(before) else { return false }
        guard anchored else { return true }
        let rest = text.dropLast(before.count)
        return rest.last.map { $0.isWhitespace } ?? true
    }

    /// The text before the caret after a successful edit, given the text before it.
    public func applied(to text: String) -> String? {
        guard text.hasSuffix(before) else { return nil }
        return String(text.dropLast(before.count)) + after
    }

    /// `insertText` as UTF-16 chunks of at most `limit` units, split only at Character
    /// boundaries (some applications accept short Unicode strings per keyboard event).
    public func unicodeChunks(limit: Int = 16) -> [[UInt16]] { Self.unicodeChunks(of: insertText, limit: limit) }

    public static func unicodeChunks(of text: String, limit: Int = 16) -> [[UInt16]] {
        var result: [[UInt16]] = [], current: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty && current.count + units.count > limit { result.append(current); current = [] }
            current += units
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func containsControl(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public extension TypedWordBuffer {
    /// The edit for an automatic decision on the token the last boundary completed.
    func completedTokenEdit(_ decide: (String) -> Decision?) -> KeystrokeEditPlan? {
        guard let completed = completedToken, let decision = decide(completed.token) else { return nil }
        return KeystrokeEditPlan(token: completed.token, boundary: completed.boundary, decision: decision)
    }

    /// The token a manual conversion applies to: the one at the caret, or else the one
    /// the last boundary completed (Double Shift after the space).
    var manualTarget: (token: String, boundary: String)? {
        let current = currentToken
        if !current.isEmpty { return (current, "") }
        return completedToken
    }
}
