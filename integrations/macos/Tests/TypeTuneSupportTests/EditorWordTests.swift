import Foundation
import Testing
@testable import TypeTuneSupport

struct EditorWordTests {
    @Test(arguments: ["\u{00A0}", " \u{00A0}", "\u{00A0} ", "\u{00A0}\u{00A0}"])
    func editorRenderedSpacesRemainExact(tail: String) {
        let before = "frr" + tail
        let replacement = "акк" + tail
        let prefix = "😀\n"
        let value = prefix + before + "end"
        let caret = (prefix + before).utf16.count
        #expect(EditorWord.beforeCaret(in: value, selection: NSRange(location: caret, length: 0)) == before)
        let edit = EditorWord.prepare(before: before, replacement: replacement,
            in: value, selection: NSRange(location: caret, length: 0))
        #expect(edit?.range == NSRange(location: prefix.utf16.count, length: before.utf16.count))
        #expect(edit?.expected == prefix + replacement + "end")
        #expect(edit?.caret == caret)
        let ascii = "frr" + String(repeating: " ", count: tail.count)
        #expect(!EditorWord.matches(ascii, in: value, selection: NSRange(location: caret, length: 0)))
    }

    @Test func onlyASCIISpaceAndNBSPMayFormTheEditableTail() {
        #expect(!EditorWord.matches("frr\u{00A0}", in: "frr ", selection: NSRange(location: 4, length: 0)))
        #expect(EditorWord.beforeCaret(in: "prefix\u{00A0}frr\u{00A0}", selection: NSRange(location: 11, length: 0)) == "frr\u{00A0}")
        #expect(EditorWord.beforeCaret(in: "frr\t", selection: NSRange(location: 4, length: 0)) == nil)
        #expect(EditorWord.beforeCaret(in: "frr\u{202F}", selection: NSRange(location: 4, length: 0)) == nil)
        #expect(EditorWord.beforeCaret(in: "\u{00A0} ", selection: NSRange(location: 2, length: 0)) == nil)
    }

    @Test func exactWhitespaceBeforeAnyOutput() {
        #expect(!EditorWord.matches("frr ",in:"frr",selection:NSRange(location:3,length:0)))
        #expect(!EditorWord.matches("frr ",in:"frr  ",selection:NSRange(location:5,length:0)))
        #expect(EditorWord.prepare(before:"frr ",replacement:"акк ",in:"frr",selection:NSRange(location:3,length:0)) == nil)
        #expect(EditorWord.prepare(before:"frr ",replacement:"акк ",in:"frr  ",selection:NSRange(location:5,length:0)) == nil)
        #expect(EditorWord.prepare(before:"frr ",replacement:"акк ",in:"frr x",selection:NSRange(location:5,length:0)) == nil)
        let edit = EditorWord.prepare(before:"frr  ",replacement:"акк  ",in:"😀\nfrr  end",selection:NSRange(location:8,length:0))
        #expect(edit?.range == NSRange(location:3,length:5))
        #expect(edit?.expected == "😀\nакк  end")
        #expect(edit?.caret == 8)
    }
    @Test func partialHistoryCannotAuthorizeSuffixReplacement() {
        #expect(!EditorWord.matches("r",in:"frr",selection:NSRange(location:3,length:0)))
        #expect(!EditorWord.matches("r ",in:"frr ",selection:NSRange(location:4,length:0)))
        #expect(EditorWord.matches("frr",in:"frr",selection:NSRange(location:3,length:0)))
        // Auto (Space): engine `before` has a trailing delimiter; AX token does not.
        #expect(EditorWord.matches("frr ",in:"frr ",selection:NSRange(location:4,length:0)))
        #expect(EditorWord.matches("frr ",in:"prefix frr ",selection:NSRange(location:11,length:0)))
        #expect(EditorWord.beforeCaret(in:"prefix frr suffix",selection:NSRange(location:10,length:0)) == "frr")
    }
    @Test func boundariesSelectionAndUnicode() {
        #expect(EditorWord.beforeCaret(in:"frr",selection:NSRange(location:2,length:0)) == nil)
        #expect(EditorWord.beforeCaret(in:"frr",selection:NSRange(location:0,length:3)) == nil)
        #expect(EditorWord.beforeCaret(in:"frr  ",selection:NSRange(location:5,length:0)) == "frr  ")
        #expect(EditorWord.beforeCaret(in:"😀\nfrr ",selection:NSRange(location:7,length:0)) == "frr ")
        #expect(EditorWord.beforeCaret(in:"😀frr",selection:NSRange(location:1,length:0)) == nil)
        #expect(EditorWord.beforeCaret(in:" ",selection:NSRange(location:1,length:0)) == nil)
        #expect(EditorWord.beforeCaret(in:"frr",selection:NSRange(location:4,length:0)) == nil)
    }
}
