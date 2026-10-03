import AppKit
import TypeTuneSupport

struct RuntimeCommitResult {
    var outcome: String
    var reason: String
    var hadDeferredEvents = false
}

struct RuntimeEditTransaction {
    let commit: (_ validate: () -> Bool) -> RuntimeCommitResult
    let finish: () -> Void
}

/// Replace system I/O in tests; the event loop, bridge and acknowledgements stay real.
struct RuntimeEnvironment {
    var buffer = InputBuffer()
    var isActive: () -> Bool = { true }
    var start: () -> Void = {}
    var recover: () -> Bool = { true }
    var stop: () -> Void = {}
    var log: (String) -> Void = DiagLog.write
    var context: ([String]) -> NativeContext = { Native.context(activeKeyboards: $0) }
    var text: (NativeContext) -> TextState? = Native.text
    var validateText: (NativeContext, TextState) -> Bool = { Native.text($0, timeout: 0.05) == $1 }
    var typingKeyHeld: () -> Bool = Native.typingKeyHeld
    var modifiersHeld: () -> Bool = Native.modifiersHeld
    var canCommit: (NativeContext) -> Bool = { Native.canCommit($0) }
    var select: (String, [String]) -> Bool = { Native.select($0, activeKeyboards: $1) }
    var now: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    var sleep: (Double) -> Void = Thread.sleep(forTimeInterval:)
    var sound: (Bool, Bool, Bool, Bool, Bool) -> Void = {
        SwitchSound.playIfAllowed(settingEnabled: $0, running: $1, suspended: $2, secure: $3, layoutChanged: $4)
    }
    var beginEdit: (Int, String, String, [String], UInt64, NativeContext) -> RuntimeEditTransaction? = { _,_,_,_,_,_ in nil }

    static func live() -> Self {
        let observer = Observer()
        var io = Self()
        io.buffer = observer.buffer
        io.isActive = { observer.isActive }
        io.start = observer.start
        io.recover = observer.recover
        io.stop = observer.stop
        io.beginEdit = { remove, replacement, mode, keyboards, revision, context in
            guard let prepared = Native.prepareReplacement(remove: remove, replacement: replacement,
                      mode: mode, activeKeyboards: keyboards) else { return nil }
            var transaction: EditTransaction?
            return RuntimeEditTransaction(commit: { validate in
                // The initial AX validation must not hold physical input. The
                // revision is checked atomically when the short gate begins.
                guard validate() else {return RuntimeCommitResult(outcome:"rejected",reason:"validation_before_gate")}
                guard let admitted = observer.begin(expectedRevision: revision, targetPID: context.pid) else {
                    return RuntimeCommitResult(outcome:"rejected",reason:"admission_after_validation")
                }
                transaction=admitted
                let result = observer.commit(admitted, prepared: prepared, initiallyValidated:true, validateBeforeOutput: validate)
                return RuntimeCommitResult(outcome: result.outcome, reason: result.reason,
                                           hadDeferredEvents: result.hadDeferredEvents)
            }, finish: { if let transaction {observer.finish(transaction)} })
        }
        return io
    }
}

final class Runtime {
    let queue = DispatchQueue(label: "dev.kartamyshev.TypeTune.runtime", qos: .userInteractive)
    private let io: RuntimeEnvironment
    private let call: ([String: Any]) -> [String: Any]
    private var timer: DispatchSourceTimer?
    private var settings = Settings()
    private var enabled = true
    private var suspended = false
    private var focus = FocusHistory()
    private var hasObservedContext = false
    private var historyBroken = false
    private var consecutiveObservedSpaces = 0
    private(set) var status = ""
    private(set) var lastOutcome: String?
    private var lastIssue: String?
    private var lastLayout = ""
    private var nextIdleCheck: UInt64 = 0
    private var nextStart: UInt64 = 0
    var publish: ((String) -> Void)?
    var feedback: (([String], [String], UInt64) -> Void)?

    init(environment: RuntimeEnvironment? = nil, engineCall: (([String: Any]) -> [String: Any])? = nil) {
        io = environment ?? .live()
        if let engineCall { call = engineCall }
        else { let engine = Engine(); call = engine.call }
    }

