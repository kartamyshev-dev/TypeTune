import AppKit
import Carbon
import Testing
@testable import TypeTune
@testable import TypeTuneSupport

/// Joins the real observer, input buffer, runtime and Rust FFI. Only AX/TIS,
/// clocks and the downstream editor transport are controlled; no desktop input
/// is posted and no event tap is installed by this fixture.
private final class ObserverRuntimeFixture {
    struct Delivery {
        let type: CGEventType
        let code: CGKeyCode
        let text: String
        let marker: Int64
    }
    private static let keys: [(CGKeyCode, String, String)] = [
        (0, "a", "ф"), (5, "g", "п"), (4, "h", "р"), (11, "b", "и"),
        (2, "d", "в"), (17, "t", "е"), (45, "n", "т"), (16, "y", "н"),
        (38, "j", "о"), (49, " ", " "),
        (18, "1", "1"), (19, "2", "2"), (20, "3", "3")
    ]
    private let engine = Engine()
    private let earlyCapture: Bool
    private let staleUnicode: Bool
    private var clock: UInt64 = 1_000_000_000
    private var eventClock: UInt64 = 1000
    private(set) var observer: Observer!
    private(set) var runtime: Runtime!
    private(set) var value = ""
    private(set) var layout = "us"
    private(set) var deliveries: [Delivery] = []
    private(set) var engineEvents: [[String: Any]] = []
    private(set) var acknowledgements: [(outcome: String, status: String)] = []
    private(set) var restorationCount = 0
    private(set) var transactions: [EditTransaction] = []
    private(set) var delayedCarriers: [CGEvent] = []
    var readable = true
    var selectionSucceeds = true
    var rejectValidation = false
    var delayCarrier = false
    var afterSelection: ((PreparedReplacement) -> Void)?
    var beforeCarrier: (() -> Void)?

    init(sessionHistory: Bool = false, staleUnicode: Bool = false) {
        earlyCapture=sessionHistory
        self.staleUnicode=staleUnicode
        var transport = ObserverTransport()
        transport.directSession = sessionHistory
        if sessionHistory {transport.intendedTarget = {9000}}
        if sessionHistory {transport.keyboardMapping = { [unowned self] in mapping(layout) }}
        transport.ready = { true }
        transport.targetIsSafe = { $0 == 9000 }
        transport.secureInput = { false }
        transport.carrierIsSafe = { true }
        transport.automaticWatchdog = false
        transport.post = { [unowned self] event in
            if sessionHistory {deliver(event);return}
            event.setIntegerValueField(.eventTargetUnixProcessID,value:9000)
            beforeCarrier?()
            if delayCarrier { delayedCarriers.append(event.copy()!) }
            else { receive(event) }
        }
        transport.afterTap = { [unowned self] event, _ in deliver(event) }
        transport.replay = { [unowned self] event, _ in deliver(event) }
        transport.select = { [unowned self] prepared, _, allowed in
            guard allowed() else { return false }
            let selected = prepared.selectAction()
            afterSelection?(prepared)
            return selected
        }
        transport.restore = { $0.restoreAction() }
        observer = Observer(transport: transport)

        var io = RuntimeEnvironment()
        io.historyOnly=sessionHistory
        io.buffer = observer.buffer
        io.log = { _ in }
        io.now = { [unowned self] in clock }
        io.sleep = { [unowned self] in clock += UInt64($0 * 1_000_000_000) }
        io.typingKeyHeld = { false }
        io.modifiersHeld = { false }
        io.sound = { _, _, _, _, _ in }
        io.context = { [unowned self] _ in
            NativeContext(identity: "9000:1", bundle: "fixture.editor", layout: layout,
                          element: nil, secure: false, permitted: true, usableOverride: true)
        }
        io.text = { [unowned self] _ in
            readable ? TextState(value: value, range: CFRange(location: value.utf16.count, length: 0)) : nil
        }
        io.canCommit = { [unowned self] _ in !rejectValidation }
        io.validateText = { [unowned self] _, expected in
            value == expected.value && expected.range.location == value.utf16.count && expected.range.length == 0
        }
        io.select = { [unowned self] mode, _ in layout = mode; return true }
        io.beginEdit = { [unowned self] remove, replacement, mode, _, revision, context in
            let prepared = prepare(remove: remove, replacement: replacement, mode: mode)
            var transaction: EditTransaction?
            return RuntimeEditTransaction(commit: { [unowned self] validate in
                // Match RuntimeEnvironment.live: validate AX before admitting
                // the gate, then validate again after the layout selection.
                guard validate(), let admitted = observer.begin(expectedRevision: revision, targetPID: context.pid) else {
                    return RuntimeCommitResult(outcome: "rejected", reason: "admission")
                }
                transaction = admitted
                transactions.append(admitted)
                let result = observer.commit(admitted, prepared: prepared, initiallyValidated: true,
                                             validateBeforeOutput: validate)
                return RuntimeCommitResult(outcome: result.outcome, reason: result.reason,
                                           hadDeferredEvents: result.hadDeferredEvents)
            }, finish: { [unowned self] in
                if let transaction { observer.finish(transaction) }
            })
        }
        runtime = Runtime(environment: io, engineCall: { [unowned self] request in
            if request["op"] as? String == "key_event", let event = request["event"] as? [String: Any] {
                engineEvents.append(event)
            }
            let response = engine.call(request)
            if request["op"] as? String == "edit_result" {
                acknowledgements.append((request["outcome"] as? String ?? "", response["status"] as? String ?? ""))
            }
            return response
        })
        runtime.configure(Settings()) { _ in }
        tick() // Consume configuration discontinuity before physical input.
    }

