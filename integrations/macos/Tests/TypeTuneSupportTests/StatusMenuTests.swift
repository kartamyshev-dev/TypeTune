import AppKit
import Combine
import Testing
@testable import TypeTune

struct StatusMenuTests {
    @Test @MainActor func pauseResumeAndExternalUpdates() {
        let running = CurrentValueSubject<Bool, Never>(true)
        let status = CurrentValueSubject<String, Never>("Нужны разрешения")
        let button = NSButton()
        let toggle = NSMenuItem()
        let binding = StatusMenu(button:button,toggle:toggle,
            running:running.eraseToAnyPublisher(),status:status.eraseToAnyPublisher())
        withExtendedLifetime(binding) {
            #expect(toggle.title == "Пауза")
            #expect(button.title == "TT")
            #expect(button.toolTip == "TypeTune — Нужны разрешения")
            running.send(false)
            #expect(toggle.title == "Продолжить")
            #expect(button.title == "TT ⏸")
            #expect(button.toolTip == "TypeTune — На паузе")
            status.send("Коррекция отключена для приложения")
            #expect(button.toolTip == "TypeTune — На паузе")
            running.send(true)
            #expect(toggle.title == "Пауза")
            #expect(button.title == "TT")
            #expect(button.toolTip == "TypeTune — Коррекция отключена для приложения")
            status.send("Работает · RU · режим совместимости")
            #expect(button.toolTip == "TypeTune — Работает · RU · режим совместимости")
        }
    }
}
