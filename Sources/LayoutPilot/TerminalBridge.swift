import AppKit
import ApplicationServices
import Carbon
import Darwin
import LayoutPilotCore

/// ZLE edits its own pending buffer. Never reads terminal output or posts terminal keys.
final class TerminalBridge {
    private final class Client {
        let file: FileHandle
        var buffer = Data()
        var host = "", nonce = ""
        var pending: Decision?
        var pendingSource = "", previousSource = ""
        var last: Decision?
        var field: AXUIElement?
        init(_ fd: Int32) { file = FileHandle(fileDescriptor: fd, closeOnDealloc: true) }
    }
    private let queue = DispatchQueue(label: "dev.layoutpilot.terminal")
    private var listener: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private let permits: (String) -> Bool
    private let decide: (String, Bool, String) -> Decision?
    private let applied: (Decision, String?, String) -> Void
    init(permits: @escaping (String) -> Bool, decide: @escaping (String, Bool, String) -> Decision?,
         applied: @escaping (Decision, String?, String) -> Void) {
        self.permits = permits; self.decide = decide; self.applied = applied
    }
    deinit { listener?.cancel() }
    func start() {
        guard listener == nil else { return }
        let path = NSHomeDirectory() + "/Library/Application Support/LayoutPilot/terminal.sock"
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return }
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { return }
            guard unlink(path) == 0 else { return }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                path.withCString { _ = strlcpy(destination, $0, 104) }
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let peer = accept(fd, nil, nil)
            guard peer >= 0 else { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(peer, &uid, &gid) == 0, uid == getuid(), self.clients.count < 32 else { close(peer); return }
            var enabled: Int32 = 1
            setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            setsockopt(peer, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let client = Client(peer); self.clients[peer] = client
            client.file.readabilityHandler = { [weak self, weak client] file in
                let data = file.availableData
                self?.queue.async {
                    guard let self, let client, self.clients[peer] === client else { return }
                    guard !data.isEmpty, client.buffer.count + data.count <= 8192 else { self.disconnect(peer); return }
                    client.buffer.append(data)
                    while let end = client.buffer.firstIndex(of: 10) {
                        let row = client.buffer[..<end]; client.buffer.removeSubrange(...end)
                        guard let line = String(data: row, encoding: .utf8) else { self.disconnect(peer); return }
                        self.receive(line, client: client, fd: peer)
                    }
                }
            }
        }
        source.setCancelHandler { close(fd) }
        listener = source; source.resume()
    }
    private func disconnect(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.file.readabilityHandler = nil
        try? client.file.close()
    }
    private func send(_ value: String, to client: Client) {
        send(Data((value + "\n").utf8), to: client)
    }
    private func send(_ payload: Data, to client: Client) {
        try? client.file.write(contentsOf: payload)
    }
    /// Check current service policy after focus and payload preparation. Socket I/O
    /// stays on the bridge queue; this is not an atomic lease across the IPC boundary.
    @discardableResult
    static func dispatchIfPermitted(host: String, permits: (String) -> Bool, send: () -> Void) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard DispatchQueue.main.sync(execute: { permits(host) }) else { return false }
        send()
        return true
    }
    private func ownsFocus(_ client: Client) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == client.host,
              !client.nonce.isEmpty else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.030)
        guard let raw = AccessibilityEditor.attribute(element, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let window = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.030)
        guard let title = AccessibilityEditor.attribute(window, kAXTitleAttribute) as? String else { return false }
        guard title.contains("[LP:" + client.nonce + "]"),
              let rawField = AccessibilityEditor.attribute(element, kAXFocusedUIElementAttribute), CFGetTypeID(rawField) == AXUIElementGetTypeID() else { return false }
        let field = rawField as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.030)
        guard AccessibilityEditor.attribute(field, kAXRoleAttribute) as? String == kAXTextAreaRole,
              let fieldWindow = AccessibilityEditor.attribute(field, kAXWindowAttribute), CFEqual(fieldWindow, window),
              client.field.map({ CFEqual($0, field) }) ?? true else { return false }
        client.field = field
        return true
    }
    func perform(_ action: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let matches = self.clients.values.filter { self.ownsFocus($0) }
            guard matches.count == 1, let client = matches.first else { return }
            let payload = Data((action + "\n").utf8)
            Self.dispatchIfPermitted(host: client.host, permits: self.permits) {
                self.send(payload, to: client)
            }
        }
    }
    private func receive(_ line: String, client: Client, fd: Int32) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if client.nonce.isEmpty {
            guard fields.count == 3, fields[0] == "hello", EditorSupport.permitsTerminalIntegration(applicationID: fields[1]),
                  UUID(uuidString: fields[2]) != nil else { disconnect(fd); return }
            client.host = fields[1]; client.nonce = fields[2]; send("ready", to: client); return
        }
        if fields == ["applied"], let decision = client.pending {
            client.pending = nil
            guard ownsFocus(client) else { return }
            client.last = decision; client.previousSource = client.pendingSource
            let host = client.host
            DispatchQueue.main.async { [weak self] in self?.applied(decision, nil, host) }
            return
        }
        if fields == ["undone"], let decision = client.last {
            client.last = nil
            guard ownsFocus(client) else { return }
            let previous = client.previousSource
            let host = client.host
            DispatchQueue.main.async { [weak self] in self?.applied(decision, previous, host) }
            return
        }
        guard fields.count == 2, ["auto", "manual"].contains(fields[0]),
              !fields[1].isEmpty, fields[1].utf16.count <= 256,
              EditorSupport.permitsKeyboardText(fields[1]) else { disconnect(fd); return }
        guard ownsFocus(client) else { client.pending = nil; send("skip", to: client); return }
        let manual = fields[0] == "manual", word = fields[1], host = client.host
        DispatchQueue.main.async { [weak self, weak client] in
            guard let self, let client else { return }
            let decision = self.decide(word, manual, host)
            let source = InputSources.identifier
            self.queue.async {
                guard self.clients[fd] === client, self.ownsFocus(client), let decision,
                      EditorSupport.permitsKeyboardText(decision.replacement) else { self.send("skip", to: client); return }
                let payload = Data(("edit\t" + decision.replacement + "\n").utf8)
                guard Self.dispatchIfPermitted(host: client.host, permits: self.permits, send: {
                    client.pending = decision; client.pendingSource = source
                    self.send(payload, to: client)
                }) else { client.pending = nil; self.send("skip", to: client); return }
            }
        }
    }
}
