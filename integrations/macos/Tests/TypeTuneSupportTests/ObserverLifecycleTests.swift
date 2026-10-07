import AppKit
import Testing
@testable import TypeTune

private final class LifecycleHarness {
    let condition=NSCondition()
    private var values:[String:Bool]=["valid":true,"enabled":true,"enableSucceeds":true]
    private var messages:[String]=[]
    private var created=0
    private var clock:UInt64=1_000_000_000
    private var registrationCount=0
    let permissions=ObserverPermissions(listen:true,post:false,accessibility:false)
    var observer:Observer!
    let sourceEntered=DispatchSemaphore(value:0)
    let releaseSource=DispatchSemaphore(value:0)
    init(blockFirstSource:Bool=false) {
        var io=ObserverLifecycleIO()
        io.observeFocus=false
        io.permissions={ [unowned self] in permissions }
        io.now={ [unowned self] in condition.lock();defer{condition.unlock()};return clock }
        io.registration={ [unowned self] mask in
            condition.lock();registrationCount+=1;condition.unlock()
            return ObserverTapRegistration(id:1,mask:get("maskMissing") ? mask & ~(1 << CGEventType.keyDown.rawValue):mask,
                                    enabled:get("enabled"))
        }
        io.createTap={ [unowned self] _,_,_ in
            condition.lock();created+=1;let fail=values["tapFails"] == true;condition.unlock()
            return fail ? nil:CFMachPortCreate(nil,{_,_,_,_ in},nil,nil)
        }
        io.createSource={ [unowned self] port in
            if blockFirstSource,attempts==1 {
                sourceEntered.signal()
                _=releaseSource.wait(timeout:.now()+2)
                return nil
            }
            return get("sourceFails") ? nil:CFMachPortCreateRunLoopSource(nil,port,0)
        }
        io.isValid={ [unowned self] _ in get("valid") }
        io.isEnabled={ [unowned self] _ in get("enabled") }
        io.enable={ [unowned self] _ in if get("enableSucceeds") {set("enabled",true)} }
        io.log={ [weak self] message in
            guard let self else {return}
            condition.lock();messages.append(message);condition.broadcast();condition.unlock()
        }
        observer=Observer(lifecycle:io)
    }
    func get(_ key:String) -> Bool {condition.lock();defer{condition.unlock()};return values[key] == true}
    func set(_ key:String,_ value:Bool) {condition.lock();values[key]=value;condition.unlock()}
    var attempts:Int {condition.lock();defer{condition.unlock()};return created}
    var registrationReads:Int {condition.lock();defer{condition.unlock()};return registrationCount}
    func advance(_ nanoseconds:UInt64) {condition.lock();clock+=nanoseconds;condition.unlock()}
    var logs:[String] {condition.lock();defer{condition.unlock()};return messages}
    func waitFor(_ prefix:String,count:Int=1) -> Bool {
        let limit=Date(timeIntervalSinceNow:1)
        condition.lock();defer{condition.unlock()}
        while messages.filter({$0.hasPrefix(prefix)}).count<count {
            if !condition.wait(until:limit) {return false}
        }
        return true
    }
    func waitUntilInactive() -> Bool {
        let limit=Date(timeIntervalSinceNow:1)
        while observer.isActive,Date()<limit {Thread.sleep(forTimeInterval:0.001)}
        return !observer.isActive
    }
}

