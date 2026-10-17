import Foundation

/// Pure gesture recognizer. Times are monotonic seconds, usually systemUptime.
/// Call advance at nextDeadline. While a modifier is held, pending singles wait;
/// a held/used/modified gesture invalidates pending taps rather than firing late.
public struct ModifierGesture: Sendable {
    /// macOS flagsChanged carries device-side bits as well as the aggregate mask.
    /// Unknown/inconsistent events cannot authorize preserving a replay context.
    public static func isRelease(keyCode: Int, rawFlags: UInt64) -> Bool {
        let side: UInt64, pair: UInt64, aggregate: UInt64
        switch keyCode {
        case 56: (side, pair, aggregate) = (0x2, 0x6, 1 << 17)
        case 60: (side, pair, aggregate) = (0x4, 0x6, 1 << 17)
        case 58: (side, pair, aggregate) = (0x20, 0x60, 1 << 19)
        case 61: (side, pair, aggregate) = (0x40, 0x60, 1 << 19)
        case 55: (side, pair, aggregate) = (0x8, 0x18, 1 << 20)
        case 54: (side, pair, aggregate) = (0x10, 0x18, 1 << 20)
        case 59: (side, pair, aggregate) = (0x1, 0x2001, 1 << 18)
        case 62: (side, pair, aggregate) = (0x2000, 0x2001, 1 << 18)
        default: return false
        }
        guard rawFlags & side == 0 else { return false }
        return rawFlags & aggregate == 0 || rawFlags & pair != 0
    }
    public enum Action: String, Codable, Equatable, Sendable {
        case switchLayout, correctText, toggleAutomatic
    }
    private struct Press: Sendable { var time: TimeInterval; var used: Bool }
    private struct Tap: Sendable { var key: Int; var time: TimeInterval }
    public var singleShift: Bool
    public var optionTap: Bool
    public var bothShiftPause: Bool
    public let doubleInterval: TimeInterval = 0.320
    public let maximumHold: TimeInterval = 0.450
    private var pressed: [Int: Press] = [:]
    private var taps: [Tap] = []
    private var lastTime: TimeInterval?
    private static let shifts: Set<Int> = [56, 60]
    private static let options: Set<Int> = [58, 61]

    public init(singleShift: Bool = true, optionTap: Bool = false, bothShiftPause: Bool = false) {
        self.singleShift = singleShift; self.optionTap = optionTap; self.bothShiftPause = bothShiftPause
    }
    public var nextDeadline: TimeInterval? {
        guard pressed.isEmpty else { return nil }
        return taps.map { $0.time + doubleInterval }.min()
    }
    public mutating func reset() { pressed.removeAll(); taps.removeAll(); lastTime = nil }
    /// Any ordinary keydown, including repeats and navigation keys, cancels gestures.
    public mutating func keyUsed() {
        for key in Array(pressed.keys) { pressed[key]?.used = true }
        taps.removeAll()
    }
    private mutating func accept(_ time: TimeInterval) -> Bool {
        guard time.isFinite, lastTime.map({ time >= $0 }) ?? true else { reset(); return false }
        lastTime = time; return true
    }
    /// hasOtherModifiers means Command/Control or another modifier outside Shift/Option.
    /// Shift+Option overlap is handled internally; deliver both sides' physical events.
    public mutating func modifier(keyCode key: Int, isDown: Bool, time: TimeInterval,
                                  hasOtherModifiers: Bool = false) -> [Action] {
        guard accept(time) else { return [] }
        guard Self.shifts.contains(key) || Self.options.contains(key) else { keyUsed(); return [] }
        if hasOtherModifiers { keyUsed() }
        if isDown {
            guard pressed[key] == nil else { return [] } // Duplicate flagsChanged is not a tap.
            let overlaps = !pressed.isEmpty
            let oppositeShift = Self.shifts.contains(key) && pressed.keys.contains(where: { Self.shifts.contains($0) && $0 != key })
            let cleanShiftChord = oppositeShift && !hasOtherModifiers && pressed.allSatisfy { Self.shifts.contains($0.key) && !$0.value.used }
            if overlaps { keyUsed() }
            pressed[key] = Press(time: time, used: overlaps || hasOtherModifiers)
            if cleanShiftChord && bothShiftPause { return [.toggleAutomatic] }
            return []
        }
        guard let press = pressed.removeValue(forKey: key) else { return [] }
        guard !press.used, !hasOtherModifiers, pressed.isEmpty,
              time <= press.time + maximumHold else { taps.removeAll(); return [] }
        if Self.options.contains(key) {
            taps.removeAll()
            return optionTap ? [.correctText] : []
        }
        if let index = taps.lastIndex(where: { $0.key == key && time <= $0.time + doubleInterval }) {
            taps.remove(at: index)
            return [.correctText]
        }
        taps.append(Tap(key: key, time: time))
        return drain(time)
    }
    public mutating func advance(time: TimeInterval) -> [Action] {
        guard accept(time), pressed.isEmpty else { return [] }
        return drain(time)
    }
    private mutating func drain(_ time: TimeInterval) -> [Action] {
        let expired = taps.filter { time >= $0.time + doubleInterval }
        taps.removeAll { time >= $0.time + doubleInterval }
        return singleShift ? expired.map { _ in .switchLayout } : []
    }
}
