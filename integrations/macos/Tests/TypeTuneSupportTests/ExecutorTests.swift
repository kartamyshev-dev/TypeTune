import Testing
@testable import TypeTuneSupport
struct ExecutorTests {
    final class Editor {
        var text="prefix ghbdtn suffix"
        var caret=13
        var emissions=0
        var pressed=Set<String>()
        func emit(_ action:EditAction)->Bool {
            emissions+=1;pressed.insert("output")
            switch action {
            case .backspace:
                guard caret>0 else {return false}
                text.remove(at:text.index(text.startIndex,offsetBy:caret-1));caret-=1
            case .text(let value):
                text.insert(contentsOf:value,at:text.index(text.startIndex,offsetBy:caret));caret+=value.count
            }
            pressed.remove("output");return true
        }
    }
    @Test func testExactTextCaretAndBalancedKeys() {
        let editor=Editor()
        let result=ReplacementExecutor.run(remove:6,replacement:"привет",guardCheck:{true},emit:editor.emit,verify:{editor.text=="prefix привет suffix" && editor.caret==13})
        #expect(result == .verified);#expect(editor.text == "prefix привет suffix");#expect(editor.caret == 13);#expect(editor.pressed.isEmpty)
    }
    @Test func testBeforeEditRefusalKeepsOriginalAndPartialFailureNeverRetries() {
        let editor=Editor()
        #expect(ReplacementExecutor.run(remove:6,replacement:"привет",guardCheck:{false},emit:editor.emit,verify:{true}) == .rejected)
        #expect(editor.text == "prefix ghbdtn suffix");#expect(editor.emissions == 0)
        #expect(ReplacementExecutor.run(remove:6,replacement:"привет",guardCheck:{editor.emissions<1},emit:editor.emit,verify:{true}) == .indeterminate)
        #expect(editor.text == "prefix ghbdt suffix");#expect(editor.emissions == 1);#expect(editor.pressed.isEmpty)
    }
    @Test func testSuccessfulAPIIsNotVerifiedTextAndUnicodePreservesBoundaries() {
        #expect(ReplacementExecutor.run(remove:1,replacement:"я",guardCheck:{true},emit:{_ in true},verify:{false}) == .indeterminate)
        #expect(ReplacementExecutor.run(remove:1,replacement:"я",guardCheck:{true},emit:{_ in true},verify:{nil}) == .submitted)
        let editor=Editor();editor.text="xA z";editor.caret=2
        #expect(ReplacementExecutor.run(remove:1,replacement:"👩‍💻",guardCheck:{true},emit:editor.emit,verify:{editor.text=="x👩‍💻 z" && editor.caret==2}) == .verified)
    }
}
