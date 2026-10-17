import AppKit
import Carbon
import Foundation

/// Calls the production decoder with enabled layouts and events constructed in
/// memory. Never selects an input source, posts an event or reads an AX field.
@main private struct InputSourceTranslationProbe {
    static func main() throws {
        let before = InputSources.identifier
        let sources = TISCreateInputSourceList(nil, false)!.takeRetainedValue() as! [TISInputSource]
        var checks: [String: Bool] = [:]
        var observations: [[String: Any]] = []
        func event(_ key: CGKeyCode = 5, flags: CGEventFlags = [], payload: String? = nil) -> CGEvent {
            let value = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
            value.flags = flags
            if let payload {
                let chars = Array(payload.utf16)
                chars.withUnsafeBufferPointer {
                    value.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress!)
                }
            }
            return value
        }
        func unicode(_ event: CGEvent) -> String {
            var count = 0, buffer = [UniChar](repeating: 0, count: 16)
            event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &count, unicodeString: &buffer)
            return String(utf16CodeUnits: buffer, count: count)
        }
        let fixtures: [(String, String, String, String)] = [
            ("abc", "com.apple.keylayout.ABC", "g", "п"),
            ("russian", "com.apple.keylayout.RussianWin", "п", "g")
        ]
        for (label, sourceID, lower, stalePayload) in fixtures {
            let found = sources.first { InputSources.property($0, kTISPropertyInputSourceID) == sourceID }
            checks[label + "_enabled_source_available"] = found != nil
            guard let source = found else { continue }
            let plain = event(payload: stalePayload)
            checks[label + "_stale_unicode_fixture_present"] = unicode(plain) == stalePayload
            checks[label + "_stale_unicode_ignored_for_verified_layout"] = InputSources.insertionText(for: plain, source: source) == lower
            for (name, flags, expected) in [
                ("plain", CGEventFlags(), lower),
                ("shift", CGEventFlags.maskShift, lower.uppercased()),
                ("caps", CGEventFlags.maskAlphaShift, lower.uppercased()),
                ("shift_caps", CGEventFlags([.maskShift, .maskAlphaShift]), lower.uppercased())
            ] {
                let actual = InputSources.insertionText(for: event(flags: flags, payload: stalePayload), source: source)
                checks[label + "_" + name + "_letter"] = actual == expected
                observations.append(["fixture": label + "_" + name, "expected": expected, "actual": actual as Any? ?? NSNull()])
            }
            checks[label + "_space"] = InputSources.insertionText(for: event(49, payload: stalePayload), source: source) == " "
            for (name, flags) in [
                ("command", CGEventFlags.maskCommand), ("control", CGEventFlags.maskControl),
                ("option", CGEventFlags.maskAlternate),
                ("command_shift", CGEventFlags([.maskCommand, .maskShift])),
                ("control_caps", CGEventFlags([.maskControl, .maskAlphaShift])),
                ("option_shift_caps", CGEventFlags([.maskAlternate, .maskShift, .maskAlphaShift]))
            ] {
                checks[label + "_" + name + "_rejected"] = InputSources.insertionText(for: event(flags: flags, payload: lower), source: source) == nil
            }
            for key: CGKeyCode in [36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126] {
                checks[label + "_control_key_" + String(key) + "_rejected"] = InputSources.insertionText(for: event(key, payload: lower), source: source) == nil
            }
            let invalid = event(payload: lower)
            invalid.setIntegerValueField(.keyboardEventKeycode, value: -1)
            checks[label + "_negative_key_rejected"] = InputSources.insertionText(for: invalid, source: source) == nil
            invalid.setIntegerValueField(.keyboardEventKeycode, value: 65_536)
            // CGEvent stores this field as a physical keycode; out-of-range setter
            // values may be normalized before the production decoder sees them.
            observations.append(["fixture": label + "_oversized_event_field", "requested": 65_536,
                "fieldReadback": invalid.getIntegerValueField(.keyboardEventKeycode)])
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)!
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            checks[label + "_unknown_source_rejected"] = InputSources.insertionText(keyCode: 5, flags: [],
                sourceID: "probe.unsupported", layoutData: data, keyboardType: UInt32(LMGetKbdType())) == nil
            checks[label + "_invalid_physical_key_rejected"] = InputSources.insertionText(keyCode: .max, flags: [],
                sourceID: sourceID, layoutData: data, keyboardType: UInt32(LMGetKbdType())) == nil
            checks[label + "_missing_layout_has_no_unicode_fallback"] = InputSources.insertionText(keyCode: 5, flags: [],
                sourceID: sourceID, layoutData: nil, keyboardType: UInt32(LMGetKbdType())) == nil
            checks[label + "_truncated_layout_rejected"] = InputSources.insertionText(keyCode: 5, flags: [],
                sourceID: sourceID, layoutData: Data([0, 1, 2]) as CFData, keyboardType: UInt32(LMGetKbdType())) == nil
        }
        if let fixture = fixtures.first(where: { $0.1 == before }) {
            checks["current_wrapper_ignores_stale_unicode"] = InputSources.insertionText(for: event(payload: fixture.3), sourceID: before) == fixture.2
            let other = fixtures.first { $0.1 != before }!.1
            checks["current_wrapper_rejects_other_enabled_layout"] = InputSources.insertionText(for: event(), sourceID: other) == nil
        } else {
            checks["current_source_supported_for_wrapper_check"] = false
        }
        checks["current_wrapper_unknown_id_has_no_fallback"] = InputSources.insertionText(for: event(payload: "g"), sourceID: "probe.unsupported") == nil
        let after = InputSources.identifier
        checks["input_source_preserved"] = before == after
        let failures = checks.filter { !$0.value }.map(\.key).sorted()
        let report: [String: Any] = [
            "passed": checks.count - failures.count, "total": checks.count, "failures": failures,
            "checks": checks, "fixtureObservations": observations, "sourceBefore": before, "sourceAfter": after,
            "productionInputSourcesUsed": true, "eventsPosted": 0, "inputSourceChanges": 0, "AXReads": 0,
            "nativeAcceptance": false,
            "notice": "Synthetic in-memory event translation only; no live source-transition or keyboard delivery acceptance."
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
