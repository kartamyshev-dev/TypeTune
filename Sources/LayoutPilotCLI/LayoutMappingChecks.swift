import LayoutPilotCore

func layoutMappingChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "layout mapping: " + name)) }
    let standard = Layout.Mapping.standardPC
    let standardKeys: [(english: String?, russian: String?)] = standard.toRussian
        .sorted { String($0.key) < String($1.key) }.map { (String($0.key), String($0.value)) }
    check(standard.coversAllLetters, "authored PC table covers every letter")
    check(Layout.Mapping.decoded(keys: standardKeys) == standard, "decoding the PC key outputs reproduces the authored table")
    // Keys equal in both layouts, untranslatable keys and multi-character output are ignored.
    let noisy = standardKeys + [("1", "1"), (nil, "ф"), ("ab", "фы"), (" ", " ")]
    check(Layout.Mapping.decoded(keys: noisy) == standard, "identical, missing and multi-character outputs are skipped")
    // An ISO § key that repeats an earlier character does not invalidate the table.
    check(Layout.Mapping.decoded(keys: standardKeys + [("`", "]")]) == standard, "a later duplicate key keeps the first assignment")
    let missing = standardKeys.filter { $0.russian != "ё" }
    check(Layout.Mapping.decoded(keys: missing) == nil, "a layout without ё falls back to the authored table")
    check(Layout.Mapping.keyboard(pairs: [("a", "ф")]) == nil, "an incomplete table is rejected")
    // A layout with ё on the backslash key and ] on the grave key (a different Russian layout shape).
    let moved = standardKeys.map { key -> (english: String?, russian: String?) in
        if key.english == "`" { return ("`", "]") }
        if key.english == "~" { return ("~", "[") }
        if key.english == "|" { return ("|", "Ё") }
        return key
    } + [("\\", "ё")]
    let alternate = Layout.Mapping.decoded(keys: moved)
    check(alternate?.coversAllLetters == true, "an alternate Russian key shape decodes")
    if let alternate {
        check(Layout.convert("\\k", to: .russian, mapping: alternate) == "ёл", "ё follows the decoded key")
        check(Layout.convert("ёлка", to: .english, mapping: alternate) == "\\krf", "conversion back uses the decoded key")
        let engine = Engine(mapping: alternate)
        check(engine.decide("ghbdtn")?.replacement == "привет", "letters keep working with the decoded table")
        check(engine.manual("\\rf")?.replacement == "ёка", "manual conversion uses the decoded table")
        check(engine.decidePartial("ghbd")?.replacement == "прив", "early correction uses the engine table")
    }
    return checks
}
