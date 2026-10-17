import Foundation
import LayoutPilotCore

func physicalPunctuationChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "physical punctuation: " + name)) }
    let mapping = Layout.Mapping.standardPC
    for (latin, cyrillic) in mapping.toRussian {
        check(mapping.toEnglish[cyrillic] == latin, "key pair is reversible: \(latin)")
    }
    check(mapping.toRussian.count == 74 && mapping.toEnglish.count == 74, "standard PC table has 74 key pairs")
    check(Layout.Mapping(pairs: [("a", "ф"), ("b", "ф")]) == nil, "duplicate Russian character is rejected")
    check(Layout.Mapping(pairs: [("a", "ф"), ("a", "и")]) == nil, "duplicate English character is rejected")
    check(Layout.convert("Ёж", to: .english) == "~;", "letters on punctuation keys keep their mapping")
    check(Layout.convert("ntcn&") == "тест?", "Shift+7 is the Russian question mark")
    check(Layout.convert("тест?", to: .english) == "ntcn&", "Russian question mark returns to Shift+7")
    check(Layout.convert("@#$^|", to: .russian) == "\"№;:/", "number row and Shift+backslash")
    check(Layout.convert("\"№;:/", to: .english) == "@#$^|", "number row returns to US characters")
    check(Layout.convert("123 -=!", to: .russian) == "123 -=!", "keys equal in both layouts stay unchanged")

    let engine = Engine()
    func token(_ value: String, _ settings: Settings = Settings()) -> Decision? {
        let engine = Engine(settings: settings)
        return engine.completedTokenDecision(value, decide: { engine.decide($0) })
    }
    let corrected: [(String, String, String)] = [
        ("ghbdtn/", "привет.", "ghbdtn"), ("ghbdtn?", "привет,", "ghbdtn"), ("ghbdtn&", "привет?", "ghbdtn"),
        ("GHBDTN/", "ПРИВЕТ.", "GHBDTN"), ("Ghbdtn//", "Привет..", "Ghbdtn"),
        ("руддщю", "hello.", "руддщ"), ("руддщб", "hello,", "руддщ"), ("руддщ,", "hello?", "руддщ")]
    for (input, expected, learned) in corrected {
        let decision = token(input)
        check(decision?.original == input && decision?.replacement == expected && decision?.reason == .layout,
              "\(input) becomes \(expected)")
        check(decision?.learnAs == learned, "undo of \(input) learns the word without punctuation")
    }
    for (input, expected) in [("ghbdtn.", "привет"), ("ghbdtn,", "привет"), ("руддщ.", "hello")] {
        let decision = token(input)
        check(decision?.original == String(input.dropLast()) && decision?.replacement == expected && decision?.learnAs == nil,
              "literal punctuation keeps the prefix decision: \(input)")
    }
    for input in ["делаю", "клуб", "муж", "этаж", "привет", "hello", "ab/", "///", "ghbdtn/x"] {
        check(token(input) == nil, "no physical punctuation correction: \(input)")
    }
    check(engine.completedTokenDecision("руддщю", decide: { engine.decide($0) }, isKnownWord: { _ in true }) == nil,
          "a token that is a known word is not split into prefix and punctuation")
    var excluded = Settings(); excluded.excludedWords = ["ghbdtn"]
    check(token("ghbdtn/", excluded) == nil, "excluded word also blocks its converted punctuation")
    var learned = Settings(); learned.learnedWords = ["руддщ"]
    check(token("руддщю", learned) == nil, "learned word also blocks its converted punctuation")
    var rule = Settings(); rule.rules = [UserRule(source: "ghbdtn", replacement: "хай")]
    check(token("ghbdtn/", rule) == nil, "a literal user rule is not combined with converted punctuation")
    check(token("ghb?")?.replacement == "при,", "a short known word takes its converted comma")
    check(token("ghbdtn!")?.original == "ghbdtn", "punctuation equal in both layouts stays literal")
    var noAuto = Settings(); noAuto.automatic = false
    check(token("ghbdtn/", noAuto) == nil, "automatic layout off disables converted punctuation")

    let events = #"[{"kind":"text","text":"ghbdtn/"},{"kind":"boundary","text":" "}]"#
    let replay = (try? JSONDecoder().decode([ReplayEvent].self, from: Data(events.utf8))).map { Replay.run($0) }
    check(replay?.text == "привет. " && replay?.reasons == ["layout"], "replay replaces the whole token")
    let legacy = #"{"original":"ghbdtn","replacement":"привет","reason":"layout"}"#
    check((try? JSONDecoder().decode(Decision.self, from: Data(legacy.utf8)))?.learnAs == nil,
          "a decision saved without learnAs still decodes")
    return checks
}
