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
    return checks
}
