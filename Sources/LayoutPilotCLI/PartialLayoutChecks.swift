import Foundation
import LayoutPilotCore

/// Independent authored expectations; no original model data or holdout tuning.
func partialLayoutChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ value: Bool, _ label: String) { checks.append((value, "partial layout: " + label)) }
    let engine = Engine()
    check(engine.decidePartial("ghb") == Decision(original: "ghb", replacement: "при", reason: .layout, targetLanguage: .russian), "three wrong-layout keys have a known Russian prefix")
    check(engine.decidePartial("ghbd")?.replacement == "прив", "four-key Russian prefix does not need a complete word")
    check(engine.decidePartial("Ghb")?.replacement == "При", "first capital is preserved without case correction")
    for token in ["hello", "help", "при", "привет", "ABc", "MHz", "GHb", "ABC", "https://ghb", "/ghb", "./ghb", "ghb.txt", "ghb()", "ghb=", "ghb123", "123ghb", "ghб", "ghb ", " ghb", "ghb\n", "gh", "g", "", "ghb,", "[ghb", "ghb;", "😀ghb", "e\u{301}ghb", "漢ghb", String(repeating: "g", count: 65)] {
        check(engine.decidePartial(token) == nil, "known source/case/context-token guard: " + token.debugDescription)
    }
    check(engine.decidePartial("ghbdtn")?.reason == .layout, "completed unknown source is still only a layout proposal")
    var settings = Settings(); settings.automatic = false
    check(Engine(settings: settings).decidePartial("ghb") == nil, "global automatic-off blocks partial proposal")
    settings.appAutomatic["test"] = true
    check(Engine(settings: settings).decidePartial("ghb") == nil, "per-app enable cannot override global pause")
    settings.automatic = true; settings.appAutomatic["test"] = false
    check(Engine(settings: settings).decidePartial("ghb") == nil, "per-app automatic-off blocks proposal")
    settings = Settings(); settings.excludedApps = ["test"]
    check(Engine(settings: settings).decidePartial("ghb") == nil, "excluded application blocks proposal")
    for context in [InputContext(secure: true), InputContext(reliable: false)] {
        check(engine.decidePartial("ghb", context: context) == nil, "unsafe or unreliable context cannot propose layout change")
    }
    for protectedWord in ["ghb", "GHBDTN", "Привет"] {
        settings = Settings(); settings.excludedWords = [protectedWord]
        check(Engine(settings: settings).decidePartial("ghb") == nil, "exclusion protects source/target before word completion: " + protectedWord)
        settings = Settings(); settings.learnedWords = [protectedWord]
        check(Engine(settings: settings).decidePartial("ghb") == nil, "learned veto protects source/target prefixes: " + protectedWord)
    }
    settings = Settings(); settings.rules = [UserRule(source: "ghbdtn", replacement: "custom")]
    check(Engine(settings: settings).decidePartial("ghb") == nil, "partial correction cannot preempt an unfinished literal rule")
    settings = Settings(); settings.typos = false; settings.yo = false
    check(Engine(settings: settings).decidePartial("ghb")?.replacement == "при", "layout proposal is independent of typo and yo toggles")
    check(Engine(settings: settings).decidePartial("ПРивет") == nil, "partial path never fixes double capitals")
    check(engine.decidePartial("руддщ")?.replacement == "hello", "wrong Russian layout converts to an English known prefix")

    var lexical = Lexicon.bundled
    lexical.english = ["hello"]; lexical.russian = ["привет"]
    lexical.typos = ["ghb": "hello"]; lexical.yo = ["ghb": "привёт"]
    let beforeMutation = PartialLayoutDetector(lexicon: lexical)
    check(Engine(lexicon: lexical).decidePartial("ghb", detector: beforeMutation)?.replacement == "при", "custom detector uses only literal vocabulary, never typo/yo maps")
    lexical.english.insert("ghbloom")
    let ambiguous = PartialLayoutDetector(lexicon: lexical)
    check(Engine(lexicon: lexical).decidePartial("ghb", detector: ambiguous) == nil, "known source prefix vetoes candidate even when source is not a complete word")
    check(Engine(lexicon: lexical).decidePartial("ghb", detector: beforeMutation)?.replacement == "при", "detector remains an immutable snapshot after lexicon mutation")
    lexical.english = ["ghb"]
    check(Engine(lexicon: lexical).decidePartial("ghb", detector: PartialLayoutDetector(lexicon: lexical)) == nil, "complete known source word vetoes partial conversion")
    lexical.english = ["hello"]; lexical.russian = ["прибор"]
    let separate = PartialLayoutDetector(lexicon: lexical)
    check(Engine(lexicon: lexical).decidePartial("ghbd", detector: separate) == nil, "candidate absent from custom prefixes cannot borrow bundled vocabulary")
    check(Engine(lexicon: lexical).decidePartial("ghb", detector: separate)?.replacement == "при", "custom known prefix does not require the queried prefix to be a full word")
    let emojiPrefix = "😀 ghb"
    let emojiProposal = engine.partialProposal(in: emojiPrefix, selection: NSRange(location: 6, length: 0))
    check(emojiProposal?.range == NSRange(location: 3, length: 3) && emojiProposal?.decision.replacement == "при", "proposal range uses UTF16 after emoji prefix")
    let nfdPrefix = "e\u{301} ghb"
    let nfdProposal = engine.partialProposal(in: nfdPrefix, selection: NSRange(location: 6, length: 0))
    check(nfdProposal?.range == NSRange(location: 3, length: 3) && nfdProposal?.decision.original == "ghb", "unrelated NFD prefix is preserved outside proposed range")
    for suffix in [" suffix", "\nsuffix", "\tsuffix"] {
        check(engine.partialProposal(in: "ghb" + suffix, selection: NSRange(location: 3, length: 0))?.decision.replacement == "при", "whitespace-delimited untouched suffix permits end-of-token proposal")
    }
    let newLine = "first\n ghb"
    check(engine.partialProposal(in: newLine, selection: NSRange(location: 10, length: 0))?.range == NSRange(location: 7, length: 3), "new line starts a separate current token")
    for (text, range) in [
        ("ghbd", NSRange(location: 3, length: 0)),
        ("ghb.txt", NSRange(location: 3, length: 0)),
        ("ghb ", NSRange(location: 4, length: 0)),
        ("ghb\n", NSRange(location: 4, length: 0)),
        ("ghb", NSRange(location: 0, length: 3)),
        ("ghb", NSRange(location: -1, length: 0)),
        ("ghb", NSRange(location: 4, length: 0)),
        ("ghb", NSRange(location: 3, length: -1)),
        ("😀 ghb", NSRange(location: 1, length: 0)),
        ("e\u{301} ghb", NSRange(location: 1, length: 0)),
        ("", NSRange(location: 0, length: 0)),
        (" ghb", NSRange(location: 1, length: 0)),
        (String(repeating: " ", count: 65534) + "ghb", NSRange(location: 65537, length: 0))
    ] {
        check(engine.partialProposal(in: text, selection: range) == nil, "proposal rejects midword, selection, invalid caret or missing token")
    }
    check(engine.partialProposal(in: "ghb", selection: NSRange(location: 3, length: 0), context: InputContext(secure: true)) == nil, "range API retains secure context veto")
    check(Engine(settings: settings).partialProposal(in: "hello", selection: NSRange(location: 5, length: 0)) == nil, "range API does not rewrite a known correct source word")
    return checks
}
