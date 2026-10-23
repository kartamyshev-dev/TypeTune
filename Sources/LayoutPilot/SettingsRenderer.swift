#if DEBUG
import AppKit
import LayoutPilotCore
import SwiftUI

/// Offline snapshots: no delegate, service start, input events or UI actions.
enum SettingsRenderer {
    static func render(to directory: URL) throws {
        let suite = "dev.layoutpilot.ui-render"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        for theme in ["light", "dark"] {
            for state in ["ready", "accessibility", "listening", "secure", "recovery", "settings", "buffering", "outstanding", "review-outstanding", "empty", "crowded", "snippets-unavailable"] {
                defaults.removePersistentDomain(forName: suite)
                if state == "settings" { defaults.set(Data("invalid".utf8), forKey: "settings.v1") }
                let snippetsURL = temporary.appendingPathComponent("\(theme)-\(state).json")
                if state == "snippets-unavailable" { try Data("invalid".utf8).write(to: snippetsURL) }
                let store = Store(defaults: defaults, snippetsURL: snippetsURL)
                let keyboard = KeyboardService(store: store, startAutomatically: false)
                store.trusted = state != "accessibility"
                store.listening = state != "listening"
                store.posting = true
                store.running = ["ready", "empty", "crowded", "buffering", "snippets-unavailable"].contains(state)
                store.secure = state == "secure"
                store.secureInputOwner = store.secure ? "Тестовое приложение" : nil
                store.serviceStatus = state == "secure" ? .secureInput : state == "settings" ? .settingsUnavailable :
                    state == "accessibility" ? .accessibilityDenied : state == "listening" ? .listeningDenied :
                    (state == "recovery" || state == "review-outstanding") ? .uncertainResult : .ready
                store.inputSource = "com.apple.keylayout.ABC"
                store.lastStatus = "Исправлена раскладка"
                if state == "recovery" || state == "review-outstanding" {
                    store.running = false
                    store.recoveryRequired = true
                    store.textReviewRequired = true
                    store.uncertainInput = 2
                    store.pendingInput = 4
                    store.bufferedEvents = 4
                }
                if state == "buffering" { store.bufferedEvents = 4 }
                if state == "outstanding" || state == "review-outstanding" {
                    store.running = false
                    store.outstandingInput = 3
                    if state == "outstanding" { store.serviceStatus = .recoveryPending }
                }
                if store.settingsStorageAvailable && state != "empty" {
                    store.settings.excludedWords = ["пример"]
                    store.settings.excludedApps = ["com.example.editor"]
                    store.settings.appAutomatic = ["com.example.notes": false]
                    store.settings.learnedWords = ["тест"]
                    _ = store.saveSnippet(Snippet(abbreviation: ";адр", text: "Пример адреса"))
                }
                if state == "crowded" {
                    store.settings.excludedWords = (1...100).map { "исключение-\($0)" }
                    store.settings.excludedApps = (1...50).map { "com.example.приложение\($0)" }
                    store.settings.appAutomatic = Dictionary(uniqueKeysWithValues: store.settings.excludedApps.map { ($0, false) })
                    store.settings.learnedWords = store.settings.excludedWords
                    for i in 1...20 { _ = store.saveSnippet(Snippet(abbreviation: ";пример\(i)", text: "Пример длинного текста для проверки списка сниппетов \(i)")) }
                }
                for section in SettingsSection.allCases {
                    let view = SettingsView(store: store, keyboard: keyboard, renderSection: section).defaultAppStorage(defaults)
                    try snapshot(view, size: NSSize(width: 820, height: 620), theme: theme,
                                 to: directory.appendingPathComponent("\(theme)-\(state)-\(section.rawValue).png"))
                }
                if state == "ready" {
                    for section in SettingsSection.allCases {
                        let view = SettingsView(store: store, keyboard: keyboard, renderSection: section).defaultAppStorage(defaults)
                        try snapshot(view, size: NSSize(width: 760, height: 560), theme: theme,
                                     to: directory.appendingPathComponent("\(theme)-minimum-\(section.rawValue).png"))
                    }
                    let editor = SnippetEditorSheet(store: store, original: Snippet(abbreviation: ";спс", text: "Спасибо! {{курсор}}"))
                        .defaultAppStorage(defaults)
                    try snapshot(editor, size: NSSize(width: 660, height: 660), theme: theme,
                                 to: directory.appendingPathComponent("\(theme)-snippet-editor.png"))
                }
                if state == "ready" {
                    for (name, snippet) in [
                        ("invalid", Snippet(abbreviation: "", text: "")),
                        ("applications", Snippet(abbreviation: ";тест", text: "Здравствуйте!\n{{курсор}}", applications: ApplicationFilter(mode: .only, applications: ["com.example.editor"])))
                    ] {
                        let editor = SnippetEditorSheet(store: store, original: snippet).defaultAppStorage(defaults)
                        try snapshot(editor, size: NSSize(width: 660, height: 660), theme: theme,
                                     to: directory.appendingPathComponent("\(theme)-snippet-editor-\(name).png"))
                    }
                }
                precondition(!store.tapActive && store.keyEvents == 0, "Отрисовка не должна запускать ввод")
            }
        }
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, theme: String, to url: URL) throws {
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, theme == "dark" ? .dark : .light)
            .environment(\.controlActiveState, .active))
        let window = SettingsRenderWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        hosting.appearance = window.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        precondition(window.frame.maxX < 0 && window.frame.maxY < 0, "Окно отрисовки должно оставаться за экраном")
        window.displayIfNeeded()
        hosting.displayIgnoringOpacity(hosting.bounds)
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "UIRender", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать bitmap"])
        }
        window.appearance!.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "UIRender", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать PNG"])
        }
        try png.write(to: url, options: .atomic)
    }
}

/// AppKit normally constrains titled windows back onto a display.
private final class SettingsRenderWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
#endif
