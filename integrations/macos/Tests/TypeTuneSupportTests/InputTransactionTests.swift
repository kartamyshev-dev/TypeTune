import AppKit
import Testing
import Synchronization
@testable import TypeTune

struct InputTransactionTests {
    @Test(arguments:[Int64(0),Int64(999),Int64.max])
    func foreignKeyUpInvalidatesTheOriginalDestinationFence(target:Int64) {
        let buffer=InputBuffer()
        let down=key(0)
        down.setIntegerValueField(.eventTargetUnixProcessID,value:123)
        _=buffer.observe(down,type:.keyDown)
        let revision=buffer.currentRevision()
        let up=key(0);up.type = .keyUp
        up.setIntegerValueField(.eventTargetUnixProcessID,value:target)
        let observation=buffer.observe(up,type:.keyUp)
        #expect(buffer.currentRevision()>revision)
        #expect(observation?.targetPID==(target==999 ? 999:0))
    }
    @Test func sameTargetKeyUpPreservesTheHeldKeyFence() {
        let buffer=InputBuffer(),event=key(0)
        event.setIntegerValueField(.eventTargetUnixProcessID,value:123)
        _=buffer.observe(event,type:.keyDown)
        let revision=buffer.currentRevision()
        event.type = .keyUp
        _=buffer.observe(event,type:.keyUp)
        #expect(buffer.currentRevision()==revision)
    }
    @Test func inputHoldStartsAtFirstArrivalAndNeverExtendsOperationDeadline() {
        let start:UInt64=1_000_000_000
        let idle=EditTransaction(id:1,targetPID:123,deadline:start+100_000_000)
        #expect(idle.deadline==start+100_000_000)
        idle.noteInput(at:start+10_000_000)
        #expect(idle.deadline==start+60_000_000)
        idle.noteInput(at:start+40_000_000)
        #expect(idle.deadline==start+60_000_000)
        let late=EditTransaction(id:2,targetPID:123,deadline:start+100_000_000)
        late.noteInput(at:start+90_000_000)
        #expect(late.deadline==start+100_000_000)
    }
    private func key(_ code:CGKeyCode=0) -> CGEvent {
        CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)!
    }
    private func unicode(_ event:CGEvent) -> String {
        var units=[UniChar](repeating:0,count:16);var length=0
        event.keyboardGetUnicodeString(maxStringLength:units.count,actualStringLength:&length,unicodeString:&units)
        return String(utf16CodeUnits:units,count:length)
    }
    @Test func physicalActivityInvalidatesFenceEvenWhenHistoryIsPaused() {
        let buffer=InputBuffer()
        buffer.push(key(),type:.keyDown)
        let fence=buffer.currentRevision()
        #expect(fence>0)
        #expect(buffer.drain().0.isEmpty)
        buffer.push(key(1),type:.keyDown)
        #expect(buffer.currentRevision()>fence)
        let second=buffer.currentRevision()
        buffer.push(CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!,type:.leftMouseDown)
        #expect(buffer.currentRevision()>second)
    }
    @Test func ownAndReplayMarkersNeitherCountNorEnterHistory() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        for marker in [ownMarker,replayMarker,transactionMarker(7,final:false),transactionMarker(7,final:true)] {
            let event=key();event.setIntegerValueField(.eventSourceUserData,value:marker)
            buffer.push(event,type:.keyDown)
        }
        #expect(buffer.currentRevision()==0)
        #expect(buffer.drain().0.isEmpty)
        #expect(transactionID(transactionMarker(7,final:true))==7)
    }
    @Test func overflowAdmissionAndDrainPreserveEveryAdmittedEdgeOnce() {
        var fifo=BoundedFIFO<String>(capacity:4)
        for edge in ["A down","A up","Shift down","Shift up"] {let added=fifo.append(edge);#expect(added)}
        let overflow=fifo.append("overflow");#expect(!overflow)
        let first=fifo.takeAll();#expect(first==["A down","A up","Shift down","Shift up"])
        let empty=fifo.takeAll();#expect(empty.isEmpty)
        let added=fifo.append("next");#expect(added)
        let last=fifo.takeAll();#expect(last==["next"])
    }
    @Test func replacementMarkerCanBeChangedAfterCopyWithoutChangingOriginal() {
        let original=Native.keyboardEvents(0,unicode:"a")!.0
        let copy=original.copy()!
        let marked=markEvent(copy,transactionMarker(42,final:true))
        #expect(marked)
        #expect(transactionID(copy.getIntegerValueField(.eventSourceUserData))==42)
        #expect(original.getIntegerValueField(.eventSourceUserData)==ownMarker)
    }
    @Test func replayKeepsTheOriginalStateTableWithoutChangingOtherMarkers() throws {
        for state in [CGEventSourceStateID.privateState,.combinedSessionState,.hidSystemState] {
            let source=try #require(CGEventSource(stateID:state));source.userData=123
            let original=try #require(CGEvent(keyboardEventSource:source,virtualKey:56,keyDown:true))
            original.type = .flagsChanged;original.flags = .maskShift
            let replay=try #require(original.copy())
            let marked=markEvent(replay,replayMarker)
            #expect(marked)
            #expect(replay.getIntegerValueField(.eventSourceStateID)==Int64(source.sourceStateID.rawValue))
            #expect(replay.getIntegerValueField(.eventSourceUserData)==replayMarker)
            #expect(original.getIntegerValueField(.eventSourceUserData)==123)
            #expect(source.userData==123)
            // This physical edge can arrive after the transaction was released.
            let laterUp=try #require(CGEvent(keyboardEventSource:source,virtualKey:56,keyDown:false))
            laterUp.type = .flagsChanged;laterUp.flags=[]
            #expect(laterUp.getIntegerValueField(.eventSourceStateID)==replay.getIntegerValueField(.eventSourceStateID))
            #expect(laterUp.getIntegerValueField(.eventSourceUserData)==123)
        }
    }
    @Test func replayKeepsPhysicalIdentityButReplacesStaleLayoutUnicode() {
        let mapping=KeyboardMapping(entries:[(0,[],"ф"),(0,.maskShift,"Ф"),(0,.maskAlphaShift,"Ф")])
        let original=Native.keyboardEvents(0,unicode:"a")!.0
        original.setIntegerValueField(.eventSourceUserData,value:0)
        let replay=mapping.replay(original)!
        #expect(replay.getIntegerValueField(.keyboardEventKeycode)==0)
        #expect(unicode(replay)=="ф")
        #expect(unicode(original)=="a")
        #expect(replay.getIntegerValueField(.eventSourceUserData)==replayMarker)
        original.flags = .maskShift
        #expect(unicode(mapping.replay(original)!)=="Ф")
        original.flags = .maskCommand
        #expect(unicode(mapping.replay(original)!)=="a")
        original.type = .keyUp;original.flags=[]
        #expect(unicode(mapping.replay(original)!)=="ф")
    }
    @Test func mappedOutputUsesRealKeyCodeAndShift() {
        let mapping=KeyboardMapping(entries:[(12,[],"й"),(12,.maskShift,"Й")])
        let stroke=mapping.stroke(for:"Й")!
        let (down,up)=Native.keyboardEvents(stroke.code,unicode:"Й",flags:stroke.flags)!
        #expect(down.getIntegerValueField(.keyboardEventKeycode)==12)
        #expect(down.flags.contains(.maskShift))
        #expect(up.flags.contains(.maskShift))
        #expect(unicode(down)=="Й")
        #expect(unicode(up)=="Й")
        #expect(mapping.stroke(for:"💡")==nil)
    }
    @Test @MainActor func nonbreakingSpaceUsesOptionSpaceWithoutChangingOrdinarySpaceReplay() {
        let mapping=KeyboardMapping(entries:[(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        let stroke=mapping.stroke(for:"\u{a0}")!
        #expect(stroke.code==49)
        #expect(stroke.flags == .maskAlternate)
        let events=mapping.replacementEvents(for:"\u{a0}")!
        #expect(NSEvent(cgEvent:events[1])?.characters=="\u{a0}")
        #expect(events[1].flags == .maskAlternate)
        let ordinary=Native.keyboardEvents(49,unicode:" ")!.0
        #expect(unicode(mapping.replay(ordinary)!)==" ")
        #expect(mapping.text(code:49,flags:[])==" ")
    }
    @Test @MainActor func nonbreakingSpaceCarriesExplicitTextOnBothKeyEdges() throws {
        let mapping=KeyboardMapping(entries:[(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        let events=try #require(mapping.replacementEvents(for:"\u{a0}"))
        for event in events where event.type == .keyDown || event.type == .keyUp {
            let native=try #require(NSEvent(cgEvent:event))
            #expect(native.characters=="\u{a0}")
            #expect(unicode(event)=="\u{a0}")
            #expect(event.getIntegerValueField(.keyboardEventKeycode)==49)
            #expect(event.flags == .maskAlternate)
        }
    }
    @Test @MainActor func nonbreakingSpacePreservesRawAndAppKitTextThroughTransport() throws {
        let mapping=KeyboardMapping(entries:[(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        let source=try #require(CGEventSource(stateID:.privateState))
        let events=try #require(mapping.replacementEvents(for:"\u{a0}",source:source))
        #expect(events.allSatisfy{$0.timestamp==0})
        for original in events where original.type == .keyDown || original.type == .keyUp {
            let copy=try #require(original.copy())
            let data=try #require(copy.data)
            let serialized=try #require(CGEvent(withDataAllocator:nil,data:data))
            for event in [original,copy,serialized] {
                let native=try #require(NSEvent(cgEvent:event))
                // The transport and AppKit consumers must receive the same
                // text; deriving NBSP only from current Option flags is not enough.
                #expect(unicode(event)=="\u{a0}")
                #expect(native.characters=="\u{a0}")
                #expect(event.type==original.type)
                #expect(event.getIntegerValueField(.keyboardEventKeycode)==49)
                #expect(event.flags == .maskAlternate)
            }
            // Serialized CGEvent data omits source metadata. Production posts
            // the original/copy, which must retain the same private state table.
            for event in [original,copy] {
                #expect(event.getIntegerValueField(.eventSourceUserData)==ownMarker)
                #expect(event.getIntegerValueField(.eventSourceStateID)==Int64(source.sourceStateID.rawValue))
                #expect(event.getIntegerValueField(.eventSourceUnixProcessID)==Int64(ProcessInfo.processInfo.processIdentifier))
            }
        }
    }
    @Test @MainActor func targetBindingAndReplayMarkersPreserveNBSPAndSourceIdentity() throws {
        let mapping=KeyboardMapping(entries:[(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        let events=try #require(mapping.replacementEvents(for:"\u{a0}"))
        for event in events {
            event.setIntegerValueField(.eventTargetUnixProcessID,value:123)
            let copy=try #require(event.copy())
            #expect(markEvent(copy,replayMarker))
            #expect(eventTargetPID(copy)==123)
            #expect(copy.getIntegerValueField(.eventSourceUnixProcessID)==Int64(ProcessInfo.processInfo.processIdentifier))
            #expect(copy.getIntegerValueField(.eventSourceStateID)==event.getIntegerValueField(.eventSourceStateID))
            #expect(event.getIntegerValueField(.eventSourceUserData)==ownMarker)
            if event.type == .keyDown || event.type == .keyUp {
                #expect(unicode(copy)=="\u{a0}")
                #expect(NSEvent(cgEvent:copy)?.characters=="\u{a0}")
            }
        }
    }
    @Test @MainActor func mappedModifierStrokeHasBalancedOwnEdges() throws {
        let mapping=KeyboardMapping(entries:[(12,.maskShift,"Й"),(49,[]," "),(49,.maskAlternate,"\u{a0}")])
        let source=try #require(CGEventSource(stateID:.privateState))
        for (text,modifier) in [("Й",56),("\u{a0}",58)] {
            let events=try #require(mapping.replacementEvents(for:text,source:source))
            #expect(events.map(\.type)==[.flagsChanged,.keyDown,.keyUp,.flagsChanged])
            #expect(events.first?.getIntegerValueField(.keyboardEventKeycode)==Int64(modifier))
            #expect(events.last?.getIntegerValueField(.keyboardEventKeycode)==Int64(modifier))
            #expect(events.last?.flags == [])
            #expect(events.allSatisfy{$0.getIntegerValueField(.eventSourceUserData)==ownMarker})
            #expect(events.allSatisfy{$0.getIntegerValueField(.eventSourceStateID)==Int64(source.sourceStateID.rawValue)})
        }
    }
    @Test func nonbreakingSpaceRequiresMatchingModifiedAndUnmodifiedMapping() {
        let wrongKey=KeyboardMapping(entries:[(49,[]," "),(0,.maskAlternate,"\u{a0}")])
        let wrongBase=KeyboardMapping(entries:[(49,[],"x"),(49,.maskAlternate,"\u{a0}")])
        let missingBase=KeyboardMapping(entries:[(49,.maskAlternate,"\u{a0}")])
        for mapping in [wrongKey,wrongBase,missingBase] {
            #expect(!mapping.supportsNativeNonbreakingSpace)
            #expect(mapping.replacementEvents(for:"\u{a0}")==nil)
        }
        let ordinary=KeyboardMapping(entries:[(12,.maskShift,"Й")])
        let events=ordinary.replacementEvents(for:"Й")!
        #expect(unicode(events[1])=="Й")
        #expect(events[1].flags == .maskShift)
    }
    @Test func secureContextCannotBeMadeUsableByOverride() {
        let context=NativeContext(identity:"123:0",bundle:"test",layout:"us",element:nil,secure:true,permitted:true,usableOverride:true)
        #expect(!context.usable)
        #expect(context.pid==123)
    }
    @Test func captureAndDeferredEnqueueDoNotLoseEventsWithConcurrentDrain() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        let room=DispatchSemaphore(value:128)
        let done=DispatchGroup()
        for producer in 0..<2 {
            done.enter()
            DispatchQueue.global().async {
                for index in 0..<2000 {
                    room.wait()
                    let event=key(CGKeyCode(producer));event.timestamp=UInt64(producer*2000+index+1)*1_000_000
                    buffer.enqueue(buffer.observe(event,type:.keyDown)!)
                }
                done.leave()
            }
        }
        var received:[UInt64]=[]
        var lost=false
        while done.wait(timeout:.now()) != .success {
            let (batch,overflow)=buffer.drain();lost = lost || overflow
            received += batch.map{$0.time}
            for _ in batch {room.signal()}
        }
        let (tail,overflow)=buffer.drain();received += tail.map{$0.time};lost = lost || overflow
        // Producers can finish before the last drain. Return those permits too:
        // libdispatch rejects disposal below the semaphore's initial value.
        for _ in tail {room.signal()}
        #expect(!lost)
        #expect(received.count==4000)
        #expect(Set(received)==Set((1...4000).map{UInt64($0)}))
        #expect(buffer.currentRevision()==4000)
    }
}
