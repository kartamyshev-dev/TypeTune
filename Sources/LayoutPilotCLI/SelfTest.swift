import Foundation
import LayoutPilotCore

func runSelfTests() -> Int {
    var count = 0, failures = 0
    func check(_ passed: @autoclosure () -> Bool, _ label: String) {
        count += 1
        if !passed() { failures += 1; FileHandle.standardError.write(Data(("FAIL: " + label + "\n").utf8)) }
    }
    check(EditorSupport.permitsTextReplacement(applicationID: "com.apple.TextEdit"), "verified TextEdit adapter remains available")
    for host in ["com.apple.Terminal", "com.mitchellh.ghostty"] {
        check(EditorSupport.permitsTerminalIntegration(applicationID: host), "terminal uses explicit ZLE integration")
        check(!EditorSupport.permitsTextReplacement(applicationID: host), "terminal screen is never an AX editor")
    }
    for host: String? in [nil, "", "com.google.Chrome", "com.apple.TextEdit", "net.kovidgoyal.kitty"] {
        check(!EditorSupport.permitsTerminalIntegration(applicationID: host), "unknown terminal bridge host is blocked")
    }
    check(EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, webContent: true), "Chrome webpage single-line field is supported")
    for application: String? in ["com.apple.TextEdit", "com.openai.codex", "net.waterfox.waterfox", nil] {
        check(!EditorSupport.permitsEditableField(applicationID: application, role: "AXTextField", subrole: nil, webContent: true), "single-line support does not expand other adapters")
    }
    check(!EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, webContent: false), "Chrome toolbar and address field stay blocked")
    for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
        check(!EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: role, subrole: "AXSecureTextField", webContent: true), "secure field is blocked before reading text")
    }
    for application in ["com.apple.TextEdit", "com.google.Chrome", "com.openai.codex"] {
        check(EditorSupport.permitsEditableField(applicationID: application, role: "AXTextArea", subrole: nil, webContent: false), "existing text-area adapter remains supported")
    }
    check(!EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: "AXComboBox", subrole: nil, webContent: true), "combo boxes remain blocked")
    check(!EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: nil, subrole: nil, webContent: true), "unknown role remains blocked")
    for applicationID: String? in [nil, "", "com.openai.chat", "com.apple.Safari", "com.todesktop.230313mzl4w4u92", "com.example.UnknownEditor"] {
        check(!EditorSupport.permitsTextReplacement(applicationID: applicationID), "unverified host cannot authorize selection or replacement: " + (applicationID ?? "nil"))
    }
    check(EditorSupport.insertionBackend(applicationID: "com.openai.codex") == .keyboardEvents, "Codex never uses the no-op AXSelectedText setter")
    check(EditorSupport.insertionBackend(applicationID: "com.google.Chrome") == .keyboardEvents, "Chrome uses native insertion")
    check(EditorSupport.insertionBackend(applicationID: "com.apple.TextEdit") == .selectedText, "TextEdit keeps native AX adapter")
    for payload in ["", "\n", "a\rb", "\t", "a\0b", String(repeating: "a", count: 4097)] {
        check(!EditorSupport.permitsKeyboardText(payload), "keyboard payload cannot submit or exceed bound")
    }
    for label in ["Адресная строка и строка поиска", "Address and search bar"] {
        check(EditorSupport.isChromeAddressBar(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, description: label, inToolbar: true), "verified Chrome omnibox label")
        check(!EditorSupport.isChromeAddressBar(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, description: label, inToolbar: false), "webpage cannot impersonate toolbar omnibox")
        check(!EditorSupport.isChromeAddressBar(applicationID: "com.google.Chrome", role: "AXTextField", subrole: "AXSecureTextField", description: label, inToolbar: true), "secure toolbar stays blocked")
    }
    check(EditorSupport.permitsEditableField(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, webContent: false, addressBar: true), "verified omnibox is supported")
    check(!EditorSupport.isChromeAddressBar(applicationID: "com.google.Chrome", role: "AXTextField", subrole: nil, description: "Find", inToolbar: true), "other toolbar search fields stay blocked")
    check(!EditorSupport.isChromeAddressBar(applicationID: "com.example.Unknown", role: "AXTextField", subrole: nil, description: "Address and search bar", inToolbar: true), "omnibox cannot expand host allowlist")
    for query in ["ghbdtn", "ghbdtn ", "ghbdtn vbh ", "привет мир", "hello", "😀 привет", "", " ", "https://ghbdtn", "http://example.com/ghbdtn", "ghbdtn.ru", "пример.рф", "xn--e1afmkfd.xn--p1ai", "localhost", "localhost ghbdtn", "127.0.0.1", "[::1]", "user@example.com", "file:///tmp/ghbdtn", "chrome://settings", "about:blank", "data:text/plain,ghbdtn", "javascript:ghbdtn", "//ghbdtn", "/ghbdtn", "ghbdtn/path", "ghbdtn?x=1", "ghbdtn#section", "ghbdtn%20", "site:example.com ghbdtn", "ghbdtn.txt", "ghbdtn123", "foo-bar", "foo_bar", "https://example.com ghbdtn", "привет\nмир", "привет\tмир"] {
        let expected = ["ghbdtn", "ghbdtn ", "ghbdtn vbh ", "привет мир", "hello"].contains(query)
        check(EditorSupport.permitsAddressBarCorrection(query) == expected, "omnibox whole-query URL protection: \(query)")
    }
    check(EditorSupport.permitsKeyboardText("Привет hello 😀 e\u{301}"), "native keyboard payload preserves Unicode")
    check(EditorSupport.permitsKeyboardText(String(repeating: "a", count: 4096)), "native keyboard payload size boundary")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.apple.TextEdit", text: "первая\nвторая\tстрока"), "TextEdit can intercept multiline native AX paste")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.google.Chrome", text: "привет"), "Chromium single-line paste can use native command")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.google.Chrome", text: "первая\nвторая\tстрока"), "Chromium native paste supports LF and TAB without Unicode key payload")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.openai.codex", text: "первая\r\nвторая"), "Codex paste policy permits CRLF; composer native acceptance remains separate")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.google.Chrome", text: String(repeating: "x", count: 65536)), "native paste UTF16 upper boundary")
    check(EditorSupport.permitsPlainPasteInterception(applicationID: "com.google.Chrome", text: String(repeating: "😀", count: 32768)), "native paste boundary measures UTF16, not graphemes")
    for value: String? in [nil, "", "a\0b", String(repeating: "x", count: 65537), String(repeating: "😀", count: 32769)] {
        check(!EditorSupport.permitsPlainPasteInterception(applicationID: "com.google.Chrome", text: value), "unsupported Chromium paste reaches editor instead of being consumed")
    }
    check(!EditorSupport.permitsPlainPasteInterception(applicationID: "com.example.Unknown", text: "hello"), "unknown host keeps native paste")
    check(!EditorSupport.permitsPlainPasteInterception(applicationID: "com.apple.TextEdit", text: String(repeating: "x", count: 65537)), "oversize TextEdit paste keeps native command")
    func pasteMatches(_ before: String, _ selection: NSRange, _ payload: String, _ actual: String,
                      application: String = "com.google.Chrome") -> Bool {
        EditorSupport.nativePasteTextMatches(applicationID: application, beforeText: before,
            selection: selection, payload: payload, actualText: actual)
    }
    let zeroCaret = NSRange(location: 0, length: 0)
    check(pasteMatches("\n", zeroCaret, "первая\nвторая\tстрока", "первая\nвторая\tстрока"), "empty Chromium paragraph sentinel may disappear on native paste")
    check(pasteMatches("\n", zeroCaret, "hello", "hello\n"), "exact expected paste text remains accepted with structural LF")
    check(pasteMatches("", zeroCaret, "hello", "hello"), "ordinary empty textarea paste is exact")
    check(!pasteMatches("\n", NSRange(location: 1, length: 0), "hello", "hello"), "sentinel equivalence never applies after newline caret")
    check(!pasteMatches("\n\n", zeroCaret, "hello", "hello"), "two real line breaks are never stripped")
    check(!pasteMatches("prefix\n", zeroCaret, "hello", "hello"), "nonempty prefix is never lost through sentinel equivalence")
    check(!pasteMatches("\n", zeroCaret, "hello\n", "hello"), "payload real final newline must remain")
    check(pasteMatches("\n", zeroCaret, "hello\n", "hello\n"), "payload final newline preserved when sentinel disappears")
    check(!pasteMatches("\n", zeroCaret, "hello", "hello", application: "com.apple.TextEdit"), "TextEdit never uses Chromium native-paste normalization")
    check(!pasteMatches("\n", zeroCaret, "hello", "hello", application: "com.example.Unknown"), "unknown host cannot use sentinel equivalence")
    check(pasteMatches("A\nB", NSRange(location: 1, length: 1), "hello", "AhelloB"), "selected real newline is replaced only through ordinary exact selection semantics")
    check(!pasteMatches("\n", zeroCaret, "hello", "hell"), "sentinel exception does not accept truncated payload")
    check(EditorSupport.nativePasteKeysReleased(hidFlags: 0, sessionFlags: 0, anyWatchedKeyDown: false), "native paste starts only after neutral shortcut release")
    check(!EditorSupport.nativePasteKeysReleased(hidFlags: 0, sessionFlags: 0, anyWatchedKeyDown: true), "held V or modifier keyState prevents starting the native frame")
    for bit: UInt64 in [1 << 16, 1 << 17, 1 << 18, 1 << 19, 1 << 20, 1 << 23, 0x8, 0x2, 0x20, 0x2000] {
        check(!EditorSupport.nativePasteKeysReleased(hidFlags: bit, sessionFlags: 0, anyWatchedKeyDown: false), "HID modifier flags prevent native shortcut overlap")
        check(!EditorSupport.nativePasteKeysReleased(hidFlags: 0, sessionFlags: bit, anyWatchedKeyDown: false), "session modifier flags prevent native shortcut overlap")
    }
    check(EditorSupport.nativePasteKeysReleased(hidFlags: 0x100, sessionFlags: 0x100, anyWatchedKeyDown: false), "noncoalesced event flag is not a held modifier")
    let commandShiftFlags: UInt64 = (1 << 20) | (1 << 17) | 0x8 | 0x2
    var releaseHandshake = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
    check(!releaseHandshake.ready && EditorSupport.nativePasteKeysReleased(hidFlags: 0, sessionFlags: 0, anyWatchedKeyDown: false), "premature global-neutral read cannot authorize a shortcut without delivered releases")
    releaseHandshake.observe(.keyUp, keyCode: 4)
    check(!releaseHandshake.vReleased && !releaseHandshake.ready, "unrelated keyUp never counts as original V release")
    releaseHandshake.observe(.keyUp, keyCode: 9)
    check(releaseHandshake.vReleased && !releaseHandshake.ready, "V release alone is insufficient")
    releaseHandshake.observe(.flagsChanged, keyCode: 56, rawFlags: (1 << 20) | 0x8)
    check(releaseHandshake.shiftReleased && !releaseHandshake.neutralModifierReleaseSeen && !releaseHandshake.ready, "Shift release with Command held is insufficient")
    releaseHandshake.observe(.flagsChanged, keyCode: 55, rawFlags: 0x100)
    check(releaseHandshake.ready, "delivered V-up then Shift-up then neutral Command-up completes handshake")
    var reverseRelease = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
    reverseRelease.observe(.flagsChanged, keyCode: 54, rawFlags: (1 << 17) | 0x4)
    reverseRelease.observe(.flagsChanged, keyCode: 60, rawFlags: 0)
    check(!reverseRelease.ready && !reverseRelease.vReleased, "both modifiers released before V still wait for V-up")
    reverseRelease.observe(.keyUp, keyCode: 9)
    check(reverseRelease.ready, "right-side modifiers and V-last release sequence completes handshake")
    var missingShift = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
    missingShift.observe(.keyUp, keyCode: 9)
    missingShift.observe(.flagsChanged, keyCode: 55, rawFlags: 0)
    check(!missingShift.ready, "neutral Command frame does not invent the missing Shift release")
    for newKey in [9, 4] {
        var interrupted = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
        interrupted.observe(.keyUp, keyCode: 9)
        interrupted.observe(.keyDown, keyCode: newKey)
        interrupted.observe(.flagsChanged, keyCode: 56, rawFlags: 0)
        interrupted.observe(.flagsChanged, keyCode: 55, rawFlags: 0)
        check(interrupted.cancelled && !interrupted.ready, "new V/ordinary keyDown cancels original shortcut handshake")
    }
    var newModifier = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
    newModifier.observe(.flagsChanged, keyCode: 58, rawFlags: (1 << 19) | 0x20)
    check(newModifier.cancelled && !newModifier.ready, "new modifier press cancels original shortcut handshake")
    releaseHandshake.observe(.cancel)
    check(releaseHandshake.cancelled && !releaseHandshake.ready && !releaseHandshake.vReleased, "focus/mouse/reset cancels and clears delivered release markers")
    releaseHandshake = NativePasteReleaseHandshake(originalFlags: commandShiftFlags)
    check(!releaseHandshake.ready && !releaseHandshake.vReleased && !releaseHandshake.commandReleased, "new request cannot reuse prior release markers")
    check(NativePasteReleaseHandshake(originalFlags: 0).cancelled, "handshake must originate from a real Command-Shift shortcut frame")
    check(Layout.convert("Ghbdtn") == "Привет", "physical US to RU and title case")
    check(Layout.convert("Руддщ") == "Hello", "physical RU to US")
    check(Layout.convert("123 👩🏽‍💻") == "123 👩🏽‍💻", "unmapped Unicode preserved")
    check(Layout.convert("Ёж", to: .english) == "~;", "shift ё and punctuation mapping")
    check(Layout.convert(Layout.convert("Привет", to: .english), to: .russian) == "Привет", "physical roundtrip")
    check(Engine().decide("ghbdtn")?.replacement == "привет", "layout correction")
    for learned in [false, true] {
        var settings = Settings()
        if learned { settings.learnedWords = ["GHBDTN."] }
        else { settings.excludedWords = ["GHBDTN."] }
        let engine = Engine(settings: settings)
        var calls = 0
        let result = engine.completedTokenDecision("ghbdtn.") { word in calls += 1; return engine.decide(word) }
        check(result == nil && calls == 0, "whole punctuated exclusion stops provider and fallback, learned=\(learned)")
        check(engine.completedTokenDecision("ghbdtn!") { engine.decide($0) }?.original == "ghbdtn",
              "exclusion of a punctuated token remains literal")
    }
    let tokenEngine = Engine()
    for (token, expected) in [("ghbdtn.", "привет. "), ("ghbdtn...?!", "привет...?! "),
                              ("rjvgm.nth", "компьютер "), ("ghbdtn.txt", "ghbdtn.txt "), ("...?!", "...?! ")] {
        let events = try! JSONDecoder().decode([ReplayEvent].self, from: JSONSerialization.data(withJSONObject: [["kind": "text", "text": token], ["kind": "boundary", "text": " "]]))
        check(Replay.run(events).text == expected, "replay and runtime share punctuation policy: \(token)")
    }
    for learned in [false, true] {
        var settings = Settings()
        if learned { settings.learnedWords = ["ghbdtn."] } else { settings.excludedWords = ["ghbdtn."] }
        let events = try! JSONDecoder().decode([ReplayEvent].self, from: Data(#"[{"kind":"text","text":"ghbdtn."},{"kind":"boundary","text":" "}]"#.utf8))
        check(Replay.run(events, engine: Engine(settings: settings)).text == "ghbdtn. ", "replay preserves whole punctuated exclusion")
    }
    for before in ["", "\n"] {
        check(!EditorSupport.nativePasteTextMatches(applicationID: "com.google.Chrome", beforeText: before,
            selection: NSRange(location: 0, length: 0), payload: "e\u{0301}", actualText: "é"),
              "paste acknowledgement rejects canonically equivalent UTF16 changes")
    }
    for token in ["ghbdtn", "ghbdtn.", "ghbdtn...?!"] {
        let value = tokenEngine.completedTokenDecision(token) { tokenEngine.decide($0) }
        check(value?.original == "ghbdtn" && value?.replacement == "привет",
              "punctuation fallback preserves word-only range and undo learning: \(token)")
    }
    check(tokenEngine.completedTokenDecision("rjvgm.nth") { tokenEngine.decide($0) }?.replacement == "компьютер",
          "whole physical punctuation token takes priority")
    check(tokenEngine.completedTokenDecision("ghbdtn.txt") { tokenEngine.decide($0) } == nil,
          "punctuation fallback cannot rewrite a filename")
    check(tokenEngine.completedTokenDecision("...?!") { tokenEngine.decide($0) } == nil,
          "punctuation alone is preserved")
    check(Engine().decide("GHBDTN")?.replacement == "ПРИВЕТ", "uppercase correction")
    check(Engine().decide("Руддщ")?.replacement == "Hello", "title correction")
    check(Engine().decide("helllo")?.reason == .typo, "typo reason")
    check(Engine().decide("Елка")?.replacement == "Ёлка", "yo correction")
    for token in ["hello", "привет", "ghbdtn123", "helloМир", "https://ghbdtn.test", "a@ghbdtn.test", "foo_bar", "<ghbdtn>", "f", "я", "zzznotaword", "все"] {
        check(Engine().decide(token) == nil, "preserve " + token)
    }
    for context in [InputContext(secure: true), InputContext(reliable: false)] {
        check(Engine().decide("ghbdtn", context: context) == nil, "automatic unsafe context")
        check(Engine().manual("ghbdtn", context: context) == nil, "manual unsafe context")
    }
    var settings = Settings(); settings.excludedApps = ["com.example.editor"]
    check(Engine(settings: settings).decide("ghbdtn", context: .init(application: "com.example.editor")) == nil, "automatic app exclusion")
    check(Engine(settings: settings).manual("ghbdtn", context: .init(application: "com.example.editor")) == nil, "manual app exclusion")
    settings.excludedWords = ["GHBDTN"]
    check(Engine(settings: settings).decide("ghbdtn") == nil, "case insensitive excluded word")
    settings.excludedWords = []; settings.learnedWords = ["ghbdtn"]
    check(Engine(settings: settings).decide("ghbdtn") == nil, "learned word")
    settings.learnedWords = []; settings.automatic = false
    check(Engine(settings: settings).decide("ghbdtn") == nil, "automatic off")
    check(Engine(settings: settings).manual("ghbdtn")?.replacement == "привет", "manual while automatic off")
    check(Engine(settings: settings).decide("превет")?.replacement == "привет", "typo independent from layout switch")
    check(Engine(settings: settings).decide("еще")?.replacement == "ещё", "yo independent from layout switch")
    settings.typos = false; settings.yo = false
    check(Engine(settings: settings).decide("превет") == nil, "all automatic features off typo")
    check(Engine(settings: settings).decide("еще") == nil, "all automatic features off yo")
    check(Engine().decide("gj;fkeqcnf")?.replacement == "пожалуйста", "punctuation physical Russian letter")
    check(Engine().decide("rjvgm.nth")?.replacement == "компьютер", "period physical Russian letter")
    check(Engine().decide("hello.com") == nil, "domain protected with punctuation conversion")
    settings = Settings(); settings.rules = [.init(source: "a.b", replacement: "example")]
    check(Engine(settings: settings).decide("a.b")?.replacement == "example", "literal rule")
    check(Engine(settings: settings).decide("axb") == nil, "rule is not regex")
    settings.yo = false; settings.typos = false
    check(Engine(settings: settings).decide("елка") == nil, "yo switch")
    check(Engine(settings: settings).decide("helllo") == nil, "typo switch")
    check((try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))) == settings, "settings roundtrip")
    // Original app-auto/global-auto interaction is established separately by
    // phase3-original-hid-*.json. Typo/yo independence below is our contract;
    // these core checks do not assert native acceptance or original parity.
    var appSettings = Settings()
    appSettings.appAutomatic = ["com.google.Chrome": false, "com.apple.TextEdit": true]
    let chromeContext = InputContext(application: "com.google.Chrome")
    check(Engine(settings: appSettings).decide("ghbdtn", context: chromeContext) == nil, "per-app false suppresses layout correction")
    check(Engine(settings: appSettings).decide("ghbdtn", context: .init(application: "com.apple.TextEdit"))?.replacement == "привет", "per-app true permits globally enabled automatic correction")
    check(Engine(settings: appSettings).decide("ghbdtn", context: .init(application: "com.example.Other"))?.replacement == "привет", "missing app policy preserves default automatic behavior")
    check(Engine(settings: appSettings).manual("ghbdtn", context: chromeContext)?.replacement == "привет", "per-app automatic pause preserves manual correction")
    // Changed contract (DECISIONS 22): an application pause stops every automatic change.
    check(Engine(settings: appSettings).decide("превет", context: chromeContext) == nil, "app automatic pause also stops typo correction")
    check(Engine(settings: appSettings).decide("еще", context: chromeContext) == nil, "app automatic pause also stops yo correction")
    appSettings.rules = [.init(source: "lpfixture", replacement: "проверка")]
    check(Engine(settings: appSettings).decide("lpfixture", context: chromeContext) == nil, "per-app false suppresses user automatic rule")
    check(Engine(settings: appSettings).decide("lpfixture", context: .init(application: "com.apple.TextEdit"))?.reason == .userRule, "per-app true permits user automatic rule")
    appSettings.automatic = false
    check(Engine(settings: appSettings).decide("ghbdtn", context: .init(application: "com.apple.TextEdit")) == nil, "automatic layout off dominates explicit per-app true")
    check(Engine(settings: appSettings).decide("lpfixture", context: .init(application: "com.apple.TextEdit")) == nil, "automatic layout off dominates per-app user-rule permission")
    appSettings.automatic = true
    appSettings.excludedApps = ["com.apple.TextEdit"]
    let excludedContext = InputContext(application: "com.apple.TextEdit")
    check(Engine(settings: appSettings).decide("ghbdtn", context: excludedContext) == nil, "full exclusion dominates app automatic true")
    check(Engine(settings: appSettings).decide("превет", context: excludedContext) == nil, "full exclusion still suppresses typo")
    check(Engine(settings: appSettings).manual("ghbdtn", context: excludedContext) == nil, "full exclusion still suppresses manual operation")
    appSettings.excludedApps = []
    appSettings.excludedWords = ["LPFIXTURE"]
    check(Engine(settings: appSettings).decide("lpfixture", context: .init(application: "com.apple.TextEdit")) == nil, "word exclusion retains priority over enabled app rule")
    appSettings.appAutomatic["com.google.Chrome"] = nil
    check(Engine(settings: appSettings).decide("ghbdtn", context: chromeContext)?.replacement == "привет", "removing app override restores default")
    // Legacy migration must preserve every old field and user-owned collection.
    var legacy = Settings()
    legacy.automatic = false; legacy.typos = false; legacy.yo = false; legacy.singleShift = false
    legacy.optionCorrection = true; legacy.shiftChordPause = true; legacy.plainPaste = false; legacy.sound = true
    legacy.excludedApps = ["com.example.Legacy"]
    legacy.excludedWords = ["legacyword"]; legacy.learnedWords = ["learnedword"]
    legacy.rules = [.init(source: "sourceword", replacement: "replacement")]
    if let encoded = try? JSONEncoder().encode(legacy),
       var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] {
        object.removeValue(forKey: "appAutomatic")
        let oldData = try? JSONSerialization.data(withJSONObject: object)
        let migrated = oldData.flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        check(migrated == legacy, "old settings JSON without appAutomatic preserves all existing values")
    } else { check(false, "encode legacy settings fixture") }
    appSettings.appAutomatic = ["com.google.Chrome": false, "com.apple.TextEdit": true]
    check((try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(appSettings))) == appSettings, "settings roundtrip preserves false and true app policies")
    check((try? JSONDecoder().decode(Settings.self, from: Data("{}".utf8))) == Settings(), "empty settings object adopts declared defaults")
    check(!Settings().plainPaste, "new core profile leaves experimental paste disabled")
    check((try? JSONDecoder().decode(Settings.self, from: Data(#"{"plainPaste":true}"#.utf8)))?.plainPaste == true,
          "saved paste preference remains available until user profile changes")
    check((try? JSONDecoder().decode(Settings.self, from: Data(#"{"futureField":17}"#.utf8))) == Settings(), "unknown future setting does not erase defaults")
    check((try? JSONDecoder().decode(Settings.self, from: Data(#"{"appAutomatic":null}"#.utf8))) == Settings(), "optional null app policy migrates to empty map")
    for malformed in [#"{"automatic":"false"}"#, #"{"appAutomatic":[]}"#, #"{"appAutomatic":{"com.google.Chrome":"false"}}"#, #"{"learnedWords":7}"#, #"{"rules":[{"source":"a"}]}"#] {
        check((try? JSONDecoder().decode(Settings.self, from: Data(malformed.utf8))) == nil, "malformed known settings field is rejected, not silently defaulted")
    }
    let text = "😀 ghbdtn"
    let edit = TextEdit(text: text, selection: NSRange(location: 3, length: 6), replacement: "привет")
    check(edit?.expectedText == "😀 привет", "UTF16 edit following surrogate pair")
    check(edit?.cursor == 9, "UTF16 cursor")
    check(TextEdit(text: text, selection: NSRange(location: 1, length: 1), replacement: "x") == nil, "reject split surrogate")
    check(TextEdit(text: text, selection: NSRange(location: 99, length: 1), replacement: "x") == nil, "reject out of bounds")
    check(TextEdit.wordBeforeCursor(in: text + "  ", cursor: 11) == NSRange(location: 3, length: 6), "word trailing spaces")
    check(TextEdit.wordBeforeCursor(in: text, cursor: -1) == nil, "negative cursor")
    check(TextEdit.wordBeforeCursor(in: text, cursor: 100) == nil, "cursor beyond end")
    check(Layout.isMixed("helloЁ"), "uppercase yo mixed script")
    let composed = "e\u{0301}👩🏽‍💻z"
    check(TextEdit(text: composed, selection: NSRange(location: 1, length: 0), replacement: "x") == nil, "reject combining grapheme split")
    check(TextEdit.wordBeforeCursor(in: composed, cursor: 1) == nil, "reject interior grapheme cursor")
    for range in [NSRange(location: Int.max, length: Int.max), NSRange(location: 1, length: Int.max), NSRange(location: -1, length: 0), NSRange(location: 0, length: -1)] {
        check(TextEdit(text: "hello", selection: range, replacement: "x") == nil, "invalid/overflow UTF16 range \(range)")
    }
    check(TextEdit.wordBeforeCursor(in: text, cursor: Int.max) == nil, "overflow cursor")
    let selectedRange = NSRange(location: 1, length: 2)
    if let selectedEdit = TextEdit(text: "abcdef", selection: selectedRange, replacement: "X") {
        check(selectedEdit.expectedText == "aXdef", "selected text replacement")
        check(selectedEdit.resultingSelection(from: selectedRange) == NSRange(location: 2, length: 0), "selected paste cursor regression")
        check(selectedEdit.resultingSelection(from: selectedRange, keepSelection: true) == NSRange(location: 1, length: 1), "keep replacement selected")
    } else { check(false, "construct selected edit") }
    if let wordEdit = TextEdit(text: "ghbdtn ", selection: NSRange(location: 0, length: 6), replacement: "приветик") {
        check(wordEdit.resultingSelection(from: NSRange(location: 7, length: 0)) == NSRange(location: 9, length: 0), "keep trailing separator after longer correction")
    } else { check(false, "construct word edit") }
    if let deletion = TextEdit(text: "abcdef", selection: selectedRange, replacement: "") {
        check(deletion.resultingSelection(from: selectedRange) == NSRange(location: 1, length: 0), "selected deletion cursor")
    } else { check(false, "construct deletion") }
    if let insertion = TextEdit(text: "ab", selection: NSRange(location: 1, length: 0), replacement: "😀") {
        check(insertion.resultingSelection(from: NSRange(location: 1, length: 0)) == NSRange(location: 3, length: 0), "surrogate insertion cursor")
    } else { check(false, "construct insertion") }
    check(Engine().decide("ПРивет")?.replacement == "Привет", "Russian double capital typo")
    check(Engine().decide("HEllo")?.replacement == "Hello", "English double capital typo")
    check(Engine().decide("ZZword")?.replacement == "Zzword", "unknown word double capitals do not require positive dictionary membership")
    check(Engine().decide("XYzzY")?.replacement == "Xyzzy", "double capitals lower the remaining tail")
    check(Engine().decide("GItHub")?.replacement == "Github", "observed mixed tail conversion")
    check(Engine().decide("FAceBook") == nil && Engine().decide("IPhone") == nil, "authored model-veto substitute")
    check(Engine().decide("MHz") == nil, "standard frequency unit retains significant internal capitals")
    check(Engine().decide("GHbdtn")?.replacement == "Привет", "case stage composes with layout conversion")
    check(Engine().decide("ПРевет")?.replacement == "Привет", "case stage composes with spelling correction")
    check(Engine().decide("ПРи")?.replacement == "При", "observed original three-letter double capital regression")
    check(Engine().decide("при") == nil && Engine().decide("При") == nil, "valid short Russian capitalization preserved")
    check(Engine().decide("ПРИ") == nil, "three-letter all-caps preserved")
    check(Engine().decide("HTTP") == nil, "acronym preserved")
    check(Engine().decide("iPhone") == nil, "mixed case preserved")
    var noTypos = Settings(); noTypos.typos = false
    check(Engine(settings: noTypos).decide("ПРивет") == nil, "double capital disabled")
    check(Engine(settings: noTypos).decide("ПРи") == nil, "short double capital respects disabled typos")
    for automatic in [true, false] {
        var settings = Settings(); settings.automatic = automatic
        for token in ["ABc.txt", "GHbdtn.txt", "ABc.test", "ABc;def", "ABc[def]", "ABc'def", "ABc--flag", "ABc=DEF", "./ABc", "/tmp/ABc.txt", "https://ABc.test/Case", "ABc123"] {
            check(Engine(settings: settings).decide(token) == nil, "F17 preserves filename/command/code/URL/digits with auto=\(automatic): \(token)")
        }
    }
    check(Engine().decide("rjvgm.nth")?.replacement == "компьютер", "physical punctuation still supports a known wrong-layout word")
    check(Engine().decide("Rjvgm.nth")?.replacement == "Компьютер", "physical punctuation preserves known title-case layout conversion")
    var punctuationNoAuto = Settings(); punctuationNoAuto.automatic = false
    check(Engine(settings: punctuationNoAuto).decide("rjvgm.nth") == nil, "physical punctuation does not force layout with automatic off")
    check(Engine(settings: punctuationNoAuto).decide("ZZword")?.replacement == "Zzword", "case correction remains independent of automatic layout")
    check(Engine(settings: punctuationNoAuto).decide("GHbdtn")?.replacement == "Ghbdtn", "automatic off allows case only, without RU conversion")
    var punctuationNoTypos = Settings(); punctuationNoTypos.typos = false
    check(Engine(settings: punctuationNoTypos).decide("ZZword") == nil, "unknown-word F17 obeys typos off")
    check(Engine(settings: punctuationNoTypos).decide("GHbdtn")?.replacement == "ПРивет", "typos off preserves capitals during independent layout correction")
    punctuationNoTypos.automatic = false
    check(Engine(settings: punctuationNoTypos).decide("GHbdtn") == nil, "case and layout both disabled preserve mixed-case input")
    for word in ["сестры", "звезды", "узнает"] {
        check(Engine().decide(word) == nil, "contextual yo preserved: " + word)
    }
    let json = #"[{"kind":"text","text":"ghbdtnx"},{"kind":"backspace"},{"kind":"boundary","text":" "},{"kind":"text","text":"руддщ"},{"kind":"boundary","text":"\n"}]"#
    if let events = try? JSONDecoder().decode([ReplayEvent].self, from: Data(json.utf8)) {
        check(Replay.run(events).text == "привет hello\n", "boundary replay")
        check(Replay.run(events).reasons == ["layout", "layout"], "replay reasons")
        check(Replay.run(events, context: .init(secure: true)).text == "ghbdtn руддщ\n", "secure replay")
        check(Replay.run(events, initialText: "😀 ").text == "😀 привет hello\n", "explicit initial replay state")
    } else { check(false, "decode replay fixture") }
    // Exercise the exact FIFO/token implementation used by KeyboardService.
    var replayQueue = InputReplayQueue<String>()
    check(replayQueue.isDrained, "input FIFO initially drained")
    check(!replayQueue.acknowledge(token: 0), "input FIFO rejects stray ACK")
    for event in ["A", "B", "C"] { replayQueue.append(event) }
    check(replayQueue.count == 3, "input FIFO pending count")
    let abcBatch = replayQueue.takeBatch()!
    check(abcBatch.events == ["A", "B", "C"] && abcBatch.token != 0, "input FIFO initial batch order and token")
    check(replayQueue.isEmpty && !replayQueue.isDrained && replayQueue.outstanding == 3, "input FIFO empty pending is not drained")
    replayQueue.append("D")
    check(replayQueue.takeBatch() == nil && replayQueue.count == 1, "input FIFO hardware D cannot overtake unacked ABC")
    check(replayQueue.acknowledge(token: abcBatch.token) && replayQueue.acknowledge(token: abcBatch.token), "input FIFO partial ABC acknowledgments")
    check(replayQueue.takeBatch() == nil && replayQueue.outstanding == 1, "input FIFO waits final ABC acknowledgment")
    check(replayQueue.acknowledge(token: abcBatch.token), "input FIFO final ABC acknowledgment")
    check(!replayQueue.acknowledge(token: abcBatch.token), "input FIFO rejects extra ABC acknowledgment")
    let dBatch = replayQueue.takeBatch()!
    check(dBatch.events == ["D"] && dBatch.token != abcBatch.token, "input FIFO D follows acknowledged ABC with new token")
    check(!replayQueue.acknowledge(token: abcBatch.token) && replayQueue.outstanding == 1, "input FIFO stale ABC ACK cannot close D")
    for event in ["E", "F"] { replayQueue.append(event) }
    check(replayQueue.takeBatch() == nil && !replayQueue.isDrained, "input FIFO EF cannot overtake unacked D")
    check(replayQueue.acknowledge(token: dBatch.token), "input FIFO D acknowledged")
    let efBatch = replayQueue.takeBatch()!
    check(efBatch.events == ["E", "F"], "input FIFO EF preserves order")
    check(replayQueue.acknowledge(token: efBatch.token) && !replayQueue.isDrained, "input FIFO stays open until final F acknowledgment")
    check(replayQueue.acknowledge(token: efBatch.token) && replayQueue.isDrained, "input FIFO closes only after all acknowledgments")
    check(replayQueue.takeBatch()?.events == [] && !replayQueue.acknowledge(token: 0), "input FIFO empty batch adds no outstanding ACK")
    replayQueue.append("uncertain")
    let canceled = replayQueue.takeBatch()!
    check(canceled.events == ["uncertain"], "input FIFO begin uncertain batch")
    replayQueue.append("pending")
    check(replayQueue.cancelOutstanding() == 1 && replayQueue.count == 1, "input FIFO timeout retains pending input")
    check(!replayQueue.acknowledge(token: canceled.token), "input FIFO canceled ACK rejected while idle")
    let recoveryBatch = replayQueue.takeBatch()!
    check(recoveryBatch.events == ["pending"] && recoveryBatch.token != canceled.token, "input FIFO recovery has a fresh token")
    check(!replayQueue.acknowledge(token: canceled.token) && replayQueue.outstanding == 1, "input FIFO late canceled ACK cannot close recovery batch")
    check(replayQueue.acknowledge(token: recoveryBatch.token) && replayQueue.isDrained, "input FIFO recovery closes on its own ACK")
    replayQueue.append("discard")
    check(replayQueue.discardPending() == ["discard"] && replayQueue.isDrained, "input FIFO explicit discard returns pending input")
    replayQueue.append("in-flight")
    let inFlight = replayQueue.takeBatch()!; replayQueue.append("discard-only-pending")
    check(replayQueue.discardPending() == ["discard-only-pending"] && replayQueue.outstanding == 1, "input FIFO discard never cancels posted batch")
    check(replayQueue.acknowledge(token: inFlight.token) && replayQueue.isDrained, "input FIFO posted batch finishes after pending discard")
    var sourceGate = InputReplayQueue<String>()
    sourceGate.append("keyUp")
    check(!sourceGate.containsPending(where: { $0 == "keyDown" }), "source change not blocked by pending release")
    sourceGate.append("keyDown")
    check(sourceGate.containsPending(where: { $0 == "keyDown" }), "source change blocked by pending text input")
    let sourceBatch = sourceGate.takeBatch()!
    check(!sourceGate.containsPending(where: { $0 == "keyDown" }) && sourceGate.outstanding == 2, "pending predicate does not reinterpret posted batch")
    check(sourceGate.receive(token: sourceBatch.token, routingAllowed: false) == .retain && sourceGate.containsPending(where: { $0 == "keyDown" }), "denied text delivery restores source gate")
    var routed = InputReplayQueue<String>()
    for event in ["A", "B", "C"] { routed.append(event) }
    let firstRoute = routed.takeBatch()!
    check(routed.receive(token: firstRoute.token, routingAllowed: true) == .forward, "route delivers A in original app")
    routed.append("D")
    check(routed.receive(token: firstRoute.token, routingAllowed: false) == .retain, "route blocks B after app changes")
    check(routed.outstanding == 0 && routed.count == 3, "route retains unacknowledged BC before new D")
    check(routed.receive(token: firstRoute.token, routingAllowed: true) == .suppress, "route suppresses late canceled C even when app returns")
    let resumedRoute = routed.takeBatch()!
    check(resumedRoute.events == ["B", "C", "D"], "route recovery never duplicates acknowledged A or reorders D")
    check(routed.receive(token: firstRoute.token, routingAllowed: true) == .suppress && routed.outstanding == 3, "route old packet cannot acknowledge recovery")
    check(routed.receive(token: resumedRoute.token, routingAllowed: true) == .forward, "route forwards recovered B")
    check(routed.receive(token: resumedRoute.token, routingAllowed: false) == .retain, "route can stop a second time")
    let secondResume = routed.takeBatch()!
    check(secondResume.events == ["C", "D"], "route repeated suspension retains only undelivered suffix")
    check(routed.receive(token: secondResume.token, routingAllowed: true) == .forward && routed.receive(token: secondResume.token, routingAllowed: true) == .forward && routed.isDrained, "route recovery drains exactly once")
    check(routed.receive(token: secondResume.token, routingAllowed: true) == .suppress, "route duplicate after drain suppressed")
    routed.append("unknown-delivery"); let timedRoute = routed.takeBatch()!
    check(routed.cancelOutstanding() == 1, "route timeout marks delivery uncertain without replay")
    check(routed.receive(token: timedRoute.token, routingAllowed: true) == .suppress && routed.isDrained, "route late timeout event suppressed")
    let predictedLatin = TextEdit.insertionPrediction(text: "ghbdt", selection: NSRange(location: 5, length: 0), characters: "n", keyCode: 45)
    check(predictedLatin?.expectedText == "ghbdtn" && predictedLatin?.cursor == 6, "prediction appends ordinary key")
    let predictedSelection = TextEdit.insertionPrediction(text: "😀 x", selection: NSRange(location: 3, length: 1), characters: "пр", keyCode: 15)
    check(predictedSelection?.expectedText == "😀 пр" && predictedSelection?.cursor == 5, "prediction preserves UTF16 prefix and selected replacement")
    check(TextEdit.insertionPrediction(text: "e\u{301}", selection: NSRange(location: 1, length: 0), characters: "x", keyCode: 7) == nil, "prediction rejects split grapheme")
    check(TextEdit.insertionPrediction(text: "", selection: NSRange(location: 0, length: 0), characters: "😀", keyCode: 0)?.cursor == 2, "prediction preserves emoji UTF16 size")
    check(TextEdit.insertionPrediction(text: "x", selection: NSRange(location: 1, length: 0), characters: "", keyCode: 0) == nil, "prediction rejects absent event text")
    check(TextEdit.insertionPrediction(text: "x", selection: NSRange(location: 1, length: 0), characters: "\n", keyCode: 36) == nil, "prediction never models Return as insertion")
    check(TextEdit.insertionPrediction(text: "x", selection: NSRange(location: 1, length: 0), characters: "\u{f702}", keyCode: 123) == nil, "prediction rejects navigation function character")
    check(TextEdit.insertionPrediction(text: "x", selection: NSRange(location: 1, length: 0), characters: "x", keyCode: 51) == nil, "prediction rejects misleading Backspace text")
    check(TextEdit.insertionPrediction(text: "x", selection: NSRange(location: 1, length: 0), characters: "\u{1}", keyCode: 0) == nil, "prediction rejects control character")
    check(TextEdit.insertionPrediction(text: String(repeating: "a", count: 65_536), selection: NSRange(location: 65_536, length: 0), characters: "x", keyCode: 7) == nil, "prediction respects editor size bound")
    check(!TextEdit.observesInsertionSuffix(text: "", selection: NSRange(location: 0, length: 0), characters: "g", keyCode: 5), "capture rejects pre-insertion empty field")
    check(TextEdit.observesInsertionSuffix(text: "g", selection: NSRange(location: 1, length: 0), characters: "g", keyCode: 5), "capture accepts visible initial character")
    check(!TextEdit.observesInsertionSuffix(text: "g", selection: NSRange(location: 1, length: 0), characters: "h", keyCode: 4), "capture rejects previous character before next insertion")
    check(TextEdit.observesInsertionSuffix(text: "gh", selection: NSRange(location: 2, length: 0), characters: "h", keyCode: 4), "capture accepts advanced character and caret")
    check(TextEdit.observesInsertionSuffix(text: "hello ", selection: NSRange(location: 6, length: 0), characters: " ", keyCode: 49), "capture observes delimiter at caret")
    check(!TextEdit.observesInsertionSuffix(text: "g", selection: NSRange(location: 0, length: 1), characters: "g", keyCode: 5), "capture rejects active selection")
    check(TextEdit.observesInsertionSuffix(text: "😀g", selection: NSRange(location: 3, length: 0), characters: "g", keyCode: 5), "capture uses UTF16 caret after emoji")
    check(!TextEdit.observesInsertionSuffix(text: "😀", selection: NSRange(location: 1, length: 0), characters: "x", keyCode: 7), "capture rejects split emoji caret")
    check(!TextEdit.observesInsertionSuffix(text: "e\u{301}", selection: NSRange(location: 2, length: 0), characters: "\u{301}", keyCode: 0), "capture never splits combining grapheme")
    check(!TextEdit.observesInsertionSuffix(text: "g", selection: NSRange(location: 1, length: 0), characters: "g", keyCode: 51), "capture rejects misleading Backspace")
    for (passed, label) in recoveryChecks() { check(passed, label) }
    for (label, passed) in snapshotChecks() { check(passed, label) }
    for (passed, label) in modifierGestureChecks() { check(passed, label) }
    for (passed, label) in statisticsChecks() { check(passed, label) }
    for (passed, label) in replayProjectionChecks() { check(passed, label) }
    for (passed, label) in replayRoutingChecks() { check(passed, label) }
    for (passed, label) in partialLayoutChecks() { check(passed, label) }
    for (passed, label) in earlyRollbackChecks() { check(passed, label) }
    for (passed, label) in physicalPunctuationChecks() { check(passed, label) }
    for (passed, label) in doubleCapitalChecks() { check(passed, label) }
    for (passed, label) in pauseChecks() { check(passed, label) }
    for (passed, label) in layoutMappingChecks() { check(passed, label) }
    for (passed, label) in mutationSessionChecks() { check(passed, label) }
    for (passed, label) in typedWordBufferChecks() { check(passed, label) }
    for (passed, label) in keystrokeEditPlanChecks() { check(passed, label) }
    for (passed, label) in inputTargetChecks() { check(passed, label) }
    print("\(count - failures)/\(count) offline invariants passed; \(failures) failures. No runtime input claim.")
    return failures
}
