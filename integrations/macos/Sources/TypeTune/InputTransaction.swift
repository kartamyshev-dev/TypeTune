import AppKit
import Carbon
import Synchronization

let replayMarker: Int64 = 0x5459504552504c59
private let transactionMarkerPrefix: Int64 = 0x5454000000000000
private let transactionMarkerMask: Int64 = 0x7fff000000000000

func transactionMarker(_ id: UInt64, final: Bool) -> Int64 {
    transactionMarkerPrefix | Int64((id & 0x0000_7fff_ffff_ffff) << 1) | (final ? 1:0)
}
func transactionID(_ marker: Int64) -> UInt64? {
    guard marker & transactionMarkerMask == transactionMarkerPrefix else {return nil}
    return UInt64(marker & 0x0000_ffff_ffff_fffe)>>1
}
func isTypeTuneMarker(_ marker: Int64) -> Bool {
    marker==ownMarker || marker==replayMarker || transactionID(marker) != nil
}

/// Only an annotated, positive process destination can authorize an edit.
func eventTargetPID(_ event:CGEvent) -> pid_t {
    let raw=event.getIntegerValueField(.eventTargetUnixProcessID)
    guard raw>0,raw<=Int64(Int32.max) else {return 0}
    return pid_t(raw)
}

/// Replacing a copied event's user-data field alone can retain its original
/// value. Recreate source metadata on the SAME state table: a fresh private
/// table per edge leaves replayed modifiers held when the original key-up comes.
func markEvent(_ event: CGEvent, _ marker: Int64) -> Bool {
    guard let source=CGEventSource(event:event) else {return false}
    source.userData=marker
    source.localEventsSuppressionInterval=0
    event.setSource(source)
    return event.getIntegerValueField(.eventSourceUserData)==marker
}

/// A FIFO admits an event only when it can retain it. The callback must forward
/// an unadmitted event, after releasing the older admitted events.
struct BoundedFIFO<Element> {
    let capacity: Int
    private(set) var elements: [Element] = []
    init(capacity: Int) {self.capacity=capacity;elements.reserveCapacity(capacity)}
    mutating func append(_ element: Element) -> Bool {
        guard elements.count<capacity else {return false}
        elements.append(element);return true
    }
    mutating func takeAll() -> [Element] {
        let result=elements;elements=[];elements.reserveCapacity(capacity);return result
    }
}

struct DeferredInput {
    let event: CGEvent
    let observation: KeyObservation
    // Admission permits only keyboard input with an authoritative positive
    // destination. Pointer/control events are immediately passed at the tap.
    let targetPID: pid_t
}

/// Mutable fields are owned by Observer.transactionLock. Token identity prevents
/// a late watchdog or completion from ending a subsequent transaction.
final class EditTransaction {
    let id: UInt64
    let targetPID: pid_t
    let operationDeadline: UInt64
    private let firstInputAt=Atomic<UInt64>(0)
    var deadline: UInt64 {
        let first=firstInputAt.load(ordering:.acquiring)
        return first==0 ? operationDeadline:min(operationDeadline,first+50_000_000)
    }
    func noteInput(at time:UInt64) {
        _=firstInputAt.compareExchange(expected:0,desired:time,ordering:.acquiringAndReleasing)
    }
    let acknowledged=DispatchSemaphore(value:0)
    var queue=BoundedFIFO<DeferredInput>(capacity:256)
    var prepared: PreparedReplacement?
    var selected=false
    var outputStarted=false
    var outputAcknowledged=false
    var released=false
    var releasing=false
    var hadDeferredEvents=false
    var deliveredKeys: [CGKeyCode:CGEvent] = [:]
    var outputClosed=false
    var failure: String?
    init(id: UInt64,targetPID:pid_t,deadline:UInt64) {
        self.id=id;self.targetPID=targetPID;self.operationDeadline=deadline
    }
}

struct NativeCommitResult {
    let outcome: String // rejected | submitted | indeterminate
    let reason: String
    let revisionAfterCommit: UInt64
    let hadDeferredEvents: Bool
}

