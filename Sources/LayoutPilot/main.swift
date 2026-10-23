import AppKit
import Carbon
import Combine
import LayoutPilotCore
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var keyboard: KeyboardService!
    var statusItem: NSStatusItem!
    private var statusMenu = NSMenu()
    var window: NSWindow?
    var cancellables = Set<AnyCancellable>()
    /// The input source the flag shows. macOS may switch the source per application or
    /// window ("document input source", Chrome web-app windows) without a selection
    /// notification reaching us, so the flag also rechecks the current source.
    private var shownSource = ""
    private var sourceTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()
        // Decode the ~60k-word lexicon and its prefix index off the main thread, so the
        // first keystroke does not pay the one-time load (static lets are initialized once).
        DispatchQueue.global(qos: .utility).async { _ = Lexicon.bundled; _ = PartialLayoutDetector.bundled }
        store.launchAtLogin = SMAppService.mainApp.status == .enabled
        keyboard = KeyboardService(store: store)
        keyboard.onRecoveryNeeded = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        rebuildMenu()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateStatusItem),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateStatusItem),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        sourceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, InputSources.identifier != self.shownSource else { return }
            self.updateStatusItem()
        }
        store.$settings.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildMenu() }.store(in: &cancellables)
        store.$serviceStatus.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildMenu() }.store(in: &cancellables)
        store.$recoveryRequired.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildMenu() }.store(in: &cancellables)
        if !ProcessInfo.processInfo.arguments.contains("--background") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if keyboard?.hasPendingInput == true {
            store.lastStatus = store.textReviewRequired ? "Проверьте текст и подтвердите продолжение в настройках" :
                "Дождитесь завершения операции или восстановите сохранённые нажатия"
            showSettings(); return .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self); sourceTimer?.invalidate()
        keyboard?.stop(); InputDiagnostics.shared.flush()
    }
    func rebuildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let title = NSMenuItem(title: "TypeTune · " + store.serviceStatus.title.lowercased(), action: nil, keyEquivalent: "")
        menu.addItem(title)
        let layout = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        layout.tag = 1001; menu.addItem(layout); menu.addItem(.separator())
        let automatic = NSMenuItem(title: "Автоисправления", action: #selector(toggleAutomatic), keyEquivalent: "")
        automatic.target = self; automatic.state = store.settings.paused ? .off : .on
        automatic.isEnabled = store.settingsStorageAvailable; menu.addItem(automatic)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из TypeTune", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); statusMenu = menu
        updateStatusItem()
    }
    @objc func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            showSettings(); return
        }
        // Attach only while tracking: a permanent menu intercepts the ordinary click.
        statusItem.menu = statusMenu
        defer { statusItem.menu = nil }
        statusItem.button?.performClick(nil)
    }
    @objc func updateStatusItem() {
        shownSource = InputSources.identifier
        let layout = InputSources.language == .russian ? "Русская" : InputSources.language == .english ? "ABC" : shownSource
        statusMenu.item(withTag: 1001)?.title = "Раскладка: " + layout
        let flag = InputSources.language == .russian ? "🇷🇺" : (InputSources.language == .english ? "🇺🇸" : "🌐")
        let suffix = store.recoveryRequired || store.serviceStatus == .tapFailed ? " !" : (store.settings.paused ? " Ⅱ" : "")
        let title = NSMutableAttributedString(string: flag, attributes: [
            .font: NSFont.systemFont(ofSize: 20), .baselineOffset: -2
        ])
        title.append(NSAttributedString(string: suffix, attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
        statusItem.button?.attributedTitle = title
        let owner = store.secure ? store.secureInputOwner.map { "\nВключило: \($0)" } ?? "" : ""
        statusItem.button?.toolTip = "TypeTune · \(InputSources.identifier)\n\(store.serviceStatus.message)" + owner
    }
    private func configureApplicationMenu() {
        let bar = NSMenu()
        let application = NSMenu(title: "TypeTune")
        let appItem = NSMenuItem(title: "TypeTune", action: nil, keyEquivalent: "")
        appItem.submenu = application; bar.addItem(appItem)
        application.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",").target = self
        application.addItem(.separator())
        application.addItem(withTitle: "Выйти из TypeTune", action: #selector(quit), keyEquivalent: "q").target = self
        let edit = NSMenu(title: "Правка")
        let editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        editItem.submenu = edit; bar.addItem(editItem)
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windows = NSMenu(title: "Окно")
        let windowItem = NSMenuItem(title: "Окно", action: nil, keyEquivalent: "")
        windowItem.submenu = windows; bar.addItem(windowItem)
        windows.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = bar; NSApp.windowsMenu = windows
    }

    @objc func toggleAutomatic() {
        guard store.settingsStorageAvailable else { return }
        store.settings.paused.toggle(); rebuildMenu()
    }
    @objc func showSettings() {
        if window == nil {
            let view = SettingsView(store: store, keyboard: keyboard)
            let controller = NSHostingController(rootView: view)
            let result = NSWindow(contentViewController: controller)
            result.appearance = NSAppearance(named: .darkAqua)
            result.title = "TypeTune"; result.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            result.contentMinSize = NSSize(width: 760, height: 560)
            result.setContentSize(NSSize(width: 760, height: 560))
            result.isReleasedWhenClosed = false; result.center(); window = result
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

#if DEBUG
if CommandLine.arguments.contains("--render-settings") {
    do {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-settings" else {
            throw NSError(domain: "UIRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Использование: LayoutPilot --render-settings <каталог>"])
        }
        try SettingsRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(("Ошибка отрисовки: \(error.localizedDescription)\n").utf8))
        exit(1)
    }
}
#endif

let instanceLock: SingleInstance
do {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
    instanceLock = try SingleInstance(url: support.appendingPathComponent("LayoutPilot/instance.lock"))
    // Older installed builds do not yet hold the file lock.
    if NSRunningApplication.runningApplications(withBundleIdentifier: "dev.layoutpilot.mac").contains(where: {
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }) { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EWOULDBLOCK)) }
} catch {
    let message = (error as NSError).code == Int(EWOULDBLOCK) ? "TypeTune уже запущен." :
        "Не удалось получить блокировку запуска TypeTune: \(error.localizedDescription)"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
