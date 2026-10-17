import Foundation

public struct Fixture: Codable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var feature: String
    public var split: String
    public var category: String
    public var provenance: String
    public var input: String
    public var expected: String
    public var originalResult: String?
    public var events: [ReplayEvent]?
    public var initialText: String?
    public var context: InputContext?
    public var settings: Settings?
}

public struct ReplayEvent: Codable, Sendable {
    public var kind: String
    public var text: String?
}

public struct ReplayResult: Codable, Sendable {
    public var text: String
    public var reasons: [String]
}

public enum Replay {
    public static func run(_ events: [ReplayEvent], engine: Engine = Engine(), context: InputContext = InputContext(), initialText: String = "") -> ReplayResult {
        var text = initialText, reasons: [String] = []
        for event in events {
            switch event.kind {
            case "text": text += event.text ?? ""
            case "backspace": if !text.isEmpty { text.removeLast() }
            case "boundary":
                if let r = TextEdit.wordBeforeCursor(in: text, cursor: text.utf16.count),
                   let swiftRange = Range(r, in: text),
                   let decision = engine.completedTokenDecision(String(text[swiftRange]), decide: { engine.decide($0, context: context) }),
                   let changed = TextEdit.validatedRange(NSRange(location: r.location, length: decision.original.utf16.count), in: text) {
                    text.replaceSubrange(changed, with: decision.replacement); reasons.append(decision.reason.rawValue)
                }
                text += event.text ?? " "
            case "reset": text = ""
            default: break
            }
        }
        return ReplayResult(text: text, reasons: reasons)
    }
}
