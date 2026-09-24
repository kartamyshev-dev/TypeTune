import AppKit

/// Status-item / header label from TIS readback + the user’s active keyboards.
/// Unknown source or unmapped layout is always `?` — never a guessed language.
enum LayoutFlag {
    static let unknown = "?"
    static let hidden = "•"
    static let allDisabled = "✕"

    /// `activeKeyboards` filters auto-correction; the flag always reflects a
    /// known us/ru layout so the menu bar is never blank after TIS readback.
    /// Returns ISO country codes (`us` / `ru`) so the UI can draw real flags.
    static func label(native: (String, String), activeKeyboards: [String]) -> String {
        let (_, mapped) = native
        switch mapped {
        case "us": return "us"
        case "ru": return "ru"
        default:
            let id = native.0
            if id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US" { return "us" }
            if id == "com.apple.keylayout.RussianWin" || id == "com.apple.keylayout.Russian" { return "ru" }
            return unknown
        }
    }

    static func statusTitle(flag: String, displayLayoutFlag: Bool, running: Bool) -> String {
        guard running else { return allDisabled }
        guard displayLayoutFlag else { return hidden }
        switch flag {
        case "us": return "🇺🇸"
        case "ru": return "🇷🇺"
        default: return flag
        }
    }
}

/// Drawn national flags for the status item (no third-party assets).
enum FlagBadge {
    /// Menu-bar badge with side padding so it does not collide with neighbours.
    static func image(for flag: String) -> NSImage? {
        // Transparent gutters mimic standard status-item spacing.
        let padX: CGFloat = 10
        let padY: CGFloat = 1
        let inner = NSSize(width: 18, height: 12)
        let canvas = NSSize(width: inner.width + padX * 2, height: inner.height + padY * 2)
        let stripe: NSImage?
        switch flag {
        case "us": stripe = drawUS(size: inner)
        case "ru": stripe = drawRU(size: inner)
        default: return nil
        }
        guard let stripe else { return nil }
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        stripe.draw(in: NSRect(x: padX, y: padY, width: inner.width, height: inner.height))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Larger icon for the disabled menu header.
    static func menuImage(for flag: String) -> NSImage? {
        guard let base = image(for: flag) else { return nil }
        let size = NSSize(width: 28, height: 18)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
    }

    private static func drawUS(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)
        // 13 stripes, simplified as 7 red bands on white.
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.69, green: 0.13, blue: 0.20, alpha: 1).setFill()
        let stripe = size.height / 13.0
        for i in stride(from: 0, to: 13, by: 2) {
            NSRect(x: 0, y: CGFloat(i) * stripe, width: size.width, height: stripe).fill()
        }
        // Canton
        let canton = NSRect(x: 0, y: size.height / 2.0, width: size.width * 0.42, height: size.height / 2.0)
        NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.42, alpha: 1).setFill()
        canton.fill()
        NSColor.white.setFill()
        let star = size.height * 0.08
        for row in 0..<3 {
            for col in 0..<4 {
                let x = canton.minX + canton.width * (CGFloat(col) + 0.5) / 4.0
                let y = canton.minY + canton.height * (CGFloat(row) + 0.5) / 3.0
                NSBezierPath(ovalIn: NSRect(x: x - star / 2, y: y - star / 2, width: star, height: star)).fill()
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawRU(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let h = size.height / 3.0
        // White (top), blue, red — Russian tricolor.
        NSColor.white.setFill()
        NSRect(x: 0, y: h * 2, width: size.width, height: h).fill()
        NSColor(calibratedRed: 0.0, green: 0.2, blue: 0.6, alpha: 1).setFill()
        NSRect(x: 0, y: h, width: size.width, height: h).fill()
        NSColor(calibratedRed: 0.7, green: 0.1, blue: 0.15, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: h).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
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