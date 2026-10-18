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
    var window: NSWindow?
    var cancellables = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Decode the ~60k-word lexicon and its prefix index off the main thread, so the
        // first keystroke does not pay the one-time load (static lets are initialized once).
        DispatchQueue.global(qos: .utility).async { _ = Lexicon.bundled; _ = PartialLayoutDetector.bundled }
        store.launchAtLogin = SMAppService.mainApp.status == .enabled
        keyboard = KeyboardService(store: store)
        keyboard.onRecoveryNeeded = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateStatusItem),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
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
        keyboard?.stop(); InputDiagnostics.shared.flush()
    }
    func rebuildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let title = NSMenuItem(title: "TypeTune · " + store.serviceStatus.title.lowercased(), action: nil, keyEquivalent: "")
        menu.addItem(title); menu.addItem(.separator())
        let automatic = NSMenuItem(title: "Автоисправления", action: #selector(toggleAutomatic), keyEquivalent: "")
        automatic.target = self; automatic.state = store.settings.paused ? .off : .on
        automatic.isEnabled = store.settingsStorageAvailable; menu.addItem(automatic)
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из TypeTune", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); statusItem.menu = menu
        updateStatusItem()
    }
    @objc func updateStatusItem() {
        let flag = InputSources.language == .russian ? "🇷🇺" : (InputSources.language == .english ? "🇺🇸" : "🌐")
        let suffix = store.recoveryRequired || store.serviceStatus == .tapFailed ? " !" : (store.settings.paused ? " Ⅱ" : "")
        let title = NSMutableAttributedString(string: flag, attributes: [
            .font: NSFont.systemFont(ofSize: 20), .baselineOffset: -2
        ])
        title.append(NSAttributedString(string: suffix, attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = "TypeTune · \(InputSources.identifier)\n\(store.serviceStatus.message)"
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
            result.title = "TypeTune"; result.styleMask = [.titled, .closable, .miniaturizable]
            result.isReleasedWhenClosed = false; result.center(); window = result
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

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
