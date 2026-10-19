import XCTest
import Foundation
@testable import LayoutPilotCore

final class CoreTests: XCTestCase {
    func testSelectionAfterReplacementRegressions() {
        let selection = NSRange(location: 1, length: 2)
        let edit = TextEdit(text: "abcdef", selection: selection, replacement: "X")!
        XCTAssertEqual(edit.expectedText, "aXdef")
        XCTAssertEqual(edit.resultingSelection(from: selection), NSRange(location: 2, length: 0))
        XCTAssertEqual(edit.resultingSelection(from: selection, keepSelection: true), NSRange(location: 1, length: 1))
        let word = TextEdit(text: "ghbdtn ", selection: NSRange(location: 0, length: 6), replacement: "приветик")!
        XCTAssertEqual(word.resultingSelection(from: NSRange(location: 7, length: 0)), NSRange(location: 9, length: 0))
        let deletion = TextEdit(text: "abcdef", selection: selection, replacement: "")!
        XCTAssertEqual(deletion.resultingSelection(from: selection), NSRange(location: 1, length: 0))
        let insertion = TextEdit(text: "ab", selection: NSRange(location: 1, length: 0), replacement: "😀")!
        XCTAssertEqual(insertion.resultingSelection(from: NSRange(location: 1, length: 0)), NSRange(location: 3, length: 0))
    }
    func testDoubleCapitalAndSemanticYoRegressions() {
        XCTAssertEqual(Engine().decide("ПРивет")?.replacement, "Привет")
        XCTAssertEqual(Engine().decide("HEllo")?.replacement, "Hello")
        XCTAssertNil(Engine().decide("HTTP"))
        XCTAssertNil(Engine().decide("iPhone"))
        var settings = Settings(); settings.typos = false
        XCTAssertNil(Engine(settings: settings).decide("ПРивет"))
        for word in ["сестры", "звезды", "узнает"] {
            XCTAssertNil(Engine().decide(word), "Do not choose a contextual ё interpretation: " + word)
        }
    }
    func testPhysicalMappingAndUnicode() {
        XCTAssertEqual(Layout.convert("Ghbdtn"), "Привет")
        XCTAssertEqual(Layout.convert("Руддщ"), "Hello")
        XCTAssertEqual(Layout.convert("123 👩🏽‍💻"), "123 👩🏽‍💻")
        XCTAssertEqual(Layout.convert("Ёж", to: .english), "~;")
        XCTAssertEqual(Layout.convert(Layout.convert("Привет", to: .english), to: .russian), "Привет")
    }
    func testKnownDecisionsAndCase() {
        XCTAssertEqual(Engine().decide("ghbdtn")?.replacement, "привет")
        XCTAssertEqual(Engine().decide("GHBDTN")?.replacement, "ПРИВЕТ")
        XCTAssertEqual(Engine().decide("Руддщ")?.replacement, "Hello")
        XCTAssertEqual(Engine().decide("helllo")?.reason, .typo)
        XCTAssertEqual(Engine().decide("Елка")?.replacement, "Ёлка")
    }
    func testConservativeBoundaries() {
        for token in ["hello", "привет", "ghbdtn123", "helloМир", "https://ghbdtn.test", "a@ghbdtn.test", "foo_bar", "<ghbdtn>", "я", "zzznotaword"] {
            XCTAssertNil(Engine().decide(token), token)
        }
        // Ambiguous forms must not be normalized blindly.
        XCTAssertNil(Engine().decide("все"))
    }
    func testContextAndSettingsGuards() {
        let engine = Engine()
        XCTAssertNil(engine.decide("ghbdtn", context: .init(secure: true)))
        XCTAssertNil(engine.manual("ghbdtn", context: .init(secure: true)))
        XCTAssertNil(engine.decide("ghbdtn", context: .init(reliable: false)))
        XCTAssertNil(engine.manual("ghbdtn", context: .init(reliable: false)))
        var settings = Settings(); settings.excludedApps = ["com.example.editor"]
        XCTAssertNil(Engine(settings: settings).decide("ghbdtn", context: .init(application: "com.example.editor")))
        XCTAssertNil(Engine(settings: settings).manual("ghbdtn", context: .init(application: "com.example.editor")))
        settings.excludedWords = ["GHBDTN"]
        XCTAssertNil(Engine(settings: settings).decide("ghbdtn"))
        settings.excludedWords = []; settings.learnedWords = ["ghbdtn"]
        XCTAssertNil(Engine(settings: settings).decide("ghbdtn"))
        settings.learnedWords = []; settings.automatic = false
        XCTAssertNil(Engine(settings: settings).decide("ghbdtn"))
        XCTAssertEqual(Engine(settings: settings).manual("ghbdtn")?.replacement, "привет")
    }
    func testLiteralRuleAndFeatureSwitches() {
        var settings = Settings(); settings.rules = [.init(source: "a.b", replacement: "example")]
        XCTAssertEqual(Engine(settings: settings).decide("a.b")?.replacement, "example")
        XCTAssertNil(Engine(settings: settings).decide("axb"))
        settings.yo = false; settings.typos = false
        XCTAssertNil(Engine(settings: settings).decide("елка"))
        XCTAssertNil(Engine(settings: settings).decide("helllo"))
        let data = try! JSONEncoder().encode(settings)
        XCTAssertEqual(try! JSONDecoder().decode(Settings.self, from: data), settings)
    }
    func testUTF16EditsAndCursor() {
        let text = "😀 ghbdtn"
        let edit = TextEdit(text: text, selection: NSRange(location: 3, length: 6), replacement: "привет")
        XCTAssertEqual(edit?.expectedText, "😀 привет")
        XCTAssertEqual(edit?.cursor, 9)
        XCTAssertNil(TextEdit(text: text, selection: NSRange(location: 1, length: 1), replacement: "x"))
        XCTAssertNil(TextEdit(text: text, selection: NSRange(location: 99, length: 1), replacement: "x"))
        XCTAssertEqual(TextEdit.wordBeforeCursor(in: text + "  ", cursor: 11), NSRange(location: 3, length: 6))
        XCTAssertNil(TextEdit.wordBeforeCursor(in: text, cursor: -1))
        XCTAssertNil(TextEdit.wordBeforeCursor(in: text, cursor: 100))
    }
    func testRejectGraphemeSplitsAndOverflowRanges() {
        let text = "e\u{0301}👩🏽‍💻z"
        XCTAssertNil(TextEdit(text: text, selection: NSRange(location: 1, length: 0), replacement: "x"))
        XCTAssertNil(TextEdit.wordBeforeCursor(in: text, cursor: 1))
        for range in [NSRange(location: Int.max, length: Int.max), NSRange(location: 1, length: Int.max), NSRange(location: -1, length: 0), NSRange(location: 0, length: -1)] {
            XCTAssertNil(TextEdit(text: "hello", selection: range, replacement: "x"))
        }
        XCTAssertNil(TextEdit.wordBeforeCursor(in: text, cursor: Int.max))
        XCTAssertTrue(Layout.isMixed("helloЁ"))
    }
    func testReplayBoundaryBackspaceResetAndContext() throws {
        let events = try JSONDecoder().decode([ReplayEvent].self, from: Data(#"[{"kind":"text","text":"ghbdtnx"},{"kind":"backspace"},{"kind":"boundary","text":" "},{"kind":"text","text":"руддщ"},{"kind":"boundary","text":"\n"}]"#.utf8))
        XCTAssertEqual(Replay.run(events).text, "привет hello\n")
        XCTAssertEqual(Replay.run(events).reasons, ["layout", "layout"])
        XCTAssertEqual(Replay.run(events, context: .init(secure: true)).text, "ghbdtn руддщ\n")
        let reset = try JSONDecoder().decode([ReplayEvent].self, from: Data(#"[{"kind":"text","text":"secret"},{"kind":"reset"},{"kind":"text","text":"next"}]"#.utf8))
        XCTAssertEqual(Replay.run(reset).text, "next")
    }
}
