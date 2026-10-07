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
    /// Diagnostic only — never user text.
    let meta: String
    var sequence: UInt64 = 0
    /// nil is reserved for manually constructed test observations. Captured
    /// keyboard events always carry a value; zero means unknown, never trusted.
    /// HID capture uses the intended foreground PID, not an annotated route.
    var targetPID: pid_t? = nil
}
final class InputBuffer {
    // Capture and deferred replay have separate producers. The short lock only
    // protects ring slots; no native calls, output or I/O run while it is held.
    private let ringLock=NSLock()
    private let sequence=Atomic<UInt64>(0)
    private let capacity: UInt64 = 256
    private let slots = UnsafeMutablePointer<KeyObservation?>.allocate(capacity:256)
    private let head = Atomic<UInt64>(0)
    private let tail = Atomic<UInt64>(0)
    private let revision = Atomic<UInt64>(0)
    private let lastKeyboardTarget=Atomic<Int32>(0)
    init() {slots.initialize(repeating:nil,count:256)}
    deinit {slots.deinitialize(count:256);slots.deallocate()}
    private let lost = Atomic<Bool>(false)
    let accepting = Atomic<Bool>(false)
    private let shiftLock=NSLock()
    private var shiftEdges=ShiftEdges()
    func push(_ event: CGEvent, type: CGEventType) {
        guard let observation=observe(event,type:type) else {return}
        if accepting.load(ordering:.relaxed) {enqueue(observation)}
    }
    /// Activity invalidates a prepared plan even while history capture is paused.
    /// Replay is accounted for on its original arrival, never a second time.
    func observe(_ event: CGEvent, type: CGEventType, intendedPID: pid_t? = nil, keyboardMapping: KeyboardMapping? = nil) -> KeyObservation? {
        guard !isTypeTuneMarker(event.getIntegerValueField(.eventSourceUserData)) else {return nil}
        let keyboard=[CGEventType.keyDown,.keyUp,.flagsChanged].contains(type)
        let target=keyboard ? (intendedPID ?? eventTargetPID(event)):nil
        let routeChanged=target.map {lastKeyboardTarget.exchange($0,ordering:.acquiringAndReleasing) != $0} ?? false
        // A release routed elsewhere invalidates a prepared plan as surely as
        // a new key. Ordinary same-target key-up preserves the held-key fence.
        let stamp = type == .keyUp && !routeChanged ? revision.load(ordering:.acquiring) : revision.wrappingAdd(1,ordering:.acquiringAndReleasing).newValue
        let order=sequence.wrappingAdd(1,ordering:.relaxed).newValue
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shiftCode = type == .flagsChanged && (code==56 || code==60) ? CGKeyCode(code):nil
        shiftLock.lock()
        let shift=shiftEdges.observe(code:shiftCode,shift:flags.contains(.maskShift))
        shiftLock.unlock()
        if shift.discontinuity {lost.store(true,ordering:.releasing)}
        var modifiers: UInt32 = flags.contains(.maskShift) ? 1 : 0
        // Caps Lock is a latch, not a chord; treating it as modifiers&2 wipes history.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { modifiers |= 2 }
        var key = "mac:\(code)"
        var action = type == .keyUp ? "up" : (event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? "repeat" : "down")
        var text: String?
        if type == .flagsChanged {
            if code == 56 || code == 60 {
                if let edge=shift.action {
                    key = code == 56 ? "left_shift" : "right_shift"
                    action=edge
                } else {key="lock_key";action="up"}
            } else {
                // Caps / Fn / Command / Option / Control / globe: not text.
                // Never map these to `context` — the engine resets history on
                // `context` and every modifier edge wiped the current word.
                key = "lock_key"
                action = "up"
            }
        } else if type == .keyDown || type == .keyUp {
            if code == 51 { key="backspace" }
            else if code == 49 { key="space" }
            else {
                if intendedPID != nil {
                    text=keyboardMapping?.text(code:CGKeyCode(code),flags:flags)
                } else {
                    var chars=[UniChar](repeating:0,count:16); var length=0
                    event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
                    if length > 0 && length < chars.count { text=String(utf16CodeUnits: chars, count:length) }
                }
            }
            if intendedPID != nil, [36,48,53,76,115,116,117,119,121,123,124,125,126].contains(code) {
                key="context";text=nil
            }
        } else { key="pointer" }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let hid = CGEventSource(event: event)?.sourceStateID == .hidSystemState
        // HID hardware: pid 0 and/or hidSystemState. A non-zero pid alone is not
        // enough — some builds stamp WindowServer pid on real keys (that marked
        // every keystroke `unknown` and reset history).
        let origin = (pid == 0 || hid) ? "physical" : "unknown"
        return KeyObservation(key:key,action:action,text:text,time:event.timestamp/1_000_000,modifiers:modifiers,revision:stamp,origin:origin,meta:"",sequence:order,targetPID:target)
    }
    func enqueue(_ observation: KeyObservation) {
        ringLock.lock();defer{ringLock.unlock()}
        let write=head.load(ordering:.relaxed)
        guard write &- tail.load(ordering:.relaxed)<capacity else {invalidate();return}
        slots[Int(write % capacity)]=observation
        head.store(write &+ 1,ordering:.releasing)
    }
    func invalidate() {
        shiftLock.lock();shiftEdges.reset();shiftLock.unlock()
        lost.store(true,ordering:.releasing)
    }
    func drain() -> ([KeyObservation], Bool) {
        ringLock.lock();defer{ringLock.unlock()}
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
        return (batch.sorted{$0.sequence<$1.sequence},lost.exchange(false,ordering:.acquiringAndReleasing))
    }
    func currentRevision() -> UInt64 {lost.load(ordering:.acquiring) ? UInt64.max : revision.load(ordering:.acquiring)}
}
final class Observer {
    private static let eventMask:CGEventMask = [CGEventType.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.scrollWheel].reduce(0){$0 | (1 << $1.rawValue)}
    let buffer=InputBuffer()
    private let transport: ObserverTransport
    private let lifecycle: ObserverLifecycleIO
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private let stateLock=NSLock()
    private var active=false
    private var generation: UInt64=0
    private var registeredTapID:UInt32?
    private var nextRegistrationCheck=UInt64.max
    private let needsReenable=Atomic<Bool>(false)
    private let foregroundPID=Atomic<Int32>(0)
    private var focusToken: NSObjectProtocol?
    private let transactionLock=NSLock()
    private var transaction: EditTransaction?
    private var recentTransactions: [UInt64:EditTransaction]=[:]
    private var nextTransaction: UInt64=0
    private let output=DispatchQueue(label:"dev.kartamyshev.TypeTune.output",qos:.userInteractive)
    private let watchdog=DispatchQueue(label:"dev.kartamyshev.TypeTune.input-watchdog",qos:.userInteractive)
    init(transport:ObserverTransport = .live,lifecycle:ObserverLifecycleIO = .live) {
        self.transport=transport;self.lifecycle=lifecycle
    }
    var isActive: Bool {stateLock.lock();defer{stateLock.unlock()};return active}

