import Foundation
import LayoutPilotCore

func snippetLibraryChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "snippet library: " + name)) }
    func json(_ text: String) -> Data { Data(text.utf8) }

    // Default trigger (DECISIONS п. 28).
    check(Snippet(abbreviation: ";адр", text: "x").trigger == .immediate, "a sign-led abbreviation fires at once")
    check(Snippet(abbreviation: "/sig", text: "x").trigger == .immediate, "slash-led abbreviation fires at once")
    check(Snippet(abbreviation: "спс", text: "x").trigger == .boundary, "a word-like abbreviation waits for the boundary")
    check(Snippet(abbreviation: "2fa", text: "x").trigger == .boundary, "a digit-led abbreviation waits for the boundary")
    let fresh = Snippet(abbreviation: ";адр", text: "x")
    check(fresh.otherLayout && fresh.matchCase && fresh.enabled && fresh.applications == ApplicationFilter(),
          "a new snippet matches the other layout and case in every application")

    // Application filter.
    let all = ApplicationFilter(), only = ApplicationFilter(mode: .only, applications: ["com.apple.mail"])
    let except = ApplicationFilter(mode: .except, applications: ["com.apple.Terminal"])
    check(all.permits("com.apple.Terminal"), "all applications")
    check(only.permits("com.apple.mail") && !only.permits("com.apple.TextEdit"), "only listed applications")
    check(!except.permits("com.apple.Terminal") && except.permits("com.apple.TextEdit"), "all except listed applications")

    // Migration of former literal rules keeps their behaviour.
    let rule = UserRule(source: "спс", replacement: "спасибо")
    let migrated = Snippet(migrating: rule)
    check(migrated.id == rule.id && migrated.abbreviation == "спс" && migrated.text == "спасибо", "a rule keeps id and text")
    check(migrated.trigger == .boundary && !migrated.otherLayout && migrated.matchCase && migrated.enabled,
          "a rule stays a whole-token, same-layout, case-carrying replacement")
    check(Snippet(migrating: UserRule(source: ";x", replacement: "y")).trigger == .boundary,
          "a sign-led rule still waits for the boundary")
    check(Snippet(migrating: UserRule(source: "tpl", replacement: "{{дата}} и {{x")).text == "\\{{дата}} и \\{{x",
          "braces of a rule stay literal after migration")
    check(Snippet(migrating: UserRule(source: "bs", replacement: "\\{{")).text == "\\\\{{",
          "a backslash before braces in a rule survives migration")

    // Loading.
    switch SnippetLibrary.load(fileData: nil, legacyRules: [rule]) {
    case .migrated(let library):
        check(library.version == SnippetLibrary.currentVersion && library.snippets == [migrated], "no file: rules are migrated")
    default: check(false, "no file: rules are migrated")
    }
    check(SnippetLibrary.load(fileData: nil, legacyRules: []) == .migrated(SnippetLibrary()), "no file and no rules: empty library")
    let library = SnippetLibrary(snippets: [fresh, migrated])
    if let data = try? library.encoded() {
        check(SnippetLibrary.load(fileData: data, legacyRules: [UserRule(source: "a", replacement: "b")]) == .loaded(library),
              "a saved library round-trips and ignores the legacy rules")
        check(String(decoding: data, as: UTF8.self).contains("\"version\" : 1"), "the file records its format version")
    } else { check(false, "a saved library encodes") }
    let id = UUID()
    let minimal = json(#"{"version":1,"snippets":[{"id":"\#(id.uuidString)","abbreviation":"спс","text":"спасибо"}]}"#)
    if case .loaded(let old) = SnippetLibrary.load(fileData: minimal, legacyRules: []), let only = old.snippets.first {
        check(only.id == id && only.trigger == .boundary && only.otherLayout && only.matchCase && only.enabled &&
              only.applications == ApplicationFilter(), "missing fields get defaults")
    } else { check(false, "missing fields get defaults") }
    check(SnippetLibrary.load(fileData: json(#"{"version":2,"snippets":[]}"#), legacyRules: []) == .unavailable(.unsupportedVersion(2)),
          "a newer format is never overwritten")
    check(SnippetLibrary.load(fileData: json(#"{"version":0,"snippets":[]}"#), legacyRules: []) == .unavailable(.unsupportedVersion(0)),
          "an impossible version is rejected")
    for (bad, name) in [("{", "truncated"), ("[]", "not an object"), (#"{"snippets":[]}"#, "no version"),
                        (#"{"version":1}"#, "no snippets"), (#"{"version":1,"snippets":[{"abbreviation":"a"}]}"#, "snippet without id"),
                        (#"{"version":1,"snippets":[{"id":"\#(id.uuidString)","abbreviation":"a","text":"b","trigger":"later"}]}"#, "unknown trigger")] {
        check(SnippetLibrary.load(fileData: json(bad), legacyRules: [rule]) == .unavailable(.malformed),
              "malformed file blocks storage instead of migrating: " + name)
    }

    // Validation.
    let empty = SnippetLibrary()
    check(empty.issues(for: fresh).isEmpty, "a valid snippet has no issues")
    check(empty.issues(for: Snippet(abbreviation: "a", text: "x")) == [.abbreviationLength], "one character is too short")
    check(empty.issues(for: Snippet(abbreviation: String(repeating: "a", count: 65), text: "x")) == [.abbreviationLength],
          "65 characters is too long")
    check(empty.issues(for: Snippet(abbreviation: String(repeating: "a", count: 64), text: "x")).isEmpty, "64 characters is allowed")
    check(empty.issues(for: Snippet(abbreviation: "e\u{301}e\u{301}", text: "x")).isEmpty, "length counts characters, not scalars")
    for abbreviation in ["a b", "ab\t", "a\nb", "a\u{0}b", "a\u{00A0}b"] {
        check(empty.issues(for: Snippet(abbreviation: abbreviation, text: "x")).contains(.abbreviationCharacters),
              "whitespace or control in the abbreviation: \(abbreviation.unicodeScalars.map { $0.value })")
    }
    check(empty.issues(for: Snippet(abbreviation: "ab", text: "")) == [.emptyText], "empty text")
    check(empty.issues(for: Snippet(abbreviation: "ab", text: String(repeating: "x", count: 10_000))).isEmpty, "10 000 characters is allowed")
    check(empty.issues(for: Snippet(abbreviation: "ab", text: String(repeating: "x", count: 10_001))) == [.textTooLong], "10 001 is too long")
    check(empty.issues(for: Snippet(abbreviation: "ab", text: "строка\nстрока\tтаб")).isEmpty, "line feed and tab are allowed")
    for text in ["a\rb", "a\u{0}b", "a\u{1B}b", "a\u{7F}b"] {
        check(empty.issues(for: Snippet(abbreviation: "ab", text: text)) == [.textCharacters],
              "other control characters: \(text.unicodeScalars.map { $0.value })")
    }

    // Duplicates.
    let base = SnippetLibrary(snippets: [Snippet(abbreviation: ";адр", text: "x")])
    let baseID = base.snippets[0].id
    check(base.issues(for: base.snippets[0]).isEmpty, "a snippet does not collide with itself")
    check(base.issues(for: Snippet(abbreviation: ";АДР", text: "y")) == [.duplicate(of: baseID)], "same abbreviation ignoring case")
    check(base.issues(for: Snippet(abbreviation: "$flh", text: "y")) == [.duplicate(of: baseID)],
          "same physical keys in the other layout")
    let literal = SnippetLibrary(snippets: [Snippet(abbreviation: "спс", text: "x", otherLayout: false)])
    check(literal.issues(for: Snippet(abbreviation: "cgc", text: "y", otherLayout: false)).isEmpty,
          "same keys are distinct when neither matches the other layout")
    check(literal.issues(for: Snippet(abbreviation: "cgc", text: "y")) == [.duplicate(of: literal.snippets[0].id)],
          "one side matching the other layout is enough to collide")

    // Usable snippets.
    let first = Snippet(abbreviation: "спс", text: "спасибо"), second = Snippet(abbreviation: "СПС", text: "другое")
    let disabled = Snippet(abbreviation: "пжл", text: "пожалуйста", enabled: false)
    let invalid = Snippet(abbreviation: "x", text: "y")
    let usable = SnippetLibrary(snippets: [first, second, disabled, invalid]).usable()
    check(usable == [first], "only enabled, valid, first-of-colliding snippets can fire")

    // Rules for the per-application path.
    let plainRule = Snippet(abbreviation: "спс", text: "спасибо")
    let escapedRule = Snippet(migrating: UserRule(source: "tpl", replacement: "{{x}}"))
    let legacy = SnippetLibrary(snippets: [
        plainRule, escapedRule,
        Snippet(abbreviation: ";адр", text: "адрес"),
        Snippet(abbreviation: "дт", text: "{{дата}}"),
        Snippet(abbreviation: "пдп", text: "С уважением,\nВасилий"),
        Snippet(abbreviation: "мл", text: "почта", applications: ApplicationFilter(mode: .only, applications: ["com.apple.mail"])),
        Snippet(abbreviation: "вкл", text: "выключено", enabled: false)
    ]).legacyRules()
    check(legacy.map(\.source) == ["спс", "tpl"] && legacy.map(\.replacement) == ["спасибо", "{{x}}"],
          "only literal whole-word snippets for every application become rules")
    check(legacy.first?.id == plainRule.id, "a derived rule keeps the snippet id")
    check(SnippetLibrary(snippets: [Snippet(migrating: rule)]).legacyRules().map(\.replacement) == [rule.replacement],
          "a migrated rule survives the round trip unchanged")
    check(SnippetTemplate.literal("a\\{{b") == "a{{b" && SnippetTemplate.literal("{{дата}}") == nil &&
          SnippetTemplate.literal("") == nil, "literal text of a template")
    return checks
}
