import AppKit
import Testing
@testable import TypeTune
@testable import TypeTuneSupport

/// Real InputBuffer → Runtime → Rust bridge → controlled editor → ACK.
/// No event is posted to the user's desktop by this fixture.
private final class RuntimeFixture {
    let buffer = InputBuffer()
    let engine = Engine()
    var runtime: Runtime!
    var clock: UInt64 = 1_000_000_000
    var eventClock: UInt64 = 1000
    var value = ""
    var caret = 0
    var layout = "us"
    var identity = "9000:1"
    var secure = false
    var readable = true
    var permission = true
    var holding = false
    var prepareFails = false
    var commitOutcome = "submitted"
    var acknowledgementOverride: String?
    var committed = 0
    var finished = 0
    var textReads = 0
    var events: [[String: Any]] = []
    var results: [[String: Any]] = []
    var layoutNotices: [[String: Any]] = []
    var logs: [String] = []
    var resets = 0
    var duringCommit: (() -> Void)?
    var beforeCommit: (() -> Void)?
    var onSleep: (() -> Void)?
    var textOverride: (() -> TextState?)?
    var shiftHeld = false
    var targetPIDOverride: Int32?

    init(settings: Settings = Settings()) {
        var io = RuntimeEnvironment()
        io.buffer = buffer
        io.log = { [unowned self] in logs.append($0) }
        io.now = { [unowned self] in clock }
        io.sleep = { [unowned self] seconds in clock += UInt64(seconds * 1_000_000_000); onSleep?() }
        io.typingKeyHeld = { [unowned self] in holding }
        io.modifiersHeld = { false }
        io.sound = { _,_,_,_,_ in }
        io.context = { [unowned self] keyboards in
            let source = layout == "us" ? "com.apple.keylayout.ABC" : "com.apple.keylayout.RussianWin"
            return NativeContext(identity: identity, bundle: "fixture.editor", layout: layout,
                element: nil, secure: secure, permitted: permission,
                usableOverride: permission && !secure && keyboards.contains(source))
        }
        io.text = { [unowned self] _ in
            textReads += 1
            if let textOverride { return textOverride() }
            return readable ? TextState(value: value, range: CFRange(location: caret, length: 0)) : nil
        }
        io.canCommit = { [unowned self] context in permission && !secure && context.identity == identity }
        io.validateText = { [unowned self] _, expected in
            readable && value == expected.value && caret == expected.range.location && expected.range.length == 0
        }
        io.select = { [unowned self] mode, _ in
            guard !prepareFails else { return false }
            layout = mode; return true
        }
        io.beginEdit = { [unowned self] remove, replacement, mode, _, revision, _ in
            guard !prepareFails, revision == buffer.currentRevision() else { return nil }
            return RuntimeEditTransaction(commit: { [unowned self] validate in
                beforeCommit?()
                guard validate() else { return RuntimeCommitResult(outcome: "rejected", reason: "guard") }
                if commitOutcome == "rejected" { return RuntimeCommitResult(outcome: "rejected", reason: "select") }
                committed += 1
                let end = String.Index(utf16Offset: caret, in: value)
                let prefix = String(value[..<end].dropLast(remove))
                let suffix = String(value[end...])
                value = prefix + replacement + suffix
                caret = prefix.utf16.count + replacement.utf16.count
                layout = mode
                let deferred = duringCommit != nil
                duringCommit?()
                return RuntimeCommitResult(outcome: commitOutcome, reason: "fixture", hadDeferredEvents: deferred)
            }, finish: { [unowned self] in finished += 1 })
        }
        runtime = Runtime(environment: io, engineCall: { [unowned self] request in
            if request["op"] as? String == "reset_context" { resets += 1 }
            if request["op"] as? String == "key_event" { events.append(request) }
            if request["op"] as? String == "edit_result" {
                results.append(request)
                let answer = engine.call(request)
                if let acknowledgementOverride { return ["status": acknowledgementOverride] }
                return answer
            }
            if request["op"] as? String == "layout_notice" { layoutNotices.append(request) }
            return engine.call(request)
        })
        runtime.configure(settings) { _ in }
        tick() // observe the configuration discontinuity before real input
    }

    func tick() {
        clock += 10_000_000
        runtime.queue.sync { runtime.tick() }
    }

