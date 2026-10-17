import AppKit
import ApplicationServices
import Foundation

/// Link-only adapters. The probe never starts the bridge or reads native fields.
enum AccessibilityEditor {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        fatalError("Native field access is outside this probe")
    }
}
enum InputSources {
    static var identifier: String { fatalError("Native input-source access is outside this probe") }
}

@main private struct TerminalDispatchProbe {
    private final class State {
        // All access to these values is on the main thread.
        var permits = true
        var checks: [String: Bool]?
    }
    static func main() throws {
        var checks: [String: Bool] = [:]
        let bridgeQueue = DispatchQueue(label: "dev.layoutpilot.terminal-dispatch-probe")
        func run(_ action: String, pauseAfterPreparation: Bool) throws {
            let state = State()
            bridgeQueue.async {
                // The decision/command and payload exist before the policy changes.
                let payload = Data((action + "\n").utf8)
                let initiallyPermitted = DispatchQueue.main.sync { () -> Bool in
                    let before = state.permits
                    if pauseAfterPreparation { state.permits = false }
                    return before
                }
                var policyOnMain = false
                var exactHost = false
                var sent = 0
                var sendOffMain = false
                var payloadPreserved = false
                let admitted = TerminalBridge.dispatchIfPermitted(host: "probe.host", permits: { host in
                    policyOnMain = Thread.isMainThread
                    exactHost = host == "probe.host"
                    return state.permits
                }, send: {
                    sent += 1
                    sendOffMain = !Thread.isMainThread
                    payloadPreserved = payload == Data((action + "\n").utf8)
                })
                let result: [String: Bool] = [
                    "initially_permitted": initiallyPermitted,
                    "policy_read_on_main": policyOnMain,
                    "policy_receives_host": exactHost,
                    "current_policy_controls_dispatch": admitted == !pauseAfterPreparation,
                    "paused_payload_not_sent": pauseAfterPreparation ? sent == 0 : sent == 1,
                    "permitted_payload_sent_off_main": pauseAfterPreparation || (sendOffMain && payloadPreserved)
                ]
                DispatchQueue.main.async { state.checks = result }
            }
            let deadline = Date().addingTimeInterval(10)
            while state.checks == nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            guard let result = state.checks else { throw CocoaError(.coderReadCorrupt) }
            let name = action.hasPrefix("edit") ? "edit" : action
            let prefix = name + (pauseAfterPreparation ? "_paused_" : "_ready_")
            for (key, value) in result { checks[prefix + key] = value }
        }
        for action in ["edit\tfixture", "manual", "undo"] {
            try run(action, pauseAfterPreparation: true)
            try run(action, pauseAfterPreparation: false)
        }
        let failures = checks.filter { !$0.value }.map(\.key).sorted()
        let report: [String: Any] = [
            "passed": checks.count - failures.count, "total": checks.count,
            "failures": failures, "checks": checks,
            "productionDispatchHelperUsed": true, "nativeEventsPosted": false,
            "bridgeStarted": false, "socketIOUsed": false, "realFieldsRead": false,
            "nativeAcceptance": false,
            "boundary": "A pause after the final policy read cannot revoke an IPC command already being sent."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        if !failures.isEmpty { exit(1) }
    }
}
