import Foundation

/// Changes are compared with the snapshot the editor actually displayed. A newer
/// dictionary or an unrelated menu edit must not be replaced by a stale draft.
public enum SettingsMerge {
    public static func edit(base: Settings, proposed: Settings, current: Settings,
                            clearLearned: Bool = false) throws -> Settings {
        try proposed.validate()
        guard base.generation <= current.generation,
              proposed.generation == base.generation else { throw SettingsError.conflict }
        var result = current
        func merge<Value: Equatable>(_ key: WritableKeyPath<Settings, Value>) throws {
            guard proposed[keyPath: key] != base[keyPath: key] else { return }
            guard current[keyPath: key] == base[keyPath: key] || current[keyPath: key] == proposed[keyPath: key] else {
                throw SettingsError.conflict
            }
            result[keyPath: key] = proposed[keyPath: key]
        }
        try merge(\.compatibility)
        try merge(\.autoSwitching)
        try merge(\.manualSwitching)
        try merge(\.switchOnlyLastWord)
        try merge(\.dontSwitchWords)
        try merge(\.dontCorrectAfterLayoutChange)
        try merge(\.displayLayoutFlag)
        try merge(\.playSwitchingSound)
        try merge(\.autostart)
        try merge(\.activeKeyboards)
        result.autoDisabledIn = mergeList(base.autoDisabledIn, proposed.autoDisabledIn, current.autoDisabledIn)
        result.exclusions = mergeList(base.exclusions, proposed.exclusions, current.exclusions)
        result.learned = clearLearned ? [] : mergeList(base.learned, proposed.learned, current.learned)
        try result.validate()
        return result
    }

    private static func mergeList(_ base: [String], _ proposed: [String], _ current: [String]) -> [String] {
        Set(current).subtracting(Set(base).subtracting(proposed))
            .union(Set(proposed).subtracting(base)).sorted()
    }

    public static func dictionaryOnly(from old: Settings, to new: Settings) -> Bool {
        var normalized = new
        normalized.generation = old.generation
        normalized.learned = old.learned
        normalized.exclusions = old.exclusions
        return normalized == old
    }
}

/// The caller and all engine completions use the same serial queue (the app's
/// main queue). File CAS also protects against an independent settings writer.
/// Feedback remains queued while an Apply is waiting for the engine ACK.
public final class SettingsTransactions {
    public struct Environment {
        public var load: () throws -> Settings
        public var save: (Settings, UInt64) throws -> Settings
        public var configure: (Settings, Bool, @escaping (Bool) -> Void) -> Void
        public var autostart: (Bool) throws -> Void
        public init(load: @escaping () throws -> Settings,
                    save: @escaping (Settings, UInt64) throws -> Settings,
                    configure: @escaping (Settings, Bool, @escaping (Bool) -> Void) -> Void,
                    autostart: @escaping (Bool) throws -> Void) {
            self.load = load; self.save = save; self.configure = configure; self.autostart = autostart
        }
    }
    public var onSettings: ((Settings) -> Void)?
    public var onError: ((String) -> Void)?
    public var onRuntimeFailure: (() -> Void)?
    public var onBusy: ((Bool) -> Void)?
    public private(set) var current: Settings
    private var removalBaseline: Settings
    private let environment: Environment
    private enum Change {
        case edit(base: Settings, proposed: Settings, clearLearned: Bool)
        case feedback(learned: [String], exclusions: [String], generation: UInt64)
    }
    private struct Request {
        var change: Change
        var completion: ((Bool) -> Void)?
        var retries = 0
    }
    private var requests: [Request] = []
    private var busy = false
    private var learnedFloor: UInt64 = 0
    private var learnedRemovals: [String: UInt64] = [:]
    private var exclusionRemovals: [String: UInt64] = [:]

    public init(initial: Settings, environment: Environment) {
        current = initial; removalBaseline = initial; self.environment = environment
    }

    public func apply(_ proposed: Settings, basedOn base: Settings, clearLearned: Bool = false,
                      completion: ((Bool) -> Void)? = nil) {
        enqueue(Request(change: .edit(base: base, proposed: proposed, clearLearned: clearLearned), completion: completion))
    }

    /// Only verified edit acknowledgements are allowed to call this entry point.
    public func feedback(learned: [String], exclusions: [String], generation: UInt64) {
        guard !learned.isEmpty || !exclusions.isEmpty else { return }
        enqueue(Request(change: .feedback(learned: learned, exclusions: exclusions, generation: generation)))
    }

    private func enqueue(_ request: Request) {
        requests.append(request)
        guard !busy else { return }
        busy = true; onBusy?(true); next()
    }

