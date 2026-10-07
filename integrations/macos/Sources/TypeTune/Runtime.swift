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
    var historyOnly = false
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
        let observer = Observer(transport:.sessionHistory,lifecycle:.hidHistory)
        var io = Self()
        io.historyOnly = true
        io.buffer = observer.buffer
        io.isActive = { observer.isActive }
        io.start = observer.start
        io.recover = observer.recover
        io.stop = observer.stop
        // Runtime owns this closure on its serial queue. TCC queries need not
        // run for every packet or while a replacement waits for key release.
        var permissionStamp: UInt64 = 0
        var permissions = ObserverPermissions(listen:false,post:false,accessibility:false)
        io.context = {
            let now=DispatchTime.now().uptimeNanoseconds
            if now>=permissionStamp {
                permissions=ObserverPermissions.current()
                permissionStamp=now+1_000_000_000
            }
            return Native.historyContext(activeKeyboards:$0,permissions:permissions)
        }
        io.text = { _ in nil }
        io.canCommit = { $0.permitted && $0.usable && !$0.secure && Native.fastTargetIsSafe($0.pid) }
        io.beginEdit = { remove, replacement, mode, keyboards, revision, context in
            guard let prepared = Native.prepareReplacement(remove: remove, replacement: replacement,
                      mode: mode, activeKeyboards: keyboards,sessionHistory:true) else { return nil }
            var transaction: EditTransaction?
            return RuntimeEditTransaction(commit: { validate in
                // Initial context validation must not hold physical input. The
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
    enum SuspensionReason: String { case sleep, session, screenLock }
    let queue = DispatchQueue(label: "dev.kartamyshev.TypeTune.runtime", qos: .userInteractive)
    private let io: RuntimeEnvironment
    private let call: ([String: Any]) -> [String: Any]
    private var timer: DispatchSourceTimer?
    private var settings = Settings()
    private var enabled = true
    private var suspensionReasons: Set<SuspensionReason> = []
    private var suspended: Bool { !suspensionReasons.isEmpty }
    private var focus = FocusHistory()
    private var hasObservedContext = false
    private var historyIdentity = ""
    private var historyBroken = false
    private var consecutiveObservedSpaces = 0
    private(set) var status = ""
    private(set) var lastOutcome: String?
    private var lastIssue: String?
    private var lastPermissionIssue: String?
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
    func setSuspended(_ value: Bool, reason: SuspensionReason) {
        io.buffer.invalidate()
        queue.async {
            let wasSuspended = self.suspended
            if value { self.suspensionReasons.insert(reason) }
            else { self.suspensionReasons.remove(reason) }
            self.reset(); self.nextIdleCheck = 0
            self.io.log("runtime_suspension reason=\(reason.rawValue) active=\(value) suspended=\(self.suspended)")
            if wasSuspended && !self.suspended {
                // Recreate the registration after the last resume signal:
                // an enabled pre-sleep port alone does not prove delivery.
                self.io.stop(); self.nextStart = 0
            }
        }
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
        // Refresh native context for input or at 2Hz, not continuously while idle.
        guard !batch.isEmpty || lost || now >= nextIdleCheck else { return }
        nextIdleCheck = now &+ 500_000_000
        let contextStarted = io.now()
        let context = io.context(settings.activeKeyboards)
        let contextMicros = (io.now() &- contextStarted) / 1_000
        noteLayout(context.layout, source: "user")
        let accepting = enabled && !suspended && settings.compatibility && context.usable && !context.secure
            && context.bundle != Bundle.main.bundleIdentifier
        io.buffer.accepting.store(accepting, ordering: .releasing)
        let historyContextChanged = io.historyOnly && historyIdentity != context.identity
        if io.historyOnly && accepting { historyIdentity = context.identity }
        if lost {
            if !batch.isEmpty || (io.historyOnly && !historyContextChanged) { historyBroken = true }
            else if historyContextChanged { historyBroken = false }
            reset()
            io.log("history_reset reason=observer_discontinuity discarded=\(batch.count)")
            return
        }
        guard enabled, !suspended, settings.compatibility else {
            reset(); report(!settings.compatibility ? "Включите режим совместимости" : "На паузе"); return
        }
        guard context.permitted else {
            reset()
            let reason=context.permissionIssue ?? "permission_access"
            if lastPermissionIssue != reason {io.log("runtime_blocked reason=\(reason)");lastPermissionIssue=reason}
            switch reason {
            case "listen_access": report("Нужен доступ: Мониторинг ввода")
            case "accessibility_access": report("Нужен доступ: Управление устройством и доступ к данным")
            case "post_access": report("Перезапустите TypeTune после изменения разрешений")
            default: report("Нужны разрешения: мониторинг ввода и универсальный доступ")
            }
            return
        }
        lastPermissionIssue=nil
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
            if changedExistingContext {
                if !io.historyOnly { historyBroken = true }
                else if historyContextChanged { historyBroken = false }
            }
            hasObservedContext = true
            _ = call(["op": "reset_context"])
            io.log("history_reset reason=focus_change")
            // AX mode cannot attribute a batch to the new field. HID history
            // already checked every intended application, and starts fresh only
            // on an actual application change, never after an observation gap.
            if changedExistingContext && !io.historyOnly { return }
        }
        for observation in batch {
            let decisionStarted = io.now()
            // Pointer navigation can move the caret within the same AX element.
            if observation.key == "pointer" {
                consecutiveObservedSpaces = 0
                historyBroken = !io.historyOnly
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
            let inferenceStarted = io.now()
            let reply = call(["op": "key_event", "event": event,
                              "automatic": automatic, "manual": settings.manualSwitching])
            let inferenceMicros = (io.now() &- inferenceStarted) / 1_000
            var logManualTiming = false
            if ["left_shift", "right_shift"].contains(observation.key) {
                let reason = reply["reason"] as? String ?? ""
                let recognized = reply["gesture_recognized"] as? Bool == true
                // Ordinary first/second edges are not logged. Only recognition
                // or a concrete refusal; no key side, typed word or field ID.
                if recognized || (!reason.isEmpty && reason != "gesture_waiting") {
                    logManualTiming = true
                    let press = (reply["gesture_press_ms"] as? NSNumber)?.stringValue ?? "unknown"
                    let gap = (reply["gesture_gap_ms"] as? NSNumber)?.stringValue ?? "unknown"
                    io.log("manual_decision recognized=\(recognized) reason=\(reason.isEmpty ? "edit_planned" : reason) press_ms=\(press) gap_ms=\(gap)")
                }
            }
            if isSpace || logManualTiming {
                let trigger = isSpace ? "automatic" : "manual"
                io.log("decision_timing trigger=\(trigger) context_us=\(contextMicros) total_us=\((io.now() &- decisionStarted) / 1_000) inference_us=\(inferenceMicros)")
            }
            if isSpace, reply["status"] as? String == "ignored" {
                // One decision summary per boundary, never key codes or text.
                io.log("auto_skipped reason=\(reply["reason"] as? String ?? "no_decision") enabled=\(automatic) editor=\(knownEditor) history_broken=\(historyBroken)")
            }
            if reply["history_reset"] as? Bool == true {
                let explicitBoundary = observation.key == "context" || observation.modifiers & ~1 != 0
                historyBroken = !(io.historyOnly && explicitBoundary)
            }
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
            io.log("edit id=\(reply["id"] as? Int ?? 0) outcome=\(outcome) ack=\(visible == "reset" ? "reset" : "ok") duration_ms=\(elapsed)")
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
        let timingStart = io.now()
        var timings: [String: UInt64] = [:]
        func measured<T>(_ stage: String, _ body: () -> T) -> T {
            let start = io.now()
            defer { timings[stage, default: 0] += (io.now() &- start) / 1_000 }
            return body()
        }
        defer {
            let stages = timings.keys.sorted().map { "\($0)_us=\(timings[$0]!)" }.joined(separator: " ")
            let trigger = observation.key == "space" ? "automatic" : "manual"
            io.log("edit_timing id=\(plan["id"] as? Int ?? 0) trigger=\(trigger) total_us=\((io.now() &- timingStart) / 1_000) \(stages)")
        }
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
        let released = measured("wait_held") {
            while io.typingKeyHeld() {
                guard unchanged() else { return false }
                io.sleep(0.002)
            }
            return true
        }
        guard released else { return reject("held_key_or_new_input") }
        let current = measured("context") { io.context(settings.activeKeyboards) }
        guard current.usable, !current.secure, current.identity == context.identity,
              observation.targetPID.map({$0>0 && $0==current.pid}) ?? true,
              unchanged() else { return reject("context_changed") }
        var old = measured("snapshot") { io.text(current) }
        var expected: ValidatedTextEdit?
        if old != nil {
            // Space can reach the tap before the editor updates AX. Wait for
            // that exact snapshot, never trim delimiters to force a match.
            let settleDeadline = min(deadline, io.now() &+ 30_000_000)
            while let snapshot = old {
                expected = measured("editor_prepare") {
                    EditorWord.prepare(before: before, replacement: replacement, in: snapshot.value,
                        selection: NSRange(location: snapshot.range.location, length: snapshot.range.length))
                }
                if expected != nil { break }
                guard unchanged(), io.now() < settleDeadline else { return reject("word_mismatch") }
                measured("settle_wait") { io.sleep(0.002) }
                old = measured("snapshot") { io.text(current) }
            }
            guard expected != nil else { return reject("snapshot_lost") }
        }
        guard unchanged(), let transaction = measured("native_prepare", {
            io.beginEdit(count, replacement, mode, settings.activeKeyboards, fence, current)
        }) else { return reject("preparation_or_stale") }
        let result = measured("commit") {
            transaction.commit {
                guard measured("validate_focus", { self.io.canCommit(current) }) else {
                    self.io.log("validation_rejected reason=field_context")
                    return false
                }
                // Programmatic edits need not produce a keyboard/focus event.
                let same = measured("validate_text") { old.map { self.io.validateText(current, $0) } ?? true }
                if !same { self.io.log("validation_rejected reason=text_snapshot") }
                return same
            }
        }
        // AX readback must never hold physical input behind a slow editor.
        measured("release") { transaction.finish() }
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
            let observedContext = measured("verify_context") { io.context(settings.activeKeyboards) }
            guard observedContext.identity == context.identity, observedContext.usable, !observedContext.secure else { return "indeterminate" }
            guard let actual = measured("verify_text", { io.text(observedContext) }) else { return "submitted" }
            if actual.value == expected.expected, actual.range.location == expected.caret, actual.range.length == 0 { return "verified" }
            measured("verify_wait") { io.sleep(0.005) }
        } while io.now() < verifyDeadline
        return "indeterminate"
    }
}
