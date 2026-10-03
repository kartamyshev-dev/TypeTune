import Foundation

/// A loss of field identity is itself a boundary. Continuous unreadable fields
/// still support history, but an earlier known field cannot authorize a suffix.
public struct FocusHistory {
    private var process = ""
    private var knownField: String?
    public init() {}
    public mutating func reset() { process = ""; knownField = nil }
    public mutating func observe(_ identity: String) -> Bool {
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        let nextProcess = parts.first.map(String.init) ?? ""
        let field = parts.count > 1 ? String(parts[1]) : "0"
        let known = field != "0" && !field.isEmpty
        let nextField: String? = known ? field : nil
        let moved = process != nextProcess || knownField != nextField
        process = nextProcess
        knownField = nextField
        return moved
    }
}
