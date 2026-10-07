import AppKit
import Carbon
import ApplicationServices

/// Carbon documents IsSecureEventInputEnabled as not thread safe. Serialize
/// our reads without making the input callback wait for a different reader.
/// Contention is conservatively treated as Secure Input until the next check.
enum SecureInputStatus {case disabled,enabled,busy}
final class SecureInputReader {
    static let shared=SecureInputReader(read:{IsSecureEventInputEnabled()})
    private let lock=NSLock()
    private let read:()->Bool
    init(read:@escaping ()->Bool) {self.read=read}
    func snapshot() -> SecureInputStatus {
        guard lock.try() else {return .busy}
        defer {lock.unlock()}
        return read() ? .enabled:.disabled
    }
    func isEnabled() -> Bool {snapshot() != .disabled}
}

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
    var sourceID: String = ""
    var pid: pid_t { pid_t(identity.split(separator: ":").first ?? "") ?? 0 }
    var usableOverride: Bool? = nil
    var permissionIssue: String? = nil
    var usable: Bool {
        if secure { return false }
        if let usableOverride { return usableOverride }
        return permitted && !secure && !bundle.isEmpty && (layout=="us" || layout=="ru")
    }
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
    /// Only layouts whose physical alphabet matches the engine's RU/EN pair.
    /// A language name alone does not prove a compatible keyboard mapping.
    static func languageCode(_ source: TISInputSource, id: String) -> String {
        switch id {
        case "com.apple.keylayout.ABC", "com.apple.keylayout.US":
            return "us"
        case "com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin":
            return "ru"
        default:
            break
        }
        return ""
    }
    static func context(activeKeyboards: [String]? = nil) -> NativeContext {
        let permitted=CGPreflightListenEventAccess() && CGPreflightPostEventAccess() && AXIsProcessTrusted()
        let source=inputSource()
        guard let app=NSWorkspace.shared.frontmostApplication else {return NativeContext(identity:"",bundle:"",layout:source.1,element:nil,secure:true,permitted:permitted)}
        let ax=AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax,0.05)
        var element: AXUIElement?
        if let raw=attribute(ax,kAXFocusedUIElementAttribute),CFGetTypeID(raw)==AXUIElementGetTypeID() {element=(raw as! AXUIElement)}
        if let element {AXUIElementSetMessagingTimeout(element,0.05)}
        let subrole=element.flatMap{attribute($0,kAXSubroleAttribute)} as? String
        // Global Secure Input is a conservative gate even when AX returns an
        // element: an unknown/custom secure field must not authorize replay.
        let elementSecure = subrole == kAXSecureTextFieldSubrole
        let secure = elementSecure || SecureInputReader.shared.isEnabled()
        let usable = permitted && !secure && !(app.bundleIdentifier ?? "").isEmpty && (source.1=="us" || source.1=="ru") && (activeKeyboards?.contains(source.0) ?? true)
        let identity="\(app.processIdentifier):\(element.map{CFHash($0)} ?? 0)"
        return NativeContext(identity:identity,bundle:app.bundleIdentifier ?? "",layout:source.1,element:element,secure:secure,permitted:permitted,sourceID:source.0,usableOverride:usable)
    }
    /// Key-history context; no editor AX round trips. Identity denotes the
    /// intended foreground application, not proof of an editor field.
    static func historyContext(activeKeyboards: [String], permissions: ObserverPermissions? = nil) -> NativeContext {
        HIDKeyboardLayout.shared.refresh()
        let permissions=permissions ?? ObserverPermissions.current()
        let source=inputSource()
        let app=NSWorkspace.shared.frontmostApplication
        let secure=SecureInputReader.shared.isEnabled()
        let permitted=permissions.listen && permissions.post && permissions.accessibility
        return NativeContext(identity:"\(app?.processIdentifier ?? 0):history",
            bundle:app?.bundleIdentifier ?? "",layout:source.1,element:nil,
            secure:secure,permitted:permitted,sourceID:source.0,
            usableOverride:permitted && !secure && app != nil &&
                activeKeyboards.contains(source.0) && ["us","ru"].contains(source.1),
            permissionIssue: !permissions.listen ? "listen_access":
                (!permissions.accessibility ? "accessibility_access":(!permissions.post ? "post_access":nil)))
    }
    static func text(_ context: NativeContext) -> TextState? {
        text(context,timeout:0.05)
    }
    static func text(_ context: NativeContext, timeout: Float) -> TextState? {
        guard let element=context.element else {return nil}
        AXUIElementSetMessagingTimeout(element,timeout)
        // One editor round trip for value and selection. Separate reads can
        // describe different frames while the editor handles a layout change.
        var result: CFArray?
        let names=[kAXValueAttribute,kAXSelectedTextRangeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element,names,AXCopyMultipleAttributeOptions(rawValue:0),&result) == .success,
              let values=result as? [Any],values.count==2,
              let value=values[0] as? String,value.utf8.count<=131072 else {return nil}
        let raw=values[1] as CFTypeRef
        guard CFGetTypeID(raw)==AXValueGetTypeID() else {return nil}
        let axValue=raw as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {return nil}
        var range=CFRange(); guard AXValueGetValue(axValue,.cfRange,&range), range.location>=0, range.length>=0,range.location<=value.utf16.count,range.length<=value.utf16.count-range.location else {return nil}
        return TextState(value:value,range:range)
    }
    static func select(_ mode: String) -> Bool {select(mode,activeKeyboards:nil)}
    static func select(_ mode: String, activeKeyboards: [String]?) -> Bool {
        if !Thread.isMainThread {return DispatchQueue.main.sync {select(mode,activeKeyboards:activeKeyboards)}}
        guard mode == "us" || mode == "ru" else {return false}
        // Prefer the classic pair; fall back to any enabled source with that language.
        let preferred=mode=="us" ? "com.apple.keylayout.ABC":"com.apple.keylayout.RussianWin"
        var candidates=[preferred]
        if mode=="us" { candidates += ["com.apple.keylayout.US"] }
        else { candidates += ["com.apple.keylayout.Russian"] }
        if let activeKeyboards { candidates = activeKeyboards.filter { candidates.contains($0) } }
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
    /// Caps Lock / Fn used as layout switch (or latched Caps) must not block
    /// the held-key wait — `keyState` for 57 stays true while Caps is on.
    static func typingKeyHeld() -> Bool {
        let locks: Set<CGKeyCode> = [57, 63]
        return (0..<128).contains { code in
            let key = CGKeyCode(code)
            return !locks.contains(key) && CGEventSource.keyState(.hidSystemState, key: key)
        }
    }
    static func keyboardEvents(_ code: CGKeyCode, unicode: String? = nil, flags: CGEventFlags = [],
                               source suppliedSource: CGEventSource? = nil) -> (CGEvent, CGEvent)? {
        guard let source=suppliedSource ?? CGEventSource(stateID:.privateState) else {return nil}
        source.localEventsSuppressionInterval = 0
        source.userData=ownMarker
        guard let down=CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:true),let up=CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:false) else {return nil}
        for event in [down,up] {
            event.flags=flags;event.setIntegerValueField(.eventSourceUserData,value:ownMarker)
        }
        if let unicode {
            let units=Array(unicode.utf16)
            // Preparation can precede the layout switch. Both edges must carry
            // the same target text rather than a key-up from the old layout.
            for event in [down,up] {event.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)}
        }
        return (down,up)
    }
    /// Modifier edges and their character share one state table. Releasing a
    /// different private source cannot clear a modifier held by the character.
    static func strokeEvents(_ code: CGKeyCode, unicode: String? = nil, flags: CGEventFlags = [],
                             source suppliedSource: CGEventSource? = nil) -> [CGEvent]? {
        guard flags.isEmpty || flags == .maskShift || flags == .maskAlternate,
              let source=suppliedSource ?? CGEventSource(stateID:.privateState),
              let (down,up)=keyboardEvents(code,unicode:unicode,flags:flags,source:source) else {return nil}
        if flags.isEmpty {return [down,up]}
        let modifier:CGKeyCode=flags == .maskShift ? 56:58
        guard let (modifierDown,modifierUp)=keyboardEvents(modifier,flags:flags,source:source) else {return nil}
        modifierDown.type = .flagsChanged;modifierUp.type = .flagsChanged
        modifierUp.flags=[]
        return [modifierDown,down,up,modifierUp]
    }
    static func pair(_ code: CGKeyCode, unicode: String? = nil) -> Bool {
        guard let (down,up)=keyboardEvents(code,unicode:unicode) else {return false}
        // Burst mode: post down/up back-to-back with no inter-pair sleep so the
        // word appears at once instead of "typing". The system queues the events
        // in order; pacing only added visible latency (3ms x N pairs).
        down.post(tap:.cgSessionEventTap);up.post(tap:.cgSessionEventTap)
        return true
    }
}
