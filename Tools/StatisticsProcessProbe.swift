import AppKit
import Foundation
import LayoutPilotCore

@main private struct StatisticsProcessProbe {
    private static func settingsBytes() throws -> Data {
        var settings = Settings(); settings.sound = false
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(settings)
    }
    private static func emit(_ result: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if !args.isEmpty {
            guard args.count == 3, args[0] == "--child",
                  ["seed","restart","increment","final"].contains(args[1]),
                  args[2].hasPrefix("dev.layoutpilot.statistics-process."),
                  UUID(uuidString: String(args[2].dropFirst("dev.layoutpilot.statistics-process.".count))) != nil,
                  let defaults = UserDefaults(suiteName: args[2]) else { exit(2) }
            let phase = args[1]
            if phase == "seed" {
                guard (defaults.persistentDomain(forName: args[2]) ?? [:]).isEmpty else { exit(3) }
                defaults.set(31, forKey: "corrected")
                defaults.set(try settingsBytes(), forKey: "settings.v1")
            }
            let store = Store(defaults: defaults)
            if phase == "seed" {
                store.recordCorrection(category: .automatic)
                store.recordCorrection(category: .manual)
                store.recordSingleShift()
            } else if phase == "increment" {
                store.recordCorrection(category: .typo)
                store.recordCorrection(category: .yo)
                store.recordSingleShift()
            }
            let later = phase == "increment" || phase == "final"
            let expected: [UsageCategory:Int64] = [.automatic:1,.manual:1,.typo:later ? 1:0,
                .yo:later ? 1:0,.singleShift:later ? 2:1,.sound:0]
            let countMatch = expected.allSatisfy { store.statistics[$0.key] == $0.value }
            let totalMatch = store.corrected == (later ? 35:33) && defaults.integer(forKey: "corrected") == store.corrected
            let timeMatch = store.statistics.estimatedSeconds == (later ? 34:19)
            let historyMatch = store.statistics.unclassifiedHistorical == 31
            let settingsMatch = defaults.data(forKey: "settings.v1") == (try settingsBytes())
            let flushed = defaults.synchronize() // Probe-only process boundary, never product code.
            try emit(["phase":phase,"pid":ProcessInfo.processInfo.processIdentifier,"countsMatch":countMatch,
                "totalsMatch":totalMatch,"timeMatch":timeMatch,"historyMatch":historyMatch,
                "ordinarySettingsUnchanged":settingsMatch,"synchronized":flushed,
                "passed":countMatch && totalMatch && timeMatch && historyMatch && settingsMatch && flushed])
            return
        }
        let suite = "dev.layoutpilot.statistics-process.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite); defaults.synchronize() }
        guard (defaults.persistentDomain(forName: suite) ?? [:]).isEmpty else { exit(3) }
        var trials: [[String:Any]] = [], pids = Set<Int32>(), passed = true
        for phase in ["seed","restart","increment","final"] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["--child",phase,suite]
            let output = Pipe(); process.standardOutput = output
            // No child diagnostic text is forwarded: only fixed count/boolean JSON.
            let errors = Pipe(); process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            var row = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] ?? [:]
            row["exit"] = process.terminationStatus
            let ownPID = process.processIdentifier
            let distinct = ownPID != ProcessInfo.processInfo.processIdentifier && pids.insert(ownPID).inserted
            row["distinctChildProcess"] = distinct
            let ok = process.terminationReason == .exit && process.terminationStatus == 0 &&
                row["passed"] as? Bool == true && distinct
            trials.append(row); passed = passed && ok
            if !ok { break }
        }
        defaults.removePersistentDomain(forName: suite); defaults.synchronize()
        let clean = (defaults.persistentDomain(forName: suite) ?? [:]).isEmpty
        let allPassed = passed && trials.count == 4 && clean
        try emit(["kind":"actual-Store-cross-process-persistence","trials":trials,"passed":allPassed,
            "children":trials.count,"ownSuiteCleaned":clean,"standardDefaultsUsed":false,"guiLaunched":false,
            "nativeEventsPosted":false,"soundPlayed":false,"originalAccessed":false,"nativeAcceptance":false])
        if !allPassed { exit(1) }
    }
}
