import CoreGraphics

/// Decode the two Shift keys from event-time state. HID keyState describes the
/// time of the callback and can already be released for a queued key-down.
struct ShiftEdges {
    struct Result {var action:String?;var discontinuity=false}
    private var held:Set<CGKeyCode>? = nil
    mutating func reset() {held=nil}
    mutating func observe(code:CGKeyCode?,shift:Bool) -> Result {
        guard shift else {
            let previous=held
            held=[] // An event with the aggregate flag clear is a safe boundary.
            guard let code,let previous else {return Result(discontinuity:previous?.isEmpty == false)}
            if previous==[code] {return Result(action:"up")}
            return Result(discontinuity:!previous.isEmpty)
        }
        guard var previous=held else {
            guard let code else {return Result()}
            // Start a candidate press. If this was actually a release while
            // the other side was held before observation began, the subsequent
            // aggregate/side mismatch invalidates it before a complete tap.
            held=[code];return Result(action:"down")
        }
        guard let code else {
            if previous.isEmpty {held=nil;return Result(discontinuity:true)}
            return Result()
        }
        let down = !previous.contains(code)
        if down {previous.insert(code)} else {previous.remove(code)}
        // Releasing the last tracked side cannot leave aggregate Shift set:
        // at least one edge was missed. Wait for a clear flag to resynchronize.
        guard !previous.isEmpty else {held=nil;return Result(discontinuity:true)}
        held=previous
        return Result(action:down ? "down":"up")
    }
}
