import Foundation
import Testing
@testable import TypeTuneSupport

struct EditorWordTests {
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
