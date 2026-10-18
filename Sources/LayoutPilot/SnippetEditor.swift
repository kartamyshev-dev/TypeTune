import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

/// Posts a SnippetEditPlan to one process as keyboard events (docs/SNIPPETS_PLAN.md, S5):
/// → presses, Backspaces, the text typed as Unicode or pasted with ⌘V, ← presses. Events carry
/// the synthetic tag, so the tap neither tracks nor intercepts them. Posting is not proof of an
/// edit; the caller verifies with Accessibility when the field is readable. Main thread only.
enum SnippetEditor {
    enum Stage { case complete, deletion, insertion }
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let vKey: CGKeyCode = 9

    enum Outcome {
        /// Nothing was posted (no permission, Secure Input, clipboard unavailable).
        case notPosted
        /// Some events were posted, then posting failed: the field state is unknown.
        case partial
        /// Every step was posted. A paste returns the clipboard to give back afterwards.
        case posted(ClipboardSwap.Saved?)
    }

    static func pasteEvents(source: CGEventSource) -> [CGEvent]? {
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else { return nil }
        commandDown.type = .flagsChanged; commandUp.type = .flagsChanged
        let held = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8)
        for event in [commandDown, vDown, vUp] { event.flags = held }
        commandUp.flags = []
        return [commandDown, vDown, vUp, commandUp]
    }

    static func perform(_ plan: SnippetEditPlan, pid: pid_t, stage: Stage = .complete) -> Outcome {
        guard CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(), pid > 0,
              let source = CGEventSource(stateID: .privateState) else { return .notPosted }
        var pasteFrame: [CGEvent] = []
        if plan.insertion == .paste, stage != .deletion {
            guard let events = pasteEvents(source: source) else { return .notPosted }
            pasteFrame = events
        }
        var postedAny = false
        func post(_ event: CGEvent?, flags: CGEventFlags = []) -> Bool {
            guard let event else { return false }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EditorSupport.syntheticEventTag)
            event.postToPid(pid)
            postedAny = true
            return true
        }
        func press(_ key: CGKeyCode, flags: CGEventFlags = []) -> Bool {
            post(CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true), flags: flags) &&
                post(CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false), flags: flags)
        }
        var failed: Outcome { postedAny ? .partial : .notPosted }
        if stage != .insertion {
            for _ in 0..<plan.moveRight { guard press(rightArrow) else { return failed } }
            for _ in 0..<plan.deleteCount { guard press(KeystrokeEditor.backspaceKey) else { return failed } }
        }
        if stage == .deletion { return .posted(nil) }
        var saved: ClipboardSwap.Saved?
        if !plan.insertText.isEmpty {
            switch plan.insertion {
            case .keystrokes:
                for chunk in plan.unicodeChunks() {
                    for down in [true, false] {
                        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return failed }
                        chunk.withUnsafeBufferPointer { buffer in
                            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                        }
                        _ = post(event)
                    }
                }
            case .paste:
                // Never type a line break as Return (DECISIONS п. 28): paste the whole text.
                guard let placed = ClipboardSwap.place(plan.insertText) else { return failed }
                // Chromium needs a complete modifier frame, as in pastePlainNative.
                for event in pasteFrame {
                    guard post(event, flags: event.flags) else { _ = ClipboardSwap.restore(placed); return .partial }
                }
                saved = placed
            }
        }
        for _ in 0..<plan.moveLeft { guard press(leftArrow) else { return .partial } }
        return .posted(saved)
    }

    /// Waits (off the main thread) until no modifier key is physically held. Events are posted
    /// without modifier flags, but some applications read the live state and would take a
    /// Backspace for ⌘⌫ or ⌥⌫ (docs/ESPANSO_RESEARCH.md, п. 1).
    static func waitForModifierRelease(timeout: TimeInterval) -> Bool {
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.010)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }
}

/// Temporarily replaces the clipboard with snippet text and gives every previous type back.
/// Our writes are marked transient and concealed (nspasteboard.org), so clipboard history
/// managers neither record the snippet nor duplicate the restored content. Main thread only.
enum ClipboardSwap {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Applications may read the clipboard after handling ⌘V; restore no earlier than this.
    static let restoreDelay: TimeInterval = 0.3

    struct Saved {
        let items: [[(NSPasteboard.PasteboardType, Data)]]
        /// The change count right after our write: anything else means someone else wrote.
        let changeCount: Int
        let placedAt: TimeInterval
    }

    static func place(_ text: String) -> Saved? {
        let pasteboard = NSPasteboard.general
        let items: [[(NSPasteboard.PasteboardType, Data)]] = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        let before = pasteboard.changeCount
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { _ = write(items, at: pasteboard); return nil }
        item.setData(Data(), forType: transient)
        item.setData(Data(), forType: concealed)
        guard pasteboard.writeObjects([item]) else { _ = write(items, at: pasteboard); return nil }
        // clearContents and writeObjects each advance the count; ours is the latest.
        guard pasteboard.changeCount > before else { return nil }
        return Saved(items: items, changeCount: pasteboard.changeCount, placedAt: ProcessInfo.processInfo.systemUptime)
    }

    /// Gives the previous contents back unless something else wrote to the clipboard since
    /// `place`. Returns false (and changes nothing) in that case.
    static func restore(_ saved: Saved) -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == saved.changeCount else { return false }
        pasteboard.clearContents()
        return write(saved.items, at: pasteboard)
    }

    private static func write(_ items: [[(NSPasteboard.PasteboardType, Data)]], at pasteboard: NSPasteboard) -> Bool {
        let objects = items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            item.setData(Data(), forType: transient)
            return item
        }
        return objects.isEmpty || pasteboard.writeObjects(objects)
    }
}
