import AppKit
import SwiftUI
import ServiceManagement
import TypeTuneSupport
import Darwin
private typealias ViewState<Value> = SwiftUI.State<Value>
typealias Settings = TypeTuneSupport.Settings

final class Controller: ObservableObject {
    enum PreferencesTab: Hashable { case layouts, words }

    @Published var settings = Settings()
    @Published var status = "Инициализация…"
    @Published var error = ""
    @Published var running = true
    @Published var applying = false
    @Published var layoutFlag = LayoutFlag.unknown
    @Published var preferredTab: PreferencesTab = .layouts
    let runtime = Runtime()
    let store = SettingsStore(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeTune/settings.json"))
    private var tokens: [NSObjectProtocol] = []
    private let flagMonitor = LayoutFlagMonitor()
    private lazy var changes: SettingsTransactions = {
        let changes = SettingsTransactions(initial: settings, environment: .init(
            load: { [store] in try store.load() },
            save: { [store] value, expected in try store.save(value, expected: expected) },
            configure: { [runtime] value, dictionaryOnly, completion in
                if dictionaryOnly { runtime.configureDictionary(value, completion: completion) }
                else { runtime.configure(value, completion: completion) }
            },
            autostart: { enabled in
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                guard (SMAppService.mainApp.status == .enabled) == enabled else {
                    throw NSError(domain: "TypeTune", code: 1, userInfo: [NSLocalizedDescriptionKey: "Автозапуск требует подтверждения в настройках macOS"])
                }
            }))
        changes.onSettings = { [weak self] saved in
            guard let self else { return }
            self.settings = saved
            self.flagMonitor.refresh()
            self.uiUpdate?()
        }
        changes.onBusy = { [weak self] busy in self?.applying = busy }
        changes.onError = { [weak self] message in self?.error = message; self?.uiUpdate?() }
        changes.onRuntimeFailure = { [weak self] in
            self?.running = false
            self?.runtime.setEnabled(false)
            self?.uiUpdate?()
        }
        return changes
    }()
    var uiUpdate: (() -> Void)?

    init() {
        runtime.publish = { [weak self] message in self?.status = message }
        do { settings = try store.load() } catch { self.error = error.localizedDescription; running = false; runtime.setEnabled(false) }
        runtime.feedback = { [weak self] learned, exclusions, generation in
            self?.changes.feedback(learned: learned, exclusions: exclusions, generation: generation)
        }
        runtime.configure(settings) { [weak self] ok in
            guard let self, !ok else { return }
            self.error = "Движок отклонил настройки"
            self.running = false
            self.runtime.setEnabled(false)
        }
        runtime.start()
        flagMonitor.onChange = { [weak self] flag in
            guard let self, self.layoutFlag != flag else { return }
            self.layoutFlag = flag
            self.uiUpdate?()
        }
        flagMonitor.start { [weak self] in self?.settings.activeKeyboards ?? [] }
        let center = NSWorkspace.shared.notificationCenter
        for (name, suspended, reason) in [
            (NSWorkspace.willSleepNotification, true, Runtime.SuspensionReason.sleep),
            (NSWorkspace.didWakeNotification, false, .sleep),
            (NSWorkspace.sessionDidResignActiveNotification, true, .session),
            (NSWorkspace.sessionDidBecomeActiveNotification, false, .session)
        ] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.runtime.setSuspended(suspended, reason: reason) })
        }
        for (name, suspended) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.runtime.setSuspended(suspended, reason: .screenLock) })
        }
    }

    func toggle() {
        running.toggle()
        runtime.setEnabled(running)
        uiUpdate?()
    }

    func shutdown() {
        flagMonitor.stop()
        runtime.stop()
    }

    func permissions() {
        _ = CGRequestListenEventAccess(); _ = CGRequestPostEventAccess()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        // Deep links after ad-hoc rebuild: TCC grants follow the old cdhash.
        let base = "x-apple.systempreferences:com.apple.preference.security?Privacy_"
        if !CGPreflightListenEventAccess() {
            NSWorkspace.shared.open(URL(string: base + "ListenEvent")!)
        }
        if !AXIsProcessTrusted() || !CGPreflightPostEventAccess() {
            NSWorkspace.shared.open(URL(string: base + "Accessibility")!)
        }
    }

    /// UI edits and verified feedback share one serialized generation/CAS path.
    func apply(_ proposed: Settings, basedOn base: Settings? = nil, completion: ((Bool) -> Void)? = nil) {
        error = ""
        changes.apply(proposed, basedOn: base ?? settings, completion: completion)
    }

    func addLearned(_ word: String) {
        let next = settings.addingLearned(word)
        guard next != settings else { return }
        apply(next)
    }

    func clearLearned() {
        error = ""
        changes.apply(settings.clearingLearned(), basedOn: settings, clearLearned: true)
    }
}

