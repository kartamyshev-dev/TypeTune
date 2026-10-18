import LayoutPilotCore

func typedWordBufferChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "typed buffer: " + name)) }
    func typed(_ keys: [String], from start: TypedWordBuffer = TypedWordBuffer()) -> TypedWordBuffer {
        var buffer = start
        for key in keys { if key == "⌫" { buffer.backspace() } else { buffer.insert(key) } }
        return buffer
    }

    // Initial state: nothing known before the caret.
    let fresh = TypedWordBuffer()
    check(fresh.text.isEmpty && !fresh.anchoredStart && fresh.lastReset == .explicit, "starts empty and unanchored")
    check(fresh.currentToken.isEmpty && fresh.completedToken == nil, "no token before typing")

    // Typing and completion.
    let word = typed(["g", "h", "b", "d", "t", "n"])
    check(word.text == "ghbdtn" && word.currentToken == "ghbdtn" && word.completedToken == nil, "letters build the current token")
    check(word.lastReset == nil, "typing clears the reset reason")
    let completed = typed([" "], from: word)
    check(completed.completedToken?.token == "ghbdtn" && completed.completedToken?.boundary == " ", "whitespace completes the token")
    check(completed.currentToken.isEmpty, "after the boundary no token is in progress")
    let two = typed(["v", "b", "h", "/", " "], from: completed)
    check(two.completedToken?.token == "vbh/" && two.completedToken?.boundary == " ", "punctuation keys belong to the token")
    check(typed(["a", " ", " "]).completedToken?.boundary == "  ", "a run of whitespace is one boundary")
    check(typed([" "]).completedToken == nil, "whitespace alone completes nothing")

    // Anchoring.
    check(!completed.tokenIsAnchored(boundaryLength: 1), "the first token after a reset is not known to start a word")
    check(two.tokenIsAnchored(boundaryLength: 1), "a token after typed whitespace is anchored")
    var afterReturn = TypedWordBuffer(); afterReturn.reset(.newline)
    afterReturn = typed(["w", "j", "n", " "], from: afterReturn)
    check(afterReturn.anchoredStart && afterReturn.tokenIsAnchored(boundaryLength: 1), "Return leaves the caret after a known boundary")
    var afterTab = TypedWordBuffer(); afterTab.reset(.tab)
    check(afterTab.anchoredStart, "Tab leaves the caret after a known boundary")
    for reason: TypedWordBuffer.ResetReason in [.pointer, .navigation, .shortcut, .focus, .secureInput, .sourceChange, .escape, .untrackedKey, .explicit] {
        var buffer = two; buffer.reset(reason)
        check(buffer.text.isEmpty && !buffer.anchoredStart && buffer.lastReset == reason, "\(reason.rawValue) reset forgets everything")
    }

    // Backspace.
    check(typed(["a", "b", "⌫"]).text == "a", "backspace removes the last typed character")
    check(typed(["a", "b", " ", "⌫"]).currentToken == "ab", "backspace over the boundary reopens the token")
    var underflow = afterReturn
    for _ in 0..<10 { underflow.backspace() }
    check(underflow.text.isEmpty && !underflow.anchoredStart, "deleting past the buffer start loses the anchor")
    check(typed(["e", "\u{301}", "⌫"]).text.isEmpty, "a composed character is one backspace")

    // Untrackable input.
    var control = word; control.insert("\u{7f}")
    check(control.text.isEmpty && control.lastReset == .untrackedKey, "a control character resets")
    var tabChar = word; tabChar.insert("\t")
    check(tabChar.text.isEmpty, "a tab character typed as text is untracked")
    var empty = word; empty.insert("")
    check(empty == word, "empty key output changes nothing")
    check(typed(["п", "р", "и", "в", "е", "т", "!", " "]).completedToken?.token == "привет!", "Cyrillic and punctuation are tracked")

    // Capacity: the retained suffix stays exact; anchoring follows the dropped text.
    var long = TypedWordBuffer()
    for _ in 0..<(TypedWordBuffer.capacity + 10) { long.insert("a") }
    check(long.text.count == TypedWordBuffer.capacity && !long.tokenIsAnchored(), "an overlong word is truncated and never anchored")
    var spaced = TypedWordBuffer()
    for _ in 0..<(TypedWordBuffer.capacity - 1) { spaced.insert("a") }
    spaced.insert(" "); spaced.insert("b"); spaced.insert("c")
    check(spaced.text.count == TypedWordBuffer.capacity && spaced.currentToken == "bc" && spaced.tokenIsAnchored(),
          "truncation keeps the recent token and its boundary")
    var cut = TypedWordBuffer()
    cut.insert(" ")
    for _ in 0..<TypedWordBuffer.capacity { cut.insert("x") }
    check(cut.anchoredStart && cut.tokenIsAnchored(), "a token whose leading space was just dropped is still anchored")

    // Own edits.
    var corrected = typed([" ", "g", "h", "b", "d", "t", "n", " "])
    check(corrected.replaceSuffix("ghbdtn ", with: "привет ") && corrected.text == " привет ", "a correction rewrites the tail")
    check(corrected.completedToken?.token == "привет", "the corrected token is the new completed token")
    var undone = corrected
    check(undone.replaceSuffix("привет ", with: "ghbdtn ") && undone.text == " ghbdtn ", "undo restores the original tail")
    var mismatch = corrected
    check(!mismatch.replaceSuffix("ghbdtn ", with: "x") && mismatch.text.isEmpty && mismatch.lastReset == .untrackedKey,
          "an edit that does not match the buffer resets it")
    var controlEdit = corrected
    check(!controlEdit.replaceSuffix("привет ", with: "a\nb") && controlEdit.text.isEmpty, "an edit with control characters resets")
    return checks
}
