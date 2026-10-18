import Foundation

/// A bounded prediction of ordinary insertion acknowledged by a replay tap.
/// It neither forwards events nor establishes Accessibility/focus ownership.
public struct ReplayInsertionProjection: Sendable {
    public enum Event: Sendable {
        /// Caller has already ruled out navigation, commands, IME and paste operations.
        case insertion(String)
        case keyUp
        case modifierRelease
    }
    public enum InvalidationReason: String, Sendable {
        case unsupportedEvent, unsupportedInsertion, focusChanged, sourceChanged, capacityExceeded
    }
    public enum UndoLearningPolicy: Sendable, Equatable { case none }
    public struct CorrectionBatch: Sendable {
        public let edit: TextEdit
        /// A contiguous aggregate replacement. Its reason represents the last changed token.
        public let decision: Decision
        /// Individual automatic decisions, in input order; never a sentence-level learning entry.
        public let tokens: [Decision]
        public let undoLearning: UndoLearningPolicy
    }

    public let anchorText: String
    public let anchorSelection: NSRange
    public let maxInsertedUTF16: Int
    public let maxCompletedTokens: Int
    public private(set) var expectedText: String
    public private(set) var expectedSelection: NSRange
    public private(set) var completedTokenRanges: [NSRange] = []
    public private(set) var invalidationReason: InvalidationReason?
    public private(set) var version: UInt64 = 0
    public var isValid: Bool { invalidationReason == nil }
    public var insertedRange: NSRange { NSRange(location: anchorSelection.location, length: insertion.utf16.count) }
    public var hasUnfinishedTail: Bool { !insertion.isEmpty && insertion.last != " " }
    public var lastCompletedToken: String? {
        guard isValid, !hasUnfinishedTail, let last = completedTokenRanges.last,
              let range = TextEdit.validatedRange(last, in: expectedText) else { return nil }
        return String(expectedText[range])
    }

    private let prefix: String
    private let suffix: String
    private var insertion = ""
    private var tokenStart: Int?
    private var awaitingFirstBoundary: Bool

    /// Ordinary delimiter semantics: carry the current word into a later exact readback.
    /// Replay itself must keep using init, which excludes pre-existing partial words.
    public static func completingToken(text: String, selection: NSRange) -> Self? {
        guard selection.length == 0 else { return nil }
        guard let word = TextEdit.wordBeforeCursor(in: text, cursor: selection.location, skipTrailingSpace: false) else {
            return Self(anchorText: text, selection: selection)
        }
        guard let range = TextEdit.validatedRange(word, in: text),
              let removal = TextEdit(text: text, selection: word, replacement: ""),
              var projection = Self(anchorText: removal.expectedText, selection: NSRange(location: word.location, length: 0)) else { return nil }
        projection.consume(.insertion(String(text[range])))
        return projection.isValid ? projection : nil
    }

    public init?(anchorText: String, selection: NSRange,
                 maxInsertedUTF16: Int = 2048, maxCompletedTokens: Int = 64) {
        guard selection.length == 0, anchorText.utf16.count <= 65_536,
              (1...65_536).contains(maxInsertedUTF16), (1...1024).contains(maxCompletedTokens),
              let range = TextEdit.validatedRange(selection, in: anchorText) else { return nil }
        self.anchorText = anchorText; self.anchorSelection = selection
        self.maxInsertedUTF16 = maxInsertedUTF16; self.maxCompletedTokens = maxCompletedTokens
        self.expectedText = anchorText; self.expectedSelection = selection
        self.prefix = String(anchorText[..<range.lowerBound])
        self.suffix = String(anchorText[range.upperBound...])
        self.awaitingFirstBoundary = range.lowerBound > anchorText.startIndex &&
            !anchorText[anchorText.index(before: range.lowerBound)].isWhitespace
    }

    public mutating func invalidate(reason: InvalidationReason = .unsupportedEvent) {
        if invalidationReason == nil { invalidationReason = reason }
        version &+= 1
    }

