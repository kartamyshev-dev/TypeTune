import AppKit
import Carbon
import Testing
@testable import TypeTune

private final class RecordedInput {
    struct Entry {let marker:Int64;let type:CGEventType;let time:UInt64;let text:String;let flags:CGEventFlags;let stateID:Int64;let targetPID:Int64;let code:Int64}
    private let lock=NSLock()
    private var entries:[Entry]=[]
    func append(_ event:CGEvent) {
        var units=[UniChar](repeating:0,count:16);var count=0
        event.keyboardGetUnicodeString(maxStringLength:units.count,actualStringLength:&count,unicodeString:&units)
        let entry=Entry(marker:event.getIntegerValueField(.eventSourceUserData),type:event.type,time:event.timestamp,text:String(utf16CodeUnits:units,count:count),flags:event.flags,stateID:event.getIntegerValueField(.eventSourceStateID),targetPID:event.getIntegerValueField(.eventTargetUnixProcessID),code:event.getIntegerValueField(.keyboardEventKeycode))
        lock.lock();entries.append(entry);lock.unlock()
    }
    var all:[Entry] {lock.lock();defer{lock.unlock()};return entries}
}

private final class ObserverHarness {
    var observer:Observer!
    let delivered=RecordedInput()
    var onPost:((CGEvent)->Void)?
    var onReplay:((CGEvent)->Void)?
    var replayDestinations:[ReplayDestination]=[]
    var delayOwn=false
    var delayed:[CGEvent]=[]
    var copyFails=false
    var selected=false
    var restorations=0
    var delayRestoration=false
    var delayedRestorations:[()->Void]=[]
    var selectionSucceeds=true
    var secureInput=false
    init(watchdog:Bool=false) {
        var transport=ObserverTransport()
        transport.ready={true};transport.targetIsSafe={_ in true}
        transport.secureInput={ [weak self] in self?.secureInput ?? true }
        transport.carrierIsSafe={true}
        transport.automaticWatchdog=watchdog
        transport.copy={ [weak self] event in self?.copyFails == true ? nil:event.copy() }
        transport.post={ [weak self] event in
            guard let self else {return}
            event.setIntegerValueField(.eventTargetUnixProcessID,value:123)
            self.onPost?(event)
            if self.delayOwn {self.delayed.append(event.copy()!);return}
            if let accepted=self.observer.receive(event,type:event.type) {self.delivered.append(accepted.takeUnretainedValue())}
        }
        transport.afterTap={ [weak self] event,_ in self?.delivered.append(event) }
        // This models downstream insertion: replay never needs our session tap
        // callback to return before it can reach the recording destination.
        transport.replay={ [weak self] event,destination in self?.replayDestinations.append(destination);self?.onReplay?(event);self?.delivered.append(event) }
        transport.select={ [weak self] prepared,_,allowed in
            guard let self,allowed() else {return false}
            self.selected=true;return prepared.selectAction() && self.selectionSucceeds
        }
        transport.restore={ [weak self] prepared in
            if let self,self.delayRestoration {self.delayedRestorations.append(prepared.restoreAction);return}
            prepared.restoreAction()
            guard let self,self.selected else {return}
            self.selected=false;self.restorations+=1
        }
        observer=Observer(transport:transport)
        observer.buffer.accepting.store(true,ordering:.relaxed)
    }
    func physical(_ number:UInt64,type:CGEventType = .keyDown,text:String = "a") -> CGEvent {
        let event=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:type != .keyUp)!
        event.type=type;event.flags=[];event.timestamp=number
        event.setIntegerValueField(.eventSourceUserData,value:0)
        event.setIntegerValueField(.eventSourceUnixProcessID,value:0)
        event.setIntegerValueField(.eventTargetUnixProcessID,value:123)
        if type == .keyDown {let units=Array(text.utf16);event.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)}
        return event
    }
    func send(_ event:CGEvent) {
        if let accepted=observer.receive(event,type:event.type) {delivered.append(accepted.takeUnretainedValue())}
    }
    func begin() -> EditTransaction {observer.begin(expectedRevision:observer.buffer.currentRevision(),targetPID:123)!}
    func plan(lease:LayoutSelectionLease? = nil) -> PreparedReplacement {
        let remove=Native.keyboardEvents(51)!,insert=Native.keyboardEvents(0,unicode:"ф")!
        return PreparedReplacement(events:[remove.0,remove.1,insert.0,insert.1],sourceID:"test.ru",mode:"ru",mapping:KeyboardMapping(entries:[(0,[],"ф")]),selectAction:{lease?.select() ?? true},restoreAction:{lease?.restore()},carrier:Native.keyboardEvents(CGKeyCode(kVK_F20))!.1,noteDeferredInput:{lease?.noteDeferredInput()},releaseWithoutOutput:{lease?.releaseWithoutOutput()},rollbackInputWasUncertain:{lease?.inputWasUncertain ?? false})
    }
}

