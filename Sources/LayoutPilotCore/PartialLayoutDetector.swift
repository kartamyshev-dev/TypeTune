import Foundation

/// Independent conservative prefix recognizer built only from our authored lexicon.
/// It is not the reference application's statistical partial-word classifier.
public struct PartialLayoutDetector: Sendable {
    /// Shared immutable index: constructing an Engine does not rebuild prefixes.
    public static let bundled = PartialLayoutDetector(lexicon: .bundled)
    private let englishPrefixes: Set<String>
    private let russianPrefixes: Set<String>

    /// Snapshot a custom lexicon once, outside the per-key path. Subsequent mutations
    /// of Engine.lexicon or this source value do not modify this immutable detector.
    public init(lexicon: Lexicon) {
        englishPrefixes = Self.prefixes(lexicon.english, language: .english)
        russianPrefixes = Self.prefixes(lexicon.russian, language: .russian)
    }

    private static func isLetter(_ scalar: Unicode.Scalar, in language: Language) -> Bool {
        switch language {
        case .english: return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        case .russian: return (0x410...0x44f).contains(scalar.value) || scalar == "ё" || scalar == "Ё"
        }
    }
    private static func prefixes(_ words: Set<String>, language: Language) -> Set<String> {
        var result = Set<String>()
        for word in words {
            let lower = word.lowercased()
            guard (3...64).contains(lower.count), lower.unicodeScalars.allSatisfy({ isLetter($0, in: language) }) else { continue }
            var prefix = "", count = 0
            for letter in lower {
                prefix.append(letter); count += 1
                if count >= 3 { result.insert(prefix) }
            }
        }
        return result
    }
    private func containsPrefix(_ word: String, language: Language) -> Bool {
        switch language {
        case .english: return englishPrefixes.contains(word)
        case .russian: return russianPrefixes.contains(word)
        }
    }
    fileprivate func candidate(_ word: String, mapping: Layout.Mapping) -> (replacement: String, language: Language)? {
        guard (3...64).contains(word.count), !word.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
        let source: Language
        if word.unicodeScalars.allSatisfy({ Self.isLetter($0, in: .english) }) { source = .english }
        else if word.unicodeScalars.allSatisfy({ Self.isLetter($0, in: .russian) }) { source = .russian }
        else { return nil }
        // Full known words are included in their prefix set. No frequency inference,
        // typo, case normalization, ё substitution or user-rule evaluation occurs.
        guard !containsPrefix(word.lowercased(), language: source) else { return nil }
        let target: Language = source == .english ? .russian : .english
        let converted = Layout.convert(word, to: target, mapping: mapping)
        guard converted.unicodeScalars.allSatisfy({ Self.isLetter($0, in: target) }),
              containsPrefix(converted.lowercased(), language: target) else { return nil }
        return (converted, target)
    }
}

public extension Engine {
    /// A partial-word layout proposal, not permission to edit or change TIS.
    /// Use an explicitly snapshotted detector for a custom/mutated lexicon; the
    /// default is intentionally the shared authored bundled vocabulary only.
    func decidePartial(_ word: String, context: InputContext = InputContext(),
                       detector: PartialLayoutDetector = .bundled) -> Decision? {
        guard settings.automatic, settings.automaticChangesAllowed(in: context.application),
              !context.secure, context.reliable,
              !settings.excludedApps.contains(context.application),
              let candidate = detector.candidate(word, mapping: mapping) else { return nil }
        let lower = word.lowercased(), converted = candidate.replacement.lowercased()
        // Respect whole-word exceptions before they finish being typed. A source
        // or target prefix of a protected entry is deliberately also protected.
        let protected = settings.excludedWords + settings.learnedWords
        guard !protected.contains(where: {
            let value = $0.lowercased()
            return value.hasPrefix(lower) || value.hasPrefix(converted)
        }), !settings.rules.contains(where: { $0.source.lowercased().hasPrefix(lower) }) else { return nil }
        return Decision(original: word, replacement: candidate.replacement, reason: .layout,
                        targetLanguage: candidate.language)
    }
}

/// A range-bound suggestion. Runtime must independently verify full editor text,
/// caret, focus/source/revision and permissions again before applying this range.
public struct PartialLayoutProposal: Equatable, Sendable {
    public let range: NSRange
    public let decision: Decision
}

public extension Engine {
    func partialProposal(in text: String, selection: NSRange,
                         context: InputContext = InputContext(),
                         detector: PartialLayoutDetector = .bundled) -> PartialLayoutProposal? {
        guard text.utf16.count <= 65_536, selection.length == 0,
              let caret = TextEdit.validatedRange(selection, in: text),
              caret.lowerBound == text.endIndex || text[caret.lowerBound].isWhitespace,
              let range = TextEdit.wordBeforeCursor(in: text, cursor: selection.location, skipTrailingSpace: false),
              (3...64).contains(range.length),
              let tokenRange = TextEdit.validatedRange(range, in: text),
              let decision = decidePartial(String(text[tokenRange]), context: context, detector: detector) else { return nil }
        return PartialLayoutProposal(range: range, decision: decision)
    }
}
