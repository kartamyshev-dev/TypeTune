import Foundation

/// A snippet abbreviation found at the caret in the typed buffer.
public struct SnippetMatch: Equatable, Sendable {
    public let snippet: Snippet
    /// The characters before the caret (ahead of `boundary`) that the expansion replaces,
    /// exactly as typed: the abbreviation, possibly in the other layout, and in boundary
    /// mode any trailing sentence punctuation.
    public let typed: String
    /// Punctuation typed after the abbreviation that stays after the expansion, in the
    /// abbreviation's layout (`cgc?` typed for `спс,` keeps `,`).
    public let suffix: String
    /// The whitespace that completed the abbreviation; empty in immediate mode.
    public let boundary: String
    public let caseStyle: SnippetTemplate.CaseStyle
    /// The buffer proves what precedes `typed`: a word boundary, or nothing is required
    /// (immediate abbreviation starting with a sign). False only when `typed` begins the
    /// buffer after a reset: the caller may still proceed when Accessibility shows a boundary.
    public let anchored: Bool
}

/// Finds abbreviations in `TypedWordBuffer` (docs/SNIPPETS_PLAN.md, S3). Pure: the caller
/// passes usable snippets (`SnippetLibrary.usable()`), and handles pause and exclusions.
/// When several abbreviations match, the longest wins.
public enum SnippetMatcher {
    static let sentencePunctuation: Set<Character> = [".", ",", "!", "?", ";", ":"]

    /// After a key typed `inserted` (already appended to `buffer`): an immediate snippet
    /// whose abbreviation now ends at the caret.
    public static func immediate(_ buffer: TypedWordBuffer, inserted: String, snippets: [Snippet],
                                 application: String, mapping: Layout.Mapping = .standardPC) -> SnippetMatch? {
        guard !inserted.isEmpty, buffer.text.hasSuffix(inserted) else { return nil }
        let text = Array(buffer.text)
        for snippet in ordered(snippets, .immediate, application) {
            let length = snippet.abbreviation.count
            guard text.count >= length else { continue }
            let typed = String(text.suffix(length))
            guard let form = forms(typed, snippet, mapping).first(where: { same($0, snippet.abbreviation) }) else { continue }
            var anchored = true
            if needsLeftBoundary(snippet) {
                if text.count > length {
                    guard text[text.count - length - 1].isWhitespace else { continue }
                } else { anchored = buffer.anchoredStart }
            }
            return SnippetMatch(snippet: snippet, typed: typed, suffix: "", boundary: "",
                                caseStyle: caseStyle(form, snippet), anchored: anchored)
        }
        return nil
    }

    /// After whitespace `boundary` was typed: a boundary snippet equal to the token it
    /// completed, optionally followed by sentence punctuation (as former literal rules).
    public static func boundary(_ buffer: TypedWordBuffer, boundary: String, snippets: [Snippet],
                                application: String, mapping: Layout.Mapping = .standardPC) -> SnippetMatch? {
        guard let completed = buffer.completedToken, completed.boundary == boundary else { return nil }
        let token = completed.token
        let anchored = buffer.tokenIsAnchored(boundaryLength: boundary.count)
        for snippet in ordered(snippets, .boundary, application) {
            let all = forms(token, snippet, mapping), converted = Array(all.dropFirst())
            func split(_ form: String) -> (core: String, suffix: String)? {
                let count = form.reversed().prefix(while: { sentencePunctuation.contains($0) }).count
                guard count > 0, count < form.count else { return nil }
                return (String(form.dropLast(count)), String(form.suffix(count)))
            }
            // In order: the whole token; punctuation and abbreviation both as typed; both
            // in the other layout (`cgc?` → `спс,`); punctuation as typed after an
            // abbreviation in the other layout (`cgc,` → `спс,`). A token is converted at
            // most once, and `?`, `;`, `:` exist in both layouts on different keys.
            var tries = all.map { (core: $0, suffix: "") }
            if let typed = split(token) { tries.append(typed) }
            tries += converted.compactMap(split)
            if let typed = split(token) {
                tries += forms(typed.core, snippet, mapping).dropFirst().map { (core: $0, suffix: typed.suffix) }
            }
            guard let hit = tries.first(where: { same($0.core, snippet.abbreviation) }) else { continue }
            return SnippetMatch(snippet: snippet, typed: token, suffix: hit.suffix, boundary: boundary,
                                caseStyle: caseStyle(hit.core, snippet), anchored: anchored)
        }
        return nil
    }

    /// How the typed abbreviation's case reaches the text. Typed as written: unchanged.
    /// Otherwise all letters upper case (two or more) → upper, first letter upper and
    /// the rest lower → capitalized. Never for a snippet that does not match case.
    public static func caseStyle(_ typed: String, _ snippet: Snippet) -> SnippetTemplate.CaseStyle {
        guard snippet.matchCase, typed != snippet.abbreviation else { return .asWritten }
        let letters = typed.filter(\.isLetter)
        guard let first = letters.first else { return .asWritten }
        if letters.count >= 2, letters.allSatisfy({ $0.isUppercase }) { return .upper }
        if first.isUppercase, letters.dropFirst().allSatisfy({ !$0.isUppercase }) { return .capitalized }
        return .asWritten
    }

    private static func ordered(_ snippets: [Snippet], _ trigger: Snippet.Trigger, _ application: String) -> [Snippet] {
        snippets.filter { $0.enabled && $0.trigger == trigger && $0.applications.permits(application) }
            .enumerated().sorted { ($0.element.abbreviation.count, -$0.offset) > ($1.element.abbreviation.count, -$1.offset) }
            .map(\.element)
    }

    /// The text as typed, then (when the snippet allows) as typed on the same keys in
    /// the Russian and in the English layout.
    private static func forms(_ text: String, _ snippet: Snippet, _ mapping: Layout.Mapping) -> [String] {
        guard snippet.otherLayout else { return [text] }
        return [text, Layout.convert(text, to: .russian, mapping: mapping), Layout.convert(text, to: .english, mapping: mapping)]
    }

    private static func same(_ typed: String, _ abbreviation: String) -> Bool {
        typed.lowercased() == abbreviation.lowercased()
    }

    /// A word-like abbreviation must not fire inside a word; one led by a sign may.
    private static func needsLeftBoundary(_ snippet: Snippet) -> Bool {
        snippet.abbreviation.first.map { $0.isLetter || $0.isNumber } ?? true
    }
}
