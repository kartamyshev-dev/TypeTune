import Foundation
import LayoutPilotCore

/// Calls the production projection and Engine. This file does not post or replay events.
func replayProjectionChecks() -> [(Bool, String)] {
    var results: [(Bool, String)] = []
    func check(_ value: Bool, _ label: String) { results.append((value, "replay projection: " + label)) }
    func evaluate(_ token: String) -> Decision? { Engine().decide(token) }
    func finish(_ projection: ReplayInsertionProjection) -> ReplayInsertionProjection.CorrectionBatch? {
        projection.finish(observedText: projection.expectedText, selection: projection.expectedSelection,
                          ownsAnchor: true, decide: evaluate)
    }

    var words = ReplayInsertionProjection(anchorText: "start ", selection: NSRange(location: 6, length: 0))!
    words.consume(.insertion("ghbdtn руддщ unfinished"))
    let batch = finish(words)
    check(words.expectedText == "start ghbdtn руддщ unfinished", "tracks every replayed character including unfinished tail")
    check(words.completedTokenRanges == [NSRange(location: 6, length: 6), NSRange(location: 13, length: 5)], "only fully inserted completed words are eligible")
    check(batch?.edit.expectedText == "start привет hello unfinished", "multiple queued words corrected together; unfinished word untouched")
    check(batch?.decision.original == "ghbdtn руддщ" && batch?.decision.replacement == "привет hello", "aggregate contains only minimal changed span")
    check(batch?.tokens.count == 2 && batch?.undoLearning == ReplayInsertionProjection.UndoLearningPolicy.none, "aggregate has word metadata and cannot learn a sentence")
    check(batch?.decision.targetLanguage == nil, "unfinished tail prevents a midword input-source change")
    check(batch?.edit.resultingSelection(from: words.expectedSelection) == NSRange(location: 29, length: 0), "aggregate preserves caret after trailing unfinished word")

    var chunks = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    chunks.consume(.insertion("ghb")); chunks.consume(.keyUp); chunks.consume(.insertion("dtn "))
    chunks.consume(.modifierRelease); chunks.consume(.insertion("руддщ "))
    check(finish(chunks)?.edit.expectedText == "привет hello ", "projection spans replay batches and ignores releases")
    check(finish(chunks)?.decision.targetLanguage == .english, "last completed changed word determines target language")
    let countBefore = chunks.completedTokenRanges.count, textBefore = chunks.expectedText, caretBefore = chunks.expectedSelection
    chunks.consume(.keyUp); chunks.consume(.modifierRelease)
    check(chunks.completedTokenRanges.count == countBefore && chunks.expectedText == textBefore && chunks.expectedSelection == caretBefore, "keyup/modifier release do not insert or create tokens")

    var unchangedLast = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    unchangedLast.consume(.insertion("ghbdtn unknown "))
    check(finish(unchangedLast)?.edit.expectedText == "привет unknown ", "unchanged last token is preserved")
    check(finish(unchangedLast)?.decision.targetLanguage == nil, "unchanged final token does not inherit an earlier language correction")

    var incomplete = ReplayInsertionProjection(anchorText: "😀 e\u{0301} ", selection: NSRange(location: 6, length: 0))!
    incomplete.consume(.insertion("ghb"))
    check(incomplete.completedTokenRanges.isEmpty && finish(incomplete) == nil, "unfinished insertion needs exact cache publication without edits")
    check(incomplete.matchesObserved(text: "😀 e\u{0301} ghb", selection: NSRange(location: 9, length: 0), ownsAnchor: true), "NFD/emoji anchor and exact incomplete-text readback")
    check(!incomplete.matchesObserved(text: "😀 é ghb", selection: NSRange(location: 8, length: 0), ownsAnchor: true), "canonically equivalent normalization is not exact UTF16 readback")

    var middle = ReplayInsertionProjection(anchorText: "😀 e\u{0301} suffix", selection: NSRange(location: 6, length: 0))!
    middle.consume(.insertion("ghbdtn "))
    check(finish(middle)?.edit.expectedText == "😀 e\u{0301} привет suffix", "middle-document insertion leaves seeded Unicode prefix and suffix unchanged")
    check(finish(middle)?.edit.resultingSelection(from: middle.expectedSelection) == NSRange(location: 13, length: 0), "middle-document caret remains before existing suffix")
    var continuation = ReplayInsertionProjection(anchorText: "prefix tail", selection: NSRange(location: 3, length: 0))!
    continuation.consume(.insertion("ghbdtn ghbdtn "))
    check(continuation.completedTokenRanges == [NSRange(location: 10, length: 6)], "first token continuing pre-existing prefix is never eligible")
    check(finish(continuation)?.edit.expectedText == "preghbdtn привет fix tail", "correction never reaches pre-existing or partial first token")
    var leadingSpace = ReplayInsertionProjection(anchorText: "ghbdtn", selection: NSRange(location: 6, length: 0))!
    leadingSpace.consume(.insertion(" ghbdtn "))
    check(finish(leadingSpace)?.edit.expectedText == "ghbdtn привет ", "pre-existing word completed by replayed Space remains untouched")

    var punct = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    punct.consume(.insertion("ABc.txt ./GHbdtn --FOo user@example.test ghbdtn, "))
    let punctBatch = punct.finish(observedText: punct.expectedText, selection: punct.expectedSelection, ownsAnchor: true) { token in
        // An authored full-token callback fixture, not a duplicate punctuation heuristic.
        if token == "ghbdtn," { return Decision(original: token, replacement: "привет,", reason: .layout, targetLanguage: .russian) }
        return evaluate(token)
    }
    check(punctBatch?.edit.expectedText == "ABc.txt ./GHbdtn --FOo user@example.test привет, ", "filenames/code/email preserved; wrapped punctuation decision keeps its suffix")
    let invalidPrefixDecision = punct.finish(observedText: punct.expectedText, selection: punct.expectedSelection, ownsAnchor: true) { token in
        token == "ghbdtn," ? Decision(original: "ghbdtn", replacement: "привет", reason: .layout) : nil
    }
    check(invalidPrefixDecision == nil, "reject prefix-only callback that would lose punctuation")

    var rules = Settings(); rules.rules = [.init(source: "fixture", replacement: "приветик"), .init(source: "second", replacement: "да")]
    var varying = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    varying.consume(.insertion("fixture middle second tail"))
    let varied = varying.finish(observedText: varying.expectedText, selection: varying.expectedSelection, ownsAnchor: true) { Engine(settings: rules).decide($0) }
    check(varied?.edit.expectedText == "приветик middle да tail", "reverse replacements handle unequal lengths and untouched intervening word")
    check(varied?.edit.resultingSelection(from: varying.expectedSelection).location == "приветик middle да tail".utf16.count, "caret follows aggregate UTF16 delta rather than end of changed range")
    if let varied {
        let replacementRange = NSRange(location: varied.edit.range.location, length: varied.decision.replacement.utf16.count)
        let undone = TextEdit(text: varied.edit.expectedText, selection: replacementRange, replacement: varied.decision.original)
        check(undone?.expectedText == varying.expectedText && varied.undoLearning == .none, "aggregate undo restores original span without learning its words/sentence")
    } else { check(false, "aggregate undo precondition") }

    var payload = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    payload.consume(.insertion("fixture "))
    for replacement in ["", "bad\ntext", "bad\ttext", "bad\u{0000}text", String(repeating: "x", count: 4097)] {
        let rejected = payload.finish(observedText: payload.expectedText, selection: payload.expectedSelection, ownsAnchor: true) {
            Decision(original: $0, replacement: replacement, reason: .userRule)
        }
        check(rejected == nil, "invalid empty/control/oversize callback payload cannot create an aggregate")
    }
    var aggregateBound = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0))!
    aggregateBound.consume(.insertion("one two "))
    check(aggregateBound.finish(observedText: aggregateBound.expectedText, selection: aggregateBound.expectedSelection, ownsAnchor: true) {
        Decision(original: $0, replacement: String(repeating: "x", count: 3000), reason: .userRule)
    } == nil, "combined payload bound applies even when each replacement is under 4096")
    var fullBound = ReplayInsertionProjection(anchorText: String(repeating: " ", count: 65_536), selection: NSRange(location: 65_536, length: 0))!
    fullBound.consume(.insertion("x"))
    check(fullBound.invalidationReason == .capacityExceeded, "projection never exceeds the runtime full-text UTF16 bound")
    let largeSeed = String(repeating: " ", count: 65_526)
    var resultBound = ReplayInsertionProjection(anchorText: largeSeed, selection: NSRange(location: 65_526, length: 0))!
    resultBound.consume(.insertion("fixture "))
    check(resultBound.finish(observedText: resultBound.expectedText, selection: resultBound.expectedSelection, ownsAnchor: true) {
        Decision(original: $0, replacement: "replacement-longer-than-budget", reason: .userRule)
    } == nil, "aggregate result cannot overflow the runtime full-text UTF16 bound")

    var calls = 0
    check(words.finish(observedText: words.expectedText, selection: words.expectedSelection, ownsAnchor: false, decide: { calls += 1; return evaluate($0) }) == nil && calls == 0, "focus/source/epoch ownership failure prevents callbacks and edits")
    check(words.finish(observedText: words.expectedText + "x", selection: words.expectedSelection, ownsAnchor: true, decide: { calls += 1; return evaluate($0) }) == nil && calls == 0, "unexpected text prevents callbacks and edits")
    check(words.finish(observedText: words.expectedText, selection: NSRange(location: 0, length: 0), ownsAnchor: true, decide: { calls += 1; return evaluate($0) }) == nil && calls == 0, "unexpected caret prevents callbacks and edits")
    check(!words.matchesObserved(text: "start ghbdtn", selection: NSRange(location: 12, length: 0), ownsAnchor: true), "lagging AX cannot publish a partial replay cache")

    for reason in [ReplayInsertionProjection.InvalidationReason.unsupportedEvent, .focusChanged, .sourceChanged] {
        var invalid = words; invalid.invalidate(reason: reason)
        check(!invalid.isValid && finish(invalid) == nil && !invalid.matchesObserved(text: invalid.expectedText, selection: invalid.expectedSelection, ownsAnchor: true), "explicit navigation/command/focus/source invalidation blocks edits/cache: \(reason)")
    }
    for unsupported in ["", "\n", "\t", "😀", "e\u{0301}", "漢"] {
        var invalid = words; invalid.consume(.insertion(unsupported))
        check(invalid.invalidationReason == .unsupportedInsertion && finish(invalid) == nil, "unsupported insertion/composition never guessed: \(unsupported.debugDescription)")
    }
    var bounded = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0), maxInsertedUTF16: 3)!
    bounded.consume(.insertion("abcd"))
    check(bounded.invalidationReason == .capacityExceeded && finish(bounded) == nil, "inserted-text memory bound invalidates only the projection")
    var boundedTokens = ReplayInsertionProjection(anchorText: "", selection: NSRange(location: 0, length: 0), maxCompletedTokens: 1)!
    boundedTokens.consume(.insertion("one two "))
    check(boundedTokens.invalidationReason == .capacityExceeded && finish(boundedTokens) == nil, "token budget exhaustion never produces a partial correction")
    check(ReplayInsertionProjection(anchorText: "😀", selection: NSRange(location: 1, length: 0)) == nil, "reject anchor inside surrogate pair")
    check(ReplayInsertionProjection(anchorText: "e\u{0301}", selection: NSRange(location: 1, length: 0)) == nil, "reject anchor inside grapheme")
    check(ReplayInsertionProjection(anchorText: "abc", selection: NSRange(location: 0, length: 1)) == nil, "selection replacement is not an ordinary insertion anchor")
    return results
}