    private func mapping(_ mode: String) -> KeyboardMapping {
        KeyboardMapping(entries: Self.keys.map { ($0.0, [], mode == "us" ? $0.1 : $0.2) })
    }

    private func prepare(remove: Int, replacement: String, mode: String) -> PreparedReplacement {
        let original = layout
        let targetMapping = mapping(mode)
        let lease = LayoutSelectionLease(originalID: original, targetID: mode,
            originalMapping: mapping(original), targetMapping: targetMapping,
            currentSource: { [unowned self] in layout },
            selectTarget: { [unowned self] in
                if selectionSucceeds { layout = mode }
                return selectionSucceeds
            }, selectOriginal: { [unowned self] in
                restorationCount += 1; layout = original; return true
            })
        var events: [CGEvent] = []
        for _ in 0..<remove {
            let pair = Native.keyboardEvents(51)!
            events += [pair.0, pair.1]
        }
        for character in replacement {
            let text = String(character)
            let stroke = targetMapping.stroke(for: text)!
            let pair = Native.keyboardEvents(stroke.code, unicode: text, flags: stroke.flags)!
            events += [pair.0, pair.1]
        }
        return PreparedReplacement(events: events, sourceID: mode, mode: mode, mapping: targetMapping,
            selectAction: lease.select, restoreAction: lease.restore,
            carrier: Native.keyboardEvents(CGKeyCode(kVK_F20))!.1,
            noteDeferredInput: lease.noteDeferredInput, releaseWithoutOutput: lease.releaseWithoutOutput,
            rollbackInputWasUncertain: { lease.inputWasUncertain })
    }

    func tick() {
        clock += 10_000_000
        runtime.queue.sync { runtime.tick() }
    }

    private func physical(code: CGKeyCode, type: CGEventType, text: String = "", flags: CGEventFlags = []) -> CGEvent {
        eventClock += 10
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.type = type; event.flags = flags; event.timestamp = eventClock * 1_000_000
        event.setIntegerValueField(.eventSourceUserData, value: 0)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: earlyCapture ? 0:9000)
        let units = Array((staleUnicode && !text.isEmpty ? "":text).utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        return event
    }

    func receive(_ event: CGEvent) {
        if let accepted = observer.receive(event, type: event.type) { deliver(accepted.takeUnretainedValue()) }
    }

    func keystrokes(_ text: String) -> [CGEvent] {
        text.flatMap { character in
            let string = String(character)
            let code = Self.keys.first { $0.1 == string || $0.2 == string }!.0
            return [physical(code: code, type: .keyDown, text: string), physical(code: code, type: .keyUp)]
        }
    }

    /// Raw event Unicode intentionally can disagree with the selected layout:
    /// only the observer's real replay mapping may translate a queued event.
    func type(_ text: String, flush: Bool = true) {
        for event in keystrokes(text) { receive(event) }
        if flush { tick() }
    }

    func doubleShift() {
        for down in [true, false, true, false] {
            receive(physical(code: 56, type: .flagsChanged, flags: down ? .maskShift : []))
        }
        tick()
    }

    func returnKey() {
        receive(physical(code: 36, type: .keyDown))
        receive(physical(code: 36, type: .keyUp))
        tick()
    }

    private func deliver(_ event: CGEvent) {
        var units = [UniChar](repeating: 0, count: 16)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        deliveries.append(Delivery(type: event.type, code: code, text: text,
                                   marker: event.getIntegerValueField(.eventSourceUserData)))
        guard event.type == .keyDown else { return }
        if code == 51 { if !value.isEmpty { value.removeLast() } }
        else if code == 36 { value += "\n" }
        else {
            value += earlyCapture && event.getIntegerValueField(.eventSourceUserData)==0
                ? (mapping(layout).text(code:code,flags:event.flags) ?? text):text
        }
    }

