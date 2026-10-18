import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

final class KeyboardService {
    static let syntheticTag: Int64 = EditorSupport.syntheticEventTag
    let store: Store
    private lazy var vocabulary = MainActor.assumeIsolated { SystemVocabulary() }
    private lazy var terminalBridge = TerminalBridge(permits: { [weak self] host in
        guard let self else { return false }
        return self.allowedFrontmost() && self.terminalPolicyPermitsAction && InputSources.language != nil &&
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host
    }, decide: { [weak self] word, manual, host in
        guard let self, self.allowedFrontmost(), self.terminalPolicyPermitsAction, InputSources.language != nil,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host else { return nil }
        let context = InputContext(application: host)
        let decision = manual ? self.engine.manual(word, context: context) :
            self.completedTokenDecision(word, context: context)
        if let language = decision?.targetLanguage, !InputSources.isAvailable(language) { return nil }
        return decision
    }, applied: { [weak self] decision, previousSource, host in
        guard let self, self.allowedFrontmost(), self.terminalPolicyPermitsAction,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host else { return }
        if let previousSource {
            if decision.reason != .manual { self.store.learn(decision.learnAs ?? decision.original) }
            _ = InputSources.restore(identifier: previousSource)
        } else {
            self.store.recordCorrection(category: self.statisticsCategory(decision))
            if let language = decision.targetLanguage { _ = InputSources.select(language) }
            if self.store.settings.sound { self.store.playCorrectionSound() }
        }
        self.store.inputSource = InputSources.identifier
    })
    private let axQueue = DispatchQueue(label: "dev.layoutpilot.accessibility", qos: .userInitiated)
    private static let replayPrefix: UInt64 = 0x4c505252
    var onRecoveryNeeded: (() -> Void)?
    private let replaySource = CGEventSource(stateID: .privateState)
    /// Barrier, replay and recovery state (Core); it changes only through session
    /// transitions. The read-only views below keep the existing call sites readable.
    private var session = MutationSession<EditorSnapshot, CGEvent>()
    private var replaying: Bool { session.replaying }
    private var replayBatchNonce: UUID { session.batchNonce }
    private var replayIdentityNonce: UUID? { session.identityNonce }
    private var replayRouteLease: ReplayDeliveryLease? { session.routeLease }
    private var mutationNonce: UUID? { session.mutationNonce }
    private var mutationGate: EditorSnapshot? { session.gate }
    private var mutationDeadline: TimeInterval? { session.deadline }
    private var inputReplay: InputReplayQueue<CGEvent> { session.queue }
    private var recoveryTarget: EditorSnapshot? { session.recoveryTarget }
    private var recovery: InputRecovery { session.recovery }
    private var tapRecovery = TapRecovery()
    private var sleeping = false
    private var observesSystem = true
    private var permissionState: [Bool]?
    private var contextFailure: EditorSnapshotFailure?
    private var recoverySourceID: String? { session.recoverySourceID }
    private var recoveryReplayProjection: ReplayInsertionProjection?
    private var recoveryReplaySource: String?
    private var replayProjection: ReplayInsertionProjection?
    private var replayProjectionSource: String?
    private var replayAllowsPartial = false
    private var replayReadbackNonce = UUID()
    private var streamReadback: (anchor: EditorSnapshot, projection: ReplayInsertionProjection, source: String, learnSingle: Bool)?
    private enum SourceChange {
        case language(Language), restore(String)
        func apply() -> Bool {
            switch self {
            case .language(let language): return InputSources.select(language)
            case .restore(let identifier): return InputSources.restore(identifier: identifier)
            }
        }
        var status: String {
            switch self {
            case .language: return "Текст исправлен. ⌘⌥Z — отменить"
            case .restore: return "Исправление отменено"
            }
        }
    }
    private var sourceAfterReplay: (pid: pid_t, change: SourceChange)?
    private var stopRequested = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var contextTimer: Timer?
    private var revision = 0
    private var observer: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var applicationObservers: [NSObjectProtocol] = []
    private var cachedConflict: String?
    private var observedKeyEvents = 0
    private var bufferedEventCount = 0
    private var skippedCount = 0
    private var lastKeyDownTime: TimeInterval = 0
    private var gestures = ModifierGesture()
    private var shiftTask: DispatchWorkItem?
    private var pendingNativePaste: (id: UUID, revision: Int, handshake: NativePasteReleaseHandshake)?
    private var cachedSnapshot: (revision: Int, value: EditorSnapshot)?
    // A failed refresh may retain a proposal for explicit actions, never for automatic prediction.
    private var explicitAnchor: (revision: Int, value: EditorSnapshot)?
    private var manualSnapshot: EditorSnapshot? {
        [cachedSnapshot, explicitAnchor].compactMap { $0 }.first { $0.revision == revision }?.value
    }
    private var contextCaptureRevision: Int?
    private var pendingKeyRead: (revision: Int, pid: pid_t?, sourceID: String, keyCode: Int, inserted: String, deadline: TimeInterval)?
    #if LAYOUTPILOT_TESTING
    private var testingContextCaptureEnabled = false
    private var testingContextRequests: [Int] = []
    #endif
    private var transaction: (before: EditorSnapshot, after: EditorSnapshot, range: NSRange, decision: Decision, sourceID: String, learnOnUndo: Bool)?

