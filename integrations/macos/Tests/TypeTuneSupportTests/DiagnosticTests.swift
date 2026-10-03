import Foundation
import Testing
@testable import TypeTune

struct DiagnosticTests {
    @Test func preservesLegacyAndRestrictsPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("diag.log")
        let legacy = Data(repeating: 65, count: 4096)
        try legacy.write(to: url)
        let writer = DiagnosticWriter(url: url, maxFileBytes: 256)
        writer.write("observer started"); writer.flush()
        let archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("diag-legacy-") }
        #expect(archives.count == 1)
        #expect(try Data(contentsOf: archives[0]) == legacy)
        for file in [url, archives[0]] {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        // A second writer recognizes current-format logs and does not archive them.
        let next = DiagnosticWriter(url: url, maxFileBytes: 256)
        next.write("restart"); next.flush()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }

    @Test func boundsQueueAndRotatesOnlyTwoFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diag.log")
        let queue = DispatchQueue(label: UUID().uuidString)
        let writer = DiagnosticWriter(url: url, maxFileBytes: 256, maxPendingRecords: 3, queue: queue)
        queue.suspend()
        for index in 0..<1000 { writer.write("result=\(index)") }
        #expect(writer.queuedRecordCount == 3)
        queue.resume(); writer.flush()
        #expect(try String(contentsOf: url, encoding: .utf8).contains("dropped=997"))
        for _ in 0..<20 {
            writer.write(String(repeating: "я", count: 500)); writer.flush()
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(Set(files.map(\.lastPathComponent)) == ["diag.log", "diag.log.1"])
        for file in files {
            #expect(try Data(contentsOf: file).count <= 256)
            #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("# TypeTune diagnostics v2\n"))
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test func refusesLogSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("untouched")
        try Data("original".utf8).write(to: target)
        let url = directory.appendingPathComponent("diag.log")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let writer = DiagnosticWriter(url: url)
        writer.write("must not overwrite"); writer.flush()
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
    }
}