struct ObserverLifecycleTests {
    @Test func staleStartupCleanupCannotInvalidateTheReplacementObserverBuffer() throws {
        let harness=LifecycleHarness(blockFirstSource:true)
        defer{harness.releaseSource.signal();harness.observer.stop()}
        harness.observer.start()
        try #require(harness.sourceEntered.wait(timeout:.now()+1) == .success)
        harness.observer.stop();harness.observer.start()
        try #require(harness.waitFor("observer_started"))
        #expect(harness.observer.recover())
        _=harness.observer.buffer.drain() // Consume the explicit stop discontinuity.
        let revision=harness.observer.buffer.currentRevision()
        harness.releaseSource.signal()
        try #require(harness.waitFor("observer_stopped attempt=1 stale=true"))
        #expect(harness.observer.isActive)
        #expect(harness.observer.buffer.currentRevision()==revision)
        #expect(!harness.observer.buffer.drain().1)
    }
    @Test func enabledTapWithAClippedMaskIsRetiredOnABoundedHealthCheck() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.observer.start();try #require(harness.waitFor("observer_started"))
        harness.set("maskMissing",true)
        for _ in 0..<20 {#expect(harness.observer.recover())}
        #expect(harness.registrationReads==1)
        harness.advance(1_000_000_000)
        #expect(!harness.observer.recover())
        #expect(!harness.observer.isActive)
        #expect(harness.registrationReads==2)
        #expect(harness.logs.contains{$0.hasPrefix("observer_registration_failed") && $0.contains("actual_mask=")})
        harness.set("maskMissing",false);harness.observer.start()
        try #require(harness.waitFor("observer_started",count:2))
        #expect(harness.observer.recover())
    }
    @Test func reducedEventMaskNeverReportsAHealthyObserver() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.set("maskMissing",true);harness.observer.start()
        try #require(harness.waitFor("observer_start_failed reason=event_mask"))
        try #require(harness.waitUntilInactive())
        #expect(!harness.logs.contains{$0.hasPrefix("observer_started")})
        harness.set("maskMissing",false);harness.observer.start()
        try #require(harness.waitFor("observer_started"))
        #expect(harness.observer.recover())
        #expect(harness.logs.contains{$0.hasPrefix("observer_started") && $0.contains("actual_mask=")})
    }
    @Test func reducedMaskAfterReenableRetiresTheRegistration() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.observer.start();try #require(harness.waitFor("observer_started"))
        harness.set("enabled",false);harness.set("maskMissing",true)
        #expect(!harness.observer.recover())
        #expect(!harness.observer.isActive)
        #expect(harness.logs.contains{$0.hasPrefix("observer_restart reason=event_mask")})
    }
    @Test func failedTapCreationCanRetryAndLogsThisProcessPermissions() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.set("tapFails",true);harness.observer.start()
        try #require(harness.waitFor("observer_start_failed reason=tap_create"))
        try #require(harness.waitUntilInactive())
        #expect(harness.logs.contains{$0.contains("pid=\(ProcessInfo.processInfo.processIdentifier)") && $0.contains("listen=true post=false accessibility=false")})
        harness.set("tapFails",false);harness.observer.start()
        try #require(harness.waitFor("observer_started"))
        #expect(harness.observer.recover())
        #expect(harness.attempts==2)
    }

    @Test func failedRunLoopSourceCreationCleansActiveAndCanRetry() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.set("sourceFails",true);harness.observer.start()
        try #require(harness.waitFor("observer_start_failed reason=run_loop_source"))
        try #require(harness.waitUntilInactive())
        harness.set("sourceFails",false);harness.observer.start()
        try #require(harness.waitFor("observer_started"))
        #expect(harness.observer.recover())
        #expect(harness.attempts==2)
    }

    @Test func invalidPortRetiresGenerationAndAllowsFreshStart() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.observer.start();try #require(harness.waitFor("observer_started"))
        harness.set("valid",false)
        #expect(!harness.observer.recover())
        #expect(!harness.observer.isActive)
        #expect(harness.observer.buffer.drain().1)
        harness.set("valid",true);harness.observer.start()
        try #require(harness.waitFor("observer_started",count:2))
        #expect(harness.observer.recover())
        #expect(harness.attempts==2)
    }

    @Test func unsuccessfulReenableRetiresPortInsteadOfRetryingItForever() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.observer.start();try #require(harness.waitFor("observer_started"))
        harness.set("enabled",false);harness.set("enableSucceeds",false)
        #expect(!harness.observer.recover())
        #expect(!harness.observer.isActive)
        #expect(harness.logs.filter{$0.hasPrefix("observer_restart reason=reenable_failed")}.count==1)
        #expect(!harness.observer.recover())
        #expect(harness.logs.filter{$0.hasPrefix("observer_restart")}.count==1)
        harness.set("enableSucceeds",true);harness.observer.start()
        try #require(harness.waitFor("observer_started",count:2))
        #expect(harness.observer.recover())
    }

    @Test func successfulReenableKeepsPortAndLogsOnlyTheTransition() throws {
        let harness=LifecycleHarness();defer{harness.observer.stop()}
        harness.observer.start();try #require(harness.waitFor("observer_started"))
        harness.set("enabled",false)
        #expect(harness.observer.recover())
        for _ in 0..<10 {#expect(harness.observer.recover())}
        #expect(harness.attempts==1)
        #expect(harness.logs.filter{$0.hasPrefix("observer_recovered")}.count==1)
    }
}
