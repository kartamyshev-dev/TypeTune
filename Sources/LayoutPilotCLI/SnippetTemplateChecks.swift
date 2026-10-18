import Foundation
import LayoutPilotCore

func snippetTemplateChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "snippet template: " + name)) }
    typealias T = SnippetTemplate
    // 2026-10-18 09:05 UTC; Moscow is UTC+3.
    let now = Date(timeIntervalSince1970: 1_792_314_300)
    let utc = TimeZone(identifier: "UTC")!, moscow = TimeZone(identifier: "Europe/Moscow")!
    func render(_ template: String, _ style: T.CaseStyle = .asWritten, clipboard: String? = "буфер",
                zone: TimeZone = utc) -> Result<T.Expansion, T.RenderFailure> {
        T.render(template, caseStyle: style, now: now, timeZone: zone, clipboard: clipboard)
    }
    func expands(_ template: String, _ style: T.CaseStyle = .asWritten, clipboard: String? = "буфер",
                 zone: TimeZone = utc, to text: String, caret: Int = 0) -> Bool {
        render(template, style, clipboard: clipboard, zone: zone) == .success(T.Expansion(text: text, caretOffset: caret))
    }

    // Parsing.
    check(T.parse("спасибо") == .success([.literal("спасибо")]), "plain text is one literal")
    check(T.parse("") == .success([]), "empty template has no parts")
    check(T.parse("Сегодня {{дата}}, {{время}}") == .success([.literal("Сегодня "), .date(format: T.defaultDateFormat),
          .literal(", "), .time(format: T.defaultTimeFormat)]), "date and time with default formats")
    check(T.parse("{{дата:d MMMM yyyy}}") == .success([.date(format: "d MMMM yyyy")]), "a custom format keeps its spaces")
    check(T.parse("{{время:HH:mm:ss}}") == .success([.time(format: "HH:mm:ss")]), "the format may contain colons")
    check(T.parse("{{ Дата }}") == .success([.date(format: T.defaultDateFormat)]), "names ignore surrounding spaces and case")
    check(T.parse("<b>{{курсор}}</b>") == .success([.literal("<b>"), .cursor, .literal("</b>")]), "cursor")
    check(T.parse("{{буфер}}") == .success([.clipboard]), "clipboard")
    check(T.parse("a } b }} c {") == .success([.literal("a } b }} c {")]), "single braces and closing pairs are literal")

    // Escape and its inverse.
    check(T.parse("\\{{дата}}") == .success([.literal("{{дата}}")]), "backslash keeps braces literal")
    check(T.parse("C:\\path\\{{x") == .success([.literal("C:\\path{{x")]), "only a backslash before braces is consumed")
    check(T.parse("a\\b\\") == .success([.literal("a\\b\\")]), "other backslashes are literal")
    for literal in ["{{", "\\{{", "{{дата}}", "\\", "}}{{}}", "{{{", "x{{y}}z\\{{w", "", "😀{{e\u{301}", "{{\u{301}", "\\\u{301}{{"] {
        let parsed = T.parse(T.escaped(literal))
        check(parsed == .success(literal.isEmpty ? [] : [.literal(literal)]), "escaped text parses back to itself: \(literal)")
    }

    // Syntax errors with positions.
    check(T.parse("ab {{дата") == .failure(.unclosed(at: 3)), "unclosed variable")
    check(T.parse("{{дата}} {{погода}}") == .failure(.unknownVariable("погода", at: 9)), "unknown variable")
    check(T.parse("{{}}") == .failure(.unknownVariable("", at: 0)), "empty variable")
    check(T.parse("{{date}}") == .failure(.unknownVariable("date", at: 0)), "English names are not variables")
    check(T.parse("{{дата:}}") == .failure(.emptyFormat(at: 0)), "colon without format")
    check(T.parse("{{буфер:x}}") == .failure(.unexpectedFormat(at: 0)), "clipboard takes no format")
    check(T.parse("{{курсор:}}") == .failure(.unexpectedFormat(at: 0)), "cursor takes no format")
    check(T.parse("{{курсор}}{{курсор}}") == .failure(.repeatedCursor(at: 10)), "one cursor at most")
    check(T.parse("😀{{x}}") == .failure(.unknownVariable("x", at: 1)), "positions count Characters")
    check(T.parse("e\u{301}{{x}}") == .failure(.unknownVariable("x", at: 1)), "positions count composed Characters")
    check(T.parse("{{дата}}\u{301}") == .success([.date(format: T.defaultDateFormat), .literal("\u{301}")]),
          "a combining mark after the closing braces does not hide them")
    check(T.parse("{{\u{301}дата}}") == .failure(.unknownVariable("\u{301}дата", at: 0)),
          "a combining mark after the opening braces is part of the name")
    check(SnippetLibrary().issues(for: Snippet(abbreviation: "ab", text: "{{погода}}")) ==
          [.template(.unknownVariable("погода", at: 0))], "a broken template is a snippet issue")
    let broken = Snippet(abbreviation: "ab", text: "{{x"), fine = Snippet(abbreviation: "cd", text: "{{дата}}")
    check(SnippetLibrary(snippets: [broken, fine]).usable() == [fine], "a broken template cannot fire")

    // Rendering.
    check(expands("Дата: {{дата}}", to: "Дата: 18.10.2026"), "default date")
    check(expands("{{время}}", to: "09:05"), "default time")
    check(expands("{{время}}", zone: moscow, to: "12:05"), "the caller's time zone")
    check(expands("{{дата:d MMMM yyyy}}", to: "18 октября 2026"), "Russian month name in the genitive")
    check(expands("{{дата:yyyy-MM-dd}}T{{время:HH:mm:ss}}", to: "2026-10-18T09:05:00"), "ISO-like format")
    check(expands("[{{буфер}}]", clipboard: "текст", to: "[текст]"), "clipboard text")
    check(render("{{буфер}}", clipboard: nil) == .failure(.clipboardUnavailable), "no clipboard text: the snippet does not fire")
    check(render("{{буфер}}", clipboard: "") == .failure(.clipboardUnavailable), "empty clipboard text: the snippet does not fire")
    check(expands("{{буфер}}", clipboard: "a\r\nb\rc\td", to: "a\nb\nc\td"), "clipboard line breaks become line feeds")
    check(render("{{буфер}}", clipboard: "a\u{1B}b") == .failure(.clipboardCharacters), "clipboard control characters are refused")
    check(expands("<b>{{курсор}}</b>", to: "<b></b>", caret: 4), "caret offset counts the text after the cursor")
    check(expands("{{курсор}}конец", to: "конец", caret: 5), "cursor at the start")
    check(expands("конец{{курсор}}", to: "конец", caret: 0), "cursor at the end")
    check(expands("e{{курсор}}\u{301}x", to: "e\u{301}x", caret: 1), "the caret never splits a Character")
    check(expands("😀{{курсор}}👍🏽", to: "😀👍🏽", caret: 1), "emoji count as one Character each")
    check(expands("строка 1\nстрока 2", to: "строка 1\nстрока 2"), "line feeds stay")
    check(render("{{x") == .failure(.template(.unclosed(at: 0))), "a syntax error does not render")
    check(render("{{буфер}}", clipboard: String(repeating: "x", count: SnippetLibrary.maximumTextLength)) ==
          .success(T.Expansion(text: String(repeating: "x", count: SnippetLibrary.maximumTextLength), caretOffset: 0)),
          "the longest allowed expansion")
    check(render("!{{буфер}}", clipboard: String(repeating: "x", count: SnippetLibrary.maximumTextLength)) == .failure(.tooLong),
          "an expansion above the limit is refused")

    // Case carried from the typed abbreviation reaches literal text only.
    check(expands("спасибо, {{буфер}}", .capitalized, clipboard: "друг", to: "Спасибо, друг"), "capitalized")
    check(expands("спасибо, {{буфер}}", .upper, clipboard: "друг", to: "СПАСИБО, друг"), "upper case leaves variables")
    check(expands("{{буфер}} спасибо", .capitalized, clipboard: "друг", to: "друг спасибо"), "a variable first is not capitalized")
    check(expands("a{{курсор}}b", .upper, to: "AB", caret: 1), "upper case on both sides of the cursor")
    return checks
}
