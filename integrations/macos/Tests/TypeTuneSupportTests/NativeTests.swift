import CoreGraphics
import Testing
@testable import TypeTune

struct NativeTests {
    func unicode(of event: CGEvent) -> String {
        var chars=[UniChar](repeating:0,count:16); var length=0
        event.keyboardGetUnicodeString(maxStringLength:chars.count,actualStringLength:&length,unicodeString:&chars)
        return String(utf16CodeUnits:chars,count:Int(length))
    }
    @Test func unicodeStringIsSetOnlyOnKeyDown() {
        let pair=Native.keyboardEvents(0,unicode:"я")!
        #expect(unicode(of:pair.0) == "я")
        #expect(unicode(of:pair.1).isEmpty)
        #expect(pair.0.getIntegerValueField(.eventSourceUserData) == ownMarker)
        #expect(pair.1.getIntegerValueField(.eventSourceUserData) == ownMarker)
        let backspace=Native.keyboardEvents(51)
        #expect(backspace != nil)
    }
}
