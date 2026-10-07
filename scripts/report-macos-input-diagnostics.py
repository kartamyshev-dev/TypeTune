#!/usr/bin/env python3
"""Summarize current-format TypeTune diagnostics without exporting raw records."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re

EVENTS = {"manual_decision", "edit", "edit_rejected", "commit_stopped",
          "auto_skipped", "history_reset", "native_validation_rejected",
          "decision_timing", "edit_timing", "observer_start", "observer_started",
          "observer_start_failed", "observer_restart", "observer_recovered",
          "observer_registration_failed", "observer_stopped", "runtime_suspension", "runtime_blocked"}
STAGES = {"context_us", "total_us", "inference_us", "wait_held_us", "snapshot_us",
          "editor_prepare_us", "settle_wait_us", "native_prepare_us", "commit_us",
          "validate_focus_us", "validate_text_us", "release_us", "verify_context_us",
          "verify_text_us", "verify_wait_us"}


def summarize(text):
    if not text.startswith("# TypeTune diagnostics v2\n"):
        raise ValueError("Expected diagnostics v2; legacy key logs are not processed")
    counters = Counter()
    timing = defaultdict(list)
    last_timestamp = None
    for line in text.splitlines()[1:]:
        match = re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) ([a-z_]+) (.*)", line)
        if not match or match[2] not in EVENTS:
            continue
        stamp, event, payload = match.groups()
        fields = dict(re.findall(r"\b([a-z_]+)=([a-z_0-9]+)\b", payload))
        last_timestamp = stamp
        counters[event] += 1
        for name in ["reason", "outcome", "recognized", "active", "suspended", "stale"]:
            value = fields.get(name, "")
            if re.fullmatch(r"[a-z_]{1,64}", value):
                counters[f"{event}.{name}.{value}"] += 1
        if event.endswith("_timing") and fields.get("trigger") in {"manual", "automatic"}:
            for stage in STAGES:
                value = fields.get(stage, "")
                if value.isdigit() and len(value) <= 16:
                    timing[f"{event}.{fields['trigger']}.{stage}"].append(int(value))
    metrics = {}
    for name, values in sorted(timing.items()):
        values.sort()
        metrics[name] = {"count": len(values), "p50": values[math.ceil(len(values)*0.5)-1],
                         "p95": values[math.ceil(len(values)*0.95)-1], "max": values[-1]}
    return {"last_recognized_record_utc": last_timestamp, "counts": dict(sorted(counters.items())),
            "timings_us": metrics,
            "limitations": ["Counts are diagnostic records, not failed physical keystrokes.",
                "A file may include several builds; no installed-build attribution is inferred.",
                "Context is per batch; commit includes validate_focus/validate_text. Do not sum overlapping timings."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, default=Path.home()/"Library/Application Support/TypeTune/diag.log")
    args = parser.parse_args()
    print(json.dumps(summarize(args.log.read_text()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