    func configure(_ value: Settings, completion: @escaping (Bool) -> Void) {
        io.buffer.invalidate()
        queue.async {
            let reply = self.call(["op": "configure", "words": [String](), "learned": value.learned,
                "exclusions": value.exclusions, "policy": [
                    "switch_only_last_word": value.switchOnlyLastWord,
                    "dont_switch_words": value.dontSwitchWords,
                    "dont_correct_after_layout_change": value.dontCorrectAfterLayoutChange]])
            let ok = reply["status"] as? String == "configured"
            if ok {
                self.settings = value; self.focus.reset(); self.consecutiveObservedSpaces = 0
                self.lastIssue = nil; self.nextIdleCheck = 0
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func configureDictionary(_ value: Settings, completion: @escaping (Bool) -> Void) {
        queue.async {
            let reply = self.call(["op": "dictionary_update", "words": [String](),
                                   "learned": value.learned, "exclusions": value.exclusions])
            let ok = reply["status"] as? String == "dictionary_updated"
            if ok {
                self.settings.learned = value.learned
                self.settings.exclusions = value.exclusions
                self.settings.generation = value.generation
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    func setEnabled(_ value: Bool) {
        io.buffer.invalidate()
        queue.async { self.enabled = value; self.lastIssue = nil; self.reset(); self.nextIdleCheck = 0 }
    }
    func setSuspended(_ value: Bool) {
        io.buffer.invalidate()
        queue.async { self.suspended = value; self.reset(); self.nextIdleCheck = 0 }
    }
    func stop() {
        io.stop()
        queue.async { self.timer?.cancel(); self.timer = nil; self.reset() }
    }
    private func reset() {
        _ = call(["op": "reset_context"]); focus.reset(); consecutiveObservedSpaces = 0
    }
    private func report(_ message: String) {
        guard status != message else { return }
        status = message
        DispatchQueue.main.async { [weak self] in self?.publish?(message) }
    }
    private func noteLayout(_ layout: String, source: String) {
        guard layout != lastLayout else { return }
        let actualSource = lastLayout.isEmpty ? "own" : source
        lastLayout = layout
        _ = call(["op": "layout_notice", "source": actualSource, "layout": layout])
    }

    /// Runs only on queue; integration tests invoke the same loop.
    func tick() {
        let now = io.now()
        if !io.isActive(), now >= nextStart {
            nextStart = now &+ 1_500_000_000
            io.start()
        }
        guard io.recover() else {
            io.buffer.accepting.store(false, ordering: .releasing)
            _ = io.buffer.drain(); reset()
            report("Восстановление наблюдения; проверьте разрешения")
            return
        }
        let (batch, lost) = io.buffer.drain()
        // AX is queried for input or at 2Hz, not continuously while idle.
        guard !batch.isEmpty || lost || now >= nextIdleCheck else { return }
        nextIdleCheck = now &+ 500_000_000
        let context = io.context(settings.activeKeyboards)
        noteLayout(context.layout, source: "user")
        let accepting = enabled && !suspended && settings.compatibility && context.usable && !context.secure
            && context.bundle != Bundle.main.bundleIdentifier
        io.buffer.accepting.store(accepting, ordering: .releasing)
        if lost {
            if !batch.isEmpty { historyBroken = true }
            reset()
            io.log("history_reset reason=observer_discontinuity discarded=\(batch.count)")
            return
        }
        guard enabled, !suspended, settings.compatibility else {
            reset(); report(!settings.compatibility ? "Включите режим совместимости" : "На паузе"); return
        }
        guard context.permitted else { reset(); report("Нужны разрешения: мониторинг ввода и универсальный доступ"); return }
        guard accepting else {
            reset()
            report(context.secure ? "Приостановлено: защищённый ввод" : "Коррекция недоступна для текущего поля или раскладки")
            return
        }
        // Frontmost/AX state can disagree with the system's actual keyboard
        // recipient. Never feed a mixed/unknown-destination batch to inference
        // or let its later Space recover history through an unrelated AX field.
        guard batch.allSatisfy({$0.targetPID.map {$0>0 && $0==context.pid} ?? true}) else {
            reset();historyBroken=true
            io.log("history_reset reason=input_target discarded=\(batch.count)")
            return
        }
        if focus.observe(context.identity) {
            consecutiveObservedSpaces = 0
            let changedExistingContext = hasObservedContext
            if changedExistingContext { historyBroken = true }
            hasObservedContext = true
            _ = call(["op": "reset_context"])
            io.log("history_reset reason=focus_change")
            // A batch captured before this AX snapshot may belong to the old
            // field. Its Space must not authorize an old suffix in a new field.
            if changedExistingContext { return }
        }
        for observation in batch {
            // Pointer navigation can move the caret within the same AX element.
            if observation.key == "pointer" {
                consecutiveObservedSpaces = 0
                historyBroken = true
                _ = call(["op": "reset_context"])
                continue
            }
            var event: [String: Any] = ["key": observation.key, "action": observation.action,
                "text": observation.text as Any? ?? NSNull(), "time_ms": observation.time,
                "device": NSNull(), "origin": observation.origin, "modifiers": observation.modifiers]
            let isSpace = observation.key == "space" && observation.action != "up"
            if observation.action != "up" {
                // Keep this count across stale/rejected plans in the same
                // field. Each observed delimiter must appear in the AX value
                // before its latest revision can authorize a replacement.
                consecutiveObservedSpaces = isSpace ? min(consecutiveObservedSpaces + 1, 129) : 0
            }
            if settings.manualSwitching, observation.action == "up",
               ["left_shift", "right_shift"].contains(observation.key),
               observation.revision == io.buffer.currentRevision() {
                if let snapshot = io.text(context) {
                    event["editor_word"] = EditorWord.beforeCaret(in: snapshot.value,
                        selection: NSRange(location: snapshot.range.location, length: snapshot.range.length)) ?? ""
                } else if historyBroken {
                    // Collect the gesture edges, but do not let its final edge
                    // recover an unreadable suffix across a discontinuity.
                    event["editor_word"] = ""
                }
            }
            if isSpace,observation.revision == io.buffer.currentRevision() {
                // A newer delimiter may follow a safely cancelled stale plan.
                // AX also exposes editor-rendered NBSPs absent from key history.
                // Preserve that exact tail; ordinary ASCII history keeps its
                // existing inference path when no recovery is needed.
                if let word = completedEditorWord(after: observation, in: context,
                                                   minimumSpaces: consecutiveObservedSpaces),
                   historyBroken || word.contains("\u{00A0}") {
                    event["editor_word"] = word
                }
            }
            let knownEditor = event["editor_word"] != nil
            let historyAllowed = !historyBroken || knownEditor
            // Following an input gap, a suffix is not a complete word. A known
            // editor snapshot can authorize it; otherwise regain a boundary first.
            if historyBroken, isSpace, !knownEditor {
                _ = call(["op": "reset_context"])
                // An old delimiter cannot establish a boundary for newer
                // input. Keep AX recovery enabled for the latest Space.
                if observation.revision == io.buffer.currentRevision() { historyBroken = false }
                continue
            }
            let automatic = settings.autoSwitching && !settings.autoDisabledIn.contains(context.bundle) && historyAllowed
            let reply = call(["op": "key_event", "event": event,
                              "automatic": automatic, "manual": settings.manualSwitching])
            if isSpace, reply["status"] as? String == "ignored" {
                // One decision summary per boundary, never key codes or text.
                io.log("auto_skipped reason=\(reply["reason"] as? String ?? "no_decision") enabled=\(automatic) editor=\(knownEditor) history_broken=\(historyBroken)")
            }
            if reply["history_reset"] as? Bool == true { historyBroken = true }
            else if isSpace { historyBroken = false }
            if reply["status"] as? String == "layout_only" {
                if observation.revision == io.buffer.currentRevision(), let mode = reply["mode"] as? String,
                   io.canCommit(context) {
                    _ = io.select(mode, settings.activeKeyboards)
                    noteLayout(io.context(settings.activeKeyboards).layout, source: "own")
                }
                continue
            }
            guard reply["status"] as? String == "inferred_edit", let id = reply["id"] else { continue }
            let generation = settings.generation
            let started = io.now()
            let outcome = execute(reply, observation: observation, context: context)
            let elapsed = (io.now() &- started) / 1_000_000
            let ack = call(["op": "edit_result", "id": id, "outcome": outcome,
                "time_ms": EditAcknowledgement.resultTime(sourceMs: observation.time, elapsedMs: elapsed)])
            let visible = EditAcknowledgement.visibleOutcome(native: outcome, engine: ack["status"] as? String ?? "")
            lastOutcome = outcome
            if outcome == "verified" { historyBroken = false }
            if visible == "reset" {
                _ = call(["op": "reset_context"])
                historyBroken = true
            }
            io.log("edit outcome=\(outcome) ack=\(visible == "reset" ? "reset" : "ok") duration_ms=\(elapsed)")
            let actual = io.context(settings.activeKeyboards)
            noteLayout(actual.layout, source: "own")
            let movedAfterEdit = focus.observe(actual.identity)
            if movedAfterEdit {
                consecutiveObservedSpaces = 0
                _ = call(["op": "reset_context"])
                historyBroken = true
            }
            if outcome == "rejected" { lastIssue = "Не исправлено: контекст изменился" }
            else if visible == "reset" || outcome == "indeterminate" { lastIssue = "Результат исправления неизвестен" }
            else if outcome == "submitted" { lastIssue = "Отправлено, не проверено" }
            else { lastIssue = nil }
            if visible != "reset", outcome == "verified", let delta = ack["feedback"] as? [String: Any] {
                let learned = delta["learned_add"] as? [String] ?? []
                let exclusions = delta["exclusions_add"] as? [String] ?? []
                if !learned.isEmpty || !exclusions.isEmpty {
                    DispatchQueue.main.async { [weak self] in self?.feedback?(learned, exclusions, generation) }
                }
            }
            // Keep the tail: a rejected stale plan may precede the next word.
            // Newly replayed input is consumed on the next tick after this ACK.
            if movedAfterEdit { break }
        }
        report(lastIssue ?? "Работает · \(context.layout.uppercased())")
    }

    /// AX may still expose the pre-Space value after the tap has observed it.
    /// This wait occurs before a transaction: newer input ends it immediately.
    private func completedEditorWord(after observation: KeyObservation, in context: NativeContext,
                                     minimumSpaces: Int) -> String? {
        let deadline = io.now() &+ 30_000_000
        var hadSnapshot = false
        while observation.revision == io.buffer.currentRevision() {
            guard let snapshot = io.text(context) else { return hadSnapshot ? "" : nil }
            hadSnapshot = true
            guard observation.revision == io.buffer.currentRevision() else { return "" }
            let word = EditorWord.beforeCaret(in: snapshot.value,
                selection: NSRange(location: snapshot.range.location, length: snapshot.range.length))
            if let word, word.reversed().prefix(while: EditorWord.isSupportedSpace).count >= minimumSpaces { return word }
            guard io.now() < deadline else { return "" }
            io.sleep(0.002)
            guard io.now() < deadline else { return "" }
        }
        // A known but stale snapshot must retain the history discontinuity;
        // otherwise the next boundary could use an incomplete history suffix.
        return hadSnapshot ? "" : nil
    }

    private func execute(_ plan: [String: Any], observation: KeyObservation, context: NativeContext) -> String {
        func reject(_ reason: String) -> String {
            io.log("edit_rejected reason=\(reason)")
            return "rejected"
        }
        guard let before = plan["before"] as? String, let replacement = plan["replacement"] as? String,
              let count = plan["remove"] as? Int, let mode = plan["mode"] as? String,
              (1...128).contains(count), !replacement.isEmpty, replacement.count <= 128,
              !replacement.contains("\0"), count == before.count else { return reject("invalid_plan") }
        let fence = observation.revision
        let deadline = io.now() &+ 800_000_000
        func unchanged() -> Bool {
            io.buffer.currentRevision() == fence && io.now() < deadline && !io.modifiersHeld()
        }
        guard unchanged() else { return reject("stale_trigger") }
        while io.typingKeyHeld() {
            guard unchanged() else { return reject("held_key_or_new_input") }
            io.sleep(0.002)
        }
        let current = io.context(settings.activeKeyboards)
        guard current.usable, !current.secure, current.identity == context.identity,
              observation.targetPID.map({$0>0 && $0==current.pid}) ?? true,
              unchanged() else { return reject("context_changed") }
        var old = io.text(current)
        var expected: ValidatedTextEdit?
        if old != nil {
            // Space can reach the tap before the editor updates AX. Wait for
            // that exact snapshot, never trim delimiters to force a match.
            let settleDeadline = min(deadline, io.now() &+ 30_000_000)
            while let snapshot = old {
                expected = EditorWord.prepare(before: before, replacement: replacement, in: snapshot.value,
                    selection: NSRange(location: snapshot.range.location, length: snapshot.range.length))
                if expected != nil { break }
                guard unchanged(), io.now() < settleDeadline else { return reject("word_mismatch") }
                io.sleep(0.002); old = io.text(current)
            }
            guard expected != nil else { return reject("snapshot_lost") }
        }
        guard unchanged(), let transaction = io.beginEdit(count, replacement, mode,
                settings.activeKeyboards, fence, current) else { return reject("preparation_or_stale") }
        let result = transaction.commit {
            guard self.io.canCommit(current) else {
                self.io.log("validation_rejected reason=field_context")
                return false
            }
            // A programmatic caret/value change need not produce a physical
            // event or change field identity. Never delete against an old range.
            let same=old.map { self.io.validateText(current, $0) } ?? true
            if !same {self.io.log("validation_rejected reason=text_snapshot")}
            return same
        }
        // AX readback must never hold physical input behind a slow editor.
        transaction.finish()
        guard result.outcome == "submitted" else {
            io.log("commit_stopped reason=\(result.reason)")
            return result.outcome
        }
        io.sound(settings.playSwitchingSound, enabled, suspended, context.secure, mode != context.layout)
        guard !result.hadDeferredEvents, io.buffer.currentRevision() == fence,
              let expected else { return "submitted" }
        let verifyDeadline = io.now() &+ 100_000_000
        repeat {
            guard io.buffer.currentRevision() == fence else { return "submitted" }
            let observedContext = io.context(settings.activeKeyboards)
            guard observedContext.identity == context.identity, observedContext.usable, !observedContext.secure else { return "indeterminate" }
            guard let actual = io.text(observedContext) else { return "submitted" }
            if actual.value == expected.expected, actual.range.location == expected.caret, actual.range.length == 0 { return "verified" }
            io.sleep(0.005)
        } while io.now() < verifyDeadline
        return "indeterminate"
    }
}