    private func next() {
        guard !requests.isEmpty else { busy = false; onBusy?(false); return }
        let request = requests.removeFirst()
        var authoritative: Settings?
        do {
            let latest = try environment.load()
            authoritative = latest
            recordRemovals(in: latest)
            var proposed: Settings
            switch request.change {
            case .edit(let base, let draft, let clear):
                proposed = try SettingsMerge.edit(base: base, proposed: draft, current: latest, clearLearned: clear)
            case .feedback(let learned, let exclusions, let generation):
                guard generation <= latest.generation else { throw SettingsError.conflict }
                proposed = latest
                if generation >= learnedFloor {
                    let allowed = learned.filter { generation >= (learnedRemovals[$0] ?? 0) }
                    proposed.learned = Set(latest.learned).union(allowed).sorted()
                }
                let allowed = exclusions.filter { generation >= (exclusionRemovals[$0] ?? 0) }
                proposed.exclusions = Set(latest.exclusions).union(allowed).sorted()
                try proposed.validate()
            }
            if proposed == latest {
                // A clear on an already empty list is still a barrier to an
                // in-flight result created before the clear was requested.
                if case .edit(_, _, true) = request.change {
                    guard latest.generation < UInt64.max else { throw SettingsError.conflict }
                } else {
                    // The bridge applies verified feedback before delivering
                    // this request. Even a filtered no-op must replace that
                    // effective dictionary with the canonical saved one.
                    let isFeedback: Bool
                    if case .feedback = request.change { isFeedback = true } else { isFeedback = false }
                    if latest == current && !isFeedback { finish(request, ok: true) }
                    else {
                        environment.configure(latest, SettingsMerge.dictionaryOnly(from: current, to: latest)) { [self] ok in
                            if ok { adopt(latest) } else { onError?("Движок отклонил обновлённые настройки") }
                            if !ok && isFeedback { onRuntimeFailure?() }
                            finish(request, ok: ok)
                        }
                    }
                    return
                }
            }
            guard latest.generation < UInt64.max else { throw SettingsError.conflict }
            proposed.generation = latest.generation + 1
            let candidate = proposed
            let dictionaryOnly = SettingsMerge.dictionaryOnly(from: current, to: candidate)
            environment.configure(candidate, dictionaryOnly) { [self] accepted in
                guard accepted else {
                    let message = "Движок отклонил настройки; изменения не сохранены"
                    if case .feedback = request.change {
                        reconcileFeedback(request, authoritative: latest, message: message)
                    } else {
                        onError?(message); finish(request, ok: false)
                    }
                    return
                }
                do {
                    if candidate.autostart != latest.autostart { try environment.autostart(candidate.autostart) }
                    let saved = try environment.save(candidate, latest.generation)
                    if case .edit(let base, let draft, let clear) = request.change {
                        if clear { learnedFloor = saved.generation }
                        for removed in Set(base.exclusions).subtracting(draft.exclusions) {
                            exclusionRemovals[removed] = saved.generation
                        }
                    }
                    adopt(saved); finish(request, ok: true)
                } catch {
                    recover(request, previous: latest, attempted: candidate, error: error)
                }
            }
        } catch {
            if case .feedback = request.change {
                reconcileFeedback(request, authoritative: authoritative, message: error.localizedDescription)
            } else {
                onError?(error.localizedDescription); finish(request, ok: false)
            }
        }
    }

    /// Validation/load can fail before configure, but verified feedback has
    /// already changed the bridge. Restore without resetting its edit history.
    private func reconcileFeedback(_ request: Request, authoritative: Settings?, message: String) {
        let target = authoritative ?? current
        environment.configure(target, SettingsMerge.dictionaryOnly(from: current, to: target)) { [self] restored in
            if let authoritative { adopt(authoritative) }
            let detail = authoritative == nil
                ? "; файл настроек недоступен, исправление приостановлено"
                : (restored ? "" : "; движок не подтвердил восстановление настроек")
            onError?(message + detail)
            // Last-confirmed settings remove transient learning on a read
            // failure, but cannot certify agreement with an unreadable file.
            if !restored || authoritative == nil { onRuntimeFailure?() }
            finish(request, ok: false)
        }
    }

    private func recover(_ request: Request, previous: Settings, attempted: Settings, error: Error) {
        // A failed CAS can mean another writer won. Restore what is on disk,
        // then rebase a bounded retry; never put an old snapshot over that edit.
        let disk: Settings
        do { disk = try environment.load() }
        catch {
            onError?("Не удалось перечитать настройки: \(error.localizedDescription)")
            if attempted.autostart != previous.autostart {
                do { try environment.autostart(previous.autostart) }
                catch { onError?("Не удалось восстановить автозапуск: \(error.localizedDescription)") }
            }
            environment.configure(previous, SettingsMerge.dictionaryOnly(from: attempted, to: previous)) { [self] restored in
                if !restored { onRuntimeFailure?() }
                finish(request, ok: false)
            }
            return
        }
        var rollbackError: Error?
        if attempted.autostart != disk.autostart {
            do { try environment.autostart(disk.autostart) } catch { rollbackError = error }
        }
        environment.configure(disk, SettingsMerge.dictionaryOnly(from: attempted, to: disk)) { [self] restored in
            adopt(disk)
            if restored, rollbackError == nil, case SettingsError.conflict = error, request.retries < 2 {
                var retry = request; retry.retries += 1; requests.insert(retry, at: 0)
                next(); return
            }
            let detail = rollbackError.map { "; автозапуск: \($0.localizedDescription)" } ?? ""
            onError?(error.localizedDescription + detail + (restored ? "" : "; движок не подтвердил восстановление настроек"))
            if !restored { onRuntimeFailure?() }
            finish(request, ok: false)
        }
    }

    private func recordRemovals(in latest: Settings) {
        guard latest.generation > removalBaseline.generation else { return }
        // This also covers another process saving a clear/removal. Its newer
        // generation wins over a verified result still queued in this process.
        for word in Set(removalBaseline.learned).subtracting(latest.learned) {
            learnedRemovals[word] = latest.generation
        }
        if !removalBaseline.learned.isEmpty && latest.learned.isEmpty {
            learnedFloor = max(learnedFloor, latest.generation)
        }
        for word in Set(removalBaseline.exclusions).subtracting(latest.exclusions) {
            exclusionRemovals[word] = latest.generation
        }
        removalBaseline = latest
    }

    private func adopt(_ settings: Settings) {
        recordRemovals(in: settings)
        current = settings; onSettings?(settings)
    }
    private func finish(_ request: Request, ok: Bool) { request.completion?(ok); next() }
}