    var replayedDowns: [Delivery] { deliveries.filter { $0.marker == replayMarker && $0.type == .keyDown } }
    var observedDownText: [String] {
        engineEvents.filter { $0["action"] as? String == "down" }.compactMap { $0["text"] as? String }
    }
}

struct ObserverRuntimeIntegrationTests {
    @Test func hidHistoryManualPreservesDigitsAndRetogglesWithoutAX() async {
        await Task.detached {
            for (source, target) in [("ghbdtn1", "привет1"), ("ghbdtn123", "привет123"), ("1ghbdtn2", "1привет2")] {
                for tail in ["", " "] {
                    let f = ObserverRuntimeFixture(sessionHistory: true, staleUnicode: true)
                    f.readable = false
                    f.type(source + tail)
                    #expect(f.value == source + tail)
                    #expect(f.transactions.isEmpty) // Numeric tokens never auto-correct.
                    f.doubleShift()
                    #expect(f.value == target + tail)
                    #expect(f.layout == "ru")
                    f.doubleShift()
                    #expect(f.value == source + tail)
                    #expect(f.layout == "us")
                    #expect(f.acknowledgements.map(\.outcome) == ["submitted", "submitted"])
                    #expect(f.acknowledgements.allSatisfy { $0.status == "ok" })
                }
            }
        }.value
    }

    @Test func hidNumericOnlyManualDoesNotSwitchAndNextWordStillCorrects() async {
        await Task.detached {
            let f = ObserverRuntimeFixture(sessionHistory: true, staleUnicode: true)
            f.readable = false
            f.type("123")
            f.doubleShift()
            #expect(f.value == "123")
            #expect(f.layout == "us")
            #expect(f.transactions.isEmpty)
            f.type(" ghbdtn ")
            #expect(f.value == "123 привет ")
            #expect(f.acknowledgements.map(\.outcome) == ["submitted"])
        }.value
    }

    @Test func hidHistoryStartsFreshAfterReturnWithoutAXRecovery() async {
        await Task.detached {
            let f = ObserverRuntimeFixture(sessionHistory: true, staleUnicode: true)
            f.readable = false
            f.type("a")
            f.returnKey()
            f.type("ghbdtn")
            f.doubleShift()
            #expect(f.value == "a\nпривет")
            #expect(f.acknowledgements.map(\.outcome) == ["submitted"])
        }.value
    }
    @Test func hidHistoryTranslatesPhysicalKeysWhenEarlyUnicodeIsMissing() async {
        await Task.detached {
            let f=ObserverRuntimeFixture(sessionHistory:true,staleUnicode:true)
            f.readable=false
            f.type("ghbdtn")
            f.type(" ")
            #expect(f.value=="привет ")
            #expect(f.acknowledgements.map(\.outcome)==["submitted"])
        }.value
    }
    @Test func sessionHistoryReplacesWithoutAXOrCarrierAndPreservesNextWord() async {
        await Task.detached {
            let f = ObserverRuntimeFixture(sessionHistory:true)
            f.readable=false
            f.type("ghbdtn")
            f.afterSelection = { _ in
                f.afterSelection=nil
                f.type("yjdjt",flush:false)
                #expect(f.value=="ghbdtn ")
            }
            f.type(" ")
            #expect(f.value=="привет новое")
            #expect(f.acknowledgements.map(\.outcome)==["submitted"])
            #expect(f.deliveries.allSatisfy{$0.code != 90}) // No F20 carrier.
            #expect(f.replayedDowns.map(\.text)==["н","о","в","о","е"])
        }.value
    }
    @Test func sessionHistoryManualAndFailedLayoutKeepTextSafe() async {
        await Task.detached {
            let f = ObserverRuntimeFixture(sessionHistory:true)
            f.readable=false
            f.type("ghbdtn")
            f.selectionSucceeds=false
            f.doubleShift()
            #expect(f.value=="ghbdtn")
            #expect(f.acknowledgements.map(\.outcome)==["rejected"])
            f.selectionSucceeds=true
            f.type(" ")
            f.type("ghbdtn")
            f.doubleShift()
            #expect(f.value=="ghbdtn привет")
            #expect(f.acknowledgements.last?.outcome=="submitted")
        }.value
    }
    @Test func sessionHistoryRejectsChangedContextBeforePostingAnyReplacement() async {
        await Task.detached {
            let f=ObserverRuntimeFixture(sessionHistory:true)
            f.readable=false
            f.type("ghbdtn")
            f.afterSelection = { _ in f.rejectValidation=true }
            f.type(" ")
            #expect(f.value=="ghbdtn ")
            #expect(f.acknowledgements.map(\.outcome)==["rejected"])
            #expect(f.deliveries.allSatisfy{$0.marker==0})
        }.value
    }
    @Test func targetMappedReplayReachesEditorOnceAndPreservesNextWordThroughRustAcknowledgement() throws {
        let f = ObserverRuntimeFixture()
        f.type("ghbdtn")
        f.beforeCarrier = {
            f.beforeCarrier = nil
            #expect(f.layout == "ru")
            f.type("yjdjt", flush: false) // Stale source Unicode, real physical key codes.
            #expect(f.value == "ghbdtn ") // The gate holds every next-word event.
        }
        f.type(" ")
        #expect(f.value == "привет новое")
        #expect(f.replayedDowns.map(\.text) == ["н", "о", "в", "о", "е"])
        #expect(f.acknowledgements.map(\.outcome) == ["submitted"])
        #expect(f.acknowledgements.map(\.status) == ["ok"])
        #expect(f.observedDownText == ["g", "h", "b", "d", "t", "n"])
        let transaction = try #require(f.transactions.first)
        #expect(transaction.released)
        #expect(transaction.hadDeferredEvents)
        f.observer.finish(transaction) // Repeated completion must not replay twice.
        #expect(f.value == "привет новое")

        f.tick() // Replayed observations reach Rust only after the prior ACK.
        #expect(Array(f.observedDownText.suffix(5)) == ["н", "о", "в", "о", "е"])
        f.readable = false // Prevent AX editor_word recovery from hiding lost history.
        f.doubleShift()
        #expect(f.value == "привет yjdjt")
        #expect(f.layout == "us")
        #expect(f.acknowledgements.map(\.outcome) == ["submitted", "submitted"])
        #expect(f.acknowledgements.map(\.status) == ["ok", "ok"])
        #expect(f.replayedDowns.count == 5)
    }

