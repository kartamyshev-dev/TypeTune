import AppKit
import TypeTuneSupport

/// Lightweight decision log (no typed text). Helps diagnose live input failures.
enum DiagLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TypeTune/diag.log")
    static func write(_ line: String) {
        let stamped = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        guard let data = stamped.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

final class Runtime {
    let queue=DispatchQueue(label:"dev.kartamyshev.TypeTune.runtime",qos:.userInteractive)
    private let observer=Observer()
    private let engine=Engine()
    private var timer: DispatchSourceTimer?
    private var settings=Settings()
    private var enabled=true
    private var suspended=false
    private var identity=""
    private var status=""
    private var lastIssue: String?
    private var lastLayout=""
    private var lastDiagAt=Date.distantPast
    var publish: ((String) -> Void)?
    func configure(_ value: Settings, completion: @escaping (Bool)->Void) {
        queue.async {
            let reply=self.engine.call([
                "op":"configure",
                "words":value.learned,
                "exclusions":value.exclusions,
                "learned":value.learned,
                "policy":[
                    "switch_only_last_word":value.switchOnlyLastWord,
                    "dont_switch_words":value.dontSwitchWords,
                    "dont_correct_after_layout_change":value.dontCorrectAfterLayoutChange
                ] as [String:Any]
            ])
            let ok=reply["status"] as? String == "configured"
            if ok { self.settings=value;self.identity="";self.lastIssue=nil }
            DispatchQueue.main.async {completion(ok)}
        }
    }
    func start() {
        queue.async { [self] in
            guard self.timer==nil else {return}
            let timer=DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now(),repeating:.milliseconds(15))
            timer.setEventHandler { [weak self] in self?.tick() }; self.timer=timer;timer.resume()
        }
    }
    func setEnabled(_ value: Bool) {observer.buffer.invalidate();queue.async {self.enabled=value;self.lastIssue=nil;self.reset()}}
    func setSuspended(_ value: Bool) {observer.buffer.invalidate();queue.async {self.suspended=value;self.reset()}}
    func stop() { observer.stop();queue.async {self.timer?.cancel();self.timer=nil;self.reset()} }
    private func reset() {_=engine.call(["op":"reset_context"]);identity=""}
    private func report(_ message: String) {
        guard status != message else {return}
        status=message
        DispatchQueue.main.async { [weak self] in self?.publish?(message) }
    }
    private func noteLayout(_ layout: String, source: String) {
        guard layout != lastLayout else {return}
        lastLayout=layout
        _=engine.call(["op":"layout_notice","source":source,"layout":layout])
    }
    private func tick() {
        let context=Native.context()
        noteLayout(context.layout, source:"user")
        let accepting = enabled && !suspended && settings.compatibility && context.usable && context.bundle != Bundle.main.bundleIdentifier
        // Recover the tap BEFORE drain: a lost-queue return used to skip recover()
        // forever and leave Double Shift / auto dead after the first tap disable.
        let listenOK = CGPreflightListenEventAccess()
        let postOK = CGPreflightPostEventAccess()
        if !listenOK || !postOK || !context.permitted {
            // Surface the real TCC state of *this* process (CLI --doctor can lie).
            report("Нужны разрешения: мониторинг ввода\(listenOK ? "" : " (listen)") и универсальный доступ")
            DiagLog.write("perm gate listen=\(listenOK) post=\(postOK) ax=\(context.permitted)")
        }
        if !observer.isActive {
            observer.start()
            DiagLog.write("observer start")
        }
        if !observer.recover() {
            _ = observer.buffer.drain()
            report(listenOK ? "Восстановление наблюдения…" : "Нужны разрешения: мониторинг ввода")
            return
        }
        observer.buffer.accepting.store(accepting,ordering:.relaxed)
        let (batch,lost)=observer.buffer.drain()
        if !accepting && Date().timeIntervalSince(lastDiagAt) > 1.5 {
            lastDiagAt = Date()
            DiagLog.write("accepting=0 layout=\(context.layout) secure=\(context.secure) bundle=\(context.bundle) enabled=\(enabled) suspended=\(suspended) compat=\(settings.compatibility) permitted=\(context.permitted)")
        }
        if lost {DiagLog.write("lost queue reset batch=\(batch.count)");reset()}
        guard enabled, !suspended, settings.compatibility else {
            reset();report(!settings.compatibility ? "Включите режим совместимости" : "На паузе");return
        }
        guard context.permitted else {reset();report("Нужны разрешения: мониторинг ввода и универсальный доступ");return}
        guard context.usable, context.bundle != Bundle.main.bundleIdentifier else {
            DiagLog.write("not-usable layout=\(context.layout) secure=\(context.secure) bundle=\(context.bundle) permitted=\(context.permitted)")
            reset();report(context.secure ? "Приостановлено: защищённый ввод" : (context.layout.isEmpty ? "Поддерживаются ABC и Русская — ПК":"Коррекция отключена для приложения"));return
        }
        // Focus/app change only — layout switches must not drop this batch
        // (that lost Double Shift taps after every auto rewrite).
        if identity != context.identity {
            DiagLog.write("identity-change \(context.identity)")
            _=engine.call(["op":"reset_context"])
            identity=context.identity
        }
        for observation in batch {
            DiagLog.write("key \(observation.key) \(observation.action) origin=\(observation.origin) \(observation.meta) hasText=\(observation.text != nil)")
            var event: [String:Any] = ["key":observation.key,"action":observation.action,"text":observation.text as Any? ?? NSNull(),"time_ms":observation.time,"device":NSNull(),"origin":observation.origin,"modifiers":observation.modifiers]
            // Always try AX word on Shift up so Double Shift recovers even when
            // a few later keys already entered the same drain batch.
            if observation.action=="up", ["left_shift","right_shift"].contains(observation.key) {
                let current=Native.context()
                if current.usable, current.identity==context.identity, let snapshot=Native.text(current) {
                    event["editor_word"]=EditorWord.beforeCaret(in:snapshot.value,selection:NSRange(location:snapshot.range.location,length:snapshot.range.length)) ?? ""
                }
            }
            let auto=settings.autoSwitching && !settings.autoDisabledIn.contains(context.bundle)
            let reply=engine.call(["op":"key_event","event":event,"automatic":auto])
            let status=reply["status"] as? String ?? "?"
            if status != "ignored" { DiagLog.write("engine \(status) auto=\(auto)") }
            if let status=reply["status"] as? String, status=="layout_only" {
                if let mode=reply["mode"] as? String { _=Native.select(mode) }
                noteLayout((reply["mode"] as? String) ?? "", source:"own")
                report("Работает · \(Native.context().layout.uppercased())")
                return
            }
            if reply["status"] as? String == "inferred_edit" {
                observer.buffer.accepting.store(false,ordering:.relaxed)
                let started=DispatchTime.now().uptimeNanoseconds
                let result=execute(reply,observation:observation,context:context)
                DiagLog.write("execute \(result) key=\(observation.key)")
                let elapsed=(DispatchTime.now().uptimeNanoseconds-started)/1_000_000
                // Bridge tri-state: ok | failed_before | unknown_after (legacy aliases accepted).
                let outcome:String = (result=="verified"||result=="submitted") ? "ok" : (result=="rejected" ? "failed_before" : "unknown_after")
                let ack=engine.call(["op":"edit_result","id":reply["id"]!,"outcome":outcome,"time_ms":EditAcknowledgement.resultTime(sourceMs:observation.time,elapsedMs:elapsed)])
                _=observer.buffer.drain()
                identity=Native.context().identity
                if let mode=reply["mode"] as? String { noteLayout(mode, source:"own") }
                if outcome=="failed_before" {report("Не исправлено");return}
                if outcome=="unknown_after" || (ack["status"] as? String ?? "reset")=="reset" {
                    lastIssue="результат неизвестен";report(lastIssue!);return
                }
                lastIssue=nil
                report("Работает · \(Native.context().layout.uppercased())")
                return // discard stale batch after one edit
            }
        }
        report(lastIssue ?? "Работает · \(context.layout.uppercased())")
    }
    private func execute(_ plan:[String:Any],observation:KeyObservation,context:NativeContext)->String {
        guard let before=plan["before"] as? String,let replacement=plan["replacement"] as? String,let count=plan["remove"] as? Int,let mode=plan["mode"] as? String,
              (1...128).contains(count), replacement.count<=128,count==before.count else {return "rejected"}
        let deadline=DispatchTime.now().uptimeNanoseconds+800_000_000
        // Allow this edit when the user is already typing the next word (batch
        // may contain later keys). Only abort if *new* events arrive during
        // execute or the focused element / session moves.
        let fence = observer.buffer.currentRevision()
        func unchanged(_ expected: String) -> Bool {
            guard observer.buffer.currentRevision()==fence,DispatchTime.now().uptimeNanoseconds<deadline,!Native.modifiersHeld() else {return false}
            let current=Native.context()
            return current.usable && current.identity==expected
        }
        guard unchanged(context.identity) else {return "rejected"}
        // Never send a synthetic Up for a key the user still holds.
        // Skip Caps/Fn (layout switch / latch) — they are not typing keys.
        while Native.typingKeyHeld() {
            guard unchanged(context.identity) else {return "rejected"};Thread.sleep(forTimeInterval:0.002)
        }
        let old=Native.text(context)
        if let old {
            guard EditorWord.matches(before,in:old.value,selection:NSRange(location:old.range.location,length:old.range.length)) else {return "rejected"}
        }
        // Select and read back BEFORE editing so a missing layout cannot erase text.
        guard Native.select(mode) else {return "rejected"}
        let changed=Native.context()
        guard changed.bundle==context.bundle,changed.element.map({CFHash($0)})==context.element.map({CFHash($0)}),unchanged(changed.identity),Native.text(changed)==old else {
            return LayoutRestore.after("rejected",original:context.layout,select:Native.select)
        }
        let outcome=ReplacementExecutor.run(remove:count,replacement:replacement,guardCheck:{unchanged(changed.identity)},emit:{ action in
            switch action {case .backspace:return Native.pair(51);case .text(let text):return Native.pair(0,unicode:text)}
        },verify:{
            guard let old else {return nil}
            let expected=(old.value as NSString).replacingCharacters(in:NSRange(location:old.range.location-before.utf16.count,length:before.utf16.count),with:replacement)
            let expectedCaret=old.range.location-before.utf16.count+replacement.utf16.count
            for _ in 0..<10 {
                guard unchanged(changed.identity) else {return false}
                if let actual=Native.text(changed),actual.value==expected,actual.range.location==expectedCaret,actual.range.length==0 {return true}
                Thread.sleep(forTimeInterval:0.01)
            }
            return false
        }).rawValue
        let final=LayoutRestore.after(outcome,original:context.layout,select:Native.select)
        // Sound only after a confirmed switch; never in secure/paused/unknown contexts.
        if final=="verified" || final=="submitted" {
            SwitchSound.playIfAllowed(settingEnabled:settings.playSwitchingSound,running:enabled,suspended:suspended,secure:context.secure,layoutChanged:mode != context.layout)
        }
        return final
    }
}