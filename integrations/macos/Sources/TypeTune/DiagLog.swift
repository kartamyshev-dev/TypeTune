import Foundation
import Darwin

/// File I/O never runs on the input thread. One drain task owns the files and
/// pending memory is bounded even if the disk stops responding.
final class DiagnosticWriter {
    private let url: URL
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let maxFileBytes: Int
    private let maxPendingRecords: Int
    private let maxPendingBytes: Int
    private var pending: [String] = []
    private var pendingBytes = 0
    private var dropped = 0
    private var scheduled = false
    private var prepared = false
    private let header = Data("# TypeTune diagnostics v2\n".utf8)

    init(url: URL, maxFileBytes: Int = 1_048_576, maxPendingRecords: Int = 256,
         maxPendingBytes: Int = 65_536,
         queue: DispatchQueue = DispatchQueue(label: "dev.kartamyshev.TypeTune.diagnostics", qos: .utility)) {
        self.url = url
        self.maxFileBytes = max(128, maxFileBytes)
        self.maxPendingRecords = max(1, maxPendingRecords)
        self.maxPendingBytes = max(128, maxPendingBytes)
        self.queue = queue
    }

    func write(_ line: String) {
        // Limit before enqueueing; a caller cannot create an arbitrarily large
        // retained record. Newlines cannot forge additional diagnostic records.
        let bounded = String(decoding: line.utf8.prefix(2048), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        lock.lock()
        if pending.count < maxPendingRecords && pendingBytes + bounded.utf8.count <= maxPendingBytes {
            pending.append(bounded)
            pendingBytes += bounded.utf8.count
        } else {
            dropped = min(dropped, Int.max - 1) + 1
        }
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    /// For orderly shutdown and tests only, never for the input callback.
    func flush() { queue.sync {} }

    var queuedRecordCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    private func drain() {
        let formatter = ISO8601DateFormatter()
        while true {
            lock.lock()
            let batch = pending
            let lost = dropped
            pending.removeAll(keepingCapacity: true)
            pendingBytes = 0
            dropped = 0
            if batch.isEmpty && lost == 0 {
                scheduled = false
                lock.unlock()
                return
            }
            lock.unlock()
            do {
                if !prepared { try prepare(); prepared = true }
                var records = batch
                if lost > 0 { records.append("diagnostics dropped=\(lost)") }
                for line in records {
                    let stamp = formatter.string(from: Date()) + " "
                    let budget = maxFileBytes - header.count - stamp.utf8.count - 1
                    var payload = Data(line.utf8.prefix(max(0, budget)))
                    // Preserve valid UTF-8 when a small configured limit cuts a scalar.
                    while String(data: payload, encoding: .utf8) == nil { payload.removeLast() }
                    var data = Data(stamp.utf8); data.append(payload); data.append(10)
                    try append(data)
                }
            } catch {
                // Logging must never block or crash input handling. Retry file
                // preparation on the next accepted batch after a disk failure.
                prepared = false
            }
        }
    }

    private func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: url.path) {
            let file = try openFile(url, flags: O_RDONLY)
            defer { try? file.close() }
            let prefix = try file.read(upToCount: header.count)
            if prefix != header {
                // Old releases logged individual keys. Keep that evidence in a
                // private archive rather than rotating it away on first launch.
                let archive = url.deletingLastPathComponent().appendingPathComponent(
                    "diag-legacy-\(UUID().uuidString).log")
                try fm.moveItem(at: url, to: archive)
            }
        }
    }

    private func append(_ data: Data) throws {
        let fm = FileManager.default
        var file = try openFile(url, flags: O_WRONLY | O_CREAT)
        var size = try file.seekToEnd()
        if size + UInt64(data.count) > UInt64(maxFileBytes) {
            try file.close()
            let previous = url.appendingPathExtension("1")
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: url, to: previous)
            file = try openFile(url, flags: O_WRONLY | O_CREAT)
            size = 0
        }
        defer { try? file.close() }
        if size == 0 { try file.write(contentsOf: header) }
        try file.write(contentsOf: data)
    }

    private func openFile(_ url: URL, flags: Int32) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, flags | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno; Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

enum DiagLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TypeTune/diag.log")
    private static let writer = DiagnosticWriter(url: url)
    static func write(_ line: String) { writer.write(line) }
    static func flush() { writer.flush() }
}
