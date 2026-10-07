import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("diagnostic_report", Path(__file__).parents[2]/"scripts/report-macos-input-diagnostics.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class DiagnosticReportTests(unittest.TestCase):
    def test_summarizes_decisions_and_stage_percentiles_without_raw_records(self):
        lines = ["# TypeTune diagnostics v2",
                 "2026-10-06T20:00:00Z manual_decision recognized=true reason=invalid_editor_word press_ms=50 gap_ms=100",
                 "2026-10-06T20:00:01Z edit outcome=rejected duration_ms=2",
                 "2026-10-06T20:00:02Z ignored_event secret=private_fixture_text",
                 "2026-10-06T20:00:03Z observer_start_failed reason=tap_create secret=private_fixture_text",
                 "2026-10-06T20:00:04Z runtime_suspension reason=sleep active=false suspended=true",
                 "2026-10-06T20:00:05Z observer_stopped attempt=1 stale=true"]
        for number in range(1, 21):
            lines.append(f"2026-10-06T20:01:00Z edit_timing trigger=manual snapshot_us={number} secret=private_fixture_text")
        result = report.summarize("\n".join(lines)+"\n")
        self.assertEqual(result["counts"]["manual_decision.recognized.true"], 1)
        self.assertEqual(result["counts"]["edit.outcome.rejected"], 1)
        self.assertEqual(result["counts"]["observer_start_failed.reason.tap_create"], 1)
        self.assertEqual(result["counts"]["runtime_suspension.suspended.true"], 1)
        self.assertEqual(result["counts"]["observer_stopped.stale.true"], 1)
        self.assertEqual(result["timings_us"]["edit_timing.manual.snapshot_us"], {"count":20,"p50":10,"p95":19,"max":20})
        self.assertNotIn("private_fixture_text", str(result))
        self.assertNotIn("press_ms", str(result))

    def test_refuses_legacy_key_logs_and_ignores_malformed_timing_values(self):
        with self.assertRaises(ValueError):
            report.summarize("old key log")
        result = report.summarize("# TypeTune diagnostics v2\n2026-10-06T20:00:00Z edit_timing trigger=manual snapshot_us=unknown total_us=99999999999999999\n")
        self.assertEqual(result["timings_us"], {})


if __name__ == "__main__":
    unittest.main()