    func send(code: CGKeyCode, type: CGEventType, text: String? = nil) {
        eventClock += 10
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.flags = type == .flagsChanged && shiftHeld ? .maskShift:[]
        event.timestamp = eventClock * 1_000_000
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        let target=targetPIDOverride ?? Int32(identity.split(separator:":").first ?? "") ?? 0
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(target))
        if let text {
            let units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        buffer.push(event, type: type)
    }

    func type(_ text: String, flush: Bool = true) {
        for character in text {
            let string = String(character)
            let code: CGKeyCode = character == " " ? 49 : 0
            send(code: code, type: .keyDown, text: string)
            send(code: code, type: .keyUp)
            let index = String.Index(utf16Offset: caret, in: value)
            value.insert(contentsOf: string, at: index)
            caret += string.utf16.count
        }
        if flush { tick() }
    }

    /// Physical Space events whose visible text is normalized by the editor.
    func spaces(_ renderedTail: String, flush: Bool = true) {
        for character in renderedTail {
            send(code: 49, type: .keyDown)
            send(code: 49, type: .keyUp)
            let index = String.Index(utf16Offset: caret, in: value)
            value.insert(character, at: index)
            caret += String(character).utf16.count
        }
        if flush { tick() }
    }

    func doubleShift(flush: Bool = true) {
        for down in [true, false, true, false] {
            shiftHeld = down
            send(code: 56, type: .flagsChanged)
        }
        if flush { tick() }
    }
}

struct RuntimeIntegrationTests {
    @Test func aMatchingSpaceCannotRecoverAWordFromAMixedDestinationBatch() {
        let f=RuntimeFixture()
        f.targetPIDOverride=7777;f.type("ghbdtn",flush:false)
        f.targetPIDOverride=nil;f.type(" ")
        #expect(f.committed==0)
        #expect(f.events.isEmpty)
        #expect(f.value=="ghbdtn ")
    }
    @Test(arguments: [Int32(0),Int32(7777)], [false,true])
    func routedInputMustMatchTheContextEvenWithAccessibleText(target:Int32,readable:Bool) {
        let f=RuntimeFixture();f.readable=readable;f.targetPIDOverride=target
        f.type("ghbdtn ")
        #expect(f.committed==0)
        #expect(f.events.isEmpty)
        #expect(f.value=="ghbdtn ")
        #expect(f.layout=="us")
    }
    @Test(arguments: ["\u{00A0}", " \u{00A0}", "\u{00A0} "])
    func automaticEditorRenderedSpacesSurviveCorrectionAndManualRetoggle(tail: String) {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.spaces(tail)
        #expect(f.value == "привет" + tail)
        #expect(f.caret == 6 + tail.utf16.count)
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
        f.doubleShift()
        #expect(f.value == "ghbdtn" + tail)
        #expect(f.runtime.lastOutcome == "verified")
        f.doubleShift()
        #expect(f.value == "привет" + tail)
        #expect(f.committed == 3)
    }

    @Test(arguments: [true, false])
    func editorRenderedSpacesWaitForTheCompleteObservedTail(historyWasBroken: Bool) {
        let f = RuntimeFixture()
        if historyWasBroken {
            f.type("ghb", flush: false)
            f.buffer.invalidate(); f.tick()
            f.type("dtn")
        } else { f.type("ghbdtn") }
        f.spaces(" \u{00A0}", flush: false)
        var reads = 0
        f.textOverride = { [unowned f] in
            reads += 1
            if reads == 1 { return TextState(value: "ghbdtn\u{00A0}", range: CFRange(location: 7, length: 0)) }
            return TextState(value: f.value, range: CFRange(location: f.caret, length: 0))
        }
        f.onSleep = { [unowned f] in f.textOverride = nil }
        f.tick()
        #expect(f.value == "привет \u{00A0}")
        #expect(f.caret == 8)
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
        #expect(!f.logs.contains("edit_rejected reason=word_mismatch"))
    }

    @Test func staleSpaceCannotReadANewerNBSPWordAndChangeItsReplacementRange() {
        let f = RuntimeFixture()
        f.type("ghbdtn", flush: false)
        f.spaces("\u{00A0}", flush: false)
        f.type("ghbdtn", flush: false)
        f.tick()
        #expect(f.value == "ghbdtn\u{00A0}ghbdtn")
        #expect(f.committed == 0)
        f.spaces("\u{00A0}")
        #expect(f.value == "ghbdtn\u{00A0}привет\u{00A0}")
        #expect(f.committed == 1)
    }

