import Foundation

/// The text of a snippet with variables (DECISIONS п. 28):
/// `{{дата}}`, `{{дата:формат}}`, `{{время}}`, `{{время:формат}}`, `{{буфер}}` (clipboard
/// text) and `{{курсор}}` (where the caret ends, at most once). `\{{` is a literal `{{`;
/// any other backslash is literal. Formats are DateFormatter patterns.
/// Pure: the clock, time zone, locale and clipboard are the caller's.
public enum SnippetTemplate {
    public static let defaultDateFormat = "dd.MM.yyyy"
    public static let defaultTimeFormat = "HH:mm"

    public enum Part: Equatable, Sendable {
        case literal(String)
        case date(format: String)
        case time(format: String)
        case clipboard
        case cursor
    }

    /// A syntax error at a Character offset of the template, for the editor.
    public enum Failure: Error, Equatable, Sendable {
        case unclosed(at: Int)
        case unknownVariable(String, at: Int)
        /// `{{дата:}}`: a colon without a format.
        case emptyFormat(at: Int)
        /// `{{буфер:…}}`, `{{курсор:…}}` take no format.
        case unexpectedFormat(at: Int)
        case repeatedCursor(at: Int)
    }

    /// Text whose every `{{` stays literal: each is written as `\{{`.
    public static func escaped(_ literal: String) -> String {
        // By scalars, as `parse` reads them: `{` + `{́` is still an opening pair.
        let scalars = Array(literal.unicodeScalars)
        var result = String.UnicodeScalarView(), index = 0
        while index < scalars.count {
            if index + 1 < scalars.count, scalars[index] == "{", scalars[index + 1] == "{" {
                result.append(contentsOf: "\\{{".unicodeScalars); index += 2
            } else { result.append(scalars[index]); index += 1 }
        }
        return String(result)
    }

    /// The text of a template made only of literal text; nil for variables, errors or empty text.
    public static func literal(_ template: String) -> String? {
        guard case .success(let parts) = parse(template), !parts.isEmpty else { return nil }
        var text = ""
        for part in parts {
            guard case .literal(let value) = part else { return nil }
            text += value
        }
        return text
    }

    public static func parse(_ template: String) -> Result<[Part], Failure> {
        // Scalars, not Characters: a combining mark after `{{` or `}}` must not hide the braces.
        let scalars = Array(template.unicodeScalars)
        var parts: [Part] = [], literal = String.UnicodeScalarView(), index = 0, cursorSeen = false
        func flush() { if !literal.isEmpty { parts.append(.literal(String(literal))); literal = String.UnicodeScalarView() } }
        func pair(_ scalar: Unicode.Scalar, at position: Int) -> Bool {
            position + 1 < scalars.count && scalars[position] == scalar && scalars[position + 1] == scalar
        }
        /// Errors report the Character offset the editor shows.
        func at(_ position: Int) -> Int { String(String.UnicodeScalarView(scalars[..<position])).count }
        while index < scalars.count {
            if scalars[index] == "\\", pair("{", at: index + 1) {
                literal.append(contentsOf: "{{".unicodeScalars); index += 3; continue
            }
            guard pair("{", at: index) else { literal.append(scalars[index]); index += 1; continue }
            var close = index + 2
            while close < scalars.count, !pair("}", at: close) { close += 1 }
            guard close < scalars.count else { return .failure(.unclosed(at: at(index))) }
            let inner = String(String.UnicodeScalarView(scalars[(index + 2)..<close]))
            let colon = inner.firstIndex(of: ":")
            let name = String(colon.map { inner[..<$0] } ?? inner[...]).trimmingCharacters(in: .whitespaces).lowercased()
            let format = colon.map { String(inner[inner.index(after: $0)...]) }
            if format?.isEmpty == true, name == "дата" || name == "время" { return .failure(.emptyFormat(at: at(index))) }
            let part: Part
            switch name {
            case "дата": part = .date(format: format ?? defaultDateFormat)
            case "время": part = .time(format: format ?? defaultTimeFormat)
            case "буфер", "курсор":
                guard format == nil else { return .failure(.unexpectedFormat(at: at(index))) }
                if name == "курсор" {
                    guard !cursorSeen else { return .failure(.repeatedCursor(at: at(index))) }
                    cursorSeen = true
                }
                part = name == "буфер" ? .clipboard : .cursor
            default: return .failure(.unknownVariable(name, at: at(index)))
            }
            flush(); parts.append(part)
            index = close + 2
        }
        flush()
        return .success(parts)
    }

    /// How the typed abbreviation's case is carried to the literal text of the snippet.
    /// Variables (date, clipboard) are never re-cased.
    public enum CaseStyle: Equatable, Sendable { case asWritten, capitalized, upper }

    /// The text to insert and how many Characters stay after the caret at `{{курсор}}`;
    /// nil without a cursor: the caret ends after everything inserted.
    public struct Expansion: Equatable, Sendable {
        public let text: String
        public let caretOffset: Int?
        public init(text: String, caretOffset: Int?) { self.text = text; self.caretOffset = caretOffset }
    }

    public enum RenderFailure: Error, Equatable {
        case template(Failure)
        /// `{{буфер}}` with no text on the clipboard: nothing is inserted rather than nothing.
        case clipboardUnavailable
        /// The clipboard text has control characters other than line breaks and tabs.
        case clipboardCharacters
        /// The expansion would exceed `SnippetLibrary.maximumTextLength`.
        case tooLong
    }

    public static func render(_ template: String, caseStyle: CaseStyle = .asWritten, now: Date,
                              timeZone: TimeZone, locale: Locale = Locale(identifier: "ru_RU"),
                              clipboard: String?) -> Result<Expansion, RenderFailure> {
        let parts: [Part]
        switch parse(template) {
        case .success(let value): parts = value
        case .failure(let failure): return .failure(.template(failure))
        }
        func formatted(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale; formatter.timeZone = timeZone; formatter.dateFormat = pattern
            return formatter.string(from: now)
        }
        var before = "", after = "", cursorPassed = false
        for (position, part) in parts.enumerated() {
            let piece: String
            switch part {
            case .literal(let text):
                switch caseStyle {
                case .asWritten: piece = text
                case .upper: piece = text.uppercased()
                case .capitalized: piece = position == 0 ? text.prefix(1).uppercased() + text.dropFirst() : text
                }
            case .date(let pattern), .time(let pattern): piece = formatted(pattern)
            case .clipboard:
                guard let clipboard, !clipboard.isEmpty else { return .failure(.clipboardUnavailable) }
                let normalized = clipboard.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                guard !normalized.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
                }) else { return .failure(.clipboardCharacters) }
                piece = normalized
            case .cursor: cursorPassed = true; continue
            }
            if cursorPassed { after += piece } else { before += piece }
            if before.count + after.count > SnippetLibrary.maximumTextLength { return .failure(.tooLong) }
        }
        // Counted on the joined text: a Character can never be split by the caret.
        let text = before + after
        return .success(Expansion(text: text, caretOffset: cursorPassed ? max(0, text.count - before.count) : nil))
    }
}
