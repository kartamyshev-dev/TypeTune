// Read-only snapshot: no event tap creation, keyboard synthesis, AX text reads,
// permission prompts, or application launches. Run with: swift <this-file>.
import AppKit
import CoreGraphics
import Foundation

let identifiers = ["com.devdanpro.LangSwitcher", "dev.kartamyshev.TypeTune"]
let apps = NSWorkspace.shared.runningApplications.filter {
    identifiers.contains($0.bundleIdentifier ?? "")
}
var count: UInt32 = 0
let first = CGGetEventTapList(0, nil, &count)
var records: [[String: Any]] = []
var snapshotStatus = "unavailable"
if first == .success, count <= 4096 {
    if count == 0 {
        snapshotStatus = "ok"
    } else {
        let capacity = count
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(capacity))
        if CGGetEventTapList(capacity, &taps, &count) == .success, count <= capacity {
            snapshotStatus = "ok"
            for tap in taps.prefix(Int(count)) {
                guard let app = apps.first(where: { $0.processIdentifier == tap.tappingProcess }) else { continue }
                let point: String
                switch tap.tapPoint {
                case .cghidEventTap: point = "hid"
                case .cgSessionEventTap: point = "session"
                case .cgAnnotatedSessionEventTap: point = "annotated_session"
                @unknown default: point = "unknown"
                }
                records.append([
                    "bundle": app.bundleIdentifier ?? "", "pid": tap.tappingProcess,
                    "id": tap.eventTapID, "point": point, "options": tap.options.rawValue,
                    "enabled": tap.enabled, "mask": tap.eventsOfInterest,
                    "latency_min_us": tap.minUsecLatency, "latency_avg_us": tap.avgUsecLatency,
                    "latency_max_us": tap.maxUsecLatency
                ])
            }
        }
    }
}
let output: [String: Any] = [
    "snapshot_status": snapshotStatus,
    "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "applications": apps.map { ["bundle": $0.bundleIdentifier ?? "", "pid": $0.processIdentifier] as [String: Any] },
    "taps": records,
    "note": "Registration snapshot and callback latency only; no proof of editor delivery or correction."
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if snapshotStatus != "ok" { exit(1) }
