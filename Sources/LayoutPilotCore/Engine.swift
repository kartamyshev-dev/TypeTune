import Foundation

public struct UserRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var source: String
    public var replacement: String
    public init(source: String, replacement: String) {
        self.id = UUID(); self.source = source; self.replacement = replacement
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var automatic = true
    public var typos = true
    public var yo = true
    public var singleShift = true
    public var optionCorrection = false
    public var shiftChordPause = false
    public var plainPaste = false
    public var sound = false
    /// Global pause: no automatic change at all (layout, typos, ё, case, rules).
    /// Manual conversion and undo keep working. `automatic` is only the layout switch.
    public var paused = false
    /// false pauses every automatic change in that application; true cannot override
    /// the global pause. Full processing exclusions remain a separate, stronger setting.
    public var appAutomatic: [String: Bool] = [:]
    public var excludedApps: [String] = []
    public var excludedWords: [String] = []
    public var rules: [UserRule] = []
    public var learnedWords: [String] = []
    public init() {}
    public func automaticChangesAllowed(in application: String) -> Bool {
        !paused && appAutomatic[application] != false
    }
    public func excludes(_ word: String) -> Bool {
        let lower = word.lowercased()
        return excludedWords.contains { $0.lowercased() == lower } || learnedWords.contains { $0.lowercased() == lower }
    }
    private enum CodingKeys: String, CodingKey {
        case automatic, paused, typos, yo, singleShift, optionCorrection, shiftChordPause,
             plainPaste, sound, appAutomatic, excludedApps, excludedWords, rules, learnedWords
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? true
        paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        typos = try values.decodeIfPresent(Bool.self, forKey: .typos) ?? true
        yo = try values.decodeIfPresent(Bool.self, forKey: .yo) ?? true
        singleShift = try values.decodeIfPresent(Bool.self, forKey: .singleShift) ?? true
        optionCorrection = try values.decodeIfPresent(Bool.self, forKey: .optionCorrection) ?? false
        shiftChordPause = try values.decodeIfPresent(Bool.self, forKey: .shiftChordPause) ?? false
        plainPaste = try values.decodeIfPresent(Bool.self, forKey: .plainPaste) ?? false
        sound = try values.decodeIfPresent(Bool.self, forKey: .sound) ?? false
        appAutomatic = try values.decodeIfPresent([String: Bool].self, forKey: .appAutomatic) ?? [:]
        excludedApps = try values.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
        excludedWords = try values.decodeIfPresent([String].self, forKey: .excludedWords) ?? []
        rules = try values.decodeIfPresent([UserRule].self, forKey: .rules) ?? []
        learnedWords = try values.decodeIfPresent([String].self, forKey: .learnedWords) ?? []
    }
}

public struct InputContext: Codable, Equatable, Sendable {
    public var application: String
    public var secure: Bool
    public var reliable: Bool
    public init(application: String = "test", secure: Bool = false, reliable: Bool = true) {
        self.application = application; self.secure = secure; self.reliable = reliable
    }
}

public struct Decision: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable { case layout, typo, yo, userRule, manual }
    public var original: String
    public var replacement: String
    public var reason: Reason
    public var targetLanguage: Language?
    /// The word an undo learns when original also covers converted punctuation.
    public var learnAs: String?
    public init(original: String, replacement: String, reason: Reason, targetLanguage: Language? = nil,
                learnAs: String? = nil) {
        self.original = original; self.replacement = replacement; self.reason = reason
        self.targetLanguage = targetLanguage; self.learnAs = learnAs
    }
}

public struct Lexicon: Codable, Sendable {
    public var english: Set<String>
    public var russian: Set<String>
    public var typos: [String: String]
    public var yo: [String: String]
    public static let bundled: Lexicon = {
        let url = CoreResources.url(forResource: "lexicon", withExtension: "json")!
        return try! JSONDecoder().decode(Lexicon.self, from: Data(contentsOf: url))
    }()
    public func contains(_ word: String) -> Bool {
        english.contains(word.lowercased()) || russian.contains(word.lowercased())
    }
}

