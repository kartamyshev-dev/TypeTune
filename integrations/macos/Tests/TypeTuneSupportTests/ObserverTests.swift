import Foundation
import CoreGraphics
import Testing
import Synchronization
@testable import TypeTune

struct ObserverTests {
    func event(code:CGKeyCode,flags:UInt64=0)->CGEvent {
        let value=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)!
        value.flags=CGEventFlags(rawValue:flags);value.timestamp=123_000_000
        return value
    }
    @Test func overlappingShiftSidesPreserveIndividualEdges() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        buffer.push(event(code:56,flags:0x20002),type:.flagsChanged)
        buffer.push(event(code:60,flags:0x20006),type:.flagsChanged)
        buffer.push(event(code:56,flags:0x20004),type:.flagsChanged)
        buffer.push(event(code:60,flags:0),type:.flagsChanged)
        let (events,lost)=buffer.drain()
        #expect(!lost)
        #expect(events.map{$0.key}==["left_shift","right_shift","left_shift","right_shift"])
        #expect(events.map{$0.action}==["down","down","up","up"])
        #expect(events.map{$0.time}==[123,123,123,123])
    }
    @Test func ownOutputDisabledCaptureAndOverflow() {
        let buffer=InputBuffer()
        buffer.push(event(code:0),type:.keyDown)
        #expect(buffer.drain().0.isEmpty)
        buffer.accepting.store(true,ordering:.relaxed)
        let own=event(code:0);own.setIntegerValueField(.eventSourceUserData,value:ownMarker)
        buffer.push(own,type:.keyDown)
        #expect(buffer.drain().0.isEmpty)
        for _ in 0..<257 {buffer.push(event(code:0),type:.keyDown)}
        #expect(buffer.currentRevision()==UInt64.max)
        let (events,lost)=buffer.drain()
        #expect(events.count==256 && lost)
    }
    @Test func repeatAndReleaseAndUnknownInjection() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        let value=event(code:0);value.setIntegerValueField(.keyboardEventAutorepeat,value:1)
        value.setIntegerValueField(.eventSourceUnixProcessID,value:42)
        buffer.push(value,type:.keyDown);buffer.push(value,type:.keyUp)
        let events=buffer.drain().0
        #expect(events.map{$0.action}==["repeat","up"])
        #expect(events.allSatisfy{$0.origin=="unknown"})
    }
    @Test func revisionReadsMustNotDropGestureEdges() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        let done=Atomic<Bool>(false)
        let started=DispatchSemaphore(value:0)
        let finished=DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            started.signal()
            while !done.load(ordering:.relaxed) {_ = buffer.currentRevision()}
            finished.signal()
        }
        started.wait()
        var dropped=0
        let value=event(code:56,flags:0x20002)
        for _ in 0..<20000 {
            buffer.push(value,type:.flagsChanged)
            let (events,lost)=buffer.drain()
            if lost || events.count != 1 {dropped+=1}
        }
        done.store(true,ordering:.relaxed);finished.wait()
        #expect(dropped==0)
    }

    @Test func concurrentProducerConsumerPreserveOrderAcrossWraps() {
        let buffer=InputBuffer();buffer.accepting.store(true,ordering:.relaxed)
        // Bound outstanding events below capacity: any loss is a race, not overflow.
        let room=DispatchSemaphore(value:128)
        let finished=DispatchSemaphore(value:0)
        let done=Atomic<Bool>(false)
        DispatchQueue.global().async {
            let value=event(code:56,flags:0x20002)
            for index in 1...10000 {
                room.wait()
                value.timestamp=UInt64(index)*1_000_000
                buffer.push(value,type:.flagsChanged)
            }
            done.store(true,ordering:.releasing)
            finished.signal()
        }
        var received:[KeyObservation]=[]
        var lost=false
        while true {
            let completed=done.load(ordering:.acquiring)
            let (batch,overflow)=buffer.drain()
            lost = lost || overflow
            received.append(contentsOf:batch)
            for _ in batch {room.signal()}
            if completed {break}
        }
        finished.wait()
        #expect(!lost)
        #expect(received.map{$0.time} == (1...10000).map{UInt64($0)})
        #expect(received.map{$0.revision} == (1...10000).map{UInt64($0)})
    }

}
