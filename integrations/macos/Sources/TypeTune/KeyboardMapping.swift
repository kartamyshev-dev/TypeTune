import AppKit
import Carbon

struct KeyboardStroke: Equatable {
    let code: CGKeyCode
    let flags: CGEventFlags
}

/// TIS translation is prepared on main, never inside the HID callback. Early
/// keyboard packets need not contain the editor's translated Unicode string.
final class HIDKeyboardLayout {
    static let shared=HIDKeyboardLayout()
    private let lock=NSLock()
    private var mapping:KeyboardMapping?
    private var sourceKey=""
    private var token:NSObjectProtocol?
    func refresh() {
        if !Thread.isMainThread {DispatchQueue.main.sync {self.refresh()};return}
        if token==nil {
            token=DistributedNotificationCenter.default().addObserver(
                forName:NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object:nil,queue:.main) { [weak self] _ in self?.refresh() }
        }
        guard let source=TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {return}
        let key="\(Native.sourceID(source)):\(LMGetKbdType())"
        lock.lock();let changed=sourceKey != key;lock.unlock()
        guard changed else {return}
        let translated=KeyboardMapping(source:source)
        lock.lock();mapping=translated;sourceKey=key;lock.unlock()
    }
    func snapshot() -> KeyboardMapping? {
        guard lock.try() else {return nil}
        defer{lock.unlock()}
        return mapping
    }
}

/// Immutable translations captured on the main thread before an edit. No TIS
/// calls are needed when releasing physical keys buffered during a layout change.
struct KeyboardMapping {
    private struct Key: Hashable {let code: CGKeyCode;let flags: UInt64}
    private var characters: [Key:String] = [:]
    private var strokes: [String:KeyboardStroke] = [:]

    init?(source: TISInputSource) {
        guard let raw=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else {return nil}
        let data=Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType=UInt32(LMGetKbdType())
        let combinations: [(CGEventFlags,UInt32)] = [([],0),(.maskShift,UInt32(shiftKey)>>8),(.maskAlphaShift,UInt32(alphaLock)>>8),([.maskShift,.maskAlphaShift],UInt32(shiftKey|alphaLock)>>8),(.maskAlternate,UInt32(optionKey)>>8)]
        data.withUnsafeBytes { bytes in
            guard let layout=bytes.bindMemory(to:UCKeyboardLayout.self).baseAddress else {return}
            for (flags,modifiers) in combinations {
                for code in 0..<128 {
                    // WebKit may represent an ordinary trailing Space as NBSP.
                    // Only the layout's actual Option-Space translation may
                    // produce it; no guessed code or arbitrary Option shortcut.
                    if flags.contains(.maskAlternate), code != kVK_Space { continue }
                    var dead: UInt32=0
                    var units=[UniChar](repeating:0,count:16)
                    var length=0
                    let result=UCKeyTranslate(layout,UInt16(code),UInt16(kUCKeyActionDown),modifiers,keyboardType,OptionBits(kUCKeyTranslateNoDeadKeysMask),&dead,units.count,&length,&units)
                    guard result==noErr, length>0, length<=units.count else {continue}
                    let text=String(utf16CodeUnits:units,count:length)
                    characters[Key(code:CGKeyCode(code),flags:flags.rawValue)]=text
                    // Prefer ordinary key codes, then Shift; never synthesize a
                    // Caps Lock edge to produce a single upper-case character.
                    if !flags.contains(.maskAlphaShift), strokes[text]==nil {
                        strokes[text]=KeyboardStroke(code:CGKeyCode(code),flags:flags)
                    }
                }
            }
        }
        guard !strokes.isEmpty else {return nil}
    }
    // Pure initializer used to test transport independently from installed TIS sources.
    init(entries: [(CGKeyCode,CGEventFlags,String)]) {
        for (code,flags,text) in entries {
            characters[Key(code:code,flags:flags.intersection([.maskShift,.maskAlphaShift,.maskAlternate]).rawValue)]=text
            if strokes[text]==nil {strokes[text]=KeyboardStroke(code:code,flags:flags)}
        }
    }
    func stroke(for character: String) -> KeyboardStroke? {strokes[character]}
    var supportsNativeNonbreakingSpace: Bool {
        stroke(for:"\u{a0}")==KeyboardStroke(code:CGKeyCode(kVK_Space),flags:.maskAlternate)
            && text(code:CGKeyCode(kVK_Space),flags:.maskAlternate)=="\u{a0}"
            && text(code:CGKeyCode(kVK_Space),flags:[])==" "
    }
    func replacementEvents(for text: String, source: CGEventSource? = nil) -> [CGEvent]? {
        guard let stroke=stroke(for:text) else {return nil}
        if text=="\u{a0}" {
            // Validate the actual Option-Space layout before deletion, then use
            // the same CG event factory as the preceding deletes and letters.
            // The prior mixed-factory burst reached Safari out of order after
            // the annotated tap; keep its entire keyboard payload consistent.
            guard supportsNativeNonbreakingSpace else {return nil}
        }
        return Native.strokeEvents(stroke.code,unicode:text,flags:stroke.flags,source:source)
    }
    func text(code: CGKeyCode, flags: CGEventFlags) -> String? {
        characters[Key(code:code,flags:flags.intersection([.maskShift,.maskAlphaShift,.maskAlternate]).rawValue)]
    }
    func replay(_ original: CGEvent) -> CGEvent? {
        guard let event=original.copy(),markEvent(event,replayMarker) else {return nil}
        if (event.type == .keyDown || event.type == .keyUp), event.flags.intersection([.maskCommand,.maskControl,.maskAlternate]).isEmpty,
           let text=text(code:CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),flags:event.flags) {
            let units=Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)
        }
        return event
    }
}

