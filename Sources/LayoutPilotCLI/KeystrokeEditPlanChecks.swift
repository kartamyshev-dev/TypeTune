import LayoutPilotCore

func keystrokeEditPlanChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "keystroke edit: " + name)) }
    let engine = Engine()
    func automatic(_ token: String) -> Decision? { engine.completedTokenDecision(token, decide: { engine.decide($0) }) }
    func buffer(_ text: String) -> TypedWordBuffer { var b = TypedWordBuffer(); for c in text { b.insert(String(c)) }; return b }

    // Whole-token layout correction.
    guard let hello = buffer("ghbdtn ").completedTokenEdit(automatic) else { check(false, "ghbdtn plan"); return checks }
    check(hello.before == "ghbdtn " && hello.after == "привет " && hello.deleteCount == 7 && hello.insertText == "привет ",
          "layout correction retypes the token and the boundary")
    check(hello.decision.targetLanguage == .russian, "the plan carries the target layout")

    // Converted physical punctuation (whole token is original).
    if let period = buffer("ghbdtn/ ").completedTokenEdit(automatic) {
        check(period.after == "привет. " && period.deleteCount == 8 && period.decision.learnAs == "ghbdtn",
              "converted punctuation is part of the retyped tail; undo learns the word")
    } else { check(false, "ghbdtn/ plan") }

    // Literal punctuation: decision covers a prefix, the suffix is kept as typed.
    if let literal = buffer("ghbdtn, ").completedTokenEdit(automatic) {
        check(literal.decision.original == "ghbdtn" && literal.after == "привет, " && literal.deleteCount == 8,
              "literal punctuation after a prefix decision is retyped unchanged")
    } else { check(false, "ghbdtn, plan") }

    // Case-only correction keeps the shared first character.
    if let caps = buffer("ПРивет ").completedTokenEdit(automatic) {
        check(caps.after == "Привет " && caps.deleteCount == 6 && caps.insertText == "ривет ",
              "a shared prefix is not deleted")
    } else { check(false, "ПРивет plan") }

    // Nothing to do.
    check(buffer("привет ").completedTokenEdit(automatic) == nil, "a correct word needs no edit")
    check(buffer("ghbdtn").completedTokenEdit(automatic) == nil, "no edit before the boundary")
    check(KeystrokeEditPlan(token: "abc", boundary: " ", decision: Decision(original: "abc", replacement: "abc", reason: .typo)) == nil,
          "an identical replacement is no edit")
    check(KeystrokeEditPlan(token: "abc", boundary: " ", decision: Decision(original: "xyz", replacement: "q", reason: .typo)) == nil,
          "a decision for another token is rejected")
    check(KeystrokeEditPlan(token: "abc", boundary: "x", decision: Decision(original: "abc", replacement: "d", reason: .typo)) == nil,
          "a non-whitespace boundary is rejected")
    check(KeystrokeEditPlan(token: "abc", boundary: " ", decision: Decision(original: "abc", replacement: "a\nb", reason: .typo)) == nil,
          "control characters are never typed")
    check(KeystrokeEditPlan(token: "abc", boundary: " ", decision: Decision(original: "abc", replacement: "", reason: .typo)) == nil,
          "an empty replacement is rejected")

    // Manual conversion at the caret or after the boundary.
    let atCaret = buffer("руддщ").manualTarget
    check(atCaret?.token == "руддщ" && atCaret?.boundary == "", "manual target is the token at the caret")
    if let target = atCaret, let decision = engine.manual(target.token),
       let plan = KeystrokeEditPlan(token: target.token, boundary: target.boundary, decision: decision) {
        check(plan.after == "hello" && plan.deleteCount == 5, "manual conversion without a boundary")
    } else { check(false, "manual plan at caret") }
    let afterSpace = buffer("руддщ ").manualTarget
    check(afterSpace?.token == "руддщ" && afterSpace?.boundary == " ", "after the boundary manual targets the completed token")
    check(buffer("").manualTarget == nil && buffer("  ").manualTarget == nil, "nothing to convert manually")

    // Undo.
    let undo = hello.inverse
    check(undo.before == "привет " && undo.after == "ghbdtn " && undo.deleteCount == 7 && undo.insertText == "ghbdtn ",
          "undo retypes the original token and boundary")
    check(undo.decision.original == "привет" && undo.decision.replacement == "ghbdtn", "undo decision is reversed")
    check(undo.inverse.before == hello.before && undo.inverse.after == hello.after, "inverse of the undo is the edit")

    // Verification against observed text.
    check(hello.expects(textBeforeCaret: "Скажи ghbdtn "), "observed text ending with the token matches")
    check(!hello.expects(textBeforeCaret: "Скажи ghbdtn  "), "an extra character (autocorrect, suggestion) does not match")
    check(!hello.expects(textBeforeCaret: "Скажи Ghbdtn "), "a changed token does not match")
    check(hello.expects(textBeforeCaret: "ghbdtn ", anchored: true), "the start of the field is a boundary")
    check(hello.expects(textBeforeCaret: "a ghbdtn ", anchored: true), "whitespace before the token anchors it")
    check(!hello.expects(textBeforeCaret: "xghbdtn ", anchored: true), "a token inside a longer word is not anchored")
    check(hello.expects(textBeforeCaret: "xghbdtn "), "without anchoring only the typed suffix is compared")
    check(hello.applied(to: "Скажи ghbdtn ") == "Скажи привет ", "the expected result after the edit")
    check(hello.applied(to: "nope") == nil, "no expected result for a mismatching field")

    // Selection conversion types over the selection.
    if let decision = engine.manual("Ghbdtn vbh"),
       let selection = KeystrokeEditPlan(replacingSelection: "Ghbdtn vbh", decision: decision) {
        check(selection.deleteCount == 0 && selection.insertText == "Привет мир" && selection.selection == "Ghbdtn vbh",
              "a selection is replaced by typing, without Backspace")
        check(selection.expects(textBeforeCaret: "anything"), "selection edits do not depend on text before the caret")
        let back = selection.inverse
        check(back.before == "Привет мир" && back.after == "Ghbdtn vbh" && back.deleteCount == 10 && back.insertText == "Ghbdtn vbh",
              "undo of a selection deletes the typed text and retypes the selection")
        check(back.selection == nil, "the undo is an ordinary tail edit")
    } else { check(false, "selection plan") }
    check(KeystrokeEditPlan(replacingSelection: "a\nb", decision: Decision(original: "a\nb", replacement: "ф\nи", reason: .manual)) == nil,
          "multi-line selections are not typed")
    check(KeystrokeEditPlan(replacingSelection: "", decision: Decision(original: "", replacement: "x", reason: .manual)) == nil,
          "an empty selection is nothing to convert")
    check(KeystrokeEditPlan(replacingSelection: "abc", decision: Decision(original: "abd", replacement: "x", reason: .manual)) == nil,
          "a decision for other text is rejected")

    // Unicode chunks for keyboard events.
    check(hello.unicodeChunks().map { $0.count } == [7] && String(utf16CodeUnits: hello.unicodeChunks()[0], count: 7) == "привет ",
          "a short insertion is one chunk")
    let long = KeystrokeEditPlan(token: "a", boundary: "", decision: Decision(original: "a", replacement: String(repeating: "б", count: 40), reason: .manual))!
    check(long.unicodeChunks().map { $0.count } == [16, 16, 8], "long insertions are split into 16-unit chunks")
    let emoji = KeystrokeEditPlan(token: "a", boundary: "", decision: Decision(original: "a", replacement: String(repeating: "x", count: 15) + "😀", reason: .manual))!
    check(emoji.unicodeChunks().map { $0.count } == [15, 2], "a surrogate pair is never split across chunks")
    check(long.unicodeChunks().flatMap { $0 } == Array(long.insertText.utf16), "chunks concatenate to the insertion")

    // Buffer and plan stay consistent after the edit.
    var typed = buffer("ghbdtn ")
    check(typed.replaceSuffix(hello.before, with: hello.after) && typed.text == "привет ", "buffer records the applied edit")
    check(typed.replaceSuffix(undo.before, with: undo.after) && typed.text == "ghbdtn ", "buffer records the undo")
    return checks
}
