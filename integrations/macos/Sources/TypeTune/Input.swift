import AppKit
import Carbon
import Synchronization

let ownMarker: Int64 = 0x5459504554554e45
struct KeyObservation {
    let key: String
    let action: String
    let text: String?
    let time: UInt64
    let modifiers: UInt32
    let revision: UInt64
    let origin: String
}
final class InputBuffer {
    // One producer (tap run loop), one consumer (runtime queue). Release/acquire
    // hands each slot over without ever blocking or dropping a callback on a reader.
    private let capacity: UInt64 = 256
    private let slots = UnsafeMutablePointer<KeyObservation?>.allocate(capacity:256)
    private let head = Atomic<UInt64>(0)
    private let tail = Atomic<UInt64>(0)
    private let revision = Atomic<UInt64>(0)
    init() {slots.initialize(repeating:nil,count:256)}
    deinit {slots.deinitialize(count:256);slots.deallocate()}
    private let lost = Atomic<Bool>(false)
    let accepting = Atomic<Bool>(false)
    func push(_ event: CGEvent, type: CGEventType) {
        guard accepting.load(ordering:.relaxed), event.getIntegerValueField(.eventSourceUserData) != ownMarker else { return }
        var stamp=revision.load(ordering:.relaxed)
        if type != .keyUp {stamp &+= 1;revision.store(stamp,ordering:.releasing)}
        let write=head.load(ordering:.relaxed)
        guard write &- tail.load(ordering:.acquiring) < capacity else {lost.store(true,ordering:.releasing);return}
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var modifiers: UInt32 = flags.contains(.maskShift) ? 1 : 0
        // Caps Lock is a latch, not a chord; treating it as modifiers&2 wipes history.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { modifiers |= 2 }
        var key = "mac:\(code)"
        var action = type == .keyUp ? "up" : (event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? "repeat" : "down")
        var text: String?
        if type == .flagsChanged {
            if code == 56 || code == 60 {
                key = code == 56 ? "left_shift" : "right_shift"
                // Prefer device-dependent bits when present (tests + some OS builds);
                // otherwise HID key state (device bits are not reliable everywhere).
                let deviceBit: UInt64 = code == 56 ? 0x2 : 0x4
                let raw = flags.rawValue
                if raw & 0x6 != 0 {
                    action = raw & deviceBit != 0 ? "down" : "up"
                } else {
                    action = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code)) ? "down" : "up"
                }
            } else if code == 57 || code == 63 {
                // Caps / Fn — often used as layout switch. Not a text key and must
                // not wipe keyboard history (`key="context"` resets the runtime).
                key = "lock_key"
                action = "up"
            } else { key="context" }
        } else if type == .keyDown || type == .keyUp {
            if code == 51 { key="backspace" }
            else if code == 49 { key="space" }
            else {
                var chars=[UniChar](repeating:0,count:16); var length=0
                event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
                if length > 0 && length < chars.count { text=String(utf16CodeUnits: chars, count:length) }
            }
        } else { key="context" }
        let origin=event.getIntegerValueField(.eventSourceUnixProcessID)==0 ? "physical":"unknown"
        slots[Int(write % capacity)] = KeyObservation(key:key,action:action,text:text,time:event.timestamp/1_000_000,modifiers:modifiers,revision:stamp,origin:origin)
        head.store(write &+ 1,ordering:.releasing)
    }
    func invalidate() { lost.store(true,ordering:.relaxed) }
    func drain() -> ([KeyObservation], Bool) {
        var read=tail.load(ordering:.relaxed)
        let end=head.load(ordering:.acquiring)
        var batch:[KeyObservation]=[]
        batch.reserveCapacity(Int(end &- read))
        while read != end {
            let index=Int(read % capacity)
            if let event=slots[index] {batch.append(event)}
            slots[index]=nil
            read &+= 1
            tail.store(read,ordering:.releasing)
        }
        return (batch,lost.exchange(false,ordering:.acquiringAndReleasing))
    }
    func currentRevision() -> UInt64 {lost.load(ordering:.acquiring) ? UInt64.max : revision.load(ordering:.acquiring)}
}
final class Observer {
    let buffer=InputBuffer()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private let stateLock=NSLock()
    private var active=false
    /// Set from the tap callback (no lock) when macOS disables the tap.
    private let needsReenable=Atomic<Bool>(false)
    var isActive: Bool {stateLock.lock();defer{stateLock.unlock()};return active}
    func start() {
        stateLock.lock();guard !active else {stateLock.unlock();return};active=true;stateLock.unlock()
        Thread.detachNewThread { [self] in
            let types:[CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            let mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }
            let callback: CGEventTapCallBack = { _,type,event,ref in
                let observer=Unmanaged<Observer>.fromOpaque(ref!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Never lock here: recover() may hold stateLock and call tapEnable.
                    observer.buffer.invalidate()
                    observer.needsReenable.store(true,ordering:.releasing)
                } else { observer.buffer.push(event,type:type) }
                return Unmanaged.passUnretained(event)
            }
            guard let port=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.tailAppendEventTap,options:.listenOnly,eventsOfInterest:mask,callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque()) else {
                stateLock.lock();active=false;stateLock.unlock();buffer.invalidate();return
            }
            let runloop=CFRunLoopGetCurrent()!
            let source=CFMachPortCreateRunLoopSource(nil,port,0)!
            stateLock.lock();tap=port;self.source=source;loop=runloop;let shouldRun=active;stateLock.unlock()
            if shouldRun { CFRunLoopAddSource(runloop,source,.commonModes);CGEvent.tapEnable(tap:port,enable:true);CFRunLoopRun() }
            CFMachPortInvalidate(port)
            stateLock.lock();tap=nil;self.source=nil;loop=nil;active=false;stateLock.unlock()
        }
    }
    func recover() -> Bool {
        stateLock.lock();let port=tap;stateLock.unlock()
        guard let port else {return false}
        let flagged=needsReenable.exchange(false,ordering:.acquiringAndReleasing)
        if flagged || !CGEvent.tapIsEnabled(tap:port) {
            buffer.invalidate()
            CGEvent.tapEnable(tap:port,enable:true)
            return false
        }
        return true
    }
    func stop() {
        stateLock.lock();active=false;let current=loop;stateLock.unlock()
        if let current {CFRunLoopStop(current)}
        buffer.invalidate()
    }
}