struct PreparedReplacement {
    let events: [CGEvent]
    let sourceID: String
    let mode: String
    let mapping: KeyboardMapping
    let selectAction: ()->Bool
    let restoreAction: ()->Void
    var carrier: CGEvent? = nil
    var noteDeferredInput: ()->Void = {}
    var releaseWithoutOutput: ()->KeyboardMapping? = {nil}
    var rollbackInputWasUncertain: ()->Bool = {false}
    // Explicitly retain the private state table through the whole transaction.
    var eventSource: CGEventSource? = nil
}

extension Native {
    static func prepareReplacement(remove: Int, replacement: String, mode: String, activeKeyboards: [String], sessionHistory: Bool = false) -> PreparedReplacement? {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {prepareReplacement(remove:remove,replacement:replacement,mode:mode,activeKeyboards:activeKeyboards,sessionHistory:sessionHistory)}
        }
        guard (1...128).contains(remove), !replacement.isEmpty, replacement.count<=128,
              !replacement.contains("\0"), mode=="us" || mode=="ru",
              (sessionHistory || !CGEventSource.keyState(.hidSystemState,key:CGKeyCode(kVK_F20))),
              let original=TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              activeKeyboards.contains(sourceID(original)),
              !languageCode(original,id:sourceID(original)).isEmpty,
              let originalMapping=KeyboardMapping(source:original) else {return nil}
        // Events are prepared before selecting the target source. NBSP must
        // have the same native Option-Space semantics in both supported layouts.
        if replacement.contains("\u{a0}"),!originalMapping.supportsNativeNonbreakingSpace {return nil}
        for id in activeKeyboards {
            guard let sources=TISCreateInputSourceList([kTISPropertyInputSourceID as String:id,kTISPropertyInputSourceIsEnabled as String:true] as CFDictionary,false)?.takeRetainedValue() as? [TISInputSource],
                  let source=sources.first, languageCode(source,id:id)==mode,
                  let mapping=KeyboardMapping(source:source) else {continue}
            guard let eventSource=CGEventSource(stateID:sessionHistory ? .combinedSessionState:.privateState) else {return nil}
            var events: [CGEvent]=[]
            for _ in 0..<remove {
                guard let (down,up)=keyboardEvents(51,source:eventSource) else {return nil}
                events += [down,up]
            }
            for character in replacement {
                let text=String(character)
                guard let strokeEvents=mapping.replacementEvents(for:text,source:eventSource) else {return nil}
                events += strokeEvents
            }
            let carrier=sessionHistory ? nil:keyboardEvents(CGKeyCode(kVK_F20))?.1
            if !sessionHistory,carrier==nil {return nil}
            let lease=LayoutSelectionLease(originalID:sourceID(original),targetID:id,
                originalMapping:originalMapping,targetMapping:mapping,
                currentSource:{Native.inputSource().0},
                selectTarget:{
                    let ok=TISSelectInputSource(source)==noErr
                    if sessionHistory {HIDKeyboardLayout.shared.refresh()}
                    return ok
                },
                selectOriginal:{
                    let ok=TISSelectInputSource(original)==noErr
                    if sessionHistory {HIDKeyboardLayout.shared.refresh()}
                    return ok
                })
            return PreparedReplacement(events:events,sourceID:id,mode:mode,mapping:mapping,
                selectAction:lease.select,restoreAction:lease.restore,carrier:carrier,
                noteDeferredInput:lease.noteDeferredInput,releaseWithoutOutput:lease.releaseWithoutOutput,
                rollbackInputWasUncertain:{lease.inputWasUncertain},eventSource:eventSource)
        }
        return nil
    }

    /// The caller's gate has an independent watchdog. A late main-queue block
    /// checks the gate again and cannot switch layouts after its cancellation.
    static func selectPrepared(_ prepared: PreparedReplacement, deadline: UInt64, allowed: @escaping ()->Bool) -> Bool {
        let result=SelectionReply()
        let work={
            guard DispatchTime.now().uptimeNanoseconds<deadline,allowed() else {_=result.complete(false);return}
            let selected=prepared.selectAction()
            if !allowed() || DispatchTime.now().uptimeNanoseconds>=deadline {
                if selected {prepared.restoreAction()}
                _=result.complete(false);return
            }
            if !result.complete(selected),selected {prepared.restoreAction()}
        }
        if Thread.isMainThread {work()} else {DispatchQueue.main.async(execute:work)}
        let now=DispatchTime.now().uptimeNanoseconds
        guard now<deadline, result.ready.wait(timeout:.now()+Double(deadline-now)/1_000_000_000) == .success else {
            if result.cancel() {restorePrepared(prepared)}
            return false
        }
        return result.value
    }
    static func restorePrepared(_ prepared: PreparedReplacement) {
        let work=prepared.restoreAction
        if Thread.isMainThread {work()} else {
            let restored=DispatchSemaphore(value:0)
            DispatchQueue.main.async {work();restored.signal()}
            _=restored.wait(timeout:.now() + .milliseconds(10))
        }
    }
    static func fastTargetIsSafe(_ pid: pid_t) -> Bool {
        targetSafetyFailure(pid)==nil
    }
    /// The same fail-closed decision as the fast Boolean guard, with enough
    /// detail for a worker rejection to distinguish lock contention from OS state.
    static func targetSafetyFailure(_ pid: pid_t,
                                    foregroundPID: ()->pid_t? = {NSWorkspace.shared.frontmostApplication?.processIdentifier},
                                    secureInput: ()->SecureInputStatus = {SecureInputReader.shared.snapshot()}) -> String? {
        guard pid>0 else {return "invalid_pid"}
        guard foregroundPID()==pid else {return "foreground"}
        switch secureInput() {
        case .disabled:return nil
        case .enabled:return "secure_global"
        case .busy:return "secure_busy"
        }
    }
}