extension Native {
    static func canCommit(_ context: NativeContext, log: (String)->Void = DiagLog.write) -> Bool {
        func reject(_ reason:String,stage:String,error:AXError? = nil) -> Bool {
            // Only fixed reason names and numeric status; no field contents,
            // identity hashes or keystrokes. This check runs outside the tap.
            let status=error.map{" ax_error=\($0.rawValue)"} ?? ""
            log("native_validation_rejected reason=\(reason) stage=\(stage)\(status)")
            return false
        }
        // Permission RPCs may take tens of milliseconds. The context was
        // refreshed before admission; tap loss and Secure Input are separate
        // live gates. Never repeat TCC round trips while input is held.
        guard context.permitted else {return reject("context_permission",stage:"before_focus")}
        guard context.usable else {return reject(context.secure ? "context_secure":"context_unusable",stage:"before_focus")}
        guard !context.secure else {return reject("context_secure",stage:"before_focus")}
        if let reason=targetSafetyFailure(context.pid) {return reject(reason,stage:"before_focus")}
        guard let expected=context.element else {return true}
        // Fresh field identity is required after the main-queue layout change.
        // This runs on the worker before output, never in the tap callback.
        let app=AXUIElementCreateApplication(context.pid)
        AXUIElementSetMessagingTimeout(app,0.05)
        var raw:CFTypeRef?
        let focusError=AXUIElementCopyAttributeValue(app,kAXFocusedUIElementAttribute as CFString,&raw)
        guard focusError == .success else {return reject("focus_error",stage:"focus",error:focusError)}
        guard let raw else {return reject("focus_missing",stage:"focus")}
        guard CFGetTypeID(raw)==AXUIElementGetTypeID() else {return reject("focus_type",stage:"focus")}
        let focused=raw as! AXUIElement
        guard CFEqual(focused,expected) else {return reject("focus_mismatch",stage:"focus")}
        AXUIElementSetMessagingTimeout(focused,0.05)
        var subrole:CFTypeRef?
        let error=AXUIElementCopyAttributeValue(focused,kAXSubroleAttribute as CFString,&subrole)
        guard error == .success || error == .attributeUnsupported || error == .noValue else {return reject("subrole_error",stage:"focus",error:error)}
        guard subrole as? String != kAXSecureTextFieldSubrole else {return reject("field_secure",stage:"focus")}
        if let reason=targetSafetyFailure(context.pid) {return reject(reason,stage:"after_focus")}
        return true
    }
}

enum ReplayDestination {case process(pid_t)}

/// Injectable transport exercises the actual observer state machine without
/// installing a tap or sending input to the user's desktop.
struct ObserverTransport {
    var copy: (CGEvent)->CGEvent? = {$0.copy()}
    var post: (CGEvent)->Void = {$0.post(tap:.cgSessionEventTap)}
    var replay: (CGEvent,ReplayDestination)->Void = {event,destination in
        // The FIFO contains only already-annotated keyboard events. Preserve
        // each captured destination and enter downstream of our annotated tap;
        // global reposting could both reroute keys and reorder the FIFO.
        switch destination {case .process(let pid):
            guard pid>0,eventTargetPID(event)==pid else {return}
            event.postToPid(pid)
        }
    }
    var afterTap: (CGEvent,CGEventTapProxy?)->Void = {$0.tapPostEvent($1)}
    var targetIsSafe: (pid_t)->Bool = Native.fastTargetIsSafe
    var select: (PreparedReplacement,UInt64,@escaping ()->Bool)->Bool = {Native.selectPrepared($0,deadline:$1,allowed:$2)}
    var restore: (PreparedReplacement)->Void = Native.restorePrepared
    var secureInput: ()->Bool = {SecureInputReader.shared.isEnabled()}
    var carrierIsSafe: ()->Bool = {!CGEventSource.keyState(.hidSystemState,key:CGKeyCode(kVK_F20))}
    var ready: (() -> Bool)? = nil
    var automaticWatchdog=true
    static let live=ObserverTransport()
}
