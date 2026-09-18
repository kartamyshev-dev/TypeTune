import AppKit
import Combine

// UI state comes from the same controller as Preferences, including changes
// made while the menu is closed. Publishers are delivered on the main thread.
final class StatusMenu {
    private var subscription: AnyCancellable?

    init(button: NSButton, toggle: NSMenuItem,
         running: AnyPublisher<Bool, Never>, status: AnyPublisher<String, Never>) {
        subscription = running.combineLatest(status).sink { enabled, message in
            toggle.title = enabled ? "Пауза" : "Продолжить"
            button.title = enabled ? "TT" : "TT ⏸"
            let description = enabled ? message : "На паузе"
            button.toolTip = "TypeTune — \(description)"
            button.setAccessibilityLabel("TypeTune — \(description)")
        }
    }
}
