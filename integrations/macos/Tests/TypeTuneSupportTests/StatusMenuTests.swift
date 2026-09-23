import AppKit
import Testing
@testable import TypeTune

@MainActor
private final class MenuRecorder {
    var applied: [Settings] = []
    var opened: [String] = []
    var toggled = 0
    var current = Settings()
    var running = true
}

struct StatusMenuTests {
    @MainActor
    private func makeMenu(_ state: StatusMenu.State = StatusMenu.State(flag: "EN")) -> (StatusMenu, MenuRecorder) {
        let recorder = MenuRecorder()
        let environment = StatusMenu.Environment(
            apply: { recorder.applied.append($0) },
            current: { recorder.current },
            isRunning: { recorder.running },
            toggleRunning: { recorder.toggled += 1 },
            showLearnedWords: { recorder.opened.append("learned") },
            showAutoDisabledIn: { recorder.opened.append("autoDisabledIn") },
            showActiveKeyboards: { recorder.opened.append("activeKeyboards") },
            showPermissions: { recorder.opened.append("permissions") },
            showSettings: { recorder.opened.append("settings") },
            quit: { recorder.opened.append("quit") }
        )
        recorder.current = state.settings
        recorder.running = state.running
        let menu = StatusMenu(button: nil, environment: environment)
        menu.render(state)
        return (menu, recorder)
    }

    @MainActor
    private func fire(_ id: String, in menu: StatusMenu) throws {
        let entry = try #require(menu.menu.items.first { $0.identifier?.rawValue == id })
        let target = try #require(entry.target as? NSObject)
        let action = try #require(entry.action)
        _ = target.perform(action, with: entry)
    }

    @MainActor
    private func item(_ id: String, in menu: StatusMenu) throws -> NSMenuItem {
        try #require(menu.menu.items.first { $0.identifier?.rawValue == id })
    }

