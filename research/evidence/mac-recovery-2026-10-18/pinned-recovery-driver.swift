
do {
    let target = URL(fileURLWithPath: "/Users/kartamyshev/git/TypeTune/research/private/probes/57B3E59A-3720-433F-8F8B-D3CF44B2E3E7.txt")
    try require(CommandLine.arguments.count == 1, "no_arguments_allowed")
    try require(modifiersNeutral(), "initial_modifiers_not_neutral")
    try require(sourceID(currentSource()) == "com.apple.keylayout.ABC", "source_mismatch")
    let probe = try Probe(target: target, pid: 6445)
    let before = try probe.snapshot()
    try require(before.0 == "привет " && before.1 == ["location": 7, "length": 0], "exact_synthetic_prefix_required")
    try probe.gesture("recover")
    settle(1)
    let after = try probe.snapshot()
    output(["document": target.path, "pid": probe.pid, "beforeText": before.0, "beforeSelection": before.1,
        "text": after.0, "selection": after.1, "events": probe.events, "inputSource": sourceID(currentSource())])
} catch let failure as ProbeFailure { output(["error": failure.message]); exit(2) }
catch { output(["error": "probe_operation_failed"]); exit(2) }
