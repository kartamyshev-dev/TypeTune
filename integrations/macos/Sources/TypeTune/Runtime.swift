import AppKit
import TypeTuneSupport

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
    private var publishedSuggestions=""
    private var lastIssue: String?
    var publish: ((String,[[String:Any]]) -> Void)?
    func configure(_ value: Settings, completion: @escaping (Bool)->Void) {
        queue.async {
            let reply=self.engine.call(["op":"configure","words":value.words,"exclusions":value.exclusions])
            let ok=reply["status"] as? String == "configured"
            if ok { self.settings=value;self.identity="";self.lastIssue=nil;self.observer.buffer.invalidate() }
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
    func dismiss(_ id: UInt64) {queue.async {_=self.engine.call(["op":"dismiss_suggestion","id":id])}}
    func stop() { observer.stop();queue.async {self.timer?.cancel();self.timer=nil;self.reset()} }
    private func reset() {_=engine.call(["op":"reset_context"]);identity=""}
    private func report(_ message: String) {
        let suggestions=engine.call(["op":"suggestions"])["items"] as? [[String:Any]] ?? []
        let signature=String(describing:suggestions)
        guard status != message || signature != publishedSuggestions else {return}
        status=message;publishedSuggestions=signature
        DispatchQueue.main.async { [weak self] in self?.publish?(message,suggestions) }
    }
    private func tick() {
        let context=Native.context()
        observer.buffer.accepting.store(enabled && !suspended && settings.compatibility && context.usable && context.bundle != Bundle.main.bundleIdentifier,ordering:.relaxed)
        let (batch,lost)=observer.buffer.drain()
        if lost {reset();return} // never replay a partial queue after observation loss
        guard enabled, !suspended, settings.compatibility else {
            reset();report(!settings.compatibility ? "Включите режим совместимости" : "На паузе");return
        }
        guard context.permitted else {reset();report("Нужны разрешения: мониторинг ввода и универсальный доступ");return}
        if !observer.isActive {observer.start();reset();report("Подключение наблюдателя…");return}
        guard observer.recover() else {reset();report("Восстановление наблюдения…");return}
        guard context.usable, context.bundle != Bundle.main.bundleIdentifier else {
            reset();report(context.secure ? "Приостановлено: защищённый ввод" : (context.layout.isEmpty ? "Поддерживаются ABC и Русская — ПК":"Коррекция отключена для приложения"));return
        }
        if identity != context.identity {reset();identity=context.identity;return}
        for observation in batch {
            var event: [String:Any] = ["key":observation.key,"action":observation.action,"text":observation.text as Any? ?? NSNull(),"time_ms":observation.time,"device":NSNull(),"origin":observation.origin,"modifiers":observation.modifiers]
            if observation.action=="up", ["left_shift","right_shift"].contains(observation.key),
               observer.buffer.currentRevision()==observation.revision {
                let current=Native.context()
                if current.usable, current.identity==context.identity, let snapshot=Native.text(current) {
                    event["editor_word"]=EditorWord.beforeCaret(in:snapshot.value,selection:NSRange(location:snapshot.range.location,length:snapshot.range.length)) ?? ""
                }
            }
            let reply=engine.call(["op":"key_event","event":event,"automatic":settings.automatic && !settings.applications.contains(context.bundle)])
            if reply["status"] as? String == "inferred_edit" {
                let result=execute(reply,observation:observation,context:context)
                _=engine.call(["op":"edit_result","id":reply["id"]!,"outcome":result,"time_ms":DispatchTime.now().uptimeNanoseconds/1_000_000])
                identity=Native.context().identity
                if result=="indeterminate" {lastIssue="Результат последней замены не определён; история очищена";report(lastIssue!);return}
                if result=="rejected" {report("Замена отменена: контекст изменился");return}
                lastIssue=nil
                report(result=="verified" ? "Замена проверена по тексту" : "Совместимость: события отправлены, текст не подтверждён")
                return // discard stale batch after one edit
            }
        }
        report(lastIssue ?? "Работает · \(context.layout.uppercased()) · режим совместимости")
    }
    private func execute(_ plan:[String:Any],observation:KeyObservation,context:NativeContext)->String {
        guard let before=plan["before"] as? String,let replacement=plan["replacement"] as? String,let count=plan["remove"] as? Int,let mode=plan["mode"] as? String,
              (1...128).contains(count), replacement.count<=128,count==before.count else {return "rejected"}
        let deadline=DispatchTime.now().uptimeNanoseconds+800_000_000
        func unchanged(_ expected: String) -> Bool {
            guard observer.buffer.currentRevision()==observation.revision,DispatchTime.now().uptimeNanoseconds<deadline,!Native.modifiersHeld() else {return false}
            let current=Native.context()
            return current.usable && current.identity==expected
        }
        guard unchanged(context.identity) else {return "rejected"}
        // Never send a synthetic Up for a key the user still holds.
        while (0..<128).contains(where:{CGEventSource.keyState(.hidSystemState,key:CGKeyCode($0))}) {
            guard unchanged(context.identity) else {return "rejected"};Thread.sleep(forTimeInterval:0.002)
        }
        let old=Native.text(context)
        if let old {
            guard EditorWord.matches(before,in:old.value,selection:NSRange(location:old.range.location,length:old.range.length)) else {return "rejected"}
        }
        // Select and read back BEFORE editing so a missing layout cannot erase text.
        guard Native.select(mode) else {return "rejected"}
        let changed=Native.context()
        guard changed.bundle==context.bundle,changed.element.map({CFHash($0)})==context.element.map({CFHash($0)}),unchanged(changed.identity),Native.text(changed)==old else {return "rejected"}
        return ReplacementExecutor.run(remove:count,replacement:replacement,guardCheck:{unchanged(changed.identity)},emit:{ action in
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
    }
}
