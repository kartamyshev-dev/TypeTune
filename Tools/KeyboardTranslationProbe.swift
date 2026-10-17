// Readonly synthetic event translation. No posting, activation or input-source changes.
import AppKit
import Carbon
let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let id = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
let russian = ["com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian"].contains(id)
precondition(russian || ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(id), "Unqualified keyboard layout")
let expected = russian ? ["р", "ф", "ж", "1"] : ["h", "a", ";", "1"]
let shifted = russian ? ["Р", "Ф", "Ж", "!"] : ["H", "A", ":", "!"]
var rows:[[String:Any]]=[]
for (index,key) in [CGKeyCode(4),0,41,18].enumerated() {
 let event=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true)!
 var stale:[UniChar] = [120] // Deliberately stale event text, independent of the physical key.
 event.keyboardSetUnicodeString(stringLength:stale.count,unicodeString:&stale)
 let ns=NSEvent(cgEvent:event)!
 let plain=ns.characters(byApplyingModifiers:[]) ?? ""
 let shift=ns.characters(byApplyingModifiers:[.shift]) ?? ""
 rows.append(["keyCode":key,"staleEventCharacters":ns.characters ?? "","plain":plain,"shift":shift,"passed":plain==expected[index] && shift==shifted[index]])
}
print(String(decoding:try JSONSerialization.data(withJSONObject:["source":id,"eventsPosted":0,"rows":rows],options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
if rows.contains(where:{$0["passed"] as? Bool != true}) {exit(1)}
