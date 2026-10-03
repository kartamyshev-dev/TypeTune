import Foundation

/// Result time stays on the source event clock; elapsed duration is added, not mixed.
public enum EditAcknowledgement {
    public static func resultTime(sourceMs: UInt64, elapsedMs: UInt64) -> UInt64 {
        sourceMs &+ elapsedMs
    }
    public static func visibleOutcome(native: String, engine: String) -> String {
        guard engine == "ok" else { return "reset" }
        return native
    }
}
