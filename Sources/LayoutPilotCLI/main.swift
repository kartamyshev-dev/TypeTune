import Foundation
import LayoutPilotCore

struct Evaluation: Codable {
    struct Row: Codable { var count = 0; var passed = 0; var corrections = 0; var falseCorrections = 0; var misses = 0; var originalCompared = 0; var originalMatches = 0 }
    var schemaVersion = 1
    var total = Row()
    var bySplit: [String: Row] = [:]
    var byCategory: [String: Row] = [:]
    var failures: [String] = []
    var notice = "Synthetic offline checks; originalResult null excludes original comparison. No live or Caramba parity claim."
}
func encode<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(2)
}
func evaluate(_ path: String, split: String?) throws -> Evaluation {
    var report = Evaluation(); var seen = Set<String>()
    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
    for (offset, line) in lines.enumerated() {
        let fixture: Fixture
        do { fixture = try JSONDecoder().decode(Fixture.self, from: Data(line.utf8)) }
        catch { throw NSError(domain: "fixture line \(offset + 1): \(error)", code: 1) }
        guard fixture.schemaVersion == 1, !fixture.id.isEmpty, ["train", "holdout"].contains(fixture.split), seen.insert(fixture.id).inserted,
              fixture.events?.allSatisfy({ ["text", "boundary", "backspace", "reset"].contains($0.kind) }) ?? true else {
            throw NSError(domain: "Invalid schema/split/duplicate id on line \(offset + 1)", code: 1)
        }
        if let split, split != fixture.split { continue }
        let engine = Engine(settings: fixture.settings ?? Settings())
        let context = fixture.context ?? InputContext()
        let actual = fixture.events.map { Replay.run($0, engine: engine, context: context, initialText: fixture.initialText ?? "").text } ?? (engine.decide(fixture.input, context: context)?.replacement ?? fixture.input)
        func update(_ row: inout Evaluation.Row) {
            row.count += 1
            if actual == fixture.expected { row.passed += 1 }
            if actual != fixture.input { row.corrections += 1 }
            if fixture.expected == fixture.input && actual != fixture.expected { row.falseCorrections += 1 }
            if fixture.expected != fixture.input && actual != fixture.expected { row.misses += 1 }
            if let original = fixture.originalResult { row.originalCompared += 1; if actual == original { row.originalMatches += 1 } }
        }
        update(&report.total)
        var splitRow = report.bySplit[fixture.split] ?? .init(); update(&splitRow); report.bySplit[fixture.split] = splitRow
        var categoryRow = report.byCategory[fixture.category] ?? .init(); update(&categoryRow); report.byCategory[fixture.category] = categoryRow
        if actual != fixture.expected { report.failures.append(fixture.id) }
    }
    guard report.total.count > 0 else { throw NSError(domain: "No fixtures selected", code: 1) }
    return report
}
func rewrite(_ text: String, engine: Engine = Engine()) -> String {
    var output = "", token = ""
    func flush() {
        guard !token.isEmpty else { return }
        if let decision = engine.completedTokenDecision(token, decide: { engine.decide($0) }) {
            output += decision.replacement + token.dropFirst(decision.original.count)
        } else { output += token }
        token = ""
    }
    for character in text {
        if character.isWhitespace { flush(); output.append(character) } else { token.append(character) }
    }
    flush()
    return output
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = args.first else { fail("Usage: layoutpilot-cli convert TEXT | decide TEXT | replay FILE.json | evaluate FILE.jsonl [--split train|holdout] | rewrite FILE.txt | selftest") }
    switch command {
    case "selftest": exit(runSelfTests() == 0 ? 0 : 1)
    case "convert": guard args.count >= 2 else { fail("Missing text") }; print(Layout.convert(args.dropFirst().joined(separator: " ")))
    case "decide": guard args.count >= 2 else { fail("Missing text") }; try encode(Engine().decide(args.dropFirst().joined(separator: " ")))
    case "replay":
        guard args.count == 2 else { fail("replay requires a JSON array of {kind,text} events") }
        let events = try JSONDecoder().decode([ReplayEvent].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        guard events.allSatisfy({ ["text", "boundary", "backspace", "reset"].contains($0.kind) }) else { fail("Unsupported replay event") }
        try encode(Replay.run(events))
    case "evaluate":
        guard args.count == 2 || (args.count == 4 && args[2] == "--split" && ["train", "holdout"].contains(args[3])) else { fail("evaluate FILE.jsonl [--split train|holdout]") }
        let result = try evaluate(args[1], split: args.count == 4 ? args[3] : nil)
        try encode(result); if !result.failures.isEmpty { exit(1) }
    case "rewrite":
        // Offline evaluation aid: every whitespace-delimited token gets the same
        // completed-token decision as automatic correction; separators are preserved.
        guard args.count == 2 else { fail("rewrite requires a UTF-8 text file") }
        print(rewrite(try String(contentsOfFile: args[1], encoding: .utf8)), terminator: "")
    default: fail("Unknown command: \(command)")
    }
} catch { fail(String(describing: error)) }
