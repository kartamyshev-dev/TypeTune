import Foundation
import Darwin

/// Bounded technical events only. Callers supply constant codes, never text,
/// keycodes, document/clipboard data, text lengths or user-derived labels.
final class InputDiagnostics {
    static let shared = InputDiagnostics()
    let enabled = true
    private static let capacity = 1000
    private static let counterNames: Set<String> = ["pending", "outstanding", "uncertainDeliveries"]
    private static let inputKeyLabels: Set<String> = ["space", "shift", "option", "down", "keyCode", "keycode",
        "rawFlags", "characters", "character", "unicodeScalar"]
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "dev.layoutpilot.diagnostics", qos: .utility)
    private let directory: URL?
    private let session = UUID().uuidString
    private var rows: [Row] = []
    private var nextRow = 0
    private var pendingFault: Report?
    private var writingFault = false

    private struct Row: Encodable {
        let phase: String
        let revision: Int
        let uptime: TimeInterval
        let checks: [String: Bool]
        let counts: [String: Int]
        let reason: String?
        let elapsedMilliseconds: Double?
    }
    private struct Report: Encodable {
        let schemaVersion = 2
        let notice = "Last 1000 technical events only; no text, keycodes, document or clipboard data."
        let session: String
        let createdAt: Date
        let reason: String?
        let records: [Row]
    }

    // The explicit directory is used by the isolated probe; no global defaults change.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("LayoutPilot/Diagnostics", isDirectory: true)
    }

    private static func technicalCode(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 96 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    func record(_ phase: String, revision: Int, checks: [String: Bool] = [:], elapsed: TimeInterval? = nil,
                counts: [String: Int] = [:], reason: String? = nil) {
        guard Self.technicalCode(phase), reason.map(Self.technicalCode) ?? true else { return }
        let milliseconds = elapsed.flatMap { $0.isFinite && $0 >= 0 && ($0 * 1000).isFinite ? $0 * 1000 : nil }
        let row = Row(phase: phase, revision: revision, uptime: ProcessInfo.processInfo.systemUptime,
            checks: checks.filter { Self.technicalCode($0.key) && !Self.inputKeyLabels.contains($0.key) },
            counts: counts.filter { Self.counterNames.contains($0.key) && $0.value >= 0 },
            reason: reason, elapsedMilliseconds: milliseconds)
        lock.lock(); defer { lock.unlock() }
        if rows.count < Self.capacity { rows.append(row) }
        else { rows[nextRow] = row; nextRow = (nextRow + 1) % Self.capacity }
    }

    private func report(reason: String?) -> Report {
        // Called under lock. Ring order is chronological, including after wrapping.
        let ordered = nextRow == 0 ? rows : Array(rows[nextRow...]) + Array(rows[..<nextRow])
        return Report(session: session, createdAt: Date(), reason: reason, records: ordered)
    }

    func fault(reason: String, revision: Int, checks: [String: Bool] = [:], counts: [String: Int] = [:]) {
        guard Self.technicalCode(reason) else { return }
        record("fault", revision: revision, checks: checks, counts: counts, reason: reason)
        lock.lock()
        pendingFault = report(reason: reason)
        lock.unlock()
        flush()
    }

    /// Periodic calls are free of filesystem work unless a fault is pending.
    func flush() {
        lock.lock()
        guard pendingFault != nil, !writingFault else { lock.unlock(); return }
        writingFault = true
        lock.unlock()
        writer.async { [self] in
            lock.lock(); let pending = pendingFault; pendingFault = nil; lock.unlock()
            // A diagnostics failure must not change keyboard handling or retry forever.
            if let pending { _ = try? write(pending) }
            lock.lock(); writingFault = false; lock.unlock()
            flush()
        }
    }

    /// Captures the current process without restart. Completion always runs on main.
    func exportReport(completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); let snapshot = report(reason: nil); lock.unlock()
        writer.async { [self] in
            // Keep the exported bytes independent of rotation while a save panel is open.
            let result = Result { try Data(contentsOf: write(snapshot)) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func saveReport(_ data: Data, to destination: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        writer.async {
            let result = Result { try Self.writePrivate(data, to: destination) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func writePrivate(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".layoutpilot-report-" + UUID().uuidString + ".tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temporary.path, destination.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch { try? handle.close(); throw error }
    }

    private func write(_ report: Report) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directoryAttributes = try manager.attributesOfItem(atPath: directory.path)
        guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteInvalidFileName) }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let file = directory.appendingPathComponent("stability-\(UUID().uuidString).json")
        do {
            try Self.writePrivate(data, to: file)
            let previous = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
                .filter { $0.lastPathComponent != file.lastPathComponent && $0.lastPathComponent.hasPrefix("stability-") && $0.pathExtension == "json" }
                .compactMap { url -> (URL, Date)? in
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          values.isRegularFile == true else { return nil }
                    return (url, values.contentModificationDate ?? .distantPast)
                }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
            for (old, _) in previous.dropFirst(2) { try manager.removeItem(at: old) }
            return file
        } catch {
            try? manager.removeItem(at: file)
            throw error
        }
    }
}