/// TIS work remains on main; only the short state snapshots below are shared
/// with the tap/output queues. Never wait for TIS while releasing physical input.
final class LayoutSelectionLease {
    private let originalID:String
    private let targetID:String
    private let originalMapping:KeyboardMapping
    private let targetMapping:KeyboardMapping
    private let currentSource:()->String
    private let selectTarget:()->Bool
    private let selectOriginal:()->Bool
    private let lock=NSLock()
    private var ownsSelection=false
    private var operationInFlight=false
    private var deferredInput=false
    private var inputDelivered=false
    private var uncertainDelivery=false
    private var confirmedMapping:KeyboardMapping?
    init(originalID:String,targetID:String,originalMapping:KeyboardMapping,targetMapping:KeyboardMapping,
         currentSource:@escaping ()->String,selectTarget:@escaping ()->Bool,selectOriginal:@escaping ()->Bool) {
        self.originalID=originalID;self.targetID=targetID
        self.originalMapping=originalMapping;self.targetMapping=targetMapping
        self.currentSource=currentSource;self.selectTarget=selectTarget;self.selectOriginal=selectOriginal
        confirmedMapping=originalMapping
    }
    func noteDeferredInput() {lock.lock();deferredInput=true;lock.unlock()}
    var inputWasUncertain:Bool {
        lock.lock();defer{lock.unlock()}
        return uncertainDelivery || operationInFlight || (deferredInput && confirmedMapping==nil)
    }
    /// Delivery claims the last confirmed layout. Once keys have left the gate,
    /// late cancellation may not switch their layout behind them. An operation
    /// already inside TIS cannot be cancelled: keep raw Unicode and report it.
    func releaseWithoutOutput() -> KeyboardMapping? {
        lock.lock();defer{lock.unlock()}
        inputDelivered=true
        if operationInFlight || confirmedMapping==nil {uncertainDelivery=true;return nil}
        return confirmedMapping
    }
    func select() -> Bool {
        lock.lock()
        guard !inputDelivered else {lock.unlock();return false}
        operationInFlight=true;confirmedMapping=nil;lock.unlock()
        let selected=selectTarget()
        let actual=currentSource()
        lock.lock();defer{lock.unlock()}
        operationInFlight=false
        ownsSelection=selected && actual==targetID
        confirmedMapping=actual==targetID ? targetMapping:(actual==originalID ? originalMapping:nil)
        return selected && actual==targetID
    }
    func restore() {
        lock.lock()
        guard ownsSelection,!inputDelivered else {lock.unlock();return}
        operationInFlight=true;confirmedMapping=nil;lock.unlock()
        // A different source belongs to the user/application. Do not translate
        // queued keys using our old mapping or overwrite their layout choice.
        let actual=currentSource()
        lock.lock()
        guard actual==targetID else {
            ownsSelection=false;operationInFlight=false;confirmedMapping=nil;lock.unlock();return
        }
        guard !inputDelivered else {
            operationInFlight=false;confirmedMapping=targetMapping;lock.unlock();return
        }
        if deferredInput {
            // Keep the selected layout for the queued next word. Restoring now
            // would deliver target Unicode and then silently return to source.
            ownsSelection=false;operationInFlight=false;confirmedMapping=targetMapping;lock.unlock();return
        }
        lock.unlock()
        let restored=selectOriginal()
        let restoredSource=currentSource()
        lock.lock();defer{lock.unlock()}
        ownsSelection=false;operationInFlight=false
        confirmedMapping=restored && restoredSource==originalID ? originalMapping:nil
    }
}

private final class SelectionReply {
    let ready=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var selected=false
    private var cancelled=false
    var value: Bool {lock.lock();defer{lock.unlock()};return selected}
    func complete(_ value: Bool) -> Bool {
        lock.lock();let accepted = !cancelled
        if accepted {selected=value};lock.unlock();ready.signal();return accepted
    }
    func cancel() -> Bool {lock.lock();defer{lock.unlock()};cancelled=true;return selected}
}