    @Test @MainActor func menuStructureMatchesContract() throws {
        let (menu, _) = makeMenu()
        let titles = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
        #expect(titles == [
            "EN",
            "—",
            "Автопереключение",
            "Ручное переключение (Double Shift)",
            "—",
            "Переключать только последнее слово",
            "Не переключать слова",
            "Не исправлять после смены раскладки",
            "—",
            "Звук переключения",
            "Показывать флаг раскладки",
            "—",
            "Выученные слова…",
            "Отключить автопереключение в…",
            "Активные раскладки…",
            "—",
            "Разрешения",
            "Автозапуск",
            "Открыть настройки",
            "—",
            "Все выключено",
            "Выйти",
        ])
        let header = try #require(menu.menu.items.first)
        #expect(!header.isEnabled)
    }

    @Test @MainActor func statusItemTitleShowsFlagOrCross() {
        #expect(StatusMenu.statusTitle(flag: "EN", displayLayoutFlag: true, running: true) == "EN")
        #expect(StatusMenu.statusTitle(flag: "RU", displayLayoutFlag: true, running: true) == "RU")
        #expect(StatusMenu.statusTitle(flag: "?", displayLayoutFlag: true, running: true) == "?")
        #expect(StatusMenu.statusTitle(flag: "EN", displayLayoutFlag: true, running: false) == "✕")
        #expect(StatusMenu.statusTitle(flag: "EN", displayLayoutFlag: false, running: true) == "•")

        var state = StatusMenu.State(flag: "EN")
        let (menu, _) = makeMenu(state)
        #expect(menu.menu.items.first?.title == "EN")

        state.running = false
        let (paused, _) = makeMenu(state)
        #expect(paused.menu.items.first?.title == "✕")
    }

    @Test @MainActor func checkmarksReflectStateAndTogglesGoThroughApply() throws {
        var state = StatusMenu.State(flag: "EN")
        state.settings.playSwitchingSound = true
        state.settings.displayLayoutFlag = false
        state.settings.autostart = true
        let (menu, recorder) = makeMenu(state)

        #expect(try item("menu.autoSwitching", in: menu).state == .on)
        #expect(try item("menu.playSwitchingSound", in: menu).state == .on)
        #expect(try item("menu.displayLayoutFlag", in: menu).state == .off)
        #expect(try item("menu.autostart", in: menu).state == .on)
        #expect(try item("menu.allDisabled", in: menu).state == .off)

        state.running = false
        menu.render(state)
        #expect(try item("menu.allDisabled", in: menu).state == .on)
        #expect(try item("menu.allDisabled", in: menu).title == "Включить")

        try fire("menu.autoSwitching", in: menu)
        #expect(recorder.applied.count == 1)
        #expect(recorder.applied.first?.autoSwitching == false)
    }

    @Test @MainActor func mutualExclusionAutoUnchecksPartner() throws {
        let (menu, recorder) = makeMenu()

        recorder.current = Settings().togglingDontSwitchWords(true)
        #expect(recorder.current.dontSwitchWords)
        #expect(!recorder.current.switchOnlyLastWord)

        try fire("menu.switchOnlyLastWord", in: menu)
        let applied = try #require(recorder.applied.first)
        #expect(applied.switchOnlyLastWord)
        #expect(!applied.dontSwitchWords)

        recorder.applied.removeAll()
        recorder.current = Settings()
        try fire("menu.dontSwitchWords", in: menu)
        let second = try #require(recorder.applied.first)
        #expect(second.dontSwitchWords)
        #expect(!second.switchOnlyLastWord)
    }

    @Test @MainActor func openersAndPowerActionsAreWired() throws {
        let (menu, recorder) = makeMenu()
        try fire("menu.learnedWords", in: menu)
        try fire("menu.autoDisabledIn", in: menu)
        try fire("menu.activeKeyboards", in: menu)
        try fire("menu.permissions", in: menu)
        try fire("menu.settings", in: menu)
        try fire("menu.quit", in: menu)
        try fire("menu.allDisabled", in: menu)
        #expect(recorder.opened == ["learned", "autoDisabledIn", "activeKeyboards", "permissions", "settings", "quit"])
        #expect(recorder.toggled == 1)
    }

    @Test func layoutFlagLabelMapsKnownPairOnly() {
        #expect(LayoutFlag.label(native: ("com.apple.keylayout.ABC", "us"), activeKeyboards: ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"]) == "EN")
        #expect(LayoutFlag.label(native: ("com.apple.keylayout.RussianWin", "ru"), activeKeyboards: ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"]) == "RU")
        // Flag follows TIS language even when the source is not in the auto-correction list.
        #expect(LayoutFlag.label(native: ("com.apple.keylayout.Dvorak", "us"), activeKeyboards: ["com.apple.keylayout.ABC"]) == "EN")
        #expect(LayoutFlag.label(native: ("com.apple.keylayout.RussianWin", "ru"), activeKeyboards: []) == "RU")
        #expect(LayoutFlag.label(native: ("com.apple.keylayout.Dvorak", ""), activeKeyboards: ["com.apple.keylayout.ABC"]) == "?")
    }

    @Test func switchSoundMutesWhenPausedSensitiveUnknown() {
        #expect(SwitchSound.shouldPlay(settingEnabled: true, running: true, suspended: false, secure: false, layoutChanged: true))
        #expect(!SwitchSound.shouldPlay(settingEnabled: false, running: true, suspended: false, secure: false, layoutChanged: true))
        #expect(!SwitchSound.shouldPlay(settingEnabled: true, running: false, suspended: false, secure: false, layoutChanged: true))
        #expect(!SwitchSound.shouldPlay(settingEnabled: true, running: true, suspended: true, secure: false, layoutChanged: true))
        #expect(!SwitchSound.shouldPlay(settingEnabled: true, running: true, suspended: false, secure: true, layoutChanged: true))
        #expect(!SwitchSound.shouldPlay(settingEnabled: true, running: true, suspended: false, secure: false, layoutChanged: false))
    }
}
