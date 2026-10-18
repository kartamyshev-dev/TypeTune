import Foundation
import LayoutPilotCore

func snippetMatcherChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "snippet matcher: " + name)) }
    let app = "com.apple.TextEdit"
    /// Types `text` key by key, after a Return when `anchored`; returns the buffer
    /// and the last key's characters.
    func typed(_ text: String, anchored: Bool = true) -> (TypedWordBuffer, String) {
        var buffer = TypedWordBuffer()
        if anchored { buffer.reset(.newline) }
        for character in text { buffer.insert(String(character)) }
        return (buffer, text.last.map(String.init) ?? "")
    }
    func now(_ text: String, _ snippets: [Snippet], anchored: Bool = true, application: String = app) -> SnippetMatch? {
        let (buffer, last) = typed(text, anchored: anchored)
        return SnippetMatcher.immediate(buffer, inserted: last, snippets: snippets, application: application)
    }
    func space(_ text: String, _ snippets: [Snippet], boundary: String = " ", anchored: Bool = true) -> SnippetMatch? {
        let (buffer, _) = typed(text, anchored: anchored)
        return SnippetMatcher.boundary(buffer, boundary: boundary, snippets: snippets, application: app)
    }

    // Immediate abbreviation led by a sign.
    let address = Snippet(abbreviation: ";адр", text: "г. Москва")
    check(address.trigger == .immediate, "fixture: ;адр is immediate")
    let hit = now("Адрес: ;адр", [address])
    check(hit?.typed == ";адр" && hit?.suffix == "" && hit?.boundary == "" && hit?.anchored == true &&
          hit?.caseStyle == .asWritten, "fires when its last character is typed")
    check(now("Адрес: ;ад", [address]) == nil, "not before the abbreviation is complete")
    check(now("$flh", [address])?.typed == "$flh", "the same keys in the English layout")
    check(now("$flh", [Snippet(abbreviation: ";адр", text: "x", otherLayout: false)]) == nil, "no other layout when turned off")
    check(now("x;адр", [address])?.anchored == true, "a sign-led abbreviation may follow a letter")
    check(now(";адр", [address], anchored: false)?.anchored == true, "a sign-led abbreviation needs no known start")
    check(now(";АДР", [address])?.caseStyle == .upper, "upper case typed")
    check(now(";Адр", [address])?.caseStyle == .capitalized, "capitalized typed")
    check(now(";аДр", [address])?.caseStyle == .asWritten, "mixed case leaves the text as written")
    check(now(";Адр", [Snippet(abbreviation: ";адр", text: "x", matchCase: false)])?.caseStyle == .asWritten,
          "case is not carried when turned off")
    check(now(";адр", [Snippet(abbreviation: ";адр", text: "x", enabled: false)]) == nil, "disabled")
    let mailOnly = Snippet(abbreviation: ";адр", text: "x", applications: ApplicationFilter(mode: .only, applications: ["com.apple.mail"]))
    check(now(";адр", [mailOnly]) == nil && now(";адр", [mailOnly], application: "com.apple.mail") != nil, "application filter")
    let (afterBackspace, _) = typed(";адрx")
    var back = afterBackspace; back.backspace()
    check(SnippetMatcher.immediate(back, inserted: "", snippets: [address], application: app) == nil, "Backspace never fires")
    check(SnippetMatcher.immediate(back, inserted: "x", snippets: [address], application: app) == nil,
          "the inserted characters must end the buffer")
    let short = Snippet(abbreviation: "!!", text: "short"), long = Snippet(abbreviation: ";!!", text: "long")
    check(now("a ;!!", [short, long])?.snippet == long && now("a ;!!", [long, short])?.snippet == long, "the longest abbreviation wins")
    check(now("a !!", [short, long])?.snippet == short, "the shorter one fires alone")
    let first = Snippet(abbreviation: ";x", text: "1"), second = Snippet(abbreviation: ";x", text: "2", otherLayout: false)
    check(now(";x", [first, second])?.snippet == first, "equal length keeps library order")

    // Immediate abbreviation that looks like a word (chosen by the user).
    let word = Snippet(abbreviation: "спс", text: "спасибо", trigger: .immediate)
    check(now("ok спс", [word])?.anchored == true, "after whitespace")
    check(now("аспс", [word]) == nil, "never inside a word")
    check(now("спс", [word], anchored: false)?.anchored == false, "after a reset the start is unknown")
    check(now("спс", [word], anchored: true)?.anchored == true, "after Return the start is known")
    check(space("спс", [word]) == nil, "an immediate snippet ignores the boundary path")

    // Boundary abbreviation (word-like, and every migrated rule).
    let thanks = Snippet(abbreviation: "спс", text: "спасибо")
    check(thanks.trigger == .boundary, "fixture: спс waits for the boundary")
    check(now("спс", [thanks]) == nil, "a boundary snippet ignores the immediate path")
    let plain = space("ok спс ", [thanks])
    check(plain?.typed == "спс" && plain?.suffix == "" && plain?.boundary == " " && plain?.anchored == true,
          "Space completes the abbreviation")
    check(space("спс ", [thanks], anchored: false)?.anchored == false, "first token after a reset is not anchored")
    check(space("Спс ", [thanks])?.caseStyle == .capitalized && space("СПС ", [thanks])?.caseStyle == .upper,
          "case of the typed abbreviation")
    check(space("API ", [Snippet(abbreviation: "API", text: "интерфейс")])?.caseStyle == .asWritten,
          "an abbreviation typed exactly as defined keeps the text as written")
    let comma = space("спс, ", [thanks])
    check(comma?.typed == "спс," && comma?.suffix == ",", "sentence punctuation stays after the expansion")
    check(space("спс!? ", [thanks])?.suffix == "!?", "several punctuation marks")
    let english = space("cgc ", [thanks])
    check(english?.typed == "cgc" && english?.suffix == "", "the same keys in the English layout")
    let wrongComma = space("cgc? ", [thanks])
    check(wrongComma?.typed == "cgc?" && wrongComma?.suffix == ",", "punctuation typed in the other layout is converted")
    let latinComma = space("cgc, ", [thanks])
    check(latinComma?.typed == "cgc," && latinComma?.suffix == ",", "a comma typed in the English layout stays a comma")
    check(space("cgc ", [Snippet(migrating: UserRule(source: "спс", replacement: "спасибо"))]) == nil,
          "a migrated rule does not match the other layout")
    check(space("адрес ", [Snippet(abbreviation: "адр", text: "x")]) == nil, "a longer word is not the abbreviation")
    check(space("спсб ", [thanks]) == nil, "a converted punctuation key is not punctuation")
    check(space("(спс ", [thanks]) == nil, "an opening bracket is part of the token")
    check(space(", ", [Snippet(abbreviation: ",,", text: "x")]) == nil, "punctuation alone is not an abbreviation")
    check(space("спс  ", [thanks]) == nil, "a second Space does not fire again")
    check(space("спс ", [thanks], boundary: "\t") == nil, "only the whitespace typed now completes the token")
    let (twoSpaces, _) = typed("спс  ")
    check(SnippetMatcher.boundary(twoSpaces, boundary: "  ", snippets: [thanks], application: app) != nil,
          "the boundary is the whole whitespace run typed now")

    // Case style rules.
    check(SnippetMatcher.caseStyle(";А", address) == .capitalized, "one capital letter is capitalized, not upper")
    check(SnippetMatcher.caseStyle(";;;", Snippet(abbreviation: ";;", text: "x")) == .asWritten, "no letters, no case")
    return checks
}
