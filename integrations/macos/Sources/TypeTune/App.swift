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
    var uiUpdate: (() -> Void)?

    init() {
        runtime.publish = { [weak self] message in self?.status = message }
        do { settings = try store.load() } catch { self.error = error.localizedDescription; running = false; runtime.setEnabled(false) }
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
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.runtime.setSuspended(true) })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.runtime.setSuspended(false) })
        }
        for (name, suspended) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.runtime.setSuspended(suspended) })
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
    }

    /// Single apply path: generation ACK, engine configure, autostart side effects.
    func apply(_ proposed: Settings) {
        guard !applying else { return }; applying = true; error = ""
        do {
            try proposed.validate()
            guard try store.load().generation == proposed.generation else { throw SettingsError.conflict }
        } catch { self.error = error.localizedDescription; applying = false; return }
        let previous = settings
        runtime.configure(proposed) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.error = "Движок отклонил настройки"; self.applying = false; return }
            do {
                if proposed.autostart != previous.autostart {
                    if proposed.autostart { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    guard (SMAppService.mainApp.status == .enabled) == proposed.autostart else { throw NSError(domain: "TypeTune", code: 1, userInfo: [NSLocalizedDescriptionKey: "Автозапуск требует подтверждения в настройках macOS"]) }
                }
                self.settings = try self.store.save(proposed, expected: previous.generation)
                self.applying = false
                self.flagMonitor.refresh()
                self.uiUpdate?()
            } catch {
                self.error = error.localizedDescription
                if let restore = LoginItemIntent.rollbackTarget(desired: proposed.autostart, previous: previous.autostart) {
                    if restore { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
                self.runtime.configure(previous) { _ in self.applying = false; self.uiUpdate?() }
            }
        }
    }

    // Learned words: Swift store only; bridge ops stay owned by the Rust side.
    func addLearned(_ word: String) {
        let next = settings.addingLearned(word)
        guard next != settings else { return }
        apply(next)
    }

    func clearLearned() {
        guard !settings.learned.isEmpty else { return }
        apply(settings.clearingLearned())
    }
}

struct PreferencesView: View {
    @ObservedObject var controller: Controller
    @ViewState private var draft = Settings()
    @ViewState private var exclusions = ""
    @ViewState private var activeKeyboards = ""
    @ViewState private var autoDisabledIn: [String] = []
    @ViewState private var runningBundles: [String] = []
    @ViewState private var newExclusion = ""

    private func load() {
        draft = controller.settings
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
                        Button("Очистить") { controller.clearLearned() }.disabled(controller.applying || draft.learned.isEmpty)
                    }
                    List(draft.learned, id: \.self) { word in Text(word).font(.caption) }
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
            HStack {
                Text("Поколение \(controller.settings.generation)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Перечитать", action: load)
                Button(controller.applying ? "Применение…" : "Применить") {
                    commitLists()
                    controller.apply(draft)
                }
                .disabled(controller.applying)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 420, height: 360)
        .onAppear(perform: load)
        .onChange(of: controller.settings.generation) { load() }
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
            let data: [String: Any] = ["protocol": version, "os": ProcessInfo.processInfo.operatingSystemVersionString, "listen": CGPreflightListenEventAccess(), "post": CGPreflightPostEventAccess(), "accessibility": AXIsProcessTrusted(), "input_source": Native.inputSource().0, "login_item": SMAppService.mainApp.status.rawValue]
            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: json, as: UTF8.self)) }
            return
        }
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
}