public struct Engine: Sendable {
    // Independently authored exceptions for established internal capitalization.
    // The reference uses a model feature veto; its data is not bundled here.
    private static let doubleCapsPreservedWords: Set<String> = [
        "facebook", "iphone", "mhz"
    ]
    /// Shape of the double-capital typo: two capitals, then a lowercase letter, letters only.
    public static func isDoubleCapitalTypo(_ word: String) -> Bool {
        let letters = Array(word)
        return letters.count > 2 && letters.allSatisfy({ $0.isLetter }) &&
            letters[0].isUppercase && letters[1].isUppercase && letters[2].isLowercase
    }
    public var settings: Settings
    public var lexicon: Lexicon
    public var mapping: Layout.Mapping
    public init(settings: Settings = Settings(), lexicon: Lexicon = .bundled, mapping: Layout.Mapping = .standardPC) {
        self.settings = settings; self.lexicon = lexicon; self.mapping = mapping
    }
    public func completedTokenLanguage(_ word: String, context: InputContext = InputContext()) -> Language? {
        guard settings.automatic, settings.automaticChangesAllowed(in: context.application),
              !context.secure, context.reliable, !settings.excludedApps.contains(context.application),
              !settings.excludes(word), !Layout.isMixed(word), word.allSatisfy({ $0.isLetter }),
              lexicon.contains(word) else { return nil }
        return Layout.language(of: word)
    }
    public func decide(_ word: String, context: InputContext = InputContext()) -> Decision? {
        guard !context.secure, context.reliable, settings.automaticChangesAllowed(in: context.application),
              !settings.excludedApps.contains(context.application), !word.isEmpty else { return nil }
        let lower = word.lowercased()
        guard !settings.excludes(word) else { return nil }
        let automatic = settings.automatic
        // User rules are literal and intentionally take precedence over automatic heuristics.
        if automatic, let rule = settings.rules.first(where: { $0.source.lowercased() == lower }) {
            let value = Layout.matchingCase(rule.replacement, source: word)
            return value == word ? nil : Decision(original: word, replacement: value, reason: .userRule,
                                                   targetLanguage: Layout.language(of: value))
        }
        let converted = Layout.convert(word, mapping: mapping)
        // Physical US punctuation keys can represent Russian letters (компьютер, пожалуйста).
        // A candidate must be a known all-letter word; paths, digits and mixed scripts stay intact.
        guard word.count >= 3, !Layout.isMixed(word),
              word.allSatisfy({ $0.isLetter }) || converted.allSatisfy({ $0.isLetter }) else { return nil }
        // A known word followed by its own sentence punctuation is ordinary text: the
        // period of "it." is not the Russian ю of шею.
        let stripped = word.prefix(while: { !".,!?;:".contains($0) })
        if stripped.count < word.count, word.dropFirst(stripped.count).allSatisfy({ ".,!?;:".contains($0) }),
           lexicon.contains(String(stripped)) { return nil }
        var result = word
        var reason: Decision.Reason?
        let letters = Array(word)
        // Physical punctuation is admitted above for dictionary-backed layout lookup,
        // but it does not license unconditional case changes in filenames/code tokens.
        // Three letters are usually an acronym plural or unit (IDs, PCs, GHz): change
        // those only when the corrected word is known in either layout (МИр, DAy), and
        // never two capitals plus a plural s, even when the lowercase word exists (ids).
        if settings.typos, Self.isDoubleCapitalTypo(word), !Self.doubleCapsPreservedWords.contains(lower) {
            let fixed = String(word.prefix(1)) + word.dropFirst().lowercased()
            if letters.count > 3 || (letters[2] != "s" &&
                (lexicon.contains(fixed) || lexicon.contains(Layout.convert(fixed, mapping: mapping)))) {
                result = fixed; reason = .typo
            }
        }
        // Stages compose in order: layout and spelling operate on the case-
        // corrected candidate, otherwise GHbdtn would become ПРивет again.
        let candidate = Layout.convert(result, mapping: mapping)
        if !lexicon.contains(result.lowercased()) {
            if automatic, lexicon.contains(candidate) {
                result = candidate; reason = .layout
            } else if settings.typos, let typo = lexicon.typos[result.lowercased()] {
                result = Layout.matchingCase(typo, source: result); reason = .typo
            }
        }
        if settings.yo, let yo = lexicon.yo[result.lowercased()] {
            result = Layout.matchingCase(yo, source: result)
            if reason == nil { reason = .yo }
        }
        guard let reason, result != word else { return nil }
        return Decision(original: word, replacement: result, reason: reason, targetLanguage: Layout.language(of: result))
    }

    /// Sentence punctuation that a trailing physical key may stand for in the other layout.
    /// `;` and `:` are excluded: in RU→EN they come from ж/Ж, which end many Russian words.
    public static let physicalSuffixPunctuation: Set<Character> = [".", ",", "?", "!"]

