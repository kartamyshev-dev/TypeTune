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
            for state in ["ready", "accessibility", "listening", "secure", "recovery", "settings", "buffering", "outstanding", "review-outstanding"] {
                defaults.removePersistentDomain(forName: suite)
                defaults.set(theme, forKey: "theme")
                if state == "settings" { defaults.set(Data("invalid".utf8), forKey: "settings.v1") }
                let store = Store(defaults: defaults, snippetsURL: temporary.appendingPathComponent("\(theme)-\(state).json"))
                let keyboard = KeyboardService(store: store, startAutomatically: false)
                store.trusted = state != "accessibility"
                store.listening = state != "listening"
                store.posting = true
                store.running = state == "ready"
                store.secure = state == "secure"
                store.secureInputOwner = store.secure ? "Тестовое приложение" : nil
                store.serviceStatus = state == "secure" ? .secureInput : state == "settings" ? .settingsUnavailable :
                    state == "accessibility" ? .accessibilityDenied : state == "listening" ? .listeningDenied :
                    state == "recovery" ? .uncertainResult : .ready
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
                if store.settingsStorageAvailable {
                    store.settings.excludedWords = ["пример"]
                    store.settings.excludedApps = ["com.example.editor"]
                    store.settings.appAutomatic = ["com.example.notes": false]
                    store.settings.learnedWords = ["тест"]
                    _ = store.saveSnippet(Snippet(abbreviation: ";адр", text: "Пример адреса"))
                }
                for section in SettingsSection.allCases {
                    let view = SettingsView(store: store, keyboard: keyboard, renderSection: section).defaultAppStorage(defaults)
                    try snapshot(view, size: NSSize(width: 1000, height: 740), theme: theme,
                                 to: directory.appendingPathComponent("\(theme)-\(state)-\(section.rawValue).png"))
                }
                if state == "ready" {
                    let editor = SnippetEditorSheet(store: store, original: Snippet(abbreviation: ";спс", text: "Спасибо! {{курсор}}"))
                        .defaultAppStorage(defaults)
                    try snapshot(editor, size: NSSize(width: 636, height: 620), theme: theme,
                                 to: directory.appendingPathComponent("\(theme)-snippet-editor.png"))
                }
                precondition(!store.tapActive && store.keyEvents == 0, "Отрисовка не должна запускать ввод")
            }
        }
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, theme: String, to url: URL) throws {
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, theme == "dark" ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        hosting.appearance = window.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
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
#endif
