import AppKit

/// Status-item / header label from TIS readback + the user’s active keyboards.
/// Unknown source or unmapped layout is always `?` — never a guessed language.
enum LayoutFlag {
    static let unknown = "?"
    static let hidden = "•"
    static let allDisabled = "✕"

    static func label(native: (String, String), activeKeyboards: [String]) -> String {
        let (id, mapped) = native
        guard !activeKeyboards.isEmpty, activeKeyboards.contains(id) else { return unknown }
        switch mapped {
        case "us": return "EN"
        case "ru": return "RU"
        default: return unknown
        }
    }

    static func statusTitle(flag: String, displayLayoutFlag: Bool, running: Bool) -> String {
        guard running else { return allDisabled }
        return displayLayoutFlag ? flag : hidden
    }
}

/// One-shot feedback on a successful layout switch. Never logs typed text.
enum SwitchSound {
    private static let queue = DispatchQueue(label: "dev.kartamyshev.TypeTune.feedback", qos: .utility)

    /// Hard floor: mute when paused, sensitive/secure, unknown, or the setting is off.
    static func shouldPlay(settingEnabled: Bool, running: Bool, suspended: Bool, secure: Bool, layoutChanged: Bool) -> Bool {
        settingEnabled && running && !suspended && !secure && layoutChanged
    }

    static func play() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let sound = NSSound(named: "Tink") ?? NSSound(named: "Ping") ?? NSSound(named: "Glass")
                sound?.play()
                continuation.resume()
            }
        }
    }

    static func playIfAllowed(settingEnabled: Bool, running: Bool, suspended: Bool, secure: Bool, layoutChanged: Bool) {
        guard shouldPlay(settingEnabled: settingEnabled, running: running, suspended: suspended, secure: secure, layoutChanged: layoutChanged) else { return }
        Task { await play() }
    }
}

/// Polls TIS on the main queue and publishes the flag label only when it changes.
final class LayoutFlagMonitor {
    private var timer: Timer?
    private var last = ""
    private var activeKeyboards: () -> [String] = { [] }
    var onChange: ((String) -> Void)?

    func start(activeKeyboards: @escaping () -> [String]) {
        guard timer == nil else { return }
        self.activeKeyboards = activeKeyboards
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let native = Native.inputSource()
        let label = LayoutFlag.label(native: native, activeKeyboards: activeKeyboards())
        guard label != last else { return }
        last = label
        onChange?(label)
    }
}
