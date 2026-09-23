import AppKit
import Carbon
import ApplicationServices

struct TextState: Equatable {
    let value: String
    let range: CFRange
    static func ==(a: Self,b: Self) -> Bool {a.value==b.value && a.range.location==b.range.location && a.range.length==b.range.length}
}
struct NativeContext {
    let identity: String
    let bundle: String
    let layout: String
    let element: AXUIElement?
    let secure: Bool
    let permitted: Bool
    var usable: Bool {permitted && !secure && !bundle.isEmpty && (layout=="us" || layout=="ru")}
}
enum Native {
    static func attribute(_ element: AXUIElement,_ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success else {return nil}
        return value
    }
    static func sourceID(_ source: TISInputSource) -> String {
        guard let raw=TISGetInputSourceProperty(source,kTISPropertyInputSourceID) else {return ""}
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
    static func inputSource() -> (String,String) {
        // macOS 27 enforces the main queue for Text Input Source APIs.
        if !Thread.isMainThread {return DispatchQueue.main.sync {inputSource()}}
        guard let source=TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {return ("","")}
        let id=sourceID(source)
        return (id,languageCode(source,id:id))
    }
    /// Map a TIS source to `us` / `ru` (or empty when unknown).
    /// Accepts common macOS layout names, not only ABC / RussianWin.
    static func languageCode(_ source: TISInputSource, id: String) -> String {
        switch id {
        case "com.apple.keylayout.ABC", "com.apple.keylayout.US", "com.apple.keylayout.USExtended-Software":
            return "us"
        case "com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian-Phonetic":
            return "ru"
        default:
            break
        }
        if let raw=TISGetInputSourceProperty(source,kTISPropertyLocalizedName) {
            let name=(Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String).lowercased()
            if name.contains("russian") || name.contains("рус") { return "ru" }
            if name.contains("u.s.") || name.contains("abc") || name == "us" || name.contains("qwerty") { return "us" }
        }
        if let raw=TISGetInputSourceProperty(source,kTISPropertyInputSourceLanguages),
           let langs=Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String],
           let first=langs.first {
            if first.hasPrefix("ru") { return "ru" }
            if first.hasPrefix("en") { return "us" }
        }
        return ""
    }
    static func context() -> NativeContext {
        let permitted=CGPreflightListenEventAccess() && CGPreflightPostEventAccess() && AXIsProcessTrusted()
        let source=inputSource()
        guard let app=NSWorkspace.shared.frontmostApplication else {return NativeContext(identity:"",bundle:"",layout:source.1,element:nil,secure:true,permitted:permitted)}
        let ax=AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax,0.05)
        var element: AXUIElement?
        if let raw=attribute(ax,kAXFocusedUIElementAttribute),CFGetTypeID(raw)==AXUIElementGetTypeID() {element=(raw as! AXUIElement)}
        if let element {AXUIElementSetMessagingTimeout(element,0.05)}
        let subrole=element.flatMap{attribute($0,kAXSubroleAttribute)} as? String
        let secure=IsSecureEventInputEnabled() || subrole==kAXSecureTextFieldSubrole
        let identity="\(app.processIdentifier):\(element.map{CFHash($0)} ?? 0):\(source.0)"
        return NativeContext(identity:identity,bundle:app.bundleIdentifier ?? "",layout:source.1,element:element,secure:secure,permitted:permitted)
    }
    static func text(_ context: NativeContext) -> TextState? {
        guard let element=context.element,
              let value=attribute(element,kAXValueAttribute) as? String, value.utf8.count <= 131072,
              let raw=attribute(element,kAXSelectedTextRangeAttribute),CFGetTypeID(raw)==AXValueGetTypeID() else {return nil}
        let axValue=raw as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {return nil}
        var range=CFRange(); guard AXValueGetValue(axValue,.cfRange,&range), range.location>=0, range.length>=0,range.location+range.length<=value.utf16.count else {return nil}
        return TextState(value:value,range:range)
    }
    static func select(_ mode: String) -> Bool {
        if !Thread.isMainThread {return DispatchQueue.main.sync {select(mode)}}
        // Prefer the classic pair; fall back to any enabled source with that language.
        let preferred=mode=="us" ? "com.apple.keylayout.ABC":"com.apple.keylayout.RussianWin"
        var candidates=[preferred]
        if mode=="us" { candidates += ["com.apple.keylayout.US"] }
        else { candidates += ["com.apple.keylayout.Russian","com.apple.keylayout.Russian-Phonetic"] }
        for id in candidates {
            if let sources=TISCreateInputSourceList([kTISPropertyInputSourceID as String:id] as CFDictionary,false)?.takeRetainedValue() as? [TISInputSource],
               let source=sources.first,
               TISSelectInputSource(source)==noErr && inputSource().1==mode {
                return true
            }
        }
        return false
    }
    static func modifiersHeld() -> Bool {
        !CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift,.maskCommand,.maskControl,.maskAlternate]).isEmpty
    }
    static func keyboardEvents(_ code: CGKeyCode, unicode: String? = nil) -> (CGEvent, CGEvent)? {
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else {return nil}
        for event in [down,up] {
            event.flags=[];event.setIntegerValueField(.eventSourceUserData,value:ownMarker)
        }
        if let unicode {
            let units=Array(unicode.utf16)
            down.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)
        }
        return (down,up)
    }
    static func pair(_ code: CGKeyCode, unicode: String? = nil) -> Bool {
        guard let (down,up)=keyboardEvents(code,unicode:unicode) else {return false}
        down.post(tap:.cgSessionEventTap);up.post(tap:.cgSessionEventTap)
        Thread.sleep(forTimeInterval:0.003)
        return true
    }
}
