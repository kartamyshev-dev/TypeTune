import LayoutPilotCore

func shortWordContextChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "short words: " + name)) }
    let engine = Engine()
    func prefix(_ before: String, _ target: Language, anchored: Bool = true, engine: Engine = Engine()) -> [String]? {
        engine.shortWordPrefix(before: before, anchoredStart: anchored, target: target).map { [$0.typed, $0.replacement] }
    }
    check(prefix("yf ", .russian) == ["yf ", "на "], "one short word before the converted word")
    check(prefix("ok z yt ", .russian) == ["z yt ", "я не "], "two short words, one letter included")
    check(prefix("b z yt ", .russian) == ["z yt ", "я не "], "at most two short words")
    check(prefix("Z ", .russian) == ["Z ", "Я "], "case is kept")
    check(prefix("yf  ", .russian) == ["yf  ", "на  "], "the whitespace run is kept")
    check(prefix("шы ", .english) == ["шы ", "is "], "Russian layout to English")
    check(prefix("ф ", .english) == ["ф ", "a "], "one-letter English word")
    check(prefix("ne ", .russian) == nil, "a word valid as typed (ne) is never converted")
    check(prefix("на ", .russian) == nil, "already in the target layout")
    check(prefix("yf, ", .russian) == nil, "punctuation stops the context")
    check(prefix("yf", .russian) == nil, "no whitespace before the token")
    check(prefix("xyf ", .russian) == nil, "three letters are not a short word")
    check(prefix("yf ", .russian, anchored: false) == nil, "a word at the start of an unanchored buffer is not whole")
    check(prefix("ok yf ", .russian, anchored: false) == ["yf ", "на "], "a word after typed whitespace is whole")
    check(prefix("qq ", .russian) == nil, "no known word in the other layout")
    var excluding = Settings(); excluding.excludedWords = ["yf"]
    check(prefix("yf ", .russian, engine: Engine(settings: excluding)) == nil, "an excluded word stays")
    check(engine.shortWordConversion("ns", to: .russian) == "ты", "conversion of a single short word")

    // A short word alone, at its own boundary (DECISIONS п. 35).
    let alone = Engine()
    for (typed, expected) in [("d", "в"), ("z", "я"), ("f", "а"), ("yf", "на"), ("ns", "ты"), ("D", "В"), ("Yf", "На"),
                              ("ш", "i"), ("ф", "a"), ("шы", "is")] {
        check(alone.decide(typed)?.replacement == expected && alone.decide(typed)?.reason == .layout,
              "converted at once: \(typed) → \(expected)")
    }
    for typed in ["a", "i", "is", "на", "в", "я", "ку", "ne", "re", "ex", "qq", "zq", "ab/", "x", "1", "d1"] {
        check(alone.decide(typed) == nil, "short word stays: \(typed)")
    }
    for typed in ["РФ", "TV", "RU", "CD", "AB", "T.", "V.", "T,"] {
        check(alone.decide(typed) == nil, "abbreviation or sign stays: \(typed)")
    }
    check(alone.completedTokenDecision("ab/", decide: { alone.decide($0) }) == nil, "a short start with a sign is a path, not a word")
    check(alone.completedTokenDecision("d,", decide: { alone.decide($0) }) == nil, "a short word with a sign is left alone")
    check(Engine(settings: { var s = Settings(); s.automatic = false; return s }()).decide("d") == nil, "layout correction off: no short words")
    check(Engine(settings: { var s = Settings(); s.paused = true; return s }()).decide("d") == nil, "paused: no short words")
    check(alone.decide("d", context: InputContext(secure: true)) == nil, "secure input: no short words")
    check(alone.decide("d", context: InputContext(reliable: false)) == nil, "unreliable context: no short words")
    check(Engine(settings: { var s = Settings(); s.excludedWords = ["d"]; return s }()).decide("d") == nil, "excluded word stays")
    check(Engine(settings: { var s = Settings(); s.learnedWords = ["yf"]; return s }()).decide("yf") == nil, "learned (undone) word stays")
    check(Engine(settings: { var s = Settings(); s.rules = [UserRule(source: "d", replacement: "дэ")]; return s }()).decide("d")?.replacement == "дэ",
          "a user rule wins over the short-word conversion")
    return checks
}