struct PreferencesView: View {
    @ObservedObject var controller: Controller
    @ViewState private var draft = Settings()
    @ViewState private var base = Settings()
    @ViewState private var exclusions = ""
    @ViewState private var activeKeyboards = ""
    @ViewState private var autoDisabledIn: [String] = []
    @ViewState private var runningBundles: [String] = []
    @ViewState private var newExclusion = ""

    private func load() {
        draft = controller.settings
        base = draft
        exclusions = draft.exclusions.joined(separator: "\n")
        activeKeyboards = draft.activeKeyboards.joined(separator: "\n")
        autoDisabledIn = draft.autoDisabledIn
        runningBundles = NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { !$0.hasPrefix("com.apple.") || $0 == "com.apple.TextEdit" }
            .sorted()
    }

    private func lines(_ value: String) -> [String] {
        Array(Set(value.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }

    private func commitLists() {
        draft.exclusions = lines(exclusions.lowercased())
        draft.activeKeyboards = lines(activeKeyboards)
        draft.autoDisabledIn = autoDisabledIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.status).accessibilityIdentifier("runtime-status").lineLimit(2)
                Spacer()
                Button(controller.running ? "Все выключено" : "Включить", action: controller.toggle)
            }
            if !controller.error.isEmpty {
                Text(controller.error).foregroundStyle(.red).textSelection(.enabled).font(.callout)
            }
            TabView(selection: $controller.preferredTab) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Активные раскладки (TIS ID)").font(.headline)
                    TextEditor(text: $activeKeyboards)
                        .accessibilityIdentifier("active-keyboards")
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    Text("Без автопереключения").font(.headline)
                    HStack {
                        Menu("Добавить приложение") {
                            ForEach(runningBundles.filter { !autoDisabledIn.contains($0) }, id: \.self) { bundle in
                                Button(bundle) {
                                    autoDisabledIn = Array(Set(autoDisabledIn + [bundle])).sorted()
                                }
                            }
                        }
                        Spacer()
                    }
                    List {
                        ForEach(autoDisabledIn, id: \.self) { bundle in
                            HStack {
                                Text(bundle).font(.caption)
                                Spacer()
                                Button("Убрать") { autoDisabledIn.removeAll { $0 == bundle } }.buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(height: 72)
                    Toggle("Режим совместимости", isOn: $draft.compatibility)
                    Text("Текст набора и буфер обмена не сохраняются в логи.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .tabItem { Text("Раскладки") }
                .tag(Controller.PreferencesTab.layouts)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Выученные слова").font(.headline)
                        Spacer()
                        Button("Очистить") { controller.clearLearned() }.disabled(controller.applying || controller.settings.learned.isEmpty)
                    }
                    List(controller.settings.learned, id: \.self) { word in Text(word).font(.caption) }
                        .frame(height: 96)
                    Text("Не переключать слова").font(.headline)
                    HStack {
                        TextField("слово", text: $newExclusion)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onSubmit {
                                let word = newExclusion.lowercased().trimmingCharacters(in: .whitespaces)
                                guard !word.isEmpty else { return }
                                exclusions = (lines(exclusions) + [word]).joined(separator: "\n")
                                newExclusion = ""
                            }
                        Button("Добавить") {
                            let word = newExclusion.lowercased().trimmingCharacters(in: .whitespaces)
                            guard !word.isEmpty else { return }
                            exclusions = (lines(exclusions) + [word]).joined(separator: "\n")
                            newExclusion = ""
                        }
                    }
                    List(lines(exclusions), id: \.self) { word in
                        HStack {
                            Text(word).font(.caption)
                            Spacer()
                            Button("Убрать") {
                                exclusions = lines(exclusions).filter { $0 != word }.joined(separator: "\n")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(height: 88)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .tabItem { Text("Слова") }
                .tag(Controller.PreferencesTab.words)
            }
            .disabled(controller.applying)
            HStack {
                Text("Поколение \(controller.settings.generation)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Перечитать", action: load)
                Button(controller.applying ? "Применение…" : "Применить") {
                    commitLists()
                    controller.apply(draft, basedOn: base) { ok in if ok { load() } }
                }
                .disabled(controller.applying)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 420, height: 360)
        .onAppear(perform: load)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lockFD: Int32 = -1
    private var item: NSStatusItem!
    private var window: NSWindow!
    private var controller: Controller!
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeTune")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch { NSApp.terminate(nil); return }
        lockFD = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        controller = Controller()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TypeTune — настройки"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView(controller: controller)); window.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let environment = StatusMenu.Environment(
            apply: { [weak self] in self?.controller.apply($0) },
            current: { [weak self] in self?.controller.settings ?? Settings() },
            isRunning: { [weak self] in self?.controller.running ?? true },
            toggleRunning: { [weak self] in self?.controller.toggle() },
            showLearnedWords: { [weak self] in self?.controller.preferredTab = .words; self?.show() },
            showAutoDisabledIn: { [weak self] in self?.controller.preferredTab = .layouts; self?.show() },
            showActiveKeyboards: { [weak self] in self?.controller.preferredTab = .layouts; self?.show() },
            showPermissions: { [weak self] in self?.controller.permissions() },
            showSettings: { [weak self] in self?.show() },
            quit: { NSApp.terminate(nil) }
        )
        let menu = StatusMenu(button: item.button, environment: environment)
        statusMenu = menu
        item.menu = menu.menu
        controller.uiUpdate = { [weak self] in
            guard let self else { return }
            self.statusMenu?.render(StatusMenu.State(settings: self.controller.settings, flag: self.controller.layoutFlag, running: self.controller.running))
        }
        controller.uiUpdate?()
        if !controller.settings.compatibility || !controller.error.isEmpty { show() }
    }

    @objc func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
        if lockFD >= 0 { close(lockFD) }
    }
}

@main struct TypeTuneMain {
    static func main() {
        if CommandLine.arguments.contains("--doctor") {
            let engine = Engine()
            let version = engine.call(["op": "protocol"])
            let bundle = Bundle.main
            let identifier = bundle.bundleIdentifier ?? "unknown"
            let otherProcesses = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                .map { Int($0.processIdentifier) }
            // This is a separate read-only process: finding the running app
            // does not establish that its event tap or worker is healthy.
            let data: [String: Any] = [
                "protocol": version,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "listen": CGPreflightListenEventAccess(),
                "post": CGPreflightPostEventAccess(),
                "accessibility": AXIsProcessTrusted(),
                "input_source": Native.inputSource().0,
                "login_item": SMAppService.mainApp.status.rawValue,
                "bundle_identifier": identifier,
                "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown",
                "build_description": bundle.object(forInfoDictionaryKey: "TypeTuneBuildDescription") ?? "unknown",
                "source_commit": bundle.object(forInfoDictionaryKey: "TypeTuneSourceCommit") ?? "unknown",
                "source_digest": bundle.object(forInfoDictionaryKey: "TypeTuneSourceDigest") ?? "unknown",
                "source_dirty": bundle.object(forInfoDictionaryKey: "TypeTuneSourceDirty") ?? NSNull(),
                "bundle_path": bundle.bundleURL.resolvingSymlinksInPath().path,
                "executable_path": bundle.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0],
                "process_id": Int(ProcessInfo.processInfo.processIdentifier),
                "runtime": [
                    "diagnostic_process_observer": "not_started",
                    "other_application_process_ids": otherProcesses,
                    "live_observer_status": "unavailable_separate_process"
                ] as [String: Any]
            ]
            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: json, as: UTF8.self)) }
            return
        }
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
}