    public mutating func consume(_ event: Event) {
        guard isValid else { return }
        version &+= 1
        switch event {
        case .keyUp, .modifierRelease:
            return
        case .insertion(let value):
            // Deliberately conservative: printable ASCII, Space and Russian letters only.
            // Unknown composition, controls, dead keys and emoji invalidate prediction.
            guard !value.isEmpty, value.unicodeScalars.allSatisfy({ scalar in
                (32...126).contains(scalar.value) || (0x410...0x44f).contains(scalar.value) || scalar == "ё" || scalar == "Ё"
            }) else { invalidate(reason: .unsupportedInsertion); return }
            guard value.utf16.count <= maxInsertedUTF16 - insertion.utf16.count,
                  anchorText.utf16.count + insertion.utf16.count + value.utf16.count <= 65_536 else {
                invalidate(reason: .capacityExceeded); return
            }
            for character in value {
                let position = anchorSelection.location + insertion.utf16.count
                if character == " " {
                    if let start = tokenStart {
                        guard completedTokenRanges.count < maxCompletedTokens else {
                            invalidate(reason: .capacityExceeded); return
                        }
                        completedTokenRanges.append(NSRange(location: start, length: position - start))
                    }
                    tokenStart = nil; awaitingFirstBoundary = false
                } else if !awaitingFirstBoundary && tokenStart == nil {
                    tokenStart = position
                }
                insertion.append(character)
            }
            expectedText = prefix + insertion + suffix
            expectedSelection = NSRange(location: anchorSelection.location + insertion.utf16.count, length: 0)
        }
    }

    /// Safe to use for bounded exact cache publication even when there are no completed words.
    /// ownsAnchor must cover runtime field identity, replay epoch, source and current revision.
    /// String equality alone is insufficient: compare exact UTF-16, not Unicode equivalence.
    public func matchesObserved(text: String, selection: NSRange, ownsAnchor: Bool) -> Bool {
        isValid && ownsAnchor && selection == expectedSelection && text.utf16.elementsEqual(expectedText.utf16)
    }

    /// No callbacks or edits on a mismatched/unowned observation. A pending AX view may be
    /// reread by the caller within its bounded deadline; this method never guesses missing text.
    public func finish(observedText: String, selection: NSRange, ownsAnchor: Bool,
                       language: (String) -> Language? = { _ in nil },
                       decide: (String) -> Decision?) -> CorrectionBatch? {
        guard matchesObserved(text: observedText, selection: selection, ownsAnchor: ownsAnchor) else { return nil }
        var changes: [(range: NSRange, decision: Decision)] = []
        var lastCompletedChanged = false
        for (index, range) in completedTokenRanges.enumerated() {
            guard let swift = TextEdit.validatedRange(range, in: observedText) else { return nil }
            let token = String(observedText[swift])
            guard let decision = decide(token) else { continue }
            // Punctuation policy belongs to the normal automatic evaluator. It must wrap
            // a prefix-only correction as a full-token replacement before returning it.
            guard decision.original.utf16.elementsEqual(token.utf16) else { return nil }
            guard !decision.replacement.utf16.elementsEqual(token.utf16) else { continue }
            guard !decision.replacement.isEmpty, decision.replacement.utf16.count <= 4096,
                  !decision.replacement.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            changes.append((range, decision))
            if index == completedTokenRanges.count - 1 { lastCompletedChanged = true }
        }
        guard let first = changes.first, let last = changes.last else { return nil }
        let aggregateRange = NSRange(location: first.range.location,
                                     length: last.range.location + last.range.length - first.range.location)
        let replacementSize = aggregateRange.length + changes.reduce(0) { $0 + $1.decision.replacement.utf16.count - $1.range.length }
        guard (1...4096).contains(replacementSize),
              observedText.utf16.count - aggregateRange.length + replacementSize <= 65_536,
              let aggregateSwift = TextEdit.validatedRange(aggregateRange, in: observedText) else { return nil }
        let original = String(observedText[aggregateSwift])
        var replacement = original
        for change in changes.reversed() {
            let relative = NSRange(location: change.range.location - aggregateRange.location, length: change.range.length)
            guard let range = TextEdit.validatedRange(relative, in: replacement) else { return nil }
            replacement.replaceSubrange(range, with: change.decision.replacement)
        }
        guard let edit = TextEdit(text: observedText, selection: aggregateRange, replacement: replacement) else { return nil }
        let target = hasUnfinishedTail ? nil : (lastCompletedChanged ? last.decision.targetLanguage : lastCompletedToken.flatMap(language))
        let aggregate = Decision(original: original, replacement: replacement, reason: last.decision.reason, targetLanguage: target)
        return CorrectionBatch(edit: edit, decision: aggregate, tokens: changes.map(\.decision), undoLearning: .none)
    }
}