    func start() {
        stateLock.lock();guard !active else {stateLock.unlock();return}
        active=true;generation &+= 1;let run=generation;stateLock.unlock()
        if lifecycle.observeFocus {foregroundPID.store(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,ordering:.releasing)}
        if lifecycle.observeFocus,focusToken==nil {
            focusToken=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:nil) { [weak self] notification in
                guard let self,let app=notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {return}
                self.foregroundPID.store(app.processIdentifier,ordering:.releasing)
                self.transactionLock.lock();let tx=self.transaction;self.transactionLock.unlock()
                if let tx,tx.targetPID != app.processIdentifier {self.abort(tx,reason:"target_changed")}
                self.buffer.invalidate()
            }
        }
        Thread.detachNewThread { [self] in
            var ownedPort: CFMachPort?
            defer {
                if let ownedPort {lifecycle.invalidate(ownedPort)}
                stateLock.lock()
                let current=generation==run
                if current {
                    tap=nil;source=nil;loop=nil;registeredTapID=nil;nextRegistrationCheck=UInt64.max;active=false
                    // A retiring thread must not discard input collected by
                    // the next generation. Keep cleanup and start serialized.
                    buffer.invalidate()
                }
                stateLock.unlock()
                lifecycle.log("observer_stopped attempt=\(run) stale=\(!current)")
            }
            let mask=Self.eventMask
            let permissions=lifecycle.permissions()
            let diagnostic="pid=\(ProcessInfo.processInfo.processIdentifier) attempt=\(run) \(permissions.diagnostic) mask=\(mask) backend=\(transport.directSession ? "hid_session":"annotated_carrier")"
            lifecycle.log("observer_start \(diagnostic)")
            let callback:CGEventTapCallBack={proxy,type,event,ref in
                Unmanaged<Observer>.fromOpaque(ref!).takeUnretainedValue().receive(event,type:type,proxy:proxy)
            }
            guard let port=lifecycle.createTap(mask,callback,Unmanaged.passUnretained(self).toOpaque()) else {
                lifecycle.log("observer_start_failed reason=tap_create \(diagnostic)")
                return
            }
            ownedPort=port
            let runloop=CFRunLoopGetCurrent()!
            guard let source=lifecycle.createSource(port) else {
                lifecycle.log("observer_start_failed reason=run_loop_source \(diagnostic)");return
            }
            stateLock.lock();let shouldRun=active && generation==run
            if shouldRun {tap=port;self.source=source;loop=runloop};stateLock.unlock()
            if shouldRun {
                CFRunLoopAddSource(runloop,source,.commonModes);lifecycle.enable(port)
                let registration=lifecycle.registration(mask)
                guard let registration,registration.contains(mask),lifecycle.isEnabled(port) else {
                    CFRunLoopRemoveSource(runloop,source,.commonModes)
                    CFRunLoopSourceInvalidate(source)
                    lifecycle.log("observer_start_failed reason=event_mask \(registration?.diagnostic ?? "registration=unknown") \(diagnostic)")
                    return
                }
                stateLock.lock()
                if generation==run {registeredTapID=registration.id;nextRegistrationCheck=lifecycle.now()+1_000_000_000}
                stateLock.unlock()
                // stop/recovery can win between publishing the loop and Run.
                // Check again inside the loop so a stopped generation cannot
                // leave a detached thread waiting on a stale port.
                CFRunLoopPerformBlock(runloop,CFRunLoopMode.commonModes.rawValue) { [self] in
                    stateLock.lock();let current=active && generation==run;stateLock.unlock()
                    if !current {CFRunLoopStop(runloop)}
                }
                lifecycle.log("observer_started \(registration.diagnostic) \(diagnostic)")
                CFRunLoopRun()
            }
        }
    }

    func receive(_ event:CGEvent,type:CGEventType,proxy:CGEventTapProxy? = nil) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            buffer.invalidate();needsReenable.store(true,ordering:.releasing)
            transactionLock.lock();let tx=transaction;transactionLock.unlock()
            if let tx {abort(tx,reason:"tap_lost")}
            return Unmanaged.passUnretained(event)
        }
        let marker=event.getIntegerValueField(.eventSourceUserData)
        if let id=transactionID(marker) {
            transactionLock.lock()
            guard let tx=recentTransactions[id] else {transactionLock.unlock();return nil}
            let carrier = type == .keyUp && event.getIntegerValueField(.keyboardEventKeycode)==Int64(kVK_F20)
            let routedTarget=eventTargetPID(event)
            if carrier,transaction === tx,!tx.released,routedTarget != tx.targetPID {
                tx.failure=tx.failure ?? "carrier_target";tx.outputClosed=true
                tx.acknowledged.signal();transactionLock.unlock();buffer.invalidate();return nil
            }
            let allowed=carrier && routedTarget>0 && routedTarget==tx.targetPID && transaction === tx && !tx.released && !tx.releasing && !tx.outputClosed && tx.failure==nil && foregroundPID.load(ordering:.acquiring)==tx.targetPID && DispatchTime.now().uptimeNanoseconds<tx.deadline
            guard allowed,let prepared=tx.prepared else {
                tx.outputClosed=true;tx.acknowledged.signal();transactionLock.unlock();return nil
            }
            // Secure Input can turn on after worker preflight while the carrier
            // is pending. Reject the whole packet here, never between its edges.
            guard !transport.secureInput() else {
                tx.failure="secure_input";tx.outputClosed=true
                tx.acknowledged.signal();transactionLock.unlock();buffer.invalidate();return nil
            }
            // All expensive work and event allocation happened before this
            // callback. One bounded burst owns the downstream stream: physical
            // callbacks cannot interleave deletes, insertion, and FIFO release.
            tx.outputStarted=true
            for outputEvent in prepared.events {transport.afterTap(outputEvent,proxy)}
            tx.outputAcknowledged=true;tx.outputClosed=true
            releaseLocked(tx,proxy:proxy,atTap:true)
            tx.acknowledged.signal();transactionLock.unlock()
            // F20 key-up is a carrier only, including late/duplicate arrivals.
            return nil
        }
        if marker==ownMarker || marker==replayMarker {return Unmanaged.passUnretained(event)}
        let intendedPID = transport.directSession ? (transport.intendedTarget?() ?? foregroundPID.load(ordering:.acquiring)) : nil
        let mapping=transport.keyboardMapping?()
        guard let observation=buffer.observe(event,type:type,intendedPID:intendedPID,keyboardMapping:mapping) else {return Unmanaged.passUnretained(event)}
        if transport.directSession,mapping==nil,type == .keyDown {
            buffer.invalidate()
            return Unmanaged.passUnretained(event)
        }
        transactionLock.lock()
        if let tx=transaction,!tx.released {
            tx.noteInput(at:DispatchTime.now().uptimeNanoseconds)
            tx.prepared?.noteDeferredInput()
            tx.hadDeferredEvents=true
            let keyCode=event.getIntegerValueField(.keyboardEventKeycode)
            let contextControl = ![CGEventType.keyDown,.keyUp,.flagsChanged].contains(type) || !event.flags.intersection([.maskCommand,.maskControl,.maskAlternate]).isEmpty || (type == .flagsChanged && (keyCode==57 || keyCode==63))
            let routedTarget=intendedPID ?? eventTargetPID(event)
            if contextControl || routedTarget<=0 || routedTarget != tx.targetPID {
                tx.failure=tx.failure ?? (contextControl ? "context_input":"input_target");tx.outputClosed=true
                // Do not admit pointer/control or foreign input into the FIFO.
                // Flush older keys downstream, then return this exact annotated
                // event unchanged, preserving hit-testing and its destination.
                releaseLocked(tx,proxy:proxy,atTap:!transport.directSession)
                tx.acknowledged.signal();transactionLock.unlock()
                buffer.invalidate()
                if buffer.accepting.load(ordering:.relaxed) {buffer.enqueue(observation)}
                return Unmanaged.passUnretained(event)
            }
            if let copy=transport.copy(event) {
                if transport.directSession {copy.setIntegerValueField(.eventTargetUnixProcessID,value:Int64(routedTarget))}
                if eventTargetPID(copy)==routedTarget,
                   tx.queue.append(DeferredInput(event:copy,observation:observation,targetPID:routedTarget)) {
                    transactionLock.unlock();return nil
                }
            }
            // Admission failed: preserve all older events before forwarding this
            // one. No native/engine/context calls or waits occur under the lock.
            tx.failure=tx.failure ?? "fifo_admission";tx.outputClosed=true
            releaseLocked(tx,proxy:proxy,atTap:!transport.directSession)
            tx.acknowledged.signal();transactionLock.unlock()
            buffer.invalidate()
            if buffer.accepting.load(ordering:.relaxed) {buffer.enqueue(observation)}
            return Unmanaged.passUnretained(event)
        }
        transactionLock.unlock()
        if buffer.accepting.load(ordering:.relaxed) {buffer.enqueue(observation)}
        return Unmanaged.passUnretained(event)
    }

    func begin(expectedRevision:UInt64,targetPID:pid_t) -> EditTransaction? {
        guard targetPID>0,transport.targetIsSafe(targetPID),buffer.currentRevision()==expectedRevision else {return nil}
        stateLock.lock();let port=tap;let running=active;stateLock.unlock()
        if let ready=transport.ready {guard ready() else {return nil}}
        else {guard running,let port,CGEvent.tapIsEnabled(tap:port) else {return nil}}
        transactionLock.lock();defer{transactionLock.unlock()}
        guard transaction==nil,buffer.currentRevision()==expectedRevision else {return nil}
        nextTransaction &+= 1
        // Layout/AX preparation may proceed while no user input is waiting.
        // The first intercepted input shortens this to at most 50 ms of hold.
        let tx=EditTransaction(id:nextTransaction,targetPID:targetPID,deadline:DispatchTime.now().uptimeNanoseconds+100_000_000)
        foregroundPID.store(targetPID,ordering:.releasing)
        transaction=tx;recentTransactions[tx.id]=tx
        // Retain old completion identities briefly so late posted events are
        // swallowed instead of being interpreted as unrelated user input.
        recentTransactions=recentTransactions.filter{$0.key &+ 8 >= tx.id || !$0.value.deliveredKeys.isEmpty}
        watch(tx)
        return tx
    }

    private func watch(_ tx:EditTransaction) {
        guard transport.automaticWatchdog else {return}
        watchdog.asyncAfter(deadline:.now() + .milliseconds(2)) { [weak self,weak tx] in
            guard let self,let tx else {return}
            self.transactionLock.lock();let alive=self.transaction === tx && !tx.released;self.transactionLock.unlock()
            guard alive else {return}
            if self.transport.secureInput() {self.abort(tx,reason:"secure_input");return}
            if DispatchTime.now().uptimeNanoseconds>=tx.deadline {self.abort(tx,reason:"commit_timeout");return}
            self.watch(tx)
        }
    }

    private func open(_ tx:EditTransaction) -> Bool {
        transactionLock.lock();defer{transactionLock.unlock()}
        return transaction === tx && !tx.released && tx.failure==nil && DispatchTime.now().uptimeNanoseconds<tx.deadline
    }
    func commit(_ tx:EditTransaction,prepared:PreparedReplacement,initiallyValidated:Bool = false,validateBeforeOutput:()->Bool) -> NativeCommitResult {
        // Output is already downstream of annotation when the carrier arrives.
        // Bind only our prepared events, never the carrier or captured input.
        for event in prepared.events {event.setIntegerValueField(.eventTargetUnixProcessID,value:Int64(tx.targetPID))}
        transactionLock.lock();tx.prepared=prepared
        if !prepared.events.allSatisfy({eventTargetPID($0)==tx.targetPID}) {tx.failure="output_target"}
        if tx.hadDeferredEvents {prepared.noteDeferredInput()}
        transactionLock.unlock()
        guard open(tx) else {return result(tx,fallback:"closed_before_layout")}
        if !initiallyValidated && !validateBeforeOutput() {return result(tx,fallback:"validation_before_layout")}
        guard transport.targetIsSafe(tx.targetPID) else {return result(tx,fallback:"target_before_layout")}
        guard transport.select(prepared,tx.deadline,{[weak self,weak tx] in
            guard let self,let tx else {return false};return self.open(tx)
        }) else {
            transactionLock.lock();tx.failure=tx.failure ?? "layout_selection";transactionLock.unlock()
            transport.restore(prepared);return result(tx,fallback:"layout_selection")
        }
        transactionLock.lock();tx.selected=true;transactionLock.unlock()
        guard open(tx) else {return result(tx,fallback:"closed_after_layout")}
        guard validateBeforeOutput() else {return result(tx,fallback:"validation_after_layout")}
        guard transport.targetIsSafe(tx.targetPID) else {return result(tx,fallback:"target_after_layout")}
        if transport.directSession {
            DispatchQueue.main.async { [self] in
                output.sync {
                    guard transport.targetIsSafe(tx.targetPID), !transport.secureInput() else {
                        abort(tx,reason:"session_target_or_secure");return
                    }
                    transactionLock.lock()
                    guard transaction === tx,!tx.released,tx.failure==nil,
                          DispatchTime.now().uptimeNanoseconds<tx.deadline else {
                        tx.acknowledged.signal();transactionLock.unlock();return
                    }
                    tx.outputStarted=true
                    for event in prepared.events {transport.post(event)}
                    tx.outputAcknowledged=true;tx.outputClosed=true
                    releaseLocked(tx,proxy:nil,atTap:false)
                    tx.acknowledged.signal();transactionLock.unlock()
                }
            }
        } else { output.sync {
            guard self.open(tx) else {return}
            guard self.transport.carrierIsSafe(),let carrier=prepared.carrier else {
                self.transactionLock.lock();tx.failure="carrier_unavailable";tx.outputClosed=true;tx.acknowledged.signal();self.transactionLock.unlock();return
            }
            carrier.flags=[]
            guard markEvent(carrier,transactionMarker(tx.id,final:true)) else {
                self.transactionLock.lock();tx.failure="carrier_marker";tx.outputClosed=true;tx.acknowledged.signal();self.transactionLock.unlock();return
            }
            self.transport.post(carrier)
        } }
        let now=DispatchTime.now().uptimeNanoseconds
        let completed=now<tx.deadline && tx.acknowledged.wait(timeout:.now()+Double(tx.deadline-now)/1_000_000_000) == .success
        if !completed {
            transactionLock.lock();tx.failure=tx.failure ?? "delivery_timeout";tx.outputClosed=true;transactionLock.unlock()
        }
        return result(tx,fallback:"delivery_timeout")
    }
    private func result(_ tx:EditTransaction,fallback:String) -> NativeCommitResult {
        transactionLock.lock()
        if !tx.outputAcknowledged || tx.failure != nil {tx.outputClosed=true}
        let restore = !tx.outputStarted ? tx.prepared:nil
        transactionLock.unlock()
        // Also covers expiry after validation but before the output queue runs.
        // Restoring an unclaimed or already-restored selection is a no-op.
        if let restore {transport.restore(restore)}
        transactionLock.lock();defer{transactionLock.unlock()}
        let ok=tx.outputAcknowledged && tx.failure==nil
        let uncertainRollback=tx.prepared?.rollbackInputWasUncertain() ?? false
        return NativeCommitResult(outcome:ok ? "submitted":(tx.outputStarted || uncertainRollback ? "indeterminate":"rejected"),reason:ok ? "stream_ack":(uncertainRollback ? "layout_during_input_release":(tx.failure ?? fallback)),revisionAfterCommit:buffer.currentRevision(),hadDeferredEvents:tx.hadDeferredEvents)
    }
    /// Called immediately after commit; AX verification happens after this.
    func finish(_ tx:EditTransaction) {output.sync{self.release(tx)}}
    func abort(_ tx:EditTransaction,reason:String) {
        transactionLock.lock()
        guard !tx.released,transaction === tx else {transactionLock.unlock();return}
        tx.failure=tx.failure ?? reason;tx.outputClosed=true;tx.acknowledged.signal();transactionLock.unlock()
        buffer.invalidate()
        output.async{[weak self] in self?.release(tx)}
    }
    private func release(_ tx:EditTransaction) {
        transactionLock.lock();defer{transactionLock.unlock()}
        releaseLocked(tx,proxy:nil,atTap:false)
    }
    /// The delivery lock covers the small bounded native-post burst. In the
    /// exceptional watchdog/overflow path a callback may wait for this burst,
    /// but never for AX, TIS, the engine or disk. No older batch is detached and
    /// delivered concurrently with a newer overflow batch.
    private func releaseLocked(_ tx:EditTransaction,proxy:CGEventTapProxy?,atTap:Bool) {
        guard !tx.released else {return}
        tx.outputClosed=true;tx.releasing=true
        for up in tx.deliveredKeys.values {
            if atTap {transport.afterTap(up,proxy)} else {transport.replay(up,.process(eventTargetPID(up)))}
        }
        tx.deliveredKeys.removeAll()
        let pending=tx.queue.takeAll()
        let mapping:KeyboardMapping?
        if tx.outputStarted && tx.selected {mapping=tx.prepared?.mapping}
        else {
            // Opening the gate permits new physical input immediately, even
            // when the FIFO is empty. Close layout ownership now so a queued
            // main-thread rollback cannot switch behind that new input.
            mapping=tx.prepared?.releaseWithoutOutput()
        }
        for item in pending {
            let replay=mapping?.replay(item.event) ?? item.event
            _=markEvent(replay,replayMarker)
            if atTap {transport.afterTap(replay,proxy)}
            else if transport.directSession,foregroundPID.load(ordering:.acquiring)==item.targetPID {
                transport.post(replay)
            } else {transport.replay(replay,.process(item.targetPID))}
            buffer.enqueue(replayedObservation(item.observation,event:replay))
        }
        tx.released=true;if transaction === tx {transaction=nil}
    }
    private func replayedObservation(_ original:KeyObservation,event:CGEvent) -> KeyObservation {
        var text=original.text
        if event.type == .keyDown,original.text != nil {
            var units=[UniChar](repeating:0,count:16);var length=0
            event.keyboardGetUnicodeString(maxStringLength:units.count,actualStringLength:&length,unicodeString:&units)
            if length>0,length<=units.count {text=String(utf16CodeUnits:units,count:length)}
        }
        return KeyObservation(key:original.key,action:original.action,text:text,time:original.time,modifiers:original.modifiers,revision:original.revision,origin:original.origin,meta:"",sequence:original.sequence,targetPID:original.targetPID)
    }
    func recover() -> Bool {
        let now=lifecycle.now()
        stateLock.lock();let port=tap;let run=generation;let registeredID=registeredTapID
        let periodicCheck=now>=nextRegistrationCheck
        if periodicCheck {nextRegistrationCheck=now+1_000_000_000}
        stateLock.unlock()
        guard let port,registeredID != nil else {return false}
        guard lifecycle.isValid(port) else {retire(port,generation:run,reason:"invalid_port");return false}
        let flagged=needsReenable.exchange(false,ordering:.acquiringAndReleasing)
        let reenable=flagged || !lifecycle.isEnabled(port)
        if reenable {
            buffer.invalidate() // Runtime alone consumes the discontinuity.
            lifecycle.enable(port)
            guard lifecycle.isValid(port),lifecycle.isEnabled(port) else {
                retire(port,generation:run,reason:"reenable_failed");return false
            }
        }
        if reenable || periodicCheck {
            let registration=lifecycle.registration(Self.eventMask)
            guard let registration,registration.id==registeredID,registration.contains(Self.eventMask) else {
                lifecycle.log("observer_registration_failed \(registration?.diagnostic ?? "registration=unknown") expected_mask=\(Self.eventMask)")
                retire(port,generation:run,reason:"event_mask");return false
            }
            if reenable {lifecycle.log("observer_recovered \(registration.diagnostic) pid=\(ProcessInfo.processInfo.processIdentifier) \(lifecycle.permissions().diagnostic)")}
        }
        stateLock.lock();defer{stateLock.unlock()}
        return active && generation==run
    }
    private func retire(_ port:CFMachPort,generation expected:UInt64,reason:String) {
        stateLock.lock()
        guard generation==expected else {stateLock.unlock();return}
        active=false;generation &+= 1
        let current=loop;tap=nil;source=nil;loop=nil;registeredTapID=nil;nextRegistrationCheck=UInt64.max;stateLock.unlock()
        lifecycle.invalidate(port)
        if let current {CFRunLoopStop(current);CFRunLoopWakeUp(current)}
        transactionLock.lock();let tx=transaction;transactionLock.unlock()
        if let tx {abort(tx,reason:"tap_lost")}
        buffer.invalidate()
        lifecycle.log("observer_restart reason=\(reason) pid=\(ProcessInfo.processInfo.processIdentifier) \(lifecycle.permissions().diagnostic)")
    }
    func stop() {
        transactionLock.lock();let tx=transaction;transactionLock.unlock()
        if let tx {abort(tx,reason:"stopped");finish(tx)}
        stateLock.lock();active=false;generation &+= 1;let current=loop;let port=tap
        tap=nil;source=nil;loop=nil;registeredTapID=nil;nextRegistrationCheck=UInt64.max;stateLock.unlock()
        if let port {lifecycle.invalidate(port)}
        if let current {CFRunLoopStop(current);CFRunLoopWakeUp(current)}
        buffer.invalidate()
    }
}