    init(store: Store, startAutomatically: Bool = true) {
        self.store = store
        observesSystem = startAutomatically
        guard startAutomatically else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.contextFailure = nil
            self?.resetTransient(); self?.captureAfterEvent(); self?.refresh()
        }
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.resetTransient(); self?.stop(); self?.refresh()
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.tapRecovery.reset(); self?.refresh(); self?.captureAfterEvent()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        contextTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.store.running, self.streamReadback == nil,
                  self.mutationGate == nil, self.recoveryTarget == nil, !self.recovery.requiresReview,
                  ProcessInfo.processInfo.systemUptime - self.lastKeyDownTime > 0.150 else { return }
            // Window changes inside one application do not send didActivateApplication.
            self.captureAfterEvent()
        }
        refresh()
    }
    deinit {
        timer?.invalidate()
        contextTimer?.invalidate()
        for value in [observer, sleepObserver, wakeObserver].compactMap({ $0 }) + applicationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(value)
        }
        stop()
    }
    func refresh() {
        guard observesSystem else { updateServiceStatus(); return }
        InputDiagnostics.shared.flush()
        // Diagnostics are displayed periodically; per-key @Published updates redraw
        // the entire settings window and must not compete with AX delivery.
        if store.keyEvents != observedKeyEvents { store.keyEvents = observedKeyEvents }
        if store.bufferedEvents != bufferedEventCount { store.bufferedEvents = bufferedEventCount }
        if store.skipped != skippedCount { store.skipped = skippedCount }
        cachedConflict = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            ["Caramba Switcher Pro", "Lang Switcher", "TypeTune"].contains($0.localizedName ?? "")
        }?.localizedName
        store.refreshLaunchAtLogin()
        store.trusted = AXIsProcessTrusted()
        store.listening = CGPreflightListenEventAccess()
        store.posting = CGPreflightPostEventAccess()
        store.secure = IsSecureEventInputEnabled()
        store.inputSource = InputSources.identifier
        let permissions = [store.trusted, store.listening, store.posting, store.secure,
                           store.settingsStorageAvailable, conflictingApp() == nil, sleeping]
        if let old = permissionState, old != permissions { tapRecovery.reset() }
        permissionState = permissions
        if !store.settingsStorageAvailable || conflictingApp() != nil || !store.trusted || !store.listening || store.secure || sleeping {
            if tap != nil { stop() }
        } else {
            if mutationGate == nil && inputReplay.outstanding == 0 { stopRequested = false }
            // A saved recovery target is not proof that its old tap still works.
            let active = tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false
            if !active { repairTap() }
        }
        updateServiceStatus()
    }
    private func repairTap() {
        let safe = mutationGate == nil && inputReplay.outstanding == 0 && !recovery.requiresReview
        switch tapRecovery.next(safe: safe) {
        case .enable:
            if let tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            else { start() }
            if !(tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false) { repairTap() }
        case .recreate:
            stop(); start()
        case .wait, .failed: break
        }
    }
    func retryConnection() {
        tapRecovery.reset(); contextFailure = nil; refresh(); captureAfterEvent()
    }
    private func updateServiceStatus() {
        func publish<Value: Equatable>(_ key: ReferenceWritableKeyPath<Store, Value>, _ value: Value) {
            if store[keyPath: key] != value { store[keyPath: key] = value }
        }
        publish(\.pendingInput, inputReplay.count)
        publish(\.outstandingInput, inputReplay.outstanding)
        publish(\.uncertainInput, recovery.uncertainDeliveries)
        publish(\.textReviewRequired, recovery.requiresReview)
        publish(\.recoveryRequired, recoveryTarget != nil || recovery.requiresReview)
        publish(\.tapActive, tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false)
        let front = observesSystem ? NSWorkspace.shared.frontmostApplication : nil
        let terminal = EditorSupport.permitsTerminalIntegration(applicationID: front?.bundleIdentifier)
        var own = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        var supportedLayout = observesSystem && InputSources.language != nil
        #if LAYOUTPILOT_TESTING
        if !observesSystem { store.tapActive = true; own = true; supportedLayout = true }
        #endif
        let status: InputServiceStatus
        if !store.settingsStorageAvailable { status = .settingsUnavailable }
        else if conflictingApp() != nil { status = .conflict }
        else if sleeping { status = .sleeping }
        else if store.secure { status = .secureInput }
        else if !store.trusted { status = .accessibilityDenied }
        else if !store.listening { status = .listeningDenied }
        else if recovery.requiresReview { status = .uncertainResult }
        else if recoveryTarget != nil { status = .recoveryPending }
        else if !store.tapActive { status = .tapFailed }
        else if !terminal && !store.posting { status = .postingDenied }
        else if !supportedLayout { status = .unsupportedLayout }
        else if let id = front?.bundleIdentifier, store.settings.excludedApps.contains(id) { status = .excludedApplication }
        else if !own && !terminal && !EditorSupport.permitsTextReplacement(applicationID: front?.bundleIdentifier) { status = .unsupportedApplication }
        else if !own && !terminal, let failure = contextFailure {
            status = failure.retryable ? .waitingForContext : .unsupportedField
        } else { status = .ready }
        publish(\.running, status == .ready)
        if store.serviceStatus != status {
            store.serviceStatus = status
            let counts = recoveryCounts
            InputDiagnostics.shared.record("service-state", revision: revision,
                checks: ["tapActive": store.tapActive, "trusted": store.trusted, "listening": store.listening,
                         "posting": store.posting, "secure": store.secure], counts: counts, reason: status.rawValue)
            if status == .tapFailed { InputDiagnostics.shared.fault(reason: "tap-failed", revision: revision, counts: counts) }
        }
    }
    private var recoveryCounts: [String: Int] {
        ["pending": inputReplay.count, "outstanding": inputReplay.outstanding,
         "uncertainDeliveries": recovery.uncertainDeliveries]
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        refresh()
    }
    private func start() {
        guard observesSystem, tap == nil, store.trusted, store.listening, !store.secure, !sleeping,
              store.settingsStorageAvailable, conflictingApp() == nil else { return }
        terminalBridge.start()
        let watched: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let mask = watched.reduce(UInt64(0)) { $0 | (1 << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<KeyboardService>.fromOpaque(info).takeUnretainedValue()
            return service.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: pointer)
        guard let tap else {
            store.lastStatus = "Не удалось подключить клавиатуру. Проверьте разрешения и нажмите «Повторить подключение»."; return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        stopRequested = false
    }
    func stop() {
        guard observesSystem else { return }
        // Keep filtering canceled delivery tokens until the user resolves uncertainty.
        if !recovery.mayDetachTap(activeMutation: mutationGate != nil, outstanding: inputReplay.outstanding) {
            stopRequested = true; revision += 1; store.running = false; return
        }
        stopRequested = false
        resetTransient()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; runLoopSource = nil; store.running = false
    }
    private func resetTransient() {
        streamReadback = nil
        // Cancel an identity query without orphaning its still-pending FIFO.
        if replaying, replayIdentityNonce != nil, let target = mutationGate { suspendReplay(target: target) }
        revision += 1; cachedSnapshot = nil; pendingKeyRead = nil; transaction = nil; shiftTask?.cancel(); shiftTask = nil
        pendingNativePaste = nil
        sourceAfterReplay = nil
        lastKeyDownTime = 0
        gestures.reset()
        replayProjection = nil; replayProjectionSource = nil; replayAllowsPartial = false; replayReadbackNonce = UUID()
        session.resetDeliveryProof()
    }
    private func allowedFrontmost() -> Bool {
        guard store.settingsStorageAvailable, !sleeping, !IsSecureEventInputEnabled(), conflictingApp() == nil, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              (EditorSupport.permitsTextReplacement(applicationID: app.bundleIdentifier) ||
               EditorSupport.permitsTerminalIntegration(applicationID: app.bundleIdentifier)) else { return false }
        return !store.settings.excludedApps.contains(app.bundleIdentifier ?? "")
    }
    private var terminalPolicyPermitsAction: Bool {
        var active = tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false
        #if LAYOUTPILOT_TESTING
        if !observesSystem { active = store.tapActive }
        #endif
        return active && store.settingsStorageAvailable && store.trusted && store.listening && !store.secure &&
            !sleeping && conflictingApp() == nil && recoveryTarget == nil && !recovery.requiresReview &&
            mutationGate == nil && inputReplay.isDrained
    }
    private func conflictingApp() -> String? {
        cachedConflict
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if replaying, let target = mutationGate { suspendReplay(target: target) }
            resetTransient()
            InputDiagnostics.shared.fault(reason: "tap-disabled", revision: revision, counts: recoveryCounts)
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return false
        }
        let tag = event.getIntegerValueField(.eventSourceUserData)
        if tag == Self.syntheticTag { return false }
        let rawTag = UInt64(bitPattern: tag)
        if rawTag >> 32 == Self.replayPrefix {
            let batchToken = UInt32(truncatingIfNeeded: rawTag)
            guard replaying, let target = mutationGate else { return true }
            let lease = replayRouteLease
            let allowed = lease?.permits(token: batchToken, revision: revision, sourceID: InputSources.identifier,
                now: ProcessInfo.processInfo.systemUptime) == true &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid &&
                allowedFrontmost() && AXIsProcessTrusted() && CGPreflightPostEventAccess()
            switch session.receiveReplay(token: batchToken, routingAllowed: allowed) {
            case .forward:
                projectReplayedEvent(type, event)
                InputDiagnostics.shared.record("replay-forward", revision: revision, checks: [
                    "keyDown": type == .keyDown,
                    "queueEmpty": inputReplay.isEmpty, "outstanding": inputReplay.outstanding > 0])
                if inputReplay.outstanding == 0 { DispatchQueue.main.async { [weak self] in self?.drainReplay() } }
                return false
            case .retain:
                InputDiagnostics.shared.record("replay-event-rejected", revision: revision, checks: [
                    "leasePresent": lease != nil, "token": lease?.token == batchToken,
                    "revision": lease?.revision == revision, "source": lease?.sourceID == InputSources.identifier,
                    "leaseFresh": lease.map { ProcessInfo.processInfo.systemUptime <= $0.deadline } ?? false,
                    "frontmost": NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                    "allowed": allowedFrontmost(), "trusted": AXIsProcessTrusted(),
                    "posting": CGPreflightPostEventAccess()])
                suspendReplay(target: target)
                return true
            case .suppress:
                return true
            }
        }
        tapRecovery.reset()
        if type == .keyDown { observedKeyEvents += 1 }
        if let gate = mutationGate {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == gate.pid, !IsSecureEventInputEnabled() {
                if !preservesContext(event) { sourceAfterReplay = nil; transaction = nil; cachedSnapshot = nil }
                let interception = session.intercept(event.copy() ?? event); bufferedEventCount += 1
                if interception.cancelWrites {
                    // Cancel further AX writes; retain input until rollback completes.
                    revision += 1
                    InputDiagnostics.shared.fault(reason: "replay-buffer-limit", revision: revision, counts: recoveryCounts)
                }
                // Typing faster than verified replay: stop draining and keep everything
                // for explicit recovery instead of growing the barrier without bound.
                if interception.suspendReplay { suspendReplay(target: gate) }
                return true
            }
            revision += 1 // external focus/secure change cancels mutation; never intercept the new app's input
        }
        if let target = recoveryTarget {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid, !IsSecureEventInputEnabled() {
                if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53,
                   event.flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]) == [.maskCommand,.maskAlternate] {
                    onRecoveryNeeded?(); return true
                }
                if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 15,
                   event.flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]) == [.maskCommand,.maskAlternate] {
                    recoverInput(); return true
                }
                // Recovery is explicit and verifies the entire saved target again.
                // Never retain new input merely because another window shares its PID.
                // Editing the old field may make recovery unavailable, but cannot divert
                // unrelated new typing into an indefinitely growing recovery buffer.
            }
            return false
        }
        if var pending = pendingNativePaste {
            if type == .keyUp {
                pending.handshake.observe(.keyUp, keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)))
                pendingNativePaste = pending
                return false
            }
            if type == .flagsChanged {
                // The initiating shortcut's releases pass through unchanged and
                // cannot start a Single Shift/Option gesture while we wait.
                gestures.reset(); shiftTask?.cancel(); shiftTask = nil
                let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
                pending.handshake.observe(.flagsChanged, keyCode: key, rawFlags: event.flags.rawValue)
                pendingNativePaste = pending
                if pending.handshake.cancelled {
                    pendingNativePaste = nil; revision += 1
                    skipped("Вставка отменена: нажата другая клавиша-модификатор")
                }
                return false
            }
            if type == .keyDown {
                pendingNativePaste = nil
                skipped("Вставка отменена: ввод изменился до отпускания сочетания")
            }
        }
        if type == .keyUp {
            // A startup AX failure can leave every key-down without an anchor.
            // The release only acquires a baseline; a later delimiter still needs
            // exact previous + insertion equality before any correction.
            captureMissingContextAfterKeyRelease(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)))
            return false
        }
        // Scrolling and dragging neither move the caret nor change text; only button
        // presses/releases invalidate the context. The barrier above still retains them.
        if [.scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) { return false }
        if type != .keyDown && type != .flagsChanged { resetTransient(); captureAfterEvent(); return false }
        guard allowedFrontmost(), InputSources.language != nil else { resetTransient(); return false }
        if EditorSupport.permitsTerminalIntegration(applicationID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            guard terminalPolicyPermitsAction else { resetTransient(); return false }
            let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if type == .flagsChanged { handleModifier(key, event.flags); return false }
            gestures.keyUsed(); shiftTask?.cancel()
            let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if flags == [.maskCommand, .maskAlternate], [6, 49].contains(key) {
                terminalBridge.perform(key == 6 ? "undo" : "manual"); return true
            }
            return false
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged { streamReadback = nil; replayReadbackNonce = UUID(); captureAfterEvent(); handleModifier(key, event.flags); return false }
        let now = ProcessInfo.processInfo.systemUptime
        let continuousInsertion = now - lastKeyDownTime <= 0.15
        lastKeyDownTime = now
        let explicitPrevious = manualSnapshot
        let previous = cachedSnapshot.flatMap { $0.revision == revision ? $0.value : nil }
        if !continuousInsertion && streamReadback?.projection.hasUnfinishedTail == true { streamReadback = nil }
        cachedSnapshot = nil
        pendingKeyRead = nil
        revision += 1
        gestures.keyUsed()
        shiftTask?.cancel()
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { streamReadback = nil }
        if key == 49 && flags == [.maskCommand, .maskAlternate] {
            InputDiagnostics.shared.record("manual", revision: revision, checks: ["previous": previous != nil])
            enqueue(boundTo: explicitPrevious) { $0.manual($1) }; return true
        }
        if key == 6 && flags == [.maskCommand, .maskAlternate] {
            enqueue(boundTo: transaction?.after) { service, _ in if !service.undo() { service.skipped("Нет актуального исправления для отмены") } }; return true
        }
        if key == 9 && flags == [.maskCommand, .maskShift] && store.settings.plainPaste {
            let clipboardChangeCount = NSPasteboard.general.changeCount
            let text = NSPasteboard.general.string(forType: .string)
            guard EditorSupport.permitsPlainPasteInterception(
                applicationID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, text: text),
                NSPasteboard.general.changeCount == clipboardChangeCount,
                let text, let previous, !previous.addressBar,
                previous.text.utf16.count - previous.selection.length + text.utf16.count <= 65_536 else {
                transaction = nil; captureAfterEvent(); return false
            }
            if EditorSupport.insertionBackend(applicationID: previous.application) == .keyboardEvents {
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                    transaction = nil; captureAfterEvent(); return false
                }
                awaitNativePasteRelease(before: previous, text: text, clipboardChangeCount: clipboardChangeCount,
                    originalFlags: event.flags.rawValue)
            } else {
                enqueue(boundTo: previous) { service, snapshot in if !service.pastePlain(snapshot, text: text, clipboardChangeCount: clipboardChangeCount) { service.skipped("Поле не поддерживает безопасную вставку") } }
            }
            return true
        }
        guard !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl),
              !event.flags.contains(.maskAlternate) else { transaction = nil; captureAfterEvent(); return false }
        transaction = nil
        var count = 0
        var buffer = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: 16, actualStringLength: &count, unicodeString: &buffer)
        let value = (0...buffer.count).contains(count) ? String(utf16CodeUnits: buffer, count: count) : ""
        let expectedRevision = revision
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // A period/semicolon may continue a filename or code token. Wait for
        // whitespace so automatic() can inspect the complete token, then trim
        // only its trailing sentence punctuation. Otherwise ABc.txt would have
        // been changed at the period before the filename guard could see it.
        let boundary = !value.isEmpty && value.allSatisfy { $0.isWhitespace }
        let sourceID = InputSources.identifier
        let layoutText = InputSources.insertionText(for: event, sourceID: sourceID)
        InputDiagnostics.shared.record("key-translation", revision: expectedRevision, checks: [
            "sourceEnglish": InputSources.englishIDs.contains(sourceID),
            "sourceRussian": InputSources.russianIDs.contains(sourceID),
            "currentLayoutTranslationAvailable": layoutText != nil,
            "currentLayoutEqualsEventUnicode": layoutText.map { $0.utf16.elementsEqual(value.utf16) } ?? false])
        // Keep event whitespace/control semantics, but never substitute a stale
        // event/AppKit character when current-layout insertion cannot be decoded.
        guard let translated = boundary ? value : layoutText else { captureAfterEvent(); return false }
        if !store.earlyCorrection, event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           TextEdit.insertionPrediction(text: "", selection: NSRange(location: 0, length: 0),
               characters: translated, keyCode: key) != nil {
            // Observe the first insertion after idle: rich editors may remove an empty placeholder newline.
            if streamReadback == nil, boundary || continuousInsertion, let previous, !previous.addressBar {
                let projection: ReplayInsertionProjection?
                if boundary {
                    projection = .completingToken(text: previous.text, selection: previous.selection)
                } else if TextEdit.wordBeforeCursor(in: previous.text, cursor: previous.selection.location, skipTrailingSpace: false) == nil {
                    projection = ReplayInsertionProjection(anchorText: previous.text, selection: previous.selection)
                } else { projection = nil }
                if let projection { streamReadback = (previous, projection, sourceID, true) }
            }
            if var stream = streamReadback, stream.source == sourceID, stream.anchor.pid == pid {
                stream.projection.consume(.insertion(translated))
                if stream.projection.isValid {
                    streamReadback = stream
                    var predicted = stream.anchor
                    predicted.text = stream.projection.expectedText; predicted.selection = stream.projection.expectedSelection
                    cachedSnapshot = (expectedRevision, predicted)
                    scheduleStreamReadback()
                    return false
                }
            }
        }
        streamReadback = nil
        if !boundary, continuousInsertion, var pinned = previous,
           translated.unicodeScalars.allSatisfy({ $0.isASCII || (0x0400...0x052f).contains($0.value) }),
           let predicted = TextEdit.insertionPrediction(text: pinned.text, selection: pinned.selection,
                                                        characters: translated, keyCode: key) {
            // Keep the last observed AX identity, predict only text/caret. At a
            // delimiter the fresh AX read below must match the entire prediction.
            // Programmatic edits, focus changes and editor substitutions fail closed.
            pinned.text = predicted.expectedText
            pinned.selection = NSRange(location: predicted.cursor, length: 0)
            // A proposal only schedules a fresh AX capture. Predicted text never
            // authorizes an early write; the full observed target/text/caret must match.
            if !store.earlyCorrection || engine.partialProposal(
                in: pinned.text, selection: pinned.selection, context: context(pinned)) == nil {
                cachedSnapshot = (expectedRevision, pinned)
                return false
            }
        }
        let inserted = TextEdit.insertionPrediction(text: "", selection: NSRange(location: 0, length: 0),
            characters: translated, keyCode: key) != nil ? translated : nil
        let deadline = ProcessInfo.processInfo.systemUptime + 0.060
        if let inserted {
            pendingKeyRead = (expectedRevision, pid, sourceID, key, inserted, deadline)
        }
        contextCaptureRevision = expectedRevision
        captureAfterKey(previous: previous, value: translated,
            inserted: inserted, keyCode: key,
            boundary: boundary, repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            revision: expectedRevision, pid: pid, sourceID: sourceID, deadline: deadline)
        return false
    }
    // AX can report the pre-event value even after the tap has returned. Acquire
    // a usable capture only after the character is visible; retry without writes
    // while this exact revision/PID/source remains current, for at most a soft 60ms budget.
    private func captureAfterKey(previous: EditorSnapshot?, value: String, inserted: String?, keyCode: Int,
                                 boundary: Bool, repeated: Bool, revision expectedRevision: Int,
                                 pid: pid_t?, sourceID: String, deadline: TimeInterval, readOnlyBaseline: Bool = false) {
        axQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
            guard let self else { return }
            guard self.isCurrent(expectedRevision, pid: pid, sourceID: sourceID) else {
                DispatchQueue.main.async { self.finishKeyBaselineCapture(revision: expectedRevision) }
                return
            }
            let began = ProcessInfo.processInfo.systemUptime
            let observation = AccessibilityEditor.captureRetrying(deadline: deadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: pid, sourceID: sourceID) })
            guard let current = observation.snapshot, self.isCurrent(expectedRevision, pid: pid, sourceID: sourceID) else {
                if let failure = observation.failure {
                    DispatchQueue.main.async {
                        var rescheduled = false
                        defer { if !rescheduled { self.finishKeyBaselineCapture(revision: expectedRevision) } }
                        guard self.revision == expectedRevision,
                              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                              InputSources.identifier == sourceID else { return }
                        if failure.retryable, self.cachedSnapshot?.revision == expectedRevision { return }
                        self.reportContextFailure(failure)
                        if !readOnlyBaseline, failure.retryable, ProcessInfo.processInfo.systemUptime < deadline {
                            rescheduled = true
                            self.captureAfterKey(previous: previous, value: value, inserted: inserted, keyCode: keyCode,
                                boundary: boundary, repeated: repeated, revision: expectedRevision, pid: pid,
                                sourceID: sourceID, deadline: deadline)
                        }
                    }
                } else {
                    DispatchQueue.main.async { self.finishKeyBaselineCapture(revision: expectedRevision) }
                }
                return
            }
            DispatchQueue.main.async {
                var rescheduled = false
                defer { if !rescheduled { self.finishKeyBaselineCapture(revision: expectedRevision) } }
                guard self.revision == expectedRevision, self.allowedFrontmost(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      InputSources.identifier == sourceID else { return }
                self.contextFailure = nil
                let predicted = previous.flatMap { TextEdit(text: $0.text, selection: $0.selection, replacement: value) }
                let matchesTarget = previous.map { AccessibilityEditor.sameTarget($0, current) } ?? false
                let matchesText = predicted.map { $0.expectedText.utf16.elementsEqual(current.text.utf16) } ?? false
                let matchesCaret = predicted.map { NSRange(location: $0.cursor, length: 0) == current.selection } ?? false
                let visible = inserted.map { TextEdit.observesInsertionSuffix(text: current.text,
                    selection: current.selection, characters: $0, keyCode: keyCode) } ?? true
                let pendingBoundary = (boundary || (self.store.earlyCorrection && inserted != nil)) &&
                    previous != nil && matchesTarget && (!matchesText || !matchesCaret)
                InputDiagnostics.shared.record(boundary ? "boundary" : "capture", revision: expectedRevision,
                    checks: ["previous": previous != nil, "sameTarget": matchesTarget, "readOnlyBaseline": readOnlyBaseline,
                        "matchesBeforeText": previous.map { $0.text.utf16.elementsEqual(current.text.utf16) } ?? false,
                        "matchesPredictedText": matchesText, "matchesPredictedCaret": matchesCaret,
                        "insertionVisible": visible, "translatedAvailable": inserted != nil,
                        "predictionEqualsTranslated": inserted.map { value.utf16.elementsEqual($0.utf16) } ?? false,
                        "predictionSuffixVisible": TextEdit.observesInsertionSuffix(text: current.text,
                            selection: current.selection, characters: value, keyCode: keyCode)],
                    elapsed: ProcessInfo.processInfo.systemUptime - began)
                if (!visible || pendingBoundary), ProcessInfo.processInfo.systemUptime < deadline {
                    rescheduled = true
                    self.captureAfterKey(previous: previous, value: value, inserted: inserted, keyCode: keyCode,
                        boundary: boundary, repeated: repeated, revision: expectedRevision, pid: pid,
                        sourceID: sourceID, deadline: deadline, readOnlyBaseline: readOnlyBaseline)
                    return
                }
                // A release may already have acquired a newer full baseline in
                // this revision. An older readiness failure must not erase it.
                guard visible else {
                    if self.cachedSnapshot?.revision != expectedRevision, ProcessInfo.processInfo.systemUptime >= deadline {
                        self.reportContextFailure(.deadlineExceeded)
                    }
                    return
                }
                if readOnlyBaseline {
                    let accepted = self.acceptKeyBaseline(current, inserted: inserted, keyCode: keyCode,
                        revision: expectedRevision, deadline: deadline, now: ProcessInfo.processInfo.systemUptime)
                    if !accepted, self.cachedSnapshot?.revision != expectedRevision {
                        self.reportContextFailure(.deadlineExceeded)
                    }
                    return
                }
                if !repeated, let before = previous, before.selection.length == 0,
                   matchesTarget, matchesText, matchesCaret {
                    if boundary { self.automatic(current) }
                    else if self.store.earlyCorrection { self.automaticPartial(current) }
                }
                self.cachedSnapshot = (expectedRevision, current)
            }
        }
    }
    // Called only on axQueue. The main run loop never waits for AX IPC.
    private func isCurrent(_ expectedRevision: Int) -> Bool {
        DispatchQueue.main.sync { self.revision == expectedRevision && self.allowedFrontmost() }
    }
    private func isCurrent(_ expectedRevision: Int, pid: pid_t?, sourceID: String) -> Bool {
        DispatchQueue.main.sync {
            self.revision == expectedRevision && self.allowedFrontmost() &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && InputSources.identifier == sourceID
        }
    }
    private func reportContextFailure(_ failure: EditorSnapshotFailure) {
        let changed = contextFailure != failure
        contextFailure = failure
        if store.lastContextFailure != failure.message { store.lastContextFailure = failure.message }
        InputDiagnostics.shared.record("snapshot-failed", revision: revision, reason: failure.diagnosticCode)
        if changed && !recovery.requiresReview {
            switch failure {
            case .deadlineExceeded, .axCannotComplete, .axError:
                InputDiagnostics.shared.fault(reason: "snapshot-" + failure.diagnosticCode, revision: revision,
                    checks: ["trusted": store.trusted, "listening": store.listening, "secure": store.secure], counts: recoveryCounts)
            default: break
            }
        }
        updateServiceStatus()
    }
    private func finishKeyBaselineCapture(revision expectedRevision: Int) {
        if contextCaptureRevision == expectedRevision { contextCaptureRevision = nil }
    }
    private func acceptKeyBaseline(_ snapshot: EditorSnapshot, inserted: String?, keyCode: Int,
                                   revision expectedRevision: Int, deadline: TimeInterval, now: TimeInterval) -> Bool {
        guard revision == expectedRevision, now.isFinite, deadline.isFinite, now < deadline, let inserted,
              TextEdit.observesInsertionSuffix(text: snapshot.text, selection: snapshot.selection,
                  characters: inserted, keyCode: keyCode) else { return false }
        cachedSnapshot = (expectedRevision, snapshot); contextFailure = nil
        updateServiceStatus()
        return true
    }
    private func captureMissingContextAfterKeyRelease(keyCode: Int) {
        guard cachedSnapshot?.revision != revision, contextCaptureRevision != revision,
              let pending = pendingKeyRead, pending.revision == revision, pending.keyCode == keyCode else { return }
        guard ProcessInfo.processInfo.systemUptime < pending.deadline else { pendingKeyRead = nil; return }
        #if LAYOUTPILOT_TESTING
        if !observesSystem {
            if testingContextCaptureEnabled {
                contextCaptureRevision = revision; testingContextRequests.append(revision)
            }
            return
        }
        #endif
        guard allowedFrontmost(), InputSources.language != nil,
              EditorSupport.permitsTextReplacement(applicationID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pending.pid,
              InputSources.identifier == pending.sourceID else { pendingKeyRead = nil; return }
        contextCaptureRevision = revision
        captureAfterKey(previous: nil, value: pending.inserted, inserted: pending.inserted, keyCode: pending.keyCode,
            boundary: false, repeated: false, revision: pending.revision, pid: pending.pid,
            sourceID: pending.sourceID, deadline: pending.deadline, readOnlyBaseline: true)
    }
    private func captureAfterEvent() {
        guard contextCaptureRevision != revision else { return }
        #if LAYOUTPILOT_TESTING
        if !observesSystem, testingContextCaptureEnabled {
            contextCaptureRevision = revision; testingContextRequests.append(revision); return
        }
        #endif
        guard observesSystem else { return }
        let expectedRevision = revision
        contextCaptureRevision = expectedRevision
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        captureContext(revision: expectedRevision, pid: pid, sourceID: InputSources.identifier,
            deadline: ProcessInfo.processInfo.systemUptime + 0.060)
    }
    private func captureContext(revision expectedRevision: Int, pid: pid_t?, sourceID: String, deadline: TimeInterval) {
        axQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
            guard let self else { return }
            guard self.isCurrent(expectedRevision, pid: pid, sourceID: sourceID) else {
                DispatchQueue.main.async {
                    self.finishContextCapture(.failure(.staleContext), revision: expectedRevision, contextMatches: false)
                }
                return
            }
            let result = AccessibilityEditor.captureRetrying(deadline: deadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: pid, sourceID: sourceID) })
            DispatchQueue.main.async {
                self.finishContextCapture(result, revision: expectedRevision,
                    contextMatches: self.allowedFrontmost() &&
                        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && InputSources.identifier == sourceID)
            }
        }
    }
    private func finishContextCapture(_ result: AccessibilityEditor.SnapshotResult,
                                      revision expectedRevision: Int, contextMatches: Bool) {
        if contextCaptureRevision == expectedRevision { contextCaptureRevision = nil }
        guard revision == expectedRevision, contextMatches else { return }
        if let snapshot = result.snapshot {
            cachedSnapshot = (expectedRevision, snapshot); contextFailure = nil
            updateServiceStatus()
        } else if let failure = result.failure {
            if failure.retryable {
                if let cachedSnapshot { explicitAnchor = cachedSnapshot }
            } else { explicitAnchor = nil }
            cachedSnapshot = nil
            reportContextFailure(failure)
        }
    }
    private func enqueue(boundTo before: EditorSnapshot?, _ operation: @escaping (KeyboardService, EditorSnapshot) -> Void) {
        let expectedRevision = revision
        let sourceID = InputSources.identifier
        InputDiagnostics.shared.record("explicit-enqueue", revision: expectedRevision, checks: ["anchor": before != nil])
        guard let before else { captureAfterEvent(); skipped("Контекст ещё не подтверждён; повторите действие после паузы"); return }
        axQueue.async { [weak self] in
            guard let self else { return }
            let current = self.isCurrent(expectedRevision) ? AccessibilityEditor.snapshot() : nil
            DispatchQueue.main.async {
                var checks = ["snapshot": current != nil]
                func checked(_ name: String, _ value: @autoclosure () -> Bool) -> Bool {
                    let result = value(); checks[name] = result; return result
                }
                guard checked("revision", self.revision == expectedRevision), checked("allowed", self.allowedFrontmost()),
                      checked("source", InputSources.identifier == sourceID), let current,
                      checked("sameTarget", AccessibilityEditor.sameTarget(before, current)), checked("sameText", before.text.utf16.elementsEqual(current.text.utf16)),
                      checked("sameSelection", before.selection == current.selection) else {
                    checks["accepted"] = false
                    InputDiagnostics.shared.record("explicit-context", revision: expectedRevision, checks: checks)
                    self.skipped("Действие пропущено: текст или фокус уже изменились"); return
                }
                checks["accepted"] = true
                InputDiagnostics.shared.record("explicit-context", revision: expectedRevision, checks: checks)
                operation(self, current)
            }
        }
    }
    /// Interception can hide modifier releases from the recognizer. Abandon
    /// the entire old gesture instead of treating replay as new user actions.
    /// Main-thread only; no revision, source, FIFO or settings changes.
    private func cancelGestureStateForInterception() {
        gestures.reset()
        shiftTask?.cancel(); shiftTask = nil
        InputDiagnostics.shared.record("gesture-interception-reset", revision: revision)
    }
    private func handleModifier(_ key: Int, _ flags: CGEventFlags) {
        gestures.singleShift = store.settings.singleShift
        gestures.optionTap = store.settings.optionCorrection
        gestures.bothShiftPause = store.settings.shiftChordPause
        let bit: UInt64 = key == 56 ? 0x2 : key == 60 ? 0x4 : key == 58 ? 0x20 : key == 61 ? 0x40 : 0
        // A barrier may have hidden the other modifier's press as well as its
        // release. Consult current physical flags before accepting a new tap.
        let otherModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) ||
            ((key == 56 || key == 60) && flags.contains(.maskAlternate)) ||
            ((key == 58 || key == 61) && flags.contains(.maskShift))
        let actions = gestures.modifier(keyCode: key, isDown: bit != 0 && flags.rawValue & bit != 0,
                                       time: ProcessInfo.processInfo.systemUptime,
                                       hasOtherModifiers: otherModifiers)
        InputDiagnostics.shared.record("gesture-modifier", revision: revision,
            checks: ["otherModifiers": otherModifiers,
                "singleEnabled": gestures.singleShift, "pendingDeadline": gestures.nextDeadline != nil,
                "correctAction": actions.contains(.correctText), "switchAction": actions.contains(.switchLayout),
                "cached": cachedSnapshot != nil, "cacheCurrent": cachedSnapshot?.revision == revision])
        execute(actions)
        scheduleGesture()
    }
    private func execute(_ actions: [ModifierGesture.Action]) {
        for action in actions {
            let allowed = allowedFrontmost(), knownSource = InputSources.language != nil
            InputDiagnostics.shared.record("gesture-action", revision: revision,
                checks: ["allowed": allowed, "knownSource": knownSource,
                    "correct": action == .correctText, "switch": action == .switchLayout,
                    "toggleAuto": action == .toggleAutomatic])
            guard allowed, knownSource else { gestures.reset(); return }
            switch action {
            case .correctText:
                if EditorSupport.permitsTerminalIntegration(applicationID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
                    guard terminalPolicyPermitsAction else { return }
                    terminalBridge.perform("manual")
                } else { enqueue(boundTo: manualSnapshot) { $0.manual($1) } }
            case .toggleAutomatic:
                revision += 1; cachedSnapshot = nil; transaction = nil
                store.settings.paused.toggle()
                store.lastStatus = store.settings.paused ? "Автоисправления на паузе" : "Автоисправления включены"
            case .switchLayout:
                revision += 1; cachedSnapshot = nil; transaction = nil
                let before = InputSources.identifier
                let selected = InputSources.toggle()
                if selected { store.recordSingleShift() }
                InputDiagnostics.shared.record("gesture-source-result", revision: revision,
                    checks: ["selected": selected, "sourceChanged": before != InputSources.identifier])
                store.lastStatus = selected ? "Раскладка переключена" : "Добавьте русскую и английскую раскладки в macOS"
                store.inputSource = InputSources.identifier
            }
        }
    }
    private func scheduleGesture() {
        shiftTask?.cancel(); shiftTask = nil
        guard let deadline = gestures.nextDeadline else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let actions = self.gestures.advance(time: ProcessInfo.processInfo.systemUptime)
            self.execute(actions); self.scheduleGesture()
        }
        shiftTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: item)
    }
    private func context(_ snapshot: EditorSnapshot) -> InputContext {
        InputContext(application: snapshot.application, secure: IsSecureEventInputEnabled())
    }
    private func manual(_ snapshot: EditorSnapshot) {
        guard allowedFrontmost(), InputSources.language != nil else { skipped("Поле или раскладка не поддерживают безопасную замену"); return }
        let range = snapshot.selection.length > 0 ? snapshot.selection : TextEdit.wordBeforeCursor(in: snapshot.text, cursor: snapshot.selection.location)
        guard let range, let swift = Range(range, in: snapshot.text),
              let decision = engine.manual(String(snapshot.text[swift]), context: context(snapshot)) else { return }
        // The reference leaves a caret after the replacement. Retaining the
        // converted selection would let the next Space erase the whole result.
        apply(snapshot, range: range, decision: decision, keepSelection: false)
    }
    private func automatic(_ snapshot: EditorSnapshot) {
        guard allowedFrontmost(), InputSources.language != nil, snapshot.selection.length == 0,
              let range = TextEdit.wordBeforeCursor(in: snapshot.text, cursor: snapshot.selection.location),
              let swift = Range(range, in: snapshot.text),
              let decision = engine.completedTokenDecision(String(snapshot.text[swift]), decide: {
                  decide($0, context: context(snapshot))
              }, isKnownWord: { self.isKnownWord($0) }) else { return }
        apply(snapshot, range: NSRange(location: range.location, length: decision.original.utf16.count), decision: decision)
    }
    private func automaticPartial(_ snapshot: EditorSnapshot) {
        guard store.earlyCorrection, !snapshot.addressBar, allowedFrontmost(), InputSources.language != nil,
              let proposal = engine.partialProposal(
                in: snapshot.text, selection: snapshot.selection, context: context(snapshot)) else { return }
        apply(snapshot, range: proposal.range, decision: proposal.decision, partial: true)
    }
    /// The decision engine for current settings and the installed layouts' key table.
    private var engine: Engine { Engine(settings: store.settings, mapping: InputSources.mapping) }
    /// A token that is itself a word never becomes a layout prefix plus converted punctuation.
    private func isKnownWord(_ word: String) -> Bool {
        if Lexicon.bundled.contains(word) { return true }
        guard store.useSystemDictionary else { return false }
        return MainActor.assumeIsolated { vocabulary.accepts(word) }
    }
    func decide(_ word: String, context: InputContext = InputContext()) -> Decision? {
        if store.useSystemDictionary {
            return MainActor.assumeIsolated { vocabulary.decision(word, settings: store.settings, context: context, mapping: InputSources.mapping) }
        }
        return engine.decide(word, context: context)
    }
    private func statisticsCategory(_ decision: Decision) -> UsageCategory {
        switch decision.reason {
        case .layout, .userRule: return .automatic
        case .yo: return .yo
        case .manual: return .manual
        case .typo:
            // The reference groups its double-capital event with automatic changes.
            return Engine.isDoubleCapitalTypo(decision.original) ? .automatic : .typo
        }
    }
    /// Return a whole-token decision, preserving trailing sentence punctuation.
    /// Catch-up uses the same whole-token-first policy as ordinary automatic().
    private func completedTokenDecision(_ token: String, context: InputContext) -> Decision? {
        guard let value = engine.completedTokenDecision(token, decide: {
            decide($0, context: context)
        }, isKnownWord: { self.isKnownWord($0) }) else { return nil }
        let punctuation = token.dropFirst(value.original.count)
        return Decision(original: token, replacement: value.replacement + punctuation,
                        reason: value.reason, targetLanguage: value.targetLanguage,
                        learnAs: value.learnAs ?? (punctuation.isEmpty ? nil : value.original))
    }
    private func apply(_ before: EditorSnapshot, range: NSRange, decision: Decision, keepSelection: Bool = false,
                       statisticsDecisions: [Decision]? = nil, learnOnUndo: Bool = true,
                       partial: Bool = false) {
        guard !before.addressBar || (!partial && EditorSupport.permitsAddressBarCorrection(before.text)) else {
            skipped("Адрес сохранён: исправляются только обычные поисковые слова"); return
        }
        streamReadback = nil
        InputDiagnostics.shared.record("apply-enqueued", revision: revision)
        if let language = decision.targetLanguage, !InputSources.isAvailable(language) {
            skipped("Добавьте нужную русскую или английскую раскладку в macOS"); return
        }
        let sourceID = InputSources.identifier
        let expectedRevision = revision
        axQueue.async { [weak self] in
            guard let self else { return }
            let (result, settled, gated) = self.mutate(before, range: range, replacement: decision.replacement,
                keepSelection: keepSelection, expectedRevision: expectedRevision, expectedSource: sourceID)
            let verified: Bool
            if case .verified = result { verified = true } else { verified = false }
            InputDiagnostics.shared.record("apply-result", revision: expectedRevision, checks: ["verified": verified, "gated": gated])
            DispatchQueue.main.async {
                var finishHere = true
                defer { if gated && finishHere { self.finishMutation(result, before: before,
                    settled: self.revision == expectedRevision ? settled : nil,
                    allowAutomaticReplay: decision.reason != .manual, recoverySource: sourceID) } }
                guard case .verified(let after) = result else {
                    self.skipped("Замена пропущена или прервана: проверьте текст поля"); return
                }
                if partial && self.inputReplay.containsPending(where: { !self.preservesContext($0) }) {
                    // This main-serialized decision precedes stats/TIS/transaction.
                    // Keep mutationGate throughout inverse replacement: later
                    // delivered hardware remains in the same FIFO. This covers
                    // observed pending input, not future OS/event delivery timing.
                    finishHere = false
                    self.rollbackPartial(before: before, after: after, range: range,
                        decision: decision, expectedRevision: expectedRevision, sourceID: sourceID)
                    return
                }
                for item in statisticsDecisions ?? [decision] {
                    self.store.recordCorrection(category: self.statisticsCategory(item))
                }
                InputDiagnostics.shared.record("apply-commit", revision: expectedRevision, checks: [
                    "currentRevision": self.revision == expectedRevision,
                    "allowed": self.allowedFrontmost(), "pendingReplay": !self.inputReplay.isEmpty])
                guard self.revision == expectedRevision, self.allowedFrontmost() else {
                    self.transaction = nil; self.cachedSnapshot = nil; return
                }
                self.transaction = (before, after, range, decision, sourceID, learnOnUndo)
                self.cachedSnapshot = (expectedRevision, after)
                let selected = decision.targetLanguage.map { self.selectSource(.language($0), pid: before.pid) } ?? true
                self.store.inputSource = InputSources.identifier
                self.store.lastStatus = selected ? "Текст исправлен. ⌘⌥Z — отменить" :
                    (self.sourceAfterReplay != nil ? "Текст исправлен; смена раскладки ожидает завершения ввода" : "Текст исправлен, раскладка не переключена")
                if self.store.settings.sound { self.store.playCorrectionSound() }
            }
        }
    }
    /// Invert a partial replacement only while the existing mutation gate owns
    /// the FIFO. No second mutate()/timer, no source change, and no automatic retry.
    private func rollbackPartial(before: EditorSnapshot, after: EditorSnapshot, range: NSRange,
                                 decision: Decision, expectedRevision: Int, sourceID: String) {
        transaction = nil; cachedSnapshot = nil; sourceAfterReplay = nil
        guard let deadline = mutationDeadline,
            let plan = PartialMutationRollbackPlan(isPartial: true, hasQueuedEditingInput: true,
            beforeText: before.text, beforeSelection: before.selection, replacementRange: range,
            decision: decision, afterText: after.text, afterSelection: after.selection) else {
            InputDiagnostics.shared.record("partial-rollback-plan-rejected", revision: expectedRevision)
            finishMutation(.uncertain, before: before, settled: nil, recoverySource: sourceID)
            return
        }
        axQueue.async { [weak self] in
            guard let self else { return }
            // replace() rechecks pinned field/window/document/full text/caret
            // and permissions/current revision before its own AX writes.
            let reverted = AccessibilityEditor.replace(after, range: plan.edit.range,
                replacement: plan.edit.replacement, keepSelection: false, deadline: deadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: before.pid, sourceID: sourceID) })
            let readback = AccessibilityEditor.capture(deadline: deadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: before.pid, sourceID: sourceID) }).snapshot
            DispatchQueue.main.async {
                let verified: Bool
                if case .verified(let value) = reverted {
                    verified = self.revision == expectedRevision && self.allowedFrontmost() &&
                        AccessibilityEditor.sameTarget(before, value) &&
                        value.text.utf16.elementsEqual(before.text.utf16) && value.selection == before.selection &&
                        readback.map { AccessibilityEditor.sameTarget(before, $0) &&
                            $0.text.utf16.elementsEqual(before.text.utf16) && $0.selection == before.selection } == true
                } else { verified = false }
                InputDiagnostics.shared.record("partial-rollback-result", revision: expectedRevision,
                    checks: ["verified": verified, "pendingReplay": !self.inputReplay.isEmpty])
                // An uncertain inverse NEVER authorizes draining, even if a
                // coincidental snapshot looks original. Keep all pending input
                // for explicit recovery; never blindly repeat the inverse.
                self.finishMutation(verified ? .notApplied : .uncertain, before: before, settled: verified ? readback : nil,
                    allowPartialReplay: verified, recoverySource: sourceID)
                if verified { self.store.lastStatus = "Раннее исправление отложено: ввод продолжается" }
            }
        }
    }
    @discardableResult private func undo() -> Bool {
        guard let value = transaction else { return false }
        transaction = nil
        let expectedRevision = revision
        let sourceID = InputSources.identifier
        let range = NSRange(location: value.range.location, length: value.decision.replacement.utf16.count)
        axQueue.async { [weak self] in
            guard let self else { return }
            let (result, settled, gated) = self.mutate(value.after, range: range, replacement: value.decision.original,
                keepSelection: value.before.selection.length > 0, expectedRevision: expectedRevision, expectedSource: sourceID)
            DispatchQueue.main.async {
                defer { if gated { self.finishMutation(result, before: value.after,
                    settled: self.revision == expectedRevision ? settled : nil, recoverySource: sourceID) } }
                guard case .verified(let after) = result, after.text.utf16.elementsEqual(value.before.text.utf16) else {
                    self.skipped("Отмена пропущена или прервана: проверьте текст"); return
                }
                guard self.revision == expectedRevision, self.allowedFrontmost() else { return }
                if value.learnOnUndo && value.decision.reason != .manual {
                    self.store.learn(value.decision.learnAs ?? value.decision.original)
                }
                let restored = self.selectSource(.restore(value.sourceID), pid: value.before.pid)
                self.store.inputSource = InputSources.identifier
                self.cachedSnapshot = (expectedRevision, after)
                self.store.lastStatus = restored ? "Исправление отменено" :
                    (self.sourceAfterReplay != nil ? "Текст восстановлен; смена раскладки ожидает завершения ввода" : "Текст восстановлен; прежняя раскладка недоступна")
            }
        }
        return true
    }
    /// Runs on main. Waiting does not acquire mutationGate or synthesize events:
    /// physical releases reach the host before our separate native-paste frame.
    private func awaitNativePasteRelease(before: EditorSnapshot, text: String, clipboardChangeCount: Int,
                                         originalFlags: UInt64) {
        let id = UUID(), expectedRevision = revision
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        pendingNativePaste = (id, expectedRevision, NativePasteReleaseHandshake(originalFlags: originalFlags))
        transaction = nil; gestures.reset(); shiftTask?.cancel(); shiftTask = nil
        func poll() {
            guard self.pendingNativePaste?.id == id else { return }
            guard self.revision == expectedRevision, self.allowedFrontmost(), AXIsProcessTrusted(),
                  CGPreflightPostEventAccess(), self.store.settings.plainPaste,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == before.pid,
                  NSPasteboard.general.changeCount == clipboardChangeCount else {
                self.pendingNativePaste = nil
                self.skipped("Вставка отменена: изменились фокус, доступ или буфер обмена")
                return
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                self.pendingNativePaste = nil
                self.skipped("Вставка отменена: отпустите V и клавиши-модификаторы и повторите")
                return
            }
            let keys: [CGKeyCode] = [9, 54, 55, 56, 60, 58, 61, 59, 62, 57, 63]
            let held = keys.contains { key in
                CGEventSource.keyState(.hidSystemState, key: key) || CGEventSource.keyState(.combinedSessionState, key: key)
            }
            let released = EditorSupport.nativePasteKeysReleased(
                hidFlags: CGEventSource.flagsState(.hidSystemState).rawValue,
                sessionFlags: CGEventSource.flagsState(.combinedSessionState).rawValue, anyWatchedKeyDown: held)
            if released && self.pendingNativePaste?.handshake.ready == true {
                self.pendingNativePaste = nil
                // enqueue rechecks complete AX identity/text/selection before
                // pastePlain can acquire the mutation gate and emit any frame.
                self.enqueue(boundTo: before) { service, snapshot in
                    if !service.pastePlain(snapshot, text: text, clipboardChangeCount: clipboardChangeCount) {
                        service.skipped("Поле не поддерживает безопасную вставку")
                    }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
                guard self != nil else { return }
                poll()
            }
        }
        // Check only after returning the original keyDown from the event tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
            guard self != nil else { return }
            poll()
        }
    }
    private func pastePlain(_ current: EditorSnapshot, text: String, clipboardChangeCount: Int) -> Bool {
        let expectedRevision = revision
        let sourceID = InputSources.identifier
        transaction = nil
        axQueue.async { [weak self] in
            guard let self else { return }
            let (result, settled, gated) = self.mutate(current, range: current.selection, replacement: text,
                keepSelection: false, expectedRevision: expectedRevision, expectedSource: sourceID,
                nativePaste: EditorSupport.insertionBackend(applicationID: current.application) == .keyboardEvents,
                clipboardChangeCount: clipboardChangeCount)
            DispatchQueue.main.async {
                defer { if gated { self.finishMutation(result, before: current,
                    settled: self.revision == expectedRevision ? settled : nil, recoverySource: sourceID) } }
                if case .verified(let after) = result {
                    if self.revision == expectedRevision { self.cachedSnapshot = (expectedRevision, after) }
                    self.store.lastStatus = "Вставлен текст без форматирования"
                } else { self.skipped("Вставка пропущена или прервана: проверьте текст") }
            }
        }
        return true
    }
    /// All calls occur on axQueue. Only the brief gate transitions touch the main loop.
    private func mutate(_ before: EditorSnapshot, range: NSRange, replacement: String,
                        keepSelection: Bool, expectedRevision: Int, expectedSource: String, nativePaste: Bool = false,
                        clipboardChangeCount: Int? = nil) -> (AccessibilityEditor.ReplacementResult, EditorSnapshot?, Bool) {
        let began = ProcessInfo.processInfo.systemUptime
        func traceResult(_ result: AccessibilityEditor.ReplacementResult, gated: Bool) {
            guard InputDiagnostics.shared.enabled else { return }
            var checks = ["nativePaste": nativePaste, "gated": gated, "current": isCurrent(expectedRevision, pid: before.pid, sourceID: expectedSource),
                "notApplied": false, "uncertain": false, "verified": false]
            switch result {
            case .notApplied: checks["notApplied"] = true
            case .uncertain: checks["uncertain"] = true
            case .verified: checks["verified"] = true
            }
            InputDiagnostics.shared.record("mutation-result", revision: expectedRevision, checks: checks,
                elapsed: ProcessInfo.processInfo.systemUptime - began)
        }
        let current = isCurrent(expectedRevision, pid: before.pid, sourceID: expectedSource)
        InputDiagnostics.shared.record("mutation-initial", revision: expectedRevision,
            checks: ["nativePaste": nativePaste, "current": current], elapsed: ProcessInfo.processInfo.systemUptime - began)
        guard current else { traceResult(.notApplied, gated: false); return (.notApplied, nil, false) }
        let operationDeadline = DispatchQueue.main.sync { () -> TimeInterval? in
            var checks = ["nativePaste": nativePaste]
            func checked(_ name: String, _ predicate: @autoclosure () -> Bool) -> Bool {
                let value = predicate(); checks[name] = value; return value
            }
            guard checked("revision", revision == expectedRevision), checked("source", InputSources.identifier == expectedSource), checked("allowedFrontmost", allowedFrontmost()),
                  checked("replaySource", replaySource != nil), checked("postAccess", CGPreflightPostEventAccess()),
                  checked("noMutation", mutationGate == nil), checked("noRecovery", recoveryTarget == nil && !recovery.requiresReview),
                  checked("noReplay", inputReplay.isEmpty) else {
                checks["granted"] = false
                InputDiagnostics.shared.record("mutation-gate", revision: expectedRevision, checks: checks,
                    elapsed: ProcessInfo.processInfo.systemUptime - began)
                return nil
            }
            checks["granted"] = true
            InputDiagnostics.shared.record("mutation-gate", revision: expectedRevision, checks: checks,
                elapsed: ProcessInfo.processInfo.systemUptime - began)
            cancelGestureStateForInterception()
            let deadline = ProcessInfo.processInfo.systemUptime + 0.2
            let nonce = session.beginMutation(before, deadline: deadline)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.mutationNonce == nonce, !self.replaying, self.revision == expectedRevision else { return }
                InputDiagnostics.shared.record("mutation-soft-deadline", revision: expectedRevision,
                    checks: ["nativePaste": nativePaste], elapsed: ProcessInfo.processInfo.systemUptime - began)
                self.revision += 1 // soft deadline; the in-flight AX request must finish before releasing input
            }
            return deadline
        }
        guard let operationDeadline else { traceResult(.notApplied, gated: false); return (.notApplied, nil, false) }
        let delay = DispatchQueue.main.sync { store.testSelectionDelay }
        let result: AccessibilityEditor.ReplacementResult
        if nativePaste {
            result = AccessibilityEditor.pastePlainNative(before, text: replacement,
                clipboardChangeCount: clipboardChangeCount, deadline: operationDeadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: before.pid, sourceID: expectedSource) })
        } else {
            result = AccessibilityEditor.replace(before, range: range, replacement: replacement,
                keepSelection: keepSelection, testSelectionDelay: delay, deadline: operationDeadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: before.pid, sourceID: expectedSource) })
        }
        traceResult(result, gated: true)
        let settled = result.settledSnapshot {
            AccessibilityEditor.capture(deadline: operationDeadline,
                isCurrent: { self.isCurrent(expectedRevision, pid: before.pid, sourceID: expectedSource) }).snapshot
        }
        return (result, settled, true)
    }
    private func finishMutation(_ result: AccessibilityEditor.ReplacementResult, before: EditorSnapshot, settled: EditorSnapshot?,
                                allowAutomaticReplay: Bool = false, allowPartialReplay: Bool = false,
                                recoverySource: String? = nil) {
        let expected: EditorSnapshot
        if case .verified(let after) = result { expected = after } else { expected = before }
        let completion: InputRecovery.Completion
        switch result {
        case .notApplied: completion = .notApplied
        case .verified: completion = .verified
        case .uncertain: completion = .uncertain
        }
        let safe = settled.map { AccessibilityEditor.sameTarget(expected, $0) && expected.matchesContent($0) } ?? false
        let sourceMatches = recoverySource == nil || recoverySource == InputSources.identifier
        let contextMatches = safe && sourceMatches && NSWorkspace.shared.frontmostApplication?.processIdentifier == expected.pid && !IsSecureEventInputEnabled()
        switch session.finish(completion, expected: expected, sourceID: recoverySource ?? InputSources.identifier,
                              contextMatches: contextMatches) {
        case .resume:
            if !contextMatches {
                resetTransient()
                captureAfterEvent()
            }
            // Commit the pinned-source proof before our own requested source change.
            if contextMatches, let source = sourceAfterReplay {
                sourceAfterReplay = nil
                if allowedFrontmost(), AXIsProcessTrusted(), source.change.apply() {
                    store.inputSource = InputSources.identifier
                    store.lastStatus = source.change.status
                }
            }
            InputDiagnostics.shared.record("recovery-empty-resume", revision: revision, counts: recoveryCounts)
        case .replay:
            let verified: Bool
            if case .verified = result { verified = true } else { verified = false }
            replayDelayedInput(target: expected, allowAutomatic: verified && allowAutomaticReplay,
                allowPartialReplay: allowPartialReplay && store.earlyCorrection)
        case .retain, .review:
            sourceAfterReplay = nil; transaction = nil; cachedSnapshot = nil
            let reason = recovery.requiresReview ? "mutation-uncertain" : "recovery-context-unavailable"
            InputDiagnostics.shared.fault(reason: reason, revision: revision, counts: recoveryCounts)
        }
        updateServiceStatus()
        if stopRequested { stop() }
    }
    private func replayDelayedInput(target: EditorSnapshot, allowAutomatic: Bool = false,
                                    allowPartialReplay: Bool = false) {
        switch session.startReplay(target: target) {
        case .blocked: updateServiceStatus(); return
        case .empty: store.pendingInput = 0; store.recoveryRequired = false; updateServiceStatus(); return
        case .started: store.pendingInput = 0; store.recoveryRequired = false
        }
        cancelGestureStateForInterception()
        revision += 1; cachedSnapshot = nil
        if inputReplay.containsPending(where: { !preservesContext($0) }) { transaction = nil }
        replayReadbackNonce = UUID()
        // Anchored-token catch-up is a separate, explicit authority granted only
        // after a verified partial rollback. Ordinary/manual/undo replay keeps
        // the existing first-boundary policy unchanged.
        replayAllowsPartial = allowPartialReplay
        replayProjection = (allowAutomatic || allowPartialReplay) ?
            ReplayInsertionProjection(anchorText: target.text, selection: target.selection) : nil
        replayProjectionSource = replayProjection != nil ? InputSources.identifier : nil
        recoveryReplayProjection = ReplayInsertionProjection(anchorText: target.text, selection: target.selection)
        recoveryReplaySource = InputSources.identifier
        drainReplay()
    }
    private func selectSource(_ change: SourceChange, pid: pid_t) -> Bool {
        if inputReplay.isEmpty && mutationGate == nil {
            let selected = change.apply()
            InputDiagnostics.shared.record("source-selection", revision: revision,
                checks: ["selected": selected, "deferred": false])
            return selected
        }
        let contextPreserved = !inputReplay.containsPending(where: { !preservesContext($0) })
        InputDiagnostics.shared.record("source-selection", revision: revision,
            checks: ["selected": false, "deferred": contextPreserved, "pendingReplay": true])
        if contextPreserved {
            sourceAfterReplay = (pid, change)
        }
        return false
    }
    private func preservesContext(_ event: CGEvent) -> Bool {
        event.type == .keyUp || (event.type == .flagsChanged && ModifierGesture.isRelease(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), rawFlags: event.flags.rawValue))
    }
    /// Observe each acknowledged replay event once. Invalid prediction disables only
    /// catch-up; it never discards, duplicates or changes FIFO delivery.
    private func projectReplayedEvent(_ type: CGEventType, _ event: CGEvent) {
        let sourceID = InputSources.identifier
        let projected = normalizedReplayInsertion(type, event, sourceID: sourceID)
        if var projection = replayProjection {
            if replayProjectionSource != sourceID { projection.invalidate(reason: .sourceChanged) }
            else if let projected { projection.consume(projected) }
            else { projection.invalidate() }
            replayProjection = projection
        }
        // Independent of automatic processing. It predicts no corrections and is
        // updated only on .forward, never on a posted, retained or timed-out event.
        if var projection = recoveryReplayProjection {
            if recoveryReplaySource != sourceID { projection.invalidate(reason: .sourceChanged) }
            else if let projected { projection.consume(projected) }
            else { projection.invalidate() }
            recoveryReplayProjection = projection
        }
    }
    private func normalizedReplayInsertion(_ type: CGEventType, _ event: CGEvent, sourceID: String) -> ReplayInsertionProjection.Event? {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp { return .keyUp }
        if type == .flagsChanged, preservesContext(event) { return .modifierRelease }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let characters = InputSources.insertionText(for: event, sourceID: sourceID),
              TextEdit.insertionPrediction(text: "", selection: NSRange(location: 0, length: 0),
                  characters: characters, keyCode: key) != nil else { return nil }
        return .insertion(characters)
    }
    /// Keep the original AX identity and change only text/caret predicted from
    /// acknowledged insertions. Recovery still requires exact observed readback.
    private func replayRecoveryTarget(_ target: EditorSnapshot) -> (value: EditorSnapshot, predicted: Bool, source: String?) {
        guard let projection = recoveryReplayProjection, projection.isValid,
              projection.anchorText.utf16.elementsEqual(target.text.utf16),
              projection.anchorSelection == target.selection, let source = recoveryReplaySource else {
            return (target, false, recoveryReplaySource)
        }
        var expected = target
        expected.text = projection.expectedText; expected.selection = projection.expectedSelection
        return (expected, true, source)
    }
    /// A tap acknowledgement precedes editor insertion. Publish a replay cache or
    /// propose corrections only after exact full-text/caret readback, never from
    /// the first potentially stale AX snapshot.
    private func scheduleStreamReadback() {
        guard let stream = streamReadback else { return }
        let expectedRevision = revision, nonce = UUID()
        replayReadbackNonce = nonce
        // Let a continuous word stream settle; predictions never authorize writes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.150) { [weak self] in
            guard let self, self.revision == expectedRevision, self.replayReadbackNonce == nonce else { return }
            self.captureAfterReplay(anchor: stream.anchor, projection: stream.projection, sourceID: stream.source,
                nonce: nonce, revision: expectedRevision, deadline: ProcessInfo.processInfo.systemUptime + 0.060,
                learnSingle: stream.learnSingle)
        }
    }
    private func captureAfterReplay(anchor: EditorSnapshot, projection: ReplayInsertionProjection,
                                    sourceID: String, nonce: UUID, revision expectedRevision: Int,
                                    deadline: TimeInterval, allowPartialReplay: Bool = false, learnSingle: Bool = false) {
        axQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
            guard let self, self.isCurrent(expectedRevision) else { return }
            let current = AccessibilityEditor.capture(deadline: deadline, isCurrent: { self.isCurrent(expectedRevision) }).snapshot
            DispatchQueue.main.async {
                guard self.replayReadbackNonce == nonce, self.revision == expectedRevision else { return }
                guard self.allowedFrontmost(), !self.replaying, self.mutationGate == nil,
                      self.recoveryTarget == nil, self.inputReplay.isEmpty,
                      self.pendingNativePaste == nil, sourceID == InputSources.identifier else {
                    self.streamReadback = nil; self.cachedSnapshot = nil
                    return
                }
                let sameTarget = current.map { AccessibilityEditor.sameTarget(anchor, $0) } ?? false
                let matched = current.map { projection.matchesObserved(text: $0.text, selection: $0.selection,
                    ownsAnchor: sameTarget) } ?? false
                let inTime = ProcessInfo.processInfo.systemUptime < deadline
                InputDiagnostics.shared.record("replay-readback", revision: expectedRevision,
                    checks: ["sameTarget": sameTarget, "exactPrediction": matched, "withinDeadline": inTime,
                        "completedTokens": !projection.completedTokenRanges.isEmpty,
                        "partialReplay": allowPartialReplay])
                guard matched, let current else {
                    self.cachedSnapshot = nil
                    if !inTime || (current != nil && !sameTarget) { self.streamReadback = nil }
                    if inTime, current == nil || sameTarget {
                        self.captureAfterReplay(anchor: anchor, projection: projection, sourceID: sourceID,
                            nonce: nonce, revision: expectedRevision, deadline: deadline,
                            allowPartialReplay: allowPartialReplay, learnSingle: learnSingle)
                    }
                    return
                }
                guard inTime else { self.cachedSnapshot = nil; self.streamReadback = nil; return }
                self.streamReadback = nil
                self.cachedSnapshot = (expectedRevision, current)
                guard !self.stopRequested else { return }
                if allowPartialReplay {
                    // Exact full AX readback above proves the acknowledged suffix
                    // belongs to this rollback's anchor/source/revision. Reuse the
                    // guarded evaluators; the prediction itself never authorizes AX.
                    guard self.store.earlyCorrection else { return }
                    InputDiagnostics.shared.record("partial-replay-catchup", revision: expectedRevision,
                        checks: ["unfinishedTail": projection.hasUnfinishedTail, "earlyEnabled": true])
                    if projection.hasUnfinishedTail { self.automaticPartial(current) }
                    else { self.automatic(current) }
                    return
                }
                let language: (String) -> Language? = { self.engine.completedTokenLanguage($0, context: self.context(current)) }
                guard let batch = projection.finish(observedText: current.text, selection: current.selection,
                        ownsAnchor: true, language: language,
                        decide: { self.completedTokenDecision($0, context: self.context(current)) }) else {
                    if let target = projection.lastCompletedToken.flatMap(language), InputSources.language != target {
                        _ = self.selectSource(.language(target), pid: current.pid)
                        self.store.inputSource = InputSources.identifier
                        self.streamReadback = nil
                    }
                    return
                }
                var decision = batch.decision
                let learnsWord = learnSingle && batch.tokens.count == 1
                if learnsWord {
                    decision = batch.tokens[0]
                    decision.targetLanguage = batch.decision.targetLanguage
                }
                self.apply(current, range: batch.edit.range, decision: decision,
                    statisticsDecisions: batch.tokens, learnOnUndo: learnsWord)
            }
        }
    }
    private func drainReplay() {
        let target: EditorSnapshot
        switch session.drainStep() {
        case .wait: return
        case .next(let next): target = next
        case .drained(let anchor):
            InputDiagnostics.shared.record("replay-drained", revision: revision,
                checks: ["pendingSource": sourceAfterReplay != nil])
            let projection = replayProjection
            let projectionSource = replayProjectionSource
            let allowPartialReplay = replayAllowsPartial
            replayProjection = nil; replayProjectionSource = nil; replayAllowsPartial = false
            recoveryReplayProjection = nil; recoveryReplaySource = nil
            if let source = sourceAfterReplay {
                sourceAfterReplay = nil
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == source.pid,
                   AXIsProcessTrusted(), allowedFrontmost(), source.change.apply() {
                    store.inputSource = InputSources.identifier
                    store.lastStatus = source.change.status
                }
            }
            if let anchor, let projection, projection.isValid, let projectionSource,
               projectionSource == InputSources.identifier, !stopRequested {
                if !allowPartialReplay {
                    streamReadback = (anchor, projection, projectionSource, false)
                    var predicted = anchor
                    predicted.text = projection.expectedText; predicted.selection = projection.expectedSelection
                    cachedSnapshot = (revision, predicted)
                    scheduleStreamReadback()
                    updateServiceStatus()
                    return
                }
                let nonce = UUID(); replayReadbackNonce = nonce
                captureAfterReplay(anchor: anchor, projection: projection, sourceID: projectionSource,
                    nonce: nonce, revision: revision, deadline: ProcessInfo.processInfo.systemUptime + 0.060,
                    allowPartialReplay: allowPartialReplay)
            } else { captureAfterEvent() }
            if stopRequested { stop() }
            updateServiceStatus()
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              allowedFrontmost(), AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            suspendReplay(target: target); return
        }
        // No AX IPC in the tap/main loop. At most one event is posted for each
        // fresh field/window/document proof; new hardware stays in the FIFO.
        let expectedRevision = revision
        let sourceID = InputSources.identifier
        let identityNonce = session.beginIdentityCheck()
        axQueue.async { [weak self] in
            guard let self else { return }
            let identityMatches = self.replayIdentityMatches(target, expectedRevision: expectedRevision)
            let checkedAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [self] in
                guard let active = self.session.identityCheckTarget(identityNonce),
                      AccessibilityEditor.sameTarget(active, target) else { return }
                self.session.clearIdentityCheck()
                let checks = ["identity": identityMatches, "revision": self.revision == expectedRevision,
                    "allowed": self.allowedFrontmost(), "trusted": AXIsProcessTrusted(),
                    "posting": CGPreflightPostEventAccess(),
                    "frontmost": NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                    "source": sourceID == InputSources.identifier,
                    "leaseFresh": ProcessInfo.processInfo.systemUptime - checkedAt <= 0.050,
                    "replaySource": self.replaySource != nil]
                guard checks.values.allSatisfy({ $0 }), let source = self.replaySource else {
                    InputDiagnostics.shared.record("replay-route-rejected", revision: expectedRevision, checks: checks)
                    self.suspendReplay(target: target); return
                }
                guard let delivery = self.session.dispatchNext(revision: expectedRevision, sourceID: sourceID,
                          issuedAt: checkedAt, leaseDuration: 0.050),
                      let event = delivery.batch.events.first else { return }
                let deliveryTag = Int64(bitPattern: (Self.replayPrefix << 32) | UInt64(delivery.batch.token))
                source.userData = deliveryTag
                source.localEventsSuppressionInterval = 0
                let batchNonce = delivery.batchNonce
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.replaying, self.replayBatchNonce == batchNonce,
                          self.inputReplay.outstanding > 0 else { return }
                    self.deliveryTimedOut()
                }
                event.setSource(source)
                event.setIntegerValueField(.eventSourceUserData, value: deliveryTag)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
    private func deliveryTimedOut() {
        guard replaying, inputReplay.outstanding > 0 else { return }
        let anchor = mutationGate.map { replayRecoveryTarget($0) }
        session.timeOutDelivery(recoveryTarget: anchor?.value, sourceID: anchor?.source)
        sourceAfterReplay = nil
        recoveryReplayProjection = nil; recoveryReplaySource = nil
        replayProjection = nil; replayProjectionSource = nil; replayAllowsPartial = false; replayReadbackNonce = UUID()
        InputDiagnostics.shared.fault(reason: "delivery-timeout", revision: revision, counts: recoveryCounts)
        updateServiceStatus()
        store.lastStatus = anchor?.predicted == true ?
            "Доставка одного события не подтверждена: сохранён только подтверждённый префикс; проверьте текст" :
            "Доставка не подтверждена; контекст после команд неизвестен — восстановление требует точного исходного текста"
    }
    /// Retry only transient AX failure, with the same pinned target and per-call limit.
    private func replayIdentityMatches(_ target: EditorSnapshot, expectedRevision: Int) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.150
        var failure: EditorSnapshotFailure = .staleContext
        func matches() -> Bool {
            guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                  let expectedWindow = target.window else { return false }
            var stage = "focused-field"
            var accepted = false
            defer { InputDiagnostics.shared.record("replay-identity", revision: -1,
                checks: ["accepted": accepted], reason: stage) }
            func attribute(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { failure = .deadlineExceeded; return (.cannotComplete, nil) }
                AXUIElementSetMessagingTimeout(element, Float(min(0.030, remaining)))
                var value: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
                if status == .cannotComplete { failure = .axCannotComplete }
                if status != .success && status != .noValue && status != .attributeUnsupported {
                    InputDiagnostics.shared.record("replay-identity-ax", revision: -1,
                        checks: ["cannotComplete": status == .cannotComplete], reason: stage)
                }
                return (status, value)
            }
            let app = AXUIElementCreateApplication(target.pid)
            let (fieldStatus, rawField) = attribute(app, kAXFocusedUIElementAttribute)
            guard fieldStatus == .success, let rawField,
                  CFGetTypeID(rawField) == AXUIElementGetTypeID() else { return false }
            let field = rawField as! AXUIElement
            stage = "field-equality"
            guard CFEqual(field, target.element) else { return false }
            stage = "field-window"
            let (windowStatus, rawWindow) = attribute(field, kAXWindowAttribute)
            guard windowStatus == .success, let rawWindow,
                  CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return false }
            let window = rawWindow as! AXUIElement
            stage = "window-equality"
            guard CFEqual(window, expectedWindow) else { return false }
            stage = "window-document"
            let (documentStatus, rawDocument) = attribute(window, kAXDocumentAttribute)
            let document: String?
            if documentStatus == .success {
                guard let value = rawDocument as? String else { return false }
                document = value
            } else if documentStatus == .noValue || documentStatus == .attributeUnsupported {
                document = nil
            } else { return false }
            stage = "document-equality"
            guard document == target.document else { return false }
            // Recheck the focused element after querying its window/document. This
            // reduces the lease gap, but cannot make AX-check → event delivery atomic.
            stage = "final-focused-field"
            let (finalStatus, finalField) = attribute(app, kAXFocusedUIElementAttribute)
            accepted = finalStatus == .success && finalField.map { CFEqual($0, target.element) } == true &&
                AXIsProcessTrusted() && !IsSecureEventInputEnabled() &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
            return accepted
        }
        let result = EditorSnapshotBudget(deadline: deadline).retry(
            now: { ProcessInfo.processInfo.systemUptime },
            isCurrent: { self.isCurrent(expectedRevision) },
            pause: { Thread.sleep(forTimeInterval: $0) }) {
                failure = .staleContext
                return matches() ? .success(true) : .failure(failure)
            }
        if case .success(true) = result { return true }
        return false
    }

    private func suspendReplay(target: EditorSnapshot) {
        let recovery = replayRecoveryTarget(target)
        replayProjection = nil; replayProjectionSource = nil; replayAllowsPartial = false; replayReadbackNonce = UUID()
        sourceAfterReplay = nil
        session.suspendReplay(recoveryTarget: recovery.value, sourceID: recovery.source)
        recoveryReplayProjection = nil; recoveryReplaySource = nil
        cachedSnapshot = nil; transaction = nil
        InputDiagnostics.shared.fault(reason: "replay-suspended", revision: revision, counts: recoveryCounts)
        updateServiceStatus()
        store.lastStatus = recovery.predicted ?
            "Доставка приостановлена: вернитесь к подтверждённому тексту и каретке в исходном поле" :
            "Доставка приостановлена; контекст после команд неизвестен — требуется точное исходное состояние"
    }
    func recoverInput() {
        guard let expected = session.recoveryCandidate,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expected.pid,
              !IsSecureEventInputEnabled() else { return }
        if let source = recoverySourceID, source != InputSources.identifier {
            skipped("Для восстановления верните исходную раскладку"); return
        }
        let expectedSource = recoverySourceID
        let expectedRevision = revision
        cancelGestureStateForInterception()
        session.beginRecovery(expected)
        axQueue.async { [weak self] in
            guard let self else { return }
            // No recovery write moves a changed caret. Match the acknowledged
            // prefix exactly; an unacknowledged event may already have arrived.
            let current = self.isCurrent(expectedRevision) ? AccessibilityEditor.snapshot() : nil
            let matched = current.map { AccessibilityEditor.sameTarget(expected, $0) &&
                expected.text.utf16.elementsEqual($0.text.utf16) && expected.selection == $0.selection } ?? false
            let sourceMatches = DispatchQueue.main.sync {
                expectedSource == nil || expectedSource == InputSources.identifier
            }
            let settled = matched && sourceMatches && self.isCurrent(expectedRevision) ? current : nil
            DispatchQueue.main.async {
                let sourceStillMatches = expectedSource == nil || expectedSource == InputSources.identifier
                self.finishMutation(.notApplied, before: expected,
                    settled: self.revision == expectedRevision && sourceStillMatches ? settled : nil,
                    recoverySource: expectedSource)
            }
        }
    }
    var hasPendingInput: Bool { session.hasPendingInput }
    func confirmTextReviewed() {
        guard session.confirmReviewed() else { return }
        InputDiagnostics.shared.record("text-review-confirmed", revision: revision, counts: recoveryCounts)
        if inputReplay.isDrained {
            recoveryReplayProjection = nil; recoveryReplaySource = nil
        }
        resetTransient(); tapRecovery.reset(); refresh(); captureAfterEvent()
    }
    func discardPendingInput() {
        guard session.mayDiscardPending else { return }
        let alert = NSAlert(); alert.messageText = "Отбросить задержанные нажатия?"
        alert.informativeText = "Они хранятся только в памяти. После удаления восстановить их нельзя."
        alert.addButton(withTitle: "Сохранить"); alert.addButton(withTitle: "Отбросить")
        // The modal panel runs the main loop; discard only if still applicable.
        if alert.runModal() == .alertSecondButtonReturn, session.discardPending() {
            recoveryReplayProjection = nil; recoveryReplaySource = nil
            InputDiagnostics.shared.record("pending-discarded", revision: revision, counts: recoveryCounts)
            if stopRequested { stop() }
            refresh(); captureAfterEvent()
        }
    }
    func saveDiagnosticReport() {
        InputDiagnostics.shared.record("manual-snapshot", revision: revision,
            checks: ["tapActive": store.tapActive, "trusted": store.trusted, "listening": store.listening,
                     "posting": store.posting, "secure": store.secure], counts: recoveryCounts,
            reason: store.serviceStatus.rawValue)
        InputDiagnostics.shared.exportReport { [weak self] result in
            switch result {
            case .success(let data):
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "TypeTune-диагностика.json"
                panel.title = "Сохранить технический отчёт"
                guard panel.runModal() == .OK, let destination = panel.url else { return }
                InputDiagnostics.shared.saveReport(data, to: destination) { [weak self] saved in
                    switch saved {
                    case .success: self?.store.lastStatus = "Диагностический отчёт сохранён на этом Mac"
                    case .failure: self?.store.lastStatus = "Не удалось сохранить отчёт в выбранном месте"
                    }
                }
            case .failure:
                self?.store.lastStatus = "Не удалось сохранить отчёт; обработка ввода не изменена"
            }
        }
    }
    private func skipped(_ message: String) {
        skippedCount += 1
        if store.lastStatus != message { store.lastStatus = message }
    }
    #if LAYOUTPILOT_TESTING
    func testingEnableContextCapture() { precondition(!observesSystem); testingContextCaptureEnabled = true }
    func testingPrepareKeyRead(inserted: String = "n", keyCode: Int = 0, deadline: TimeInterval? = nil) {
        precondition(!observesSystem)
        pendingKeyRead = (revision, -1, "test-source", keyCode, inserted,
            deadline ?? ProcessInfo.processInfo.systemUptime + 0.060)
    }
    func testingMarkPrimaryCapture() { precondition(!observesSystem); contextCaptureRevision = revision }
    func testingReleaseKey(keyCode: Int = 0) {
        precondition(!observesSystem)
        _ = handle(.keyUp, CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)!)
    }
    var testingRequestedContextRevisions: [Int] { testingContextRequests }
    var testingHasCurrentContext: Bool { cachedSnapshot?.revision == revision }
    var testingHasManualProposal: Bool { manualSnapshot != nil }
    var testingContextCapturePending: Bool { contextCaptureRevision == revision }
    func testingInvalidateContext() { precondition(!observesSystem); resetTransient() }
    func testingCompleteContextCapture(revision: Int, contextMatches: Bool = true,
                                       failure: EditorSnapshotFailure? = nil, text: String = "ghbdtn",
                                       selection: NSRange? = nil, now: TimeInterval? = nil) {
        precondition(!observesSystem)
        let snapshot = EditorSnapshot(element: AXUIElementCreateApplication(-1), window: nil,
            document: nil, pid: -1, application: "com.apple.TextEdit", text: text,
            selection: selection ?? NSRange(location: text.utf16.count, length: 0))
        if let failure {
            finishContextCapture(.failure(failure), revision: revision, contextMatches: contextMatches)
        } else if !contextMatches {
            finishContextCapture(.failure(.staleContext), revision: revision, contextMatches: false)
        } else if let pending = pendingKeyRead {
            let time = now ?? ProcessInfo.processInfo.systemUptime
            let accepted = acceptKeyBaseline(snapshot, inserted: pending.inserted, keyCode: pending.keyCode,
                revision: revision, deadline: pending.deadline, now: time)
            if accepted || time >= pending.deadline { finishKeyBaselineCapture(revision: revision) }
        }
    }
    func testingFinish(_ completion: InputRecovery.Completion, pending: Int = 0) {
        precondition(!observesSystem)
        let field = AXUIElementCreateApplication(-1)
        let snapshot = EditorSnapshot(element: field, window: nil, document: nil, pid: -1,
            application: "com.apple.TextEdit", text: "fixture", selection: NSRange(location: 7, length: 0))
        for _ in 0..<pending { _ = session.intercept(CGEvent(source: nil)!) }
        let result: AccessibilityEditor.ReplacementResult
        switch completion {
        case .verified: result = .verified(snapshot)
        case .notApplied: result = .notApplied
        case .uncertain: result = .uncertain
        }
        finishMutation(result, before: snapshot, settled: nil, recoverySource: "test-source")
    }
    func testingStartOutstanding(pendingAfter: Int = 0) {
        precondition(!observesSystem)
        testingFinish(.notApplied, pending: 1)
        // The retained fixture event becomes one posted, unacknowledged delivery.
        if let target = recoveryTarget, session.startReplay(target: target) == .started {
            _ = session.dispatchNext(revision: revision, sourceID: "test-source", issuedAt: 0, leaseDuration: 0)
        }
        for _ in 0..<pendingAfter { _ = session.intercept(CGEvent(source: nil)!) }
        updateServiceStatus()
    }
    func testingDeliveryTimeout() { precondition(!observesSystem); deliveryTimedOut() }
    func testingRefreshStatus() { precondition(!observesSystem); updateServiceStatus() }
    func testingNextTapAction(safe: Bool) -> TapRecovery.Action {
        precondition(!observesSystem); return tapRecovery.next(safe: safe)
    }
    func testingTerminalPolicy() -> Bool {
        precondition(!observesSystem); return terminalPolicyPermitsAction
    }
    func testingSnapshotFailure(_ failure: EditorSnapshotFailure) {
        precondition(!observesSystem); reportContextFailure(failure)
    }
    #endif

}
