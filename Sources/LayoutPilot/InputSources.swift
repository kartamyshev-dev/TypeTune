import AppKit
import Carbon
import LayoutPilotCore

enum InputSources {
    static let englishIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
    static let russianIDs = ["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian-PC"]
    static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    static var current: TISInputSource? { TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() }
    static var identifier: String { current.flatMap { property($0, kTISPropertyInputSourceID) } ?? "Неизвестно" }
    static var language: Language? {
        guard let current else { return nil }
        let id = property(current, kTISPropertyInputSourceID) ?? ""
        if russianIDs.contains(id) { return .russian }
        if englishIDs.contains(id) { return .english }
        return nil
    }
    /// AppKit may still use its previous layout immediately after another process
    /// selects a source. Bind physical-key translation to the verified TIS source.
    static func insertionText(for event: CGEvent, sourceID: String) -> String? {
        guard let source = current, property(source, kTISPropertyInputSourceID) == sourceID,
              let text = insertionText(for: event, source: source), identifier == sourceID else { return nil }
        return text
    }
    static func insertionText(for event: CGEvent, source: TISInputSource) -> String? {
        guard property(source, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String,
              let sourceID = property(source, kTISPropertyInputSourceID),
              let enabledPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
              CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabledPointer).takeUnretainedValue()),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let keyCode = CGKeyCode(exactly: event.getIntegerValueField(.keyboardEventKeycode)) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
        return insertionText(keyCode: keyCode, flags: event.flags, sourceID: sourceID,
            layoutData: data, keyboardType: UInt32(LMGetKbdType()))
    }
    static func insertionText(keyCode: CGKeyCode, flags: CGEventFlags, sourceID: String,
                              layoutData: CFData?, keyboardType: UInt32) -> String? {
        guard englishIDs.contains(sourceID) || russianIDs.contains(sourceID),
              keyCode < 128,
              flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let layoutData, CFDataGetLength(layoutData) >= MemoryLayout<UCKeyboardLayout>.size,
              let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlphaShift) { modifiers |= UInt32(alphaLock) }
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 16)
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers >> 8,
            keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
            characters.count, &length, &characters)
        guard status == noErr, deadKeyState == 0, (1...characters.count).contains(length) else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        guard TextEdit.insertionPrediction(text: "", selection: NSRange(location: 0, length: 0),
            characters: text, keyCode: Int(keyCode)) != nil else { return nil }
        return text
    }
    static func select(_ language: Language) -> Bool {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return false }
        let verifiedIDs = language == .russian ? russianIDs : englishIDs
        if Self.language == language { return true }
        let source = list.first { source in
            guard property(source, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String else { return false }
            return verifiedIDs.contains(property(source, kTISPropertyInputSourceID) ?? "")
        }
        guard let source else { return false }
        return selectVerified(source)
    }
    /// Restore the exact enabled layout saved before a correction, regardless of text language.
    static func restore(identifier: String) -> Bool {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first(where: {
                  property($0, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String &&
                  property($0, kTISPropertyInputSourceID) == identifier
              }) else { return false }
        return selectVerified(source)
    }
    private static func selectVerified(_ source: TISInputSource) -> Bool {
        guard let expectedID = property(source, kTISPropertyInputSourceID) else { return false }
        if identifier == expectedID { return true }
        guard TISSelectInputSource(source) == noErr else { return false }
        return identifier == expectedID
    }
    static func isAvailable(_ language: Language) -> Bool {
        if Self.language == language { return true }
        let ids = language == .russian ? russianIDs : englishIDs
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return false }
        return list.contains { ids.contains(property($0, kTISPropertyInputSourceID) ?? "") }
    }
    static func toggle() -> Bool {
        guard let language else { return false }
        return select(language == .english ? .russian : .english)
    }
}