    @Test func initialLayoutBaselineDoesNotSuppressTheFirstWord() {
        let f = RuntimeFixture()
        f.type("ghbdtn ")
        #expect(f.value == "привет ")
        #expect(f.runtime.lastOutcome == "verified")
        #expect(f.layoutNotices.first?["source"] as? String == "own")
    }

    @Test func automaticEditVerifiesExactTextAndCanImmediatelyRetoggle() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.type(" ")
        #expect(f.value == "привет ")
        #expect(f.caret == "привет ".utf16.count)
        #expect(f.runtime.lastOutcome == "verified")
        #expect(f.finished == 1)
        f.doubleShift()
        #expect(f.value == "ghbdtn ")
        #expect(f.runtime.lastOutcome == "verified")
        f.doubleShift()
        #expect(f.value == "привет ")
        #expect(f.committed == 3)
    }

    @Test func laggingAXSpaceSettlesWithoutDeletingWrongRange() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        f.onSleep = { [unowned f] in
            if f.value == "ghbdtn" { f.value += " "; f.caret += 1 }
        }
        f.tick()
        #expect(f.value == "привет ")
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
    }

    @Test func permanentlyLaggingAXRefusesBeforeOutput() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        f.tick()
        #expect(f.value == "ghbdtn")
        #expect(f.committed == 0)
        #expect(f.runtime.lastOutcome == "rejected")
    }

    @Test func brokenHistoryWaitsForAXSpaceBeforeRecoveringTheCompleteWord() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        f.onSleep = { [unowned f] in
            if f.value == "ghbdtn" { f.value += " "; f.caret += 1 }
        }
        f.tick()
        #expect(f.value == "привет ")
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
    }

    @Test func brokenHistoryWithPermanentlyLaggingAXNeverBeginsAnEdit() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        let before = f.clock
        f.tick()
        #expect(f.clock - before == 40_000_000) // one tick plus the bounded AX wait
        #expect(f.value == "ghbdtn")
        #expect(f.committed == 0)
        #expect(f.results.isEmpty)
    }

    @Test func secondSpaceRecoversAfterTheFirstAXSnapshotWasInvalid() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        f.tick()
        #expect(f.committed == 0)
        // The editor catches up after the first bounded wait, then receives
        // another Space. The engine's history_reset must still be respected.
        f.value += " "; f.caret += 1
        f.type(" ")
        #expect(f.value == "привет  ")
        #expect(f.caret == 8)
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
    }

    @Test func brokenHistoryWithTwoSpacesInOneBatchRecoversAtTheLatestBoundary() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.type("  ")
        #expect(f.value == "привет  ")
        #expect(f.caret == 8)
        #expect(f.committed == 1)
        #expect(f.results.map { $0["outcome"] as? String } == ["verified"])
    }

    @Test(arguments: [true, false])
    func recoveryWaitsForEveryObservedSpaceBeforePlanningTheReplacement(historyWasBroken: Bool) {
        let f = RuntimeFixture()
        if historyWasBroken {
            f.type("ghb", flush: false)
            f.buffer.invalidate(); f.tick()
            f.type("dtn")
        } else { f.type("ghbdtn") }
        f.type("  ", flush: false)
        var reads = 0
        f.textOverride = { [unowned f] in
            reads += 1
            // AX initially exposes only the first of the two observed Spaces.
            if reads == 1 { return TextState(value: "ghbdtn ", range: CFRange(location: 7, length: 0)) }
            return TextState(value: f.value, range: CFRange(location: f.caret, length: 0))
        }
        f.onSleep = { [unowned f] in f.textOverride = nil }
        f.tick()
        #expect(f.value == "привет  ")
        #expect(f.caret == 8)
        #expect(f.committed == 1)
        let outcomes = historyWasBroken ? ["verified"] : ["rejected", "verified"]
        #expect(f.results.map { $0["outcome"] as? String } == outcomes)
        #expect(!f.logs.contains("edit_rejected reason=word_mismatch"))
    }

    @Test func recoveryRefusesIfAXNeverIncludesEveryObservedSpace() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.type("  ", flush: false)
        f.textOverride = { TextState(value: "ghbdtn ", range: CFRange(location: 7, length: 0)) }
        f.tick()
        #expect(f.value == "ghbdtn  ")
        #expect(f.committed == 0)
        #expect(f.results.isEmpty)
    }

    @Test(arguments: ["pointer", "field", "observation_loss"])
    func delimiterCountDoesNotCarryAcrossContextChanges(change: String) {
        let f = RuntimeFixture()
        f.type("hello  ")
        f.value = "ghbdtn"; f.caret = 6
        switch change {
        case "pointer": f.send(code: 0, type: .leftMouseDown)
        case "field": f.identity = "9000:2"; f.clock += 500_000_000
        default:
            f.send(code: 123, type: .keyDown)
            f.buffer.invalidate()
        }
        f.tick()
        if change == "observation_loss" {
            // Loss also invalidates the remembered field. Establish its fresh
            // identity before admitting the next input batch.
            f.clock += 500_000_000; f.tick()
        }
        f.type(" ")
        #expect(f.value == "привет ")
        #expect(f.committed == 1)
        #expect(f.runtime.lastOutcome == "verified")
    }

    @Test func newInputDuringBrokenHistoryAXWaitCannotAuthorizeAnOldBoundary() {
        let f = RuntimeFixture()
        f.type("ghb", flush: false)
        f.buffer.invalidate(); f.tick()
        f.type("dtn")
        f.send(code: 49, type: .keyDown)
        f.send(code: 49, type: .keyUp)
        f.onSleep = { [unowned f] in
            f.onSleep = nil
            f.type(" ghbdtn", flush: false)
        }
        f.tick()
        #expect(f.value == "ghbdtn ghbdtn")
        #expect(f.committed == 0)
        #expect(f.results.isEmpty)
        f.tick() // consume the newer input only after the old boundary is refused
        f.type(" ")
        #expect(f.value == "ghbdtn привет ")
        #expect(f.committed == 1)
    }

    @Test func staleSpaceCannotEraseNextWordAndItsTailIsProcessed() {
        let f = RuntimeFixture()
        f.type("ghbdtn ghbdtn", flush: false)
        f.tick()
        #expect(f.value == "ghbdtn ghbdtn")
        #expect(f.committed == 0)
        #expect(f.runtime.lastOutcome == "rejected")
        f.type(" ")
        #expect(f.value == "ghbdtn привет ")
        #expect(f.committed == 1)
    }

    @Test func additionalSpaceReplansCompleteAXWordWithoutShiftedDeletion() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.type("  ")
        #expect(f.value == "привет  ")
        #expect(f.caret == 8)
        #expect(f.committed == 1)
        #expect(f.results.map{$0["outcome"] as? String} == ["rejected","verified"])
    }

    @Test func additionalSpaceWithoutAXCannotRecoverFromAStalePlan() {
        let f=RuntimeFixture();f.readable=false
        f.type("ghbdtn");f.type("  ")
        #expect(f.value=="ghbdtn  ")
        #expect(f.committed==0)
    }

    @Test func noAXStillSupportsManualAndAutoWithoutVerifiedFeedback() {
        let f = RuntimeFixture()
        f.readable = false
        f.type("ghbdtn")
        f.type(" ")
        #expect(f.value == "привет ")
        #expect(f.runtime.lastOutcome == "submitted")
        #expect(f.results.last?["outcome"] as? String == "submitted")
        f.doubleShift()
        #expect(f.value == "ghbdtn ")
        #expect(f.runtime.lastOutcome == "submitted")
    }

    @Test func inputDuringCommitSurvivesAndIsConsumedAfterAcknowledgement() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.duringCommit = { [unowned f] in f.type("новое", flush: false) }
        f.type(" ")
        #expect(f.value == "привет новое")
        #expect(f.runtime.lastOutcome == "submitted")
        #expect(f.finished == 1)
        let previousEvents = f.events.count
        f.duringCommit = nil
        f.tick()
        #expect(f.events.count == previousEvents + 10)
        f.doubleShift()
        #expect(f.value == "привет yjdjt")
    }

    @Test func manualSettingDoesNotDisableAutomaticMode() {
        var settings = Settings(); settings.manualSwitching = false
        let f = RuntimeFixture(settings: settings)
        f.type("ghbdtn")
        f.doubleShift()
        #expect(f.value == "ghbdtn")
        #expect(f.committed == 0)
        f.type(" ")
        #expect(f.value == "привет ")
    }

    @Test func secureAndUnselectedSourcesNeverBeginAnEdit() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.secure = true
        f.doubleShift()
        #expect(f.committed == 0)
        #expect(f.value == "ghbdtn")
        var settings = Settings(); settings.activeKeyboards = []
        let disabled = RuntimeFixture(settings: settings)
        disabled.type("ghbdtn ")
        disabled.doubleShift()
        #expect(disabled.committed == 0)
    }

    @Test func observationLossDiscardsTheEntireAffectedBatch() {
        let f = RuntimeFixture()
        f.type("ghbdtn", flush: false)
        f.buffer.invalidate()
        f.doubleShift(flush: false)
        f.tick()
        #expect(f.events.isEmpty)
        #expect(f.committed == 0)
        #expect(f.value == "ghbdtn")
    }

    @Test func staleAcknowledgementCannotClaimSuccessfulCorrection() {
        let f = RuntimeFixture()
        f.acknowledgementOverride = "stale"
        f.type("ghbdtn ")
        #expect(f.value == "привет ")
        #expect(f.runtime.status == "Результат исправления неизвестен")
        let resets = f.resets
        f.acknowledgementOverride = nil
        f.readable = false
        f.doubleShift()
        #expect(f.value == "привет ")
        #expect(f.committed == 1)
        #expect(resets >= 2)
    }

    @Test func losingAKnownFieldBreaksHistoryBeforeAnotherFieldAppears() {
        let f = RuntimeFixture()
        f.type("ghbdtn")
        f.identity = "9000:0"; f.readable = false
        f.doubleShift()
        #expect(f.committed == 0)
        #expect(f.value == "ghbdtn")
        f.identity = "9000:2"; f.readable = true
        f.value = "rfr"; f.caret = 3
        f.clock += 500_000_000
        f.tick() // establish the new field before its fresh gesture
        f.doubleShift()
        #expect(f.value == "как")
        #expect(f.committed == 1)
    }

    @Test func oldBatchCannotBecomeHistoryInANewUnreadableField() {
        let f = RuntimeFixture()
        f.type("old")
        f.type(" ghbdtn", flush: false)
        f.doubleShift(flush: false)
        f.identity = "9000:2"; f.readable = false
        f.value = "targetword"; f.caret = 10
        f.tick()
        #expect(f.value == "targetword")
        #expect(f.committed == 0)
    }

    @Test func programmaticCaretChangeInTheSameFieldRejectsBeforeDeletion() {
        let f = RuntimeFixture()
        f.beforeCommit = { f.value = "targetword"; f.caret = 10 }
        f.type("ghbdtn ")
        #expect(f.value == "targetword")
        #expect(f.committed == 0)
        #expect(f.runtime.lastOutcome == "rejected")
    }

    @Test func engineHistoryResetDisallowsNoAXSuffixCorrections() {
        let f = RuntimeFixture()
        f.readable = false
        f.type("_ghbdtn")
        f.doubleShift()
        #expect(f.value == "_ghbdtn")
        #expect(f.committed == 0)
        f.send(code: 123, type: .keyDown)
        f.send(code: 123, type: .keyUp)
        f.caret -= 1
        f.type("ghbdtn")
        f.doubleShift()
        #expect(f.committed == 0)
    }

    @Test func historyOnlyNeverRewritesASuffixAfterObservationGap() {
        let f = RuntimeFixture()
        f.readable = false
        f.type("ghb", flush: false)
        f.buffer.invalidate()
        f.tick()
        f.type("dtn")
        f.doubleShift()
        #expect(f.value == "ghbdtn")
        #expect(f.committed == 0)
        f.type(" ") // known boundary restores history-only mode for the next word
        f.type("ghbdtn ")
        #expect(f.value == "ghbdtn привет ")
    }

    @Test func rejectionReportsActualLayoutWithoutFalseExternalSwitch() {
        let f = RuntimeFixture()
        f.prepareFails = true
        f.type("ghbdtn ")
        #expect(f.layout == "us")
        #expect(f.value == "ghbdtn ")
        #expect(!f.layoutNotices.contains { $0["layout"] as? String == "ru" })
    }

    @Test func slowReadbackNeverHoldsTheInputTransaction() {
        let f = RuntimeFixture()
        f.commitOutcome = "indeterminate"
        f.type("ghbdtn ")
        #expect(f.finished == 1)
        #expect(f.runtime.lastOutcome == "indeterminate")
        #expect(f.committed == 1)
        f.tick()
        #expect(f.committed == 1)
    }

    @Test func selectedRangeAndUnicodeSurroundingsRemainIntact() {
        let f = RuntimeFixture()
        f.value = "😀\nghbdtn suffix"; f.caret = "😀\nghbdtn".utf16.count
        f.doubleShift()
        #expect(f.value == "😀\nпривет suffix")
        #expect(f.caret == "😀\nпривет".utf16.count)
        #expect(f.runtime.lastOutcome == "verified")
    }
}
