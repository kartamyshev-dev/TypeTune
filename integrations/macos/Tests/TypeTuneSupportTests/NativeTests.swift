import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import TypeTune

struct NativeTests {
    @Test func secureInputReadsAreSerializedAndContentionFailsClosed() throws {
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
        let calls=Atomic<Int>(0),firstResult=Atomic<Bool>(true)
        let reader=SecureInputReader {
            let count=calls.wrappingAdd(1,ordering:.relaxed).newValue
            if count==1 {entered.signal();_ = release.wait(timeout:.now() + .seconds(2))}
            return false
        }
        DispatchQueue.global().async {
            firstResult.store(reader.isEnabled(),ordering:.releasing);done.signal()
        }
        defer {release.signal()}
        try #require(entered.wait(timeout:.now() + .seconds(2)) == .success)
        #expect(reader.snapshot() == .busy)
        #expect(reader.isEnabled())
        let callsDuringContention=calls.load(ordering:.relaxed)
        #expect(callsDuringContention==1)
        release.signal()
        try #require(done.wait(timeout:.now() + .seconds(2)) == .success)
        let initialResult=firstResult.load(ordering:.acquiring)
        #expect(!initialResult)
        #expect(!reader.isEnabled())
        let totalCalls=calls.load(ordering:.relaxed)
        #expect(totalCalls==2)
    }
    @Test func secureStatusDistinguishesOSStateFromConservativeContention() {
        #expect(SecureInputReader(read:{false}).snapshot() == .disabled)
        #expect(SecureInputReader(read:{true}).snapshot() == .enabled)
        #expect(!SecureInputReader(read:{false}).isEnabled())
        #expect(SecureInputReader(read:{true}).isEnabled())
    }
    @Test func targetRejectionReasonsPreserveTheGuardAndItsShortCircuitOrder() {
        func mustNotReadSecure() -> SecureInputStatus {Issue.record("Secure Input read after a failed PID guard");return .disabled}
        #expect(Native.targetSafetyFailure(0,foregroundPID:{123},secureInput:mustNotReadSecure)=="invalid_pid")
        #expect(Native.targetSafetyFailure(123,foregroundPID:{nil},secureInput:mustNotReadSecure)=="foreground")
        #expect(Native.targetSafetyFailure(123,foregroundPID:{456},secureInput:mustNotReadSecure)=="foreground")
        #expect(Native.targetSafetyFailure(123,foregroundPID:{123},secureInput:{.busy})=="secure_busy")
        #expect(Native.targetSafetyFailure(123,foregroundPID:{123},secureInput:{.enabled})=="secure_global")
        #expect(Native.targetSafetyFailure(123,foregroundPID:{123},secureInput:{.disabled})==nil)
    }
    @Test func rejectedContextEmitsOneFixedReasonWithoutSensitiveFields() {
        let context=NativeContext(identity:"123:456",bundle:"private.fixture",layout:"us",element:nil,secure:false,permitted:false)
        var records:[String]=[]
        #expect(!Native.canCommit(context,log:{records.append($0)}))
        #expect(records==["native_validation_rejected reason=context_permission stage=before_focus"])
    }
    func unicode(of event: CGEvent) -> String {
        var chars=[UniChar](repeating:0,count:16); var length=0
        event.keyboardGetUnicodeString(maxStringLength:chars.count,actualStringLength:&length,unicodeString:&chars)
        return String(utf16CodeUnits:chars,count:Int(length))
    }
    @Test func explicitUnicodeAndMarkersAreConsistentForBothEdges() {
        let pair=Native.keyboardEvents(0,unicode:"я")!
        #expect(unicode(of:pair.0) == "я")
        #expect(unicode(of:pair.1)=="я")
        #expect(pair.0.getIntegerValueField(.eventSourceUserData) == ownMarker)
        #expect(pair.1.getIntegerValueField(.eventSourceUserData) == ownMarker)
        let backspace=Native.keyboardEvents(51)
        #expect(backspace != nil)
    }
}
