import Foundation

/// Only the production file lock in a temporary directory; no Store, AppKit or input tap.
@main private struct SingleInstanceProbe {
    static func main() throws {
        if CommandLine.arguments.count == 2 {
            do {
                let lock = try SingleInstance(url: URL(fileURLWithPath: CommandLine.arguments[1]))
                withExtendedLifetime(lock) {}
            } catch { exit(1) }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        var checks: [String: Bool] = [:]
        func child() throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [url.path]
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        var first: SingleInstance? = try SingleInstance(url: url)
        checks["first_acquires"] = first != nil
        checks["second_process_refused"] = try child() == 1
        withExtendedLifetime(first) {}
        first = nil
        checks["released_lock_reacquired_by_process"] = try child() == 0
        try FileManager.default.removeItem(at: url)
        let original = directory.appendingPathComponent("original")
        try Data("protected".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: original)
        checks["symlink_refused_original_unchanged"] = try child() == 1 && Data(contentsOf: original) == Data("protected".utf8)
        let passed = checks.values.allSatisfy { $0 }
        let report: [String: Any] = ["checks": checks, "passed": passed, "nativeEventsPosted": false,
                                    "standardDefaultsUsed": false, "nativeAcceptance": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if !passed { exit(1) }
    }
}