private final class LayoutHarness {
    var source="original"
    var restoreSucceeds=true
    var restoreCalls=0
    var duringSelection:(()->Void)?
    var duringRestoration:(()->Void)?
    func lease() -> LayoutSelectionLease {
        LayoutSelectionLease(originalID:"original",targetID:"target",
            originalMapping:KeyboardMapping(entries:[(0,[],"a")]),
            targetMapping:KeyboardMapping(entries:[(0,[],"ф")]),
            currentSource:{self.source},selectTarget:{self.duringSelection?();self.source="target";return true},
            selectOriginal:{self.restoreCalls+=1;self.duringRestoration?();if self.restoreSucceeds {self.source="original"};return self.restoreSucceeds})
    }
}

struct ObserverTransactionFlowTests {
    @Test func secureInputEnabledAfterPreflightRejectsTheWholePacketAndReleasesFIFOOnce() throws {
        let harness=ObserverHarness()
        var lateCarrier:CGEvent?
        harness.onPost={ event in
            lateCarrier=event.copy()
            harness.secureInput=true
        }
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:harness.plan(),initiallyValidated:true,validateBeforeOutput:{
            harness.send(harness.physical(1,text:"a"))
            harness.send(harness.physical(2,type:.keyUp,text:"a"))
            return true
        })
        #expect(result.outcome=="rejected")
        #expect(result.reason=="secure_input")
        #expect(!tx.outputStarted)
        #expect(harness.delivered.all.isEmpty)
        harness.observer.finish(tx)
        harness.observer.finish(tx)
        harness.send(try #require(lateCarrier))
        let delivered=harness.delivered.all
        #expect(delivered.map(\.time)==[1,2])
        #expect(delivered.allSatisfy{$0.marker==replayMarker && $0.targetPID==123})
        let (observations,lost)=harness.observer.buffer.drain()
        #expect(lost)
        #expect(observations.count==2)
    }
    @Test(arguments:[Int64(0),Int64(999)])
    func carrierDestinationMustMatchBeforeAnyReplacementOutput(target:Int64) {
        let harness=ObserverHarness()
        harness.onPost={$0.setIntegerValueField(.eventTargetUnixProcessID,value:target)}
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{true})
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(harness.delivered.all.isEmpty)
    }
    @Test func replacementOutputCarriesTheValidatedDestination() {
        let harness=ObserverHarness()
        let prepared=harness.plan()
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:prepared,validateBeforeOutput:{true})
        harness.observer.finish(tx)
        #expect(result.outcome=="submitted")
        #expect(harness.delivered.all.count==4)
        #expect(harness.delivered.all.allSatisfy{$0.targetPID==123})
    }
    @Test func nonbreakingTailFollowsDeletesAndLettersInTheCommittedPacket() throws {
        let harness=ObserverHarness()
        let source=try #require(CGEventSource(stateID:.privateState))
        let mapping=KeyboardMapping(entries:[(5,[],"п"),(4,[],"р"),(11,[],"и"),
            (2,[],"в"),(17,[],"е"),(45,[],"т"),(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        var events:[CGEvent]=[]
        for _ in 0..<7 {
            let pair=try #require(Native.keyboardEvents(51,source:source))
            events += [pair.0,pair.1]
        }
        for character in "привет\u{a0}" {
            events += try #require(mapping.replacementEvents(for:String(character),source:source))
        }
        let prepared=PreparedReplacement(events:events,sourceID:"test.ru",mode:"ru",mapping:mapping,
            selectAction:{true},restoreAction:{},carrier:Native.keyboardEvents(CGKeyCode(kVK_F20))!.1,
            eventSource:source)
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:prepared,validateBeforeOutput:{true})
        harness.observer.finish(tx)
        #expect(result.outcome=="submitted")
        let delivered=harness.delivered.all
        try #require(delivered.count==30)
        #expect(delivered.prefix(14).allSatisfy{$0.code==51})
        let expectedLetters=Array("привет").flatMap{[String($0),String($0)]}
        #expect(delivered[14..<26].map(\.text)==expectedLetters)
        #expect(delivered.suffix(4).map(\.type)==[.flagsChanged,.keyDown,.keyUp,.flagsChanged])
        #expect(delivered.suffix(4).map(\.code)==[58,49,49,58])
        #expect(delivered[27].text=="\u{a0}" && delivered[28].text=="\u{a0}")
        #expect(delivered.last?.flags==[])
        #expect(delivered.allSatisfy{$0.targetPID==123 && $0.marker==ownMarker})
        #expect(delivered.allSatisfy{$0.stateID==Int64(source.sourceStateID.rawValue)})
        // This checks the packet supplied to the native transport. Actual
        // AppKit/WebKit delivery order is covered by the guarded DOM acceptance.
        var text="ghbdtn\u{a0}"
        for edge in delivered where edge.type == .keyDown {
            if edge.code==51 {text.removeLast()} else {text += edge.text}
        }
        #expect(text=="привет\u{a0}")
    }
    @Test(arguments:[Int64(0),Int64(999)])
    func foreignInputCancelsBeforeOutputAndRetainsItsOriginalRoute(target:Int64) throws {
        let harness=ObserverHarness()
        let tx=harness.begin()
        let first=harness.physical(1),foreign=harness.physical(2,text:"z")
        foreign.setIntegerValueField(.eventTargetUnixProcessID,value:target)
        let result=harness.observer.commit(tx,prepared:harness.plan(),initiallyValidated:true,validateBeforeOutput:{
            harness.send(first);harness.send(foreign);return true
        })
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        let delivered=harness.delivered.all
        try #require(delivered.count==2)
        #expect(delivered.map(\.time)==[1,2])
        #expect(delivered.map(\.targetPID)==[123,target])
        #expect(delivered.last?.text=="z")
        #expect(delivered.last?.marker==0)
    }
    @Test func watchdogReplayUsesCapturedDestinationDownstream() throws {
        let harness=ObserverHarness(),tx=harness.begin()
        harness.send(harness.physical(1))
        harness.observer.abort(tx,reason:"fixture_timeout")
        harness.observer.finish(tx)
        try #require(harness.replayDestinations.count==1)
        if case .process(let pid)=harness.replayDestinations[0] {#expect(pid==123)}
        else {Issue.record("Replay reentered the global annotation path")}
        #expect(harness.delivered.all.first?.targetPID==123)
    }
    @Test func ownModifierReleasePrecedesQueuedPhysicalModifierAndItsLaterRelease() throws {
        let harness=ObserverHarness()
        let ownSource=try #require(CGEventSource(stateID:.privateState))
        let physicalSource=try #require(CGEventSource(stateID:.privateState))
        let mapping=KeyboardMapping(entries:[(12,.maskShift,"Й")])
        let insertion=try #require(mapping.replacementEvents(for:"Й",source:ownSource))
        let deletion=try #require(Native.keyboardEvents(51,source:ownSource))
        let events=[deletion.0,deletion.1]+insertion
        let prepared=PreparedReplacement(events:events,sourceID:"test.ru",mode:"ru",mapping:mapping,
            selectAction:{true},restoreAction:{},carrier:Native.keyboardEvents(CGKeyCode(kVK_F20))!.1,
            eventSource:ownSource)
        func physicalShift(down:Bool) -> CGEvent {
            let event=CGEvent(keyboardEventSource:physicalSource,virtualKey:56,keyDown:down)!
            event.type = .flagsChanged;event.flags=down ? .maskShift:[]
            event.timestamp=down ? 1:2
            event.setIntegerValueField(.eventSourceUnixProcessID,value:0)
            event.setIntegerValueField(.eventTargetUnixProcessID,value:123)
            return event
        }
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:prepared,initiallyValidated:true,validateBeforeOutput:{
            harness.send(physicalShift(down:true));return true
        })
        harness.observer.finish(tx)
        #expect(result.outcome=="submitted")
        #expect(result.hadDeferredEvents)
        let first=harness.delivered.all
        try #require(first.count==events.count+1)
        #expect(first[events.count-1].flags == [])
        #expect(first.prefix(events.count).allSatisfy{$0.stateID==Int64(ownSource.sourceStateID.rawValue)})
        #expect(first.last?.marker==replayMarker)
        #expect(first.last?.flags == .maskShift)
        #expect(first.last?.stateID==Int64(physicalSource.sourceStateID.rawValue))
        // The physical release occurs after the gate has opened and must clear
        // the same source table that delivered the queued down edge.
        harness.send(physicalShift(down:false))
        let final=harness.delivered.all
        #expect(final.count==events.count+2)
        #expect(final.last?.flags == [])
        #expect(final.last?.stateID==first.last?.stateID)
    }

    @Test func emptyGateReleaseCancelsQueuedRollbackBeforeNewPhysicalInput() throws {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        harness.delayRestoration=true
        let tx=harness.begin()
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),initiallyValidated:true,validateBeforeOutput:{false})
        #expect(result.outcome=="rejected")
        #expect(!result.hadDeferredEvents)
        try #require(harness.delayedRestorations.count==1)
        #expect(layout.source=="target")
        harness.observer.finish(tx)
        // The first key arrives after the empty gate has already opened. Its
        // delivery must prevent the restore that is still queued on main.
        harness.send(harness.physical(1,text:"ф"))
        for restore in harness.delayedRestorations {restore()}
        harness.send(harness.physical(2,text:"ф"))
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["ф","ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф","ф"])
    }
    @Test func emptyReleaseDuringSelectionPreventsAnotherLateLayoutChange() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin()
        layout.duringSelection={harness.observer.finish(tx)}
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{true})
        #expect(result.outcome=="indeterminate")
        #expect(!result.hadDeferredEvents)
        harness.send(harness.physical(1,text:"ф"));lease.restore()
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
    }
    @Test func layoutOperationIsUncertainEvenBeforeFirstDeferredKey() {
        let layout=LayoutHarness(),lease=layout.lease()
        layout.duringSelection={#expect(lease.inputWasUncertain)}
        #expect(lease.select())
        #expect(!lease.inputWasUncertain)
        layout.duringRestoration={#expect(lease.inputWasUncertain)}
        lease.restore()
        #expect(!lease.inputWasUncertain)
        #expect(layout.source=="original")
    }
    @Test func alreadyValidatedPreparationStillChecksAfterLayoutBeforeOutput() {
        let harness=ObserverHarness();let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(),initiallyValidated:true,validateBeforeOutput:{checks+=1;return false})
        harness.observer.finish(tx)
        #expect(checks==1)
        #expect(result.outcome=="rejected")
        #expect(harness.delivered.all.isEmpty)
        #expect(harness.restorations==1)
    }

    @Test func rejectedEditWithQueuedInputKeepsTargetLayoutAndReplaysOnce() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {harness.send(harness.physical(1,text:"ф"));return false}
            return true
        })
        harness.observer.finish(tx);harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="rejected")
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф"])
    }

    @Test func confirmedRollbackRemapsLateTargetUnicodeToOriginalExactlyOnce() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {
                // Created while target was selected, delivered after rollback.
                let late=harness.physical(1,text:"ф")
                lease.restore();harness.send(late);return false
            }
            return true
        })
        harness.observer.finish(tx);harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(layout.source=="original")
        #expect(layout.restoreCalls==1)
        #expect(harness.delivered.all.map{$0.text}==["a"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["a"])
    }

    @Test func failedRollbackDoesNotPretendOriginalMappingWasRestored() {
        let harness=ObserverHarness(),layout=LayoutHarness();layout.restoreSucceeds=false
        let lease=layout.lease(),tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {lease.restore();harness.send(harness.physical(1,text:"ф"));return false}
            return true
        })
        harness.observer.finish(tx)
        #expect(result.outcome=="indeterminate")
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==1)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф"])
    }

    @Test func externalLayoutChangeKeepsRawQueuedInputWithoutRollback() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {layout.source="external";harness.send(harness.physical(1,text:"Ω"));return false}
            return true
        })
        harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="indeterminate")
        #expect(layout.source=="external")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["Ω"])
    }

    @Test func releaseDuringSelectionPreservesRawInputAndForbidsLateRollback() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin()
        layout.duringSelection={
            harness.send(harness.physical(1,text:"ф"))
            // Watchdog may release the gate before the main TIS call returns.
            harness.observer.finish(tx)
        }
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{true})
        harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="indeterminate")
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф"])
    }

    @Test func releaseDuringUncancellableRollbackIsIndeterminateAndDoesNotRetry() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        layout.duringRestoration={
            harness.send(harness.physical(1,text:"ф"))
            harness.observer.finish(tx)
        }
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{checks+=1;return checks==1})
        harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="indeterminate")
        #expect(layout.source=="original")
        #expect(layout.restoreCalls==1)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф"])
    }

    @Test func contextControlReleasesTargetMappedPrefixBeforePointerAndPreventsRollback() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {
                harness.send(harness.physical(1))
                let pointer=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
                pointer.timestamp=2;harness.send(pointer);return false
            }
            return true
        })
        harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="rejected")
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.time}==[1,2])
        #expect(harness.delivered.all.map{$0.type}==[.keyDown,.leftMouseDown])
        #expect(harness.delivered.all.first?.text=="ф")
    }

    @Test func unadmittedInputAlsoPreventsRollbackAfterItIsForwarded() {
        let harness=ObserverHarness(),layout=LayoutHarness();let lease=layout.lease()
        let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(lease:lease),validateBeforeOutput:{
            checks+=1
            if checks==2 {
                harness.copyFails=true
                harness.send(harness.physical(1,text:"ф"));return false
            }
            return true
        })
        harness.observer.finish(tx);lease.restore()
        #expect(result.outcome=="rejected")
        #expect(layout.source=="target")
        #expect(layout.restoreCalls==0)
        #expect(harness.delivered.all.map{$0.text}==["ф"])
        #expect(harness.observer.buffer.drain().0.map{$0.text}==["ф"])
    }

    @Test func physicalTypingDuringEditIsReplayedOnceAfterBalancedOutput() throws {
        let harness=ObserverHarness();let tx=harness.begin()
        var inserted=false
        harness.onPost={ _ in
            guard !inserted else {return};inserted=true
            harness.send(harness.physical(1));harness.send(harness.physical(2,type:.keyUp))
        }
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{true})
        harness.observer.finish(tx);harness.observer.finish(tx)
        #expect(result.outcome=="submitted", "Commit reason: \(result.reason)")
        #expect(result.hadDeferredEvents)
        let all=harness.delivered.all
        try #require(all.count==6)
        #expect(all.map{$0.type}==[.keyDown,.keyUp,.keyDown,.keyUp,.keyDown,.keyUp])
        #expect(all.suffix(2).map{$0.marker}==[replayMarker,replayMarker])
        #expect(all[4].text=="ф")
        let batch=harness.observer.buffer.drain().0
        #expect(batch.count==2)
        #expect(batch.first?.text=="ф")
    }

    @Test func unsuccessfulSelectionRestoresBeforeAnyDeletion() {
        let harness=ObserverHarness();harness.selectionSucceeds=false
        let tx=harness.begin();harness.send(harness.physical(1))
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{true})
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(!harness.selected)
        #expect(harness.restorations==1)
        #expect(harness.delivered.all.map{$0.text}==["a"])
    }

    @Test func focusChangeAfterSelectionRejectsWithoutDeletingAndRestores() {
        let harness=ObserverHarness();let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{checks+=1;return checks==1})
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(harness.delivered.all.isEmpty)
        #expect(harness.restorations==1)
    }

    @Test func expiryAfterFinalValidationStillRestoresSelection() {
        let harness=ObserverHarness();let tx=harness.begin();var checks=0
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{
            checks+=1
            if checks==2 {harness.observer.abort(tx,reason:"commit_timeout")}
            return true
        })
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(harness.delivered.all.isEmpty)
        #expect(!harness.selected)
        #expect(harness.restorations==1)
    }

    @Test func timeoutClosesOutputBeforeReplayAndLateOwnEventsCannotEnter() {
        let harness=ObserverHarness();harness.delayOwn=true
        let tx=harness.begin();harness.send(harness.physical(1))
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{true})
        harness.observer.finish(tx)
        // Only a nonprinting carrier was posted; the callback never started
        // deletion, so timeout is a clean before-output rejection.
        #expect(result.outcome=="rejected")
        let before=harness.delivered.all.count
        for event in harness.delayed {harness.send(event)}
        #expect(before==1)
        #expect(harness.delivered.all.count==before)
        #expect(harness.observer.buffer.drain().0.count==1)
    }

    @Test func overflowFlushesOlderInputBeforeForwardingNewestExactlyOnce() {
        let harness=ObserverHarness();let tx=harness.begin()
        for number in 1...257 {harness.send(harness.physical(UInt64(number)))}
        harness.observer.finish(tx)
        #expect(harness.delivered.all.map{$0.time}==(1...257).map{UInt64($0)})
        #expect(tx.released)
    }

    @Test func copyFailureFlushesOlderInputBeforeForwardingUncopiedEvent() {
        let harness=ObserverHarness();let tx=harness.begin()
        harness.send(harness.physical(1));harness.copyFails=true
        harness.send(harness.physical(2));harness.observer.finish(tx)
        #expect(harness.delivered.all.map{$0.time}==[1,2])
    }

    @Test func contextControlCancelsAndFlushesThroughCurrentTapBeforeReturn() {
        let harness=ObserverHarness();let tx=harness.begin()
        var asynchronousReplay=false
        harness.onReplay={_ in asynchronousReplay=true}
        harness.send(harness.physical(1))
        let pointer=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
        pointer.timestamp=2
        pointer.setIntegerValueField(.eventTargetUnixProcessID,value:999)
        harness.send(pointer)
        #expect(tx.released)
        #expect(tx.failure=="context_input")
        #expect(!asynchronousReplay)
        #expect(harness.delivered.all.map{$0.time}==[1,2])
        #expect(harness.delivered.all.map{$0.targetPID}==[123,999])
        #expect(harness.delivered.all.last?.marker==pointer.getIntegerValueField(.eventSourceUserData))
        let result=harness.observer.commit(tx,prepared:harness.plan(),validateBeforeOutput:{true})
        harness.observer.finish(tx)
        #expect(result.outcome=="rejected")
        #expect(harness.delivered.all.map{$0.type}==[.keyDown,.leftMouseDown])
    }

    @Test func watchdogReleasesWhileRuntimeDoesNoWork() {
        let harness=ObserverHarness(watchdog:true);let tx=harness.begin()
        harness.send(harness.physical(1))
        Thread.sleep(forTimeInterval:0.08)
        harness.observer.finish(tx)
        #expect(tx.failure=="commit_timeout")
        #expect(harness.delivered.all.map{$0.time}==[1])
    }

    @Test func releaseOwnsDeliveryUntilOlderBatchHasBeenSubmitted() {
        let harness=ObserverHarness();let tx=harness.begin()
        for number in 1...256 {harness.send(harness.physical(UInt64(number)))}
        let paused=DispatchSemaphore(value:0),resume=DispatchSemaphore(value:0),finished=DispatchGroup()
        var first=true
        harness.onReplay={ _ in if first {first=false;paused.signal();resume.wait()} }
        finished.enter();DispatchQueue.global().async {harness.observer.finish(tx);finished.leave()}
        #expect(paused.wait(timeout:.now()+1) == .success)
        let attempted=DispatchSemaphore(value:0)
        finished.enter();DispatchQueue.global().async {
            attempted.signal();harness.send(harness.physical(257));finished.leave()
        }
        attempted.wait();resume.signal()
        #expect(finished.wait(timeout:.now()+1) == .success)
        #expect(harness.delivered.all.map{$0.time}==(1...257).map{UInt64($0)})
    }
}