    @Test(arguments: [false, true])
    func rejectionReplaysOriginalLayoutAfterFailedSelectionOrConfirmedRollback(rollback: Bool) {
        let f = ObserverRuntimeFixture()
        f.type("ghbdtn")
        f.selectionSucceeds = rollback
        f.afterSelection = { prepared in
            f.afterSelection = nil
            let pending = f.keystrokes(rollback ? "ф" : "a")
            if rollback {
                #expect(f.layout == "ru")
                prepared.restoreAction()
                f.rejectValidation = true
            }
            #expect(f.layout == "us")
            // In the rollback case this key was translated while target was
            // selected but reached the observer after confirmed restoration.
            for event in pending { f.receive(event) }
            #expect(f.value == "ghbdtn ")
        }
        f.type(" ")
        #expect(f.value == "ghbdtn a")
        #expect(f.layout == "us")
        #expect(f.replayedDowns.map(\.text) == ["a"])
        #expect(!f.deliveries.contains { $0.code == 51 })
        #expect(f.restorationCount == (rollback ? 1 : 0))
        #expect(f.acknowledgements.map(\.outcome) == ["rejected"])
        #expect(f.acknowledgements.map(\.status) == ["reset"])
        f.tick()
        #expect(f.observedDownText.last == "a")
        #expect(f.observedDownText.filter { $0 == "a" }.count == 1)
        #expect(f.replayedDowns.count == 1)
    }

    @Test func carrierTimeoutReleasesQueuedInputAndLateCarrierCannotDeleteAfterRuntimeAcknowledgement() throws {
        let f = ObserverRuntimeFixture()
        f.type("ghbdtn")
        f.delayCarrier = true
        f.beforeCarrier = {
            f.beforeCarrier = nil
            f.type("a", flush: false)
        }
        f.type(" ")
        #expect(f.value == "ghbdtn ф")
        #expect(f.layout == "ru") // Deferred typing claims the selected layout.
        #expect(f.replayedDowns.map(\.text) == ["ф"])
        #expect(f.acknowledgements.map(\.outcome) == ["rejected"])
        #expect(f.acknowledgements.map(\.status) == ["reset"])
        let carrier = try #require(f.delayedCarriers.first)
        let transaction = try #require(f.transactions.first)
        #expect(transaction.released)
        #expect(transaction.failure == "delivery_timeout")
        let count = f.deliveries.count
        f.receive(carrier)
        f.observer.finish(transaction)
        #expect(f.deliveries.count == count)
        #expect(!f.deliveries.contains { $0.code == 51 })
        #expect(f.value == "ghbdtn ф")
        f.tick()
        #expect(f.observedDownText.last == "ф")
        #expect(f.observedDownText.filter { $0 == "ф" }.count == 1)
    }
}
