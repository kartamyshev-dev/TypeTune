#!/usr/bin/env python3
"""Strict new-session audit; old results stay historical, never upgraded by inference."""
import argparse
import json
import math
import pathlib
import statistics
from native_evidence import capture, validate_binding, validate_workload_segments, require, digest, target_binary


def validate_session(folder, current_identity, root=None):
    folder = pathlib.Path(folder)
    data = json.loads((folder/'summary.json').read_text())
    samples = json.loads((folder/'telemetry.json').read_text())
    required_duration = data.get('requiredDurationSeconds')
    require(type(required_duration) is int and 1800 <= required_duration <= 86400 and required_duration % 60 == 0, 'Invalid required session duration')
    duration = data.get('durationSeconds')
    require(type(duration) in (int, float) and math.isfinite(duration) and duration >= required_duration, 'Session shorter than requested duration')
    require(data.get('status') == 'completed' and data.get('atLeast30Minutes') is True, 'Incomplete/short session')
    require(data.get('atLeast4Hours') is (duration >= 14400), 'Four-hour duration evidence mismatch')
    require(type(data.get('requiredIdleSecondsPerBatch')) is int and data['requiredIdleSecondsPerBatch'] == 30, 'Session idle policy missing')
    require(data.get('identityUnchanged') is True and data.get('identityBefore') == data.get('identityAfter') == current_identity, 'Whole session/current identity mismatch')
    require(len(samples) >= 850, 'Insufficient telemetry coverage')
    times = [row['seconds'] for row in samples]
    require(times[0] <= 5 and data['durationSeconds']-times[-1] <= 5, 'Telemetry misses session boundary')
    gaps = [b-a for a,b in zip(times,times[1:])]
    require(all(0 < gap <= 5 for gap in gaps), 'Telemetry gap or unordered samples')
    root = pathlib.Path(root) if root is not None else pathlib.Path(__file__).resolve().parents[1]
    comparison = root/'research/evidence/native-corpus-prototype'/data['comparisonRun']
    from compare_native import read, unique_rows
    case_file = root/'corpus/native-v1.json'
    fixtures = unique_rows(json.loads(case_file.read_text()), 'session comparison fixtures')
    actual_rows = read([comparison/f'{index:02}.json' for index in range(5)], fixtures, 'prototype', digest(case_file), require_bound=True)
    from native_integrity import load_corpus_oracle, unknown_corpus_rows, correction_failures
    oracle, oracle_identity = load_corpus_oracle(case_file, root/'corpus/synthetic-v2.jsonl')
    require(not unknown_corpus_rows(actual_rows.values(), oracle, fixtures), 'Unknown/unsafe corpus text')
    comparison_misses = correction_failures(actual_rows.values(), list(fixtures.values()))
    evidence = []
    input_seconds, idle_seconds = 0, 0
    for index in range(5):
        path = comparison/f'{index:02}.json'
        batch = json.loads(path.read_text())
        require(validate_binding(batch) == current_identity, 'Comparison identity differs from session')
        batch_input, batch_idle = validate_workload_segments(batch, 0)
        input_seconds += batch_input
        idle_seconds += batch_idle
        require(batch.get('target') == 'prototype' and batch.get('completed') == 200 and len(batch.get('results', [])) == 200, 'Incomplete comparison batch')
        require(batch.get('corpusIntegrity', {}).get('fixtureIdentity') == oracle_identity, 'Corpus integrity fixture identity mismatch')
        evidence.append({'path': str(path), 'sha256': digest(path)})
    require(data.get('stabilityBatches'), 'No stability workload recorded')
    stream_fixture = root/'corpus/native-fast-stream-v1.json'
    require(data.get('streamFixtureSha256') == digest(stream_fixture), 'Stream regression fixture identity mismatch')
    stream_cases = json.loads(stream_fixture.read_text())
    unique_rows(stream_cases, 'stream regression fixtures')
    require(stream_cases, 'Empty stream regression fixture')
    stability_misses = []
    for batch in data['stabilityBatches']:
        require(not batch['textIntegrityFailures'], 'Integrity failure')
        path = folder/f"stability-{batch['index']}.json"
        result = json.loads(path.read_text())
        require(validate_binding(result) == current_identity, 'Stability identity differs from session')
        batch_input, batch_idle = validate_workload_segments(result, 30)
        require(batch.get('inputSegmentSeconds') == batch_input and batch.get('idleSegmentSeconds') == batch_idle, 'Stability segment summary mismatch')
        input_seconds += batch_input
        idle_seconds += batch_idle
        batch_file = root/'research/private/native-batches'/f"stability-{data['comparisonRun']}-{batch['index']}.json"
        expected = json.loads(batch_file.read_text())
        require(expected == [dict(stream_cases[i % len(stream_cases)], id=f"stability-{batch['index']}-{i}")
                             for i in range(len(expected))], 'Stability procedure/expectation differs from regression fixture')
        require(result.get('nativeBatchSha256') == digest(batch_file), 'Stability fixture digest mismatch')
        require(len(result.get('results', [])) == len(expected) and {r['id'] for r in result['results']} == {r['id'] for r in expected}, 'Stability IDs mismatch')
        require(result.get('completed') == batch['cases'] and len(result.get('results', [])) == batch['cases'], 'Stability completion mismatch')
        # Recompute integrity from actual immutable rows, never trust summary flags.
        from native_integrity import preserved_alternating
        require(all(preserved_alternating(row['text']) for row in result['results']), 'Stability text tampering/integrity failure')
        stability_misses.extend(correction_failures(result['results'], expected))
        evidence.append({'path': str(path), 'sha256': digest(path)})
    quality_passed = not comparison_misses and not stability_misses
    require(data.get('inputDurationSeconds') == input_seconds and data.get('idleDurationSeconds') == idle_seconds, 'Session segment summary mismatch')
    require(input_seconds + idle_seconds <= duration + 0.01, 'Segment durations exceed session')
    return {'passed': quality_passed, 'integrityPassed': True, 'correctionQualityPassed': quality_passed,
        'comparisonCorrectionFailureIDs': comparison_misses, 'stabilityCorrectionFailureIDs': stability_misses,
        'streamFixtureSha256': digest(stream_fixture),
        'durationSeconds': duration, 'requiredDurationSeconds': required_duration,
        'inputDurationSeconds': input_seconds, 'idleDurationSeconds': idle_seconds,
        'requiredIdleSecondsPerBatch': 30,
        'atLeast4Hours': duration >= 14400, 'samples': len(samples),
        'maxSampleGapSeconds': max(gaps), 'identityVerified': True, 'evidence': evidence,
        'first30sMedianRSSKiB': statistics.median(s['rssKiB'] for s in samples if s['seconds'] <= 30),
        'last30sMedianRSSKiB': statistics.median(s['rssKiB'] for s in samples if s['seconds'] >= times[-1]-30),
        'medianCPUPercent': statistics.median(s['cpuPercent'] for s in samples),
        'stabilityCases': sum(b['cases'] for b in data['stabilityBatches']),
        'notice': 'Bound synthetic TextEdit session only; not other-host, sleep/wake, physical input or correction-only latency acceptance.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('session')
    parser.add_argument('--app', help='Exact running .app; defaults to dist/LayoutPilot.app')
    args = parser.parse_args()
    folder = pathlib.Path(args.session)
    data = json.loads((folder/'summary.json').read_text())
    root = pathlib.Path(__file__).resolve().parents[1]
    current = capture(root, target_binary(root, args.app), data['pid'])
    report = validate_session(folder, current)
    with (folder/'verification.json').open('x') as stream:
        stream.write(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
