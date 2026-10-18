import Foundation
import LayoutPilotCore

func snippetEditPlanChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "snippet edit plan: " + name)) }
    let app = "com.apple.TextEdit"
    let now = Date(timeIntervalSince1970: 1_792_314_300), utc = TimeZone(identifier: "UTC")!
    func buffer(_ text: String) -> TypedWordBuffer {
        var value = TypedWordBuffer(); value.reset(.newline)
        for character in text { value.insert(String(character)) }
        return value
    }
    /// Types `text`, matches (boundary when it ends with Space), renders and plans.
    func plan(_ text: String, _ snippet: Snippet, clipboard: String? = nil) -> SnippetEditPlan? {
        let typed = buffer(text)
        let match = text.last == " "
            ? SnippetMatcher.boundary(typed, boundary: " ", snippets: [snippet], application: app)
            : SnippetMatcher.immediate(typed, inserted: String(text.last!), snippets: [snippet], application: app)
        guard let match, case .success(let expansion) = SnippetTemplate.render(
            snippet.text, caseStyle: match.caseStyle, now: now, timeZone: utc, clipboard: clipboard) else { return nil }
        return SnippetEditPlan(match: match, expansion: expansion)
    }
    let thanks = Snippet(abbreviation: "спс", text: "спасибо")
    let address = Snippet(abbreviation: ";адр", text: "г. Москва")

    // Forward edits.
    if let p = plan("ok спс ", thanks) {
        check(p.expectedBefore == "спс " && p.expectedAfter == "спасибо " && p.deleteCount == 2 && p.insertText == "асибо " &&
              p.insertion == .keystrokes && p.moveRight == 0 && p.moveLeft == 0 && !p.restoresTyped,
              "boundary: shared start kept, tail and Space retyped")
    } else { check(false, "boundary: shared start kept, tail and Space retyped") }
    if let p = plan("Адрес: ;адр", address) {
        check(p.expectedBefore == ";адр" && p.expectedAfter == "г. Москва" && p.deleteCount == 4 && p.insertText == "г. Москва",
              "immediate: the abbreviation is replaced, nothing after it")
    } else { check(false, "immediate: the abbreviation is replaced, nothing after it") }
    check(plan("Спс ", thanks)?.expectedAfter == "Спасибо " && plan("Спс ", thanks)?.deleteCount == 2, "capitalized keeps the shared start")
    check(plan("СПС ", thanks)?.expectedAfter == "СПАСИБО ", "upper case")
    check(plan("спс, ", thanks)?.expectedAfter == "спасибо, " && plan("спс, ", thanks)?.expectedBefore == "спс, ",
          "punctuation stays between the expansion and the Space")
    check(plan("cgc? ", thanks)?.expectedAfter == "спасибо, " && plan("cgc? ", thanks)?.deleteCount == 5,
          "the other layout replaces the whole typed token")
    check(plan("$flh", address)?.deleteCount == 4 && plan("$flh", address)?.expectedAfter == "г. Москва", "immediate in the other layout")
    let today = Snippet(abbreviation: ";дт", text: "{{дата}}")
    check(plan(";дт", today)?.insertText == "18.10.2026", "variables are rendered before planning")

    // Cursor.
    let bold = Snippet(abbreviation: ";b", text: "<b>{{курсор}}</b>")
    if let p = plan(";b", bold) {
        check(p.insertText == "<b></b>" && p.moveLeft == 4 && p.expectedAfter == "<b>", "immediate: caret moves back to the cursor")
    } else { check(false, "immediate: caret moves back to the cursor") }
    let tag = Snippet(abbreviation: "тег", text: "<b>{{курсор}}</b>")
    if let p = plan("тег, ", tag) {
        check(p.moveLeft == 6 && p.expectedAfter == "<b>" && p.confirms(textBeforeCaret: "x <b>"),
              "boundary: caret moves back over the closing text, punctuation and Space")
    } else { check(false, "boundary: caret moves back over the closing text, punctuation and Space") }

    let end = Snippet(abbreviation: "кнц", text: "конец{{курсор}}")
    check(plan("кнц, ", end)?.moveLeft == 2 && plan("кнц, ", end)?.expectedAfter == "конец",
          "a cursor at the end of the text stops before the punctuation and Space")
    check(plan("ok спс ", thanks)?.moveLeft == 0, "no cursor: the caret stays after the Space")

    // Insertion method (DECISIONS п. 28).
    let exactly = Snippet(abbreviation: ";л", text: String(repeating: "я", count: 100))
    let longer = Snippet(abbreviation: ";л", text: String(repeating: "я", count: 101))
    check(plan(";л", exactly)?.insertion == .keystrokes, "100 characters are typed")
    check(plan(";л", longer)?.insertion == .paste, "101 characters are pasted")
    check(plan(";п", Snippet(abbreviation: ";п", text: "С уважением,\nВасилий"))?.insertion == .paste, "a line break is pasted, never typed as Return")
    check(plan(";т", Snippet(abbreviation: ";т", text: "a\tb"))?.insertion == .paste, "a tab is pasted")
    check(plan(";б", Snippet(abbreviation: ";б", text: "{{буфер}}"), clipboard: "строка\r\nстрока")?.insertion == .paste,
          "clipboard text with line breaks is pasted")
    check(SnippetEditPlan.insertion(for: "😀😀") == .keystrokes, "short Unicode is typed")
    if let p = plan(";л", longer) {
        check(p.unicodeChunks().flatMap { $0 } == Array(p.insertText.utf16) && p.unicodeChunks().allSatisfy { $0.count <= 16 },
              "chunks concatenate to the insertion")
    } else { check(false, "chunks concatenate to the insertion") }

    // Nothing to change.
    check(plan("abc ", Snippet(abbreviation: "abc", text: "abc")) == nil, "same text: no edit")
    let empty = SnippetTemplate.Expansion(text: "", caretOffset: nil)
    if let match = SnippetMatcher.boundary(buffer("спс "), boundary: " ", snippets: [thanks], application: app) {
        check(SnippetEditPlan(match: match, expansion: empty) == nil, "empty expansion: no edit")
    } else { check(false, "empty expansion: no edit") }

    // Field verification.
    if let p = plan("ok спс ", thanks) {
        check(p.expects(textBeforeCaret: "Привет, спс "), "the field ends with the typed abbreviation")
        check(!p.expects(textBeforeCaret: "Привет, спа "), "a changed field is refused")
        check(p.expects(textBeforeCaret: "спс ", anchored: true) && p.expects(textBeforeCaret: "x спс ", anchored: true),
              "a boundary before the abbreviation")
        check(!p.expects(textBeforeCaret: "xспс ", anchored: true) && p.expects(textBeforeCaret: "xспс "),
              "inside a word only when the buffer already proved the boundary")
        check(p.confirms(textBeforeCaret: "ok спасибо ") && !p.confirms(textBeforeCaret: "ok спс "), "confirmation")
    } else { check(false, "field verification") }

    // Undo.
    if let p = plan("ok спс ", thanks) {
        let undo = p.inverse
        check(undo.expectedBefore == "спасибо " && undo.expectedAfter == "спс " && undo.deleteCount == 6 && undo.insertText == "с " &&
              undo.moveRight == 0 && undo.moveLeft == 0 && undo.restoresTyped && undo.insertion == .keystrokes,
              "undo retypes the abbreviation as typed")
    } else { check(false, "undo retypes the abbreviation as typed") }
    if let p = plan("cgc? ", thanks) {
        check(p.inverse.expectedAfter == "cgc? ", "undo restores the other-layout typing exactly")
    } else { check(false, "undo restores the other-layout typing exactly") }
    if let p = plan(";b", bold) {
        let undo = p.inverse
        check(undo.moveRight == 4 && undo.expectedBefore == "<b>" && undo.deleteCount == 7 && undo.insertText == ";b" &&
              undo.expectedAfter == ";b", "undo first returns the caret to the end of the insertion")
    } else { check(false, "undo first returns the caret to the end of the insertion") }
    if let p = plan(";п", Snippet(abbreviation: ";п", text: "С уважением,\nВасилий")) {
        check(p.inverse.insertion == .keystrokes && p.inverse.deleteCount == 20, "a pasted expansion is undone by typing the abbreviation")
    } else { check(false, "a pasted expansion is undone by typing the abbreviation") }

    // The typed buffer after the edit.
    if let p = plan("ok спс ", thanks) {
        var after = buffer("ok спс "); p.update(&after)
        check(after.text.isEmpty && after.lastReset == .inserted && after.anchoredStart, "inserted text is not typed; a trailing Space anchors")
        for character in "ghbdtn " { after.insert(String(character)) }
        check(after.completedToken?.token == "ghbdtn" && after.tokenIsAnchored(boundaryLength: 1), "the next word may still be corrected")
        var undone = TypedWordBuffer(); p.inverse.update(&undone)
        check(undone.text == "спс " && undone.lastReset == nil, "after undo the abbreviation is known typed text again")
    } else { check(false, "buffer after a boundary edit") }
    if let p = plan(";адр", address) {
        var after = buffer(";адр"); p.update(&after)
        check(!after.anchoredStart, "an insertion ending in a word does not anchor")
        for character in "у " { after.insert(String(character)) }
        check(!after.tokenIsAnchored(boundaryLength: 1), "letters typed onto the inserted word are never corrected blind")
        check(after.lastReset == nil, "typing after the insertion ends its undo window")
    } else { check(false, "buffer after an immediate edit") }
    var reset = buffer("ab"); reset.resetAfterInsertion(endingWith: "")
    check(reset.text.isEmpty && !reset.anchoredStart && reset.lastReset == .inserted, "an empty insertion anchors nothing")
    return checks
}
