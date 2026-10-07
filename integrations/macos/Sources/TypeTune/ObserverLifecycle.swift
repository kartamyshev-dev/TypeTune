import AppKit

struct ObserverPermissions: Equatable {
    let listen: Bool
    let post: Bool
    let accessibility: Bool
    static func current() -> Self {
        Self(listen:CGPreflightListenEventAccess(),post:CGPreflightPostEventAccess(),accessibility:AXIsProcessTrusted())
    }
    var diagnostic: String {"listen=\(listen) post=\(post) accessibility=\(accessibility)"}
}

struct ObserverTapRegistration {
    let id:UInt32
    let mask:CGEventMask
    let enabled:Bool
    func contains(_ required:CGEventMask) -> Bool {enabled && mask & required == required}
    var diagnostic:String {"tap_id=\(id) actual_mask=\(mask) registered_enabled=\(enabled)"}

    static func current(point: CGEventTapLocation = .cgAnnotatedSessionEventTap) -> Self? {
        var count:UInt32=0
        guard CGGetEventTapList(0,nil,&count) == .success,count>0,count<=4096 else {return nil}
        var taps=[CGEventTapInformation](repeating:CGEventTapInformation(),count:Int(count))
        let capacity=count
        guard CGGetEventTapList(capacity,&taps,&count) == .success,count<=capacity else {return nil}
        // There is exactly one owned annotated tap in this process. The public
        // API does not document a mapping from CFMachPort to eventTapID; refuse
        // ambiguity rather than accidentally certifying another registration.
        let own=taps.prefix(Int(count)).filter {
            $0.tappingProcess==ProcessInfo.processInfo.processIdentifier &&
            $0.tapPoint == point && $0.options == .defaultTap
        }
        guard own.count==1,let tap=own.first else {return nil}
        return Self(id:tap.eventTapID,mask:tap.eventsOfInterest,enabled:tap.enabled)
    }
}

/// Replace native port operations in lifecycle tests; production still owns one
/// dedicated run loop, and no test needs an event tap or Accessibility access.
struct ObserverLifecycleIO {
    var createTap: (CGEventMask,CGEventTapCallBack,UnsafeMutableRawPointer)->CFMachPort? = {
        CGEvent.tapCreate(tap:.cgAnnotatedSessionEventTap,place:.tailAppendEventTap,options:.defaultTap,
                          eventsOfInterest:$0,callback:$1,userInfo:$2)
    }
    var createSource: (CFMachPort)->CFRunLoopSource? = {CFMachPortCreateRunLoopSource(nil,$0,0)}
    var isValid: (CFMachPort)->Bool = CFMachPortIsValid
    var isEnabled: (CFMachPort)->Bool = {CGEvent.tapIsEnabled(tap:$0)}
    var enable: (CFMachPort)->Void = {CGEvent.tapEnable(tap:$0,enable:true)}
    var invalidate: (CFMachPort)->Void = CFMachPortInvalidate
    var permissions: ()->ObserverPermissions = ObserverPermissions.current
    var registration: (CGEventMask)->ObserverTapRegistration? = {_ in ObserverTapRegistration.current()}
    var now: ()->UInt64 = {DispatchTime.now().uptimeNanoseconds}
    var log: (String)->Void = DiagLog.write
    var observeFocus=true
    static let live=Self()
    static var hidHistory: Self {
        var io = Self()
        io.createTap = {
            CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,
                              eventsOfInterest:$0,callback:$1,userInfo:$2)
        }
        io.registration = { _ in ObserverTapRegistration.current(point:.cghidEventTap) }
        return io
    }
}
