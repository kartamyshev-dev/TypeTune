import Foundation

/// Exercises production diagnostics in temporary directories. No AppKit, AX or input events.
@main private struct InputDiagnosticsProbe {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("layoutpilot-diagnostics-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let directory = root.appendingPathComponent("Diagnostics")
        let diagnostics = InputDiagnostics(directory: directory)
        var checks: [String: Bool] = [:]
        func export(_ instance: InputDiagnostics) throws -> Data {
            var result: Result<Data, Error>?
            instance.exportReport { value in
                checks["completion_on_main"] = Thread.isMainThread
                result = value
            }
            let deadline = Date().addingTimeInterval(10)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard let result else { throw CocoaError(.coderReadCorrupt) }
            return try result.get()
        }
        func read(_ url: URL) throws -> [String: Any] {
            try read(Data(contentsOf: url))
        }
        func read(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        func save(_ data: Data, to destination: URL) throws {
            var result: Result<Void, Error>?
            diagnostics.saveReport(data, to: destination) { value in
                checks["save_completion_on_main"] = Thread.isMainThread
                result = value
            }
            let deadline = Date().addingTimeInterval(10)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard let result else { throw CocoaError(.coderReadCorrupt) }
            try result.get()
        }
        func managed() throws -> [URL] {
            try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("stability-") && $0.pathExtension == "json" }
        }
        func permissions(_ url: URL) throws -> Int {
            (try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue & 0o777
        }
        checks["always_enabled"] = diagnostics.enabled
        diagnostics.record("normal", revision: -1)
        diagnostics.flush()
        checks["ordinary_flush_creates_no_files"] = !manager.fileExists(atPath: directory.path)
        for number in 0..<1105 { diagnostics.record("capture", revision: number, checks: ["snapshot": true], counts: ["pending": number % 3]) }
        diagnostics.record("late-failure", revision: 1105, checks: ["snapshot": false], elapsed: 0.031,
            counts: ["pending": 0], reason: "snapshot-unavailable")
        let first = try export(diagnostics)
        let firstFile = try managed().first!
        let report = try read(first)
        let records = report["records"] as! [[String: Any]]
        checks["ring_keeps_last_1000"] = records.count == 1000 && records.first?["revision"] as? Int == 106
        checks["late_event_retained"] = records.last?["phase"] as? String == "late-failure" && records.last?["revision"] as? Int == 1105
        checks["ring_chronological"] = records.compactMap { $0["revision"] as? Int } == Array(106...1105)
        checks["schema_version_2"] = report["schemaVersion"] as? Int == 2
        let topKeys: Set<String> = ["schemaVersion", "notice", "session", "createdAt", "reason", "records"]
        let rowKeys: Set<String> = ["phase", "revision", "uptime", "checks", "counts", "reason", "elapsedMilliseconds"]
        checks["schema_has_no_raw_payload_fields"] = Set(report.keys).isSubset(of: topKeys) && records.allSatisfy { Set($0.keys).isSubset(of: rowKeys) }
        checks["directory_private"] = try permissions(directory) == 0o700
        checks["file_private"] = try permissions(firstFile) == 0o600
        let legacy = directory.appendingPathComponent(UUID().uuidString + ".json")
        let legacyData = Data("existing-diagnostic-evidence".utf8)
        try legacyData.write(to: legacy)
        let unrelated = directory.appendingPathComponent("stability-not-a-report.txt")
        try legacyData.write(to: unrelated)
        for number in 0..<6 {
            diagnostics.fault(reason: "snapshot-failure", revision: number, checks: ["snapshot": false], counts: ["pending": 0])
            _ = try export(diagnostics)
        }
        let retained = try managed()
        checks["rotation_keeps_three_managed_files"] = retained.count == 3
        checks["rotation_files_private"] = try retained.allSatisfy { try permissions($0) == 0o600 }
        checks["legacy_evidence_preserved"] = try Data(contentsOf: legacy) == legacyData
        checks["unrelated_file_preserved"] = try Data(contentsOf: unrelated) == legacyData
        checks["automatic_fault_saved"] = try retained.contains { try read($0)["reason"] as? String == "snapshot-failure" }
        checks["old_managed_export_rotated"] = !manager.fileExists(atPath: firstFile.path)
        let destination = root.appendingPathComponent("user-export.json")
        try legacyData.write(to: destination)
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        try save(first, to: destination)
        checks["held_export_survives_rotation"] = try Data(contentsOf: destination) == first
        checks["replacement_export_is_private"] = try permissions(destination) == 0o600
        let failedDestination = root.appendingPathComponent("existing-directory")
        try manager.createDirectory(at: failedDestination, withIntermediateDirectories: true)
        let protected = failedDestination.appendingPathComponent("original")
        try legacyData.write(to: protected)
        do { try save(first, to: failedDestination); checks["failed_export_reported"] = false }
        catch { checks["failed_export_reported"] = true }
        checks["failed_export_preserves_destination"] = try Data(contentsOf: protected) == legacyData
        checks["export_leaves_no_temporary_files"] = try !manager.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".layoutpilot-report-") }
        diagnostics.record("bad phase with text", revision: 9998)
        diagnostics.record("capture", revision: 9999, elapsed: .infinity, reason: "bad reason with spaces")
        diagnostics.record("finite", revision: 1106,
            checks: ["snapshot": true, "space": true, "shift": true, "option": true, "down": true, "keyCode": true], elapsed: .infinity,
            counts: ["pending": 0, "keycode": 7, "textLength": 12, "clipboardLength": 16, "outstanding": -1])
        let validated = try read(export(diagnostics))["records"] as! [[String: Any]]
        checks["invalid_codes_not_recorded"] = !validated.contains { ($0["revision"] as? Int) == 9998 || ($0["revision"] as? Int) == 9999 }
        checks["nonfinite_timing_omitted"] = validated.last?["phase"] as? String == "finite" && validated.last?["elapsedMilliseconds"] == nil
        checks["only_nonnegative_technical_counters"] = validated.last?["counts"] as? [String: Int] == ["pending": 0]
        checks["physical_key_flags_not_serialized"] = validated.last?["checks"] as? [String: Bool] == ["snapshot": true]
        let concurrent = InputDiagnostics(directory: root.appendingPathComponent("Concurrent"))
        DispatchQueue.concurrentPerform(iterations: 4) { worker in
            for number in 0..<600 { concurrent.record("concurrent", revision: worker * 600 + number) }
        }
        concurrent.fault(reason: "last-concurrent-fault", revision: 2400)
        let concurrentRows = try read(export(concurrent))["records"] as! [[String: Any]]
        checks["concurrent_ring_bounded"] = concurrentRows.count == 1000
        checks["concurrent_late_fault_retained"] = concurrentRows.last?["reason"] as? String == "last-concurrent-fault"
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("preserve".utf8).write(to: blocked)
        let failing = InputDiagnostics(directory: blocked.appendingPathComponent("Diagnostics"))
        failing.fault(reason: "test-write-failure", revision: 1)
        do { _ = try export(failing); checks["write_failure_reported_without_crash"] = false }
        catch { checks["write_failure_reported_without_crash"] = true }
        failing.record("still-running", revision: 2)
        failing.flush()
        checks["write_failure_preserves_blocking_file"] = try Data(contentsOf: blocked) == Data("preserve".utf8)
        let passed = checks.values.allSatisfy { $0 }
        let output: [String: Any] = ["passed": passed, "checks": checks, "nativeEventsPosted": false,
            "standardDefaultsUsed": false, "nativeAcceptance": false, "retainedManagedFiles": retained.count]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if !passed { exit(1) }
    }
}
