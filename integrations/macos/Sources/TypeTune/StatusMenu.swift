import AppKit

/// Menu and status-item titles follow the product menu contract:
/// flag header, grouped toggles, list openers, then permissions / power.
/// Every toggle goes through `environment.apply` (Controller generation ACK).
final class StatusMenu: NSObject {
    struct State: Equatable {
        var settings = Settings()
        var flag = LayoutFlag.unknown
        var running = true
    }

    struct Environment {
        var apply: (Settings) -> Void
        var current: () -> Settings
        var isRunning: () -> Bool
        var toggleRunning: () -> Void
        var showLearnedWords: () -> Void
        var showAutoDisabledIn: () -> Void
        var showActiveKeyboards: () -> Void
        var showPermissions: () -> Void
        var showSettings: () -> Void
        var quit: () -> Void
    }

    private let button: NSButton?
    private let environment: Environment
    private var state = State()
    private(set) var menu = NSMenu()

    private var header: NSMenuItem!
    private var autoSwitching: NSMenuItem!
    private var manualSwitching: NSMenuItem!
    private var switchOnlyLastWord: NSMenuItem!
    private var dontSwitchWords: NSMenuItem!
    private var dontCorrectAfterLayoutChange: NSMenuItem!
    private var playSwitchingSound: NSMenuItem!
    private var displayLayoutFlag: NSMenuItem!
    private var learnedWords: NSMenuItem!
    private var autoDisabledIn: NSMenuItem!
    private var activeKeyboards: NSMenuItem!
    private var permissions: NSMenuItem!
    private var autostart: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var allDisabled: NSMenuItem!
    private var quitItem: NSMenuItem!

    init(button: NSButton?, environment: Environment) {
        self.button = button
        self.environment = environment
        super.init()
        build()
        render(State())
    }

    static func statusTitle(flag: String, displayLayoutFlag: Bool, running: Bool) -> String {
        LayoutFlag.statusTitle(flag: flag, displayLayoutFlag: displayLayoutFlag, running: running)
    }

    func render(_ state: State) {
        self.state = state
        let settings = state.settings
        let title = Self.statusTitle(flag: state.flag, displayLayoutFlag: settings.displayLayoutFlag, running: state.running)
        button?.title = title
        button?.toolTip = "TypeTune — \(title)"
        button?.setAccessibilityLabel("TypeTune — \(title)")
        header.title = state.running ? state.flag : LayoutFlag.allDisabled
        autoSwitching.state = settings.autoSwitching ? .on : .off
        manualSwitching.state = settings.manualSwitching ? .on : .off
        switchOnlyLastWord.state = settings.switchOnlyLastWord ? .on : .off
        dontSwitchWords.state = settings.dontSwitchWords ? .on : .off
        dontCorrectAfterLayoutChange.state = settings.dontCorrectAfterLayoutChange ? .on : .off
        playSwitchingSound.state = settings.playSwitchingSound ? .on : .off
        displayLayoutFlag.state = settings.displayLayoutFlag ? .on : .off
        autostart.state = settings.autostart ? .on : .off
        allDisabled.state = state.running ? .off : .on
        allDisabled.title = state.running ? "Все выключено" : "Включить"
    }

    private func item(_ title: String, id: String, action: Selector?) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.identifier = NSUserInterfaceItemIdentifier(id)
        return entry
    }

    private func build() {
        header = item(LayoutFlag.unknown, id: "menu.flagHeader", action: nil)
        header.isEnabled = false
        autoSwitching = item("Автопереключение", id: "menu.autoSwitching", action: #selector(toggleAutoSwitching))
        manualSwitching = item("Ручное переключение (Double Shift)", id: "menu.manualSwitching", action: #selector(toggleManualSwitching))
        switchOnlyLastWord = item("Переключать только последнее слово", id: "menu.switchOnlyLastWord", action: #selector(toggleSwitchOnlyLastWord))
        dontSwitchWords = item("Не переключать слова", id: "menu.dontSwitchWords", action: #selector(toggleDontSwitchWords))
        dontCorrectAfterLayoutChange = item("Не исправлять после смены раскладки", id: "menu.dontCorrectAfterLayoutChange", action: #selector(toggleDontCorrectAfterLayoutChange))
        playSwitchingSound = item("Звук переключения", id: "menu.playSwitchingSound", action: #selector(togglePlaySwitchingSound))
        displayLayoutFlag = item("Показывать флаг раскладки", id: "menu.displayLayoutFlag", action: #selector(toggleDisplayLayoutFlag))
        learnedWords = item("Выученные слова…", id: "menu.learnedWords", action: #selector(openLearnedWords))
        autoDisabledIn = item("Отключить автопереключение в…", id: "menu.autoDisabledIn", action: #selector(openAutoDisabledIn))
        activeKeyboards = item("Активные раскладки…", id: "menu.activeKeyboards", action: #selector(openActiveKeyboards))
        permissions = item("Разрешения", id: "menu.permissions", action: #selector(openPermissions))
        autostart = item("Автозапуск", id: "menu.autostart", action: #selector(toggleAutostart))
        settingsItem = item("Открыть настройки", id: "menu.settings", action: #selector(openSettings))
        allDisabled = item("Все выключено", id: "menu.allDisabled", action: #selector(toggleRunning))
        quitItem = item("Выйти", id: "menu.quit", action: #selector(quit))

        menu.autoenablesItems = false
        menu.addItem(header)
        menu.addItem(.separator())
        for entry in [autoSwitching, manualSwitching] as [NSMenuItem] { menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [switchOnlyLastWord, dontSwitchWords, dontCorrectAfterLayoutChange] as [NSMenuItem] { menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [playSwitchingSound, displayLayoutFlag] as [NSMenuItem] { menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [learnedWords, autoDisabledIn, activeKeyboards] as [NSMenuItem] { menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [permissions, autostart, settingsItem] as [NSMenuItem] { menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [allDisabled, quitItem] as [NSMenuItem] { menu.addItem(entry) }
    }

    private func applyCurrent(_ mutate: (inout Settings) -> Void) {
        var next = environment.current()
        mutate(&next)
        environment.apply(next)
    }

    @objc private func toggleAutoSwitching() { applyCurrent { $0.autoSwitching.toggle() } }
    @objc private func toggleManualSwitching() { applyCurrent { $0.manualSwitching.toggle() } }
    @objc private func toggleSwitchOnlyLastWord() {
        let on = !environment.current().switchOnlyLastWord
        environment.apply(environment.current().togglingSwitchOnlyLastWord(on))
    }
    @objc private func toggleDontSwitchWords() {
        let on = !environment.current().dontSwitchWords
        environment.apply(environment.current().togglingDontSwitchWords(on))
    }
    @objc private func toggleDontCorrectAfterLayoutChange() { applyCurrent { $0.dontCorrectAfterLayoutChange.toggle() } }
    @objc private func togglePlaySwitchingSound() { applyCurrent { $0.playSwitchingSound.toggle() } }
    @objc private func toggleDisplayLayoutFlag() { applyCurrent { $0.displayLayoutFlag.toggle() } }
    @objc private func toggleAutostart() { applyCurrent { $0.autostart.toggle() } }
    @objc private func openLearnedWords() { environment.showLearnedWords() }
    @objc private func openAutoDisabledIn() { environment.showAutoDisabledIn() }
    @objc private func openActiveKeyboards() { environment.showActiveKeyboards() }
    @objc private func openPermissions() { environment.showPermissions() }
    @objc private func openSettings() { environment.showSettings() }
    @objc private func toggleRunning() { environment.toggleRunning() }
    @objc private func quit() { environment.quit() }
}