    /// Returns the whole-token decision, a layout decision whose trailing keys are the
    /// other layout's sentence punctuation (ghbdtn/ → привет., руддщю → hello.), or a
    /// prefix decision before literal sentence punctuation.
    /// isKnownWord protects a token that is itself a word; the default is the lexicon.
    public func completedTokenDecision(_ token: String, decide: (String) -> Decision?,
                                       isKnownWord: ((String) -> Bool)? = nil) -> Decision? {
        guard !settings.excludes(token) else { return nil }
        if let value = decide(token) { return value }
        let converted = Array(Layout.convert(token, mapping: mapping))
        // Only keys that differ between layouts: `!` is literal punctuation in both.
        let original = Array(token)
        let physical = zip(original.reversed(), converted.reversed())
            .prefix(while: { $0 != $1 && Self.physicalSuffixPunctuation.contains($1) }).count
        if physical > 0, physical < original.count, converted.count == original.count,
           !(isKnownWord ?? { lexicon.contains($0) })(token) {
            let prefix = String(token.dropLast(physical))
            if let value = decide(prefix), value.reason == .layout {
                return Decision(original: token, replacement: value.replacement + String(converted.suffix(physical)),
                                reason: .layout, targetLanguage: value.targetLanguage, learnAs: value.learnAs ?? prefix)
            }
        }
        let suffix = token.reversed().prefix(while: { ".,!?;:".contains($0) }).count
        guard suffix > 0, suffix < token.count else { return nil }
        return decide(String(token.dropLast(suffix)))
    }

    public func manual(_ text: String, context: InputContext = InputContext()) -> Decision? {
        guard !context.secure, context.reliable, !settings.excludedApps.contains(context.application),
              !text.isEmpty, Layout.language(of: text) != nil else { return nil }
        let replacement = Layout.convert(text, mapping: mapping)
        guard replacement != text else { return nil }
        return Decision(original: text, replacement: replacement, reason: .manual,
                        targetLanguage: Layout.language(of: replacement))
    }
}

public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var original: String
    public var replacement: String
    public var expectedText: String
    public var cursor: Int

    public init?(text: String, selection: NSRange, replacement: String) {
        guard let range = Self.validatedRange(selection, in: text) else { return nil }
        self.range = selection; self.original = String(text[range]); self.replacement = replacement
        self.expectedText = text.replacingCharacters(in: range, with: replacement)
        self.cursor = selection.location + replacement.utf16.count
    }

    /// Predict ordinary insertion into a previously pinned editor. This is only
    /// an expectation: callers must reread AX target/text/caret before any write.
    public static func insertionPrediction(text: String, selection: NSRange,
                                           characters: String, keyCode: Int) -> TextEdit? {
        guard !characters.isEmpty,
              ![36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keyCode),
              characters.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0) && !(0xf700...0xf8ff).contains($0.value)
              }),
              let result = TextEdit(text: text, selection: selection, replacement: characters),
              result.expectedText.utf16.count <= 65_536 else { return nil }
        return result
    }

    /// A capture readiness check, not proof that this event caused the text.
    /// Full target/text/caret equality is still required before replacement.
    public static func observesInsertionSuffix(text: String, selection: NSRange,
                                               characters: String, keyCode: Int) -> Bool {
        guard text.utf16.count <= 65_536, selection.length == 0,
              validatedRange(selection, in: text) != nil,
              insertionPrediction(text: "", selection: NSRange(location: 0, length: 0),
                                  characters: characters, keyCode: keyCode) != nil,
              selection.location >= characters.utf16.count,
              let suffix = validatedRange(NSRange(location: selection.location - characters.utf16.count,
                                                   length: characters.utf16.count), in: text) else { return false }
        return String(text[suffix]) == characters
    }

    public func resultingSelection(from originalSelection: NSRange, keepSelection: Bool = false) -> NSRange {
        if keepSelection { return NSRange(location: range.location, length: replacement.utf16.count) }
        let location = originalSelection.length > 0 ? cursor : originalSelection.location + replacement.utf16.count - range.length
        return NSRange(location: max(0, location), length: 0)
    }

    public static func validatedRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        let size = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= size,
              range.length <= size - range.location else { return nil }
        let start = String.Index(utf16Offset: range.location, in: text)
        let end = String.Index(utf16Offset: range.location + range.length, in: text)
        let boundaries = Set(text.indices).union([text.endIndex])
        guard boundaries.contains(start), boundaries.contains(end) else { return nil }
        return start..<end
    }

    public static func wordBeforeCursor(in text: String, cursor: Int, skipTrailingSpace: Bool = true) -> NSRange? {
        guard let empty = validatedRange(NSRange(location: cursor, length: 0), in: text) else { return nil }
        let endIndex = empty.lowerBound
        var end = endIndex
        if skipTrailingSpace { while end > text.startIndex && text[text.index(before: end)].isWhitespace { end = text.index(before: end) } }
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous].isWhitespace { break }
            start = previous
        }
        guard start < end else { return nil }
        return NSRange(start..<end, in: text)
    }
}
