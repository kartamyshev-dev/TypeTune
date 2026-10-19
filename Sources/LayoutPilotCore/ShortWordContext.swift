import Foundation

/// Short words (one or two letters: «в», «на», «не», `a`, `is`) are never converted on their
/// own: too many are valid in both layouts or are abbreviations. In running text they are
/// about a fifth of Russian words, so typing «yf ghbdtn» left «yf привет». When the next word
/// is converted to a language, the short words typed right before it in the other layout are
/// converted with it, if each is a known word of that language and not a word as typed.
public extension Engine {
    /// One-letter words; the lexicon holds words of two letters or more.
    static let oneLetterWords: [Language: Set<String>] = [
        .russian: ["а", "в", "и", "к", "о", "с", "у", "я"], .english: ["a", "i"]
    ]
    static let shortWordContextLimit = 2

    /// The short words to convert together with a token converted to `target`.
    /// `before` is the typed text that ends right where the token starts (so it ends with the
    /// whitespace before the token). Each short word must be preceded by whitespace inside
    /// `before`, or start it while `anchoredStart` is true: its characters were typed and it
    /// is a whole word. Returns the text as typed and its replacement, covering the short
    /// words and the whitespace after each; nil when there is none.
    func shortWordPrefix(before: String, anchoredStart: Bool, target: Language) -> (typed: String, replacement: String)? {
        var rest = Substring(before), typed = "", replacement = ""
        for _ in 0..<Self.shortWordContextLimit {
            let space = rest.reversed().prefix(while: { $0 == " " }).count
            guard space > 0 else { break }
            let beforeSpace = rest.dropLast(space)
            let word = String(beforeSpace.reversed().prefix(while: { $0.isLetter }).reversed())
            guard (1...2).contains(word.count) else { break }
            let start = beforeSpace.dropLast(word.count)
            guard start.last?.isWhitespace ?? anchoredStart else { break }
            guard let converted = shortWordConversion(word, to: target) else { break }
            typed = word + String(repeating: " ", count: space) + typed
            replacement = converted + String(repeating: " ", count: space) + replacement
            rest = start
        }
        return typed.isEmpty ? nil : (typed, replacement)
    }

    /// `word` typed in the other layout as a known short word of `target`, or nil when it is
    /// not in the other layout, is a word as typed, or converts to no known word.
    func shortWordConversion(_ word: String, to target: Language) -> String? {
        let source: Language = target == .russian ? .english : .russian
        guard Layout.language(of: word) == source, !Layout.isMixed(word), !settings.excludes(word) else { return nil }
        let converted = Layout.convert(word, to: target, mapping: mapping)
        guard converted != word, Layout.language(of: converted) == target,
              isShortWord(converted, in: target), !isShortWord(word, in: source) else { return nil }
        return converted
    }

    private func isShortWord(_ word: String, in language: Language) -> Bool {
        let lower = word.lowercased()
        if Self.oneLetterWords[language]?.contains(lower) == true { return true }
        return lower.count == 2 && (language == .russian ? lexicon.russian : lexicon.english).contains(lower)
    }
}
