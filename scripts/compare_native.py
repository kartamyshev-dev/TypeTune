#!/usr/bin/env python3
"""Compare complete immutable native runs by ID; never train or modify expectations."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
from native_evidence import validate_binding

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_rows(rows, description):
    require(isinstance(rows, list), description + ': array required')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get('id'), str), description + ': row/id required')
        require(row['id'] not in result, description + ': duplicate ID ' + row['id'])
        result[row['id']] = row
    return result


def read(paths, fixtures, target, case_digest, require_bound=False):
    require(len(paths) == 5, target + ': exactly five complete 200-case batches required')
    result = {}
    bound_identity = None
    for path in paths:
        data = json.loads(Path(path).read_text())
        require(isinstance(data, dict), str(path) + ': object required')
        require(type(data.get('processExitCode')) is int and data['processExitCode'] == 0 and 'error' not in data, str(path) + ': failed/partial run')
        require(data.get('target') == target, str(path) + ': wrong target label')
        if require_bound or 'identityBefore' in data:
            identity = validate_binding(data)
            if bound_identity is None: bound_identity = identity
            require(identity == bound_identity, str(path) + ': target/helper identity changed between batches')
        require(type(data.get('cases')) is int and data['cases'] == 200 and type(data.get('completed')) is int and data['completed'] == 200, str(path) + ': incomplete checkpoint/case count')
        require(isinstance(data.get('checkpoint'), str) and data['checkpoint'].endswith('.results.json'), str(path) + ': checkpoint reference required')
        if require_bound: require(data.get('caseFileSha256') == case_digest, str(path) + ': bound fixture digest required')
        if 'caseFileSha256' in data:
            require(data['caseFileSha256'] == case_digest, str(path) + ': fixture digest mismatch')
        # Old complete logs remain valid regardless of helper or binary revision; hashes are recorded, not inferred.
        require(data.get('initialSyntheticText') in (None, ''), str(path) + ': unexpected initial text')
        rows = unique_rows(data.get('results'), str(path))
        require(len(rows) == 200, str(path) + ': expected 200 result rows')
        events = 0
        for identifier, row in rows.items():
            require(identifier in fixtures and identifier not in result, str(path) + ': unknown or duplicate ID ' + identifier)
            fixture = fixtures[identifier]
            require(row.get('physicalASCII') == fixture['text'], identifier + ': physical input mismatch')
            require(row.get('requestedSource') == 'com.apple.keylayout.' + fixture['source'], identifier + ': source ID mismatch')
            require(row.get('boundary') is True and row.get('gesture') == 'none', identifier + ': different boundary/gesture procedure')
            require(row.get('selectAllBeforeGesture') is False, identifier + ': unexpected selection procedure')
            require(row.get('clipboardRestore') == 'not_used' and row.get('pasteText') is None, identifier + ': unexpected clipboard procedure')
            require(row.get('initialSyntheticText') in (None, ''), identifier + ': unexpected initial text')
            require(isinstance(row.get('text'), str), identifier + ': result text required')
            require(type(row.get('events')) is int and 0 < row['events'] <= 600, identifier + ': invalid event bound')
            events += row['events']
            result[identifier] = row
        require(type(data.get('totalEvents')) is int and data['totalEvents'] == events, str(path) + ': total event count mismatch')
    require(result.keys() == fixtures.keys(), target + ': comparison requires all 1000 unique IDs')
    return result


def metrics(rows, ids, fixtures, inputs):
    counts = collections.Counter()
    for key in ids:
        expected, before, actual = fixtures[key]['expected'], inputs[key], rows[key]['text']
        counts['count'] += 1
        counts['matchesExpected'] += actual == expected
        counts['correctCorrections'] += expected != before and actual == expected
        counts['falseCorrections'] += expected == before and actual != before
        counts['misses'] += expected != before and actual == before
        counts['otherWrongResults'] += expected != before and actual not in (before, expected)
    return dict(counts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--original', nargs='+', required=True)
    parser.add_argument('--prototype', nargs='+', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--require-bound-identity', action='store_true', help='Reject legacy logs without whole bundle/process/helper proof')
    args = parser.parse_args()
    case_path, input_path = ROOT / 'corpus/native-v1.json', ROOT / 'corpus/synthetic-v2.jsonl'
    fixtures = unique_rows(json.loads(case_path.read_text()), 'native fixtures')
    require(len(fixtures) == 1000, 'Native fixtures require 1000 unique IDs')
    input_rows = unique_rows([json.loads(line) for line in input_path.read_text().splitlines()], 'input fixtures')
    require(fixtures.keys() <= input_rows.keys(), 'Native ID absent from synthetic source')
    inputs = {identifier: input_rows[identifier]['input'] + ' ' for identifier in fixtures}
    case_digest = hashlib.sha256(case_path.read_bytes()).hexdigest()
    original = read(args.original, fixtures, 'original', case_digest, args.require_bound_identity)
    prototype = read(args.prototype, fixtures, 'prototype', case_digest, args.require_bound_identity)
    # Metrics can describe historical runs with different procedures. Never let
    # that imply a controlled comparison when protocol metadata is absent.
    protocol_fields = ['probeSourceSha256', 'probeBinarySha256', 'intervalMilliseconds']
    protocols = [json.loads(Path(path).read_text()) for path in args.original + args.prototype]
    recorded_protocol = {field: sorted({str(item[field]) for item in protocols if field in item})
                         for field in protocol_fields}
    protocol_complete = all(all(field in item for field in protocol_fields) for item in protocols)
    bound_complete = all(item.get('identityUnchanged') is True and 'identityBefore' in item for item in protocols)
    report = {
        'notice': 'Authored lexicon consistency sample, synthetic HID TextEdit only. Not independent language quality or correction latency p95.',
        'wholeBundleIdentityComplete': bound_complete,
        'historicalMetricsOnly': not bound_complete,
        'caseSha256': case_digest,
        'recordedProtocol': recorded_protocol,
        'recordedProtocolComplete': protocol_complete,
        'recordedProtocolMatches': protocol_complete and all(len(values) == 1 for values in recorded_protocol.values()),
        'protocolLimit': 'Helper/interval metadata only; does not prove equal app settings, original learning state, independent corpus or correction-only latency.',
        'syntheticInputSha256': hashlib.sha256(input_path.read_bytes()).hexdigest(),
        'files': {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in args.original + args.prototype},
        'overall': {}, 'bySplit': {}, 'byCategory': {}, 'differences': []}
    for name, rows in [('original', original), ('prototype', prototype)]:
        report['overall'][name] = metrics(rows, fixtures, fixtures, inputs)
    for field, title in [('split', 'bySplit'), ('category', 'byCategory')]:
        for group in sorted({row[field] for row in fixtures.values()}):
            ids = [key for key, row in fixtures.items() if row[field] == group]
            report[title][group] = {name: metrics(rows, ids, fixtures, inputs) for name, rows in [('original', original), ('prototype', prototype)]}
    for key, fixture in fixtures.items():
        a, b = original[key]['text'], prototype[key]['text']
        if a == b:
            continue
        label = 'prototype_matches_authored_expected' if b == fixture['expected'] else 'original_matches_authored_expected' if a == fixture['expected'] else 'neither_matches_authored_expected'
        report['differences'].append(dict(id=key, split=fixture['split'], category=fixture['category'], input=inputs[key], expected=fixture['expected'], original=a, prototype=b, classification=label, cause='requires_review'))
    hold = report['bySplit']['holdout']
    a, b = hold['original'], hold['prototype']
    report['authoredHoldoutCriterionPassed'] = b['falseCorrections'] <= a['falseCorrections'] and b['correctCorrections'] >= a['correctCorrections']
    report['boundProtocolCriterionPassed'] = bound_complete and report['recordedProtocolMatches'] and report['authoredHoldoutCriterionPassed']
    report['fullAcceptance'] = False  # authored corpus is not independent language validation
    output = Path(args.output)
    resolved_inputs = {Path(path).resolve() for path in args.original + args.prototype}
    require(output.resolve() not in resolved_inputs | {case_path.resolve(), input_path.resolve()}, 'Output must not overwrite evidence or fixtures')
    # Never replace a previous comparison report: choose a new explicit output path.
    with output.open('x') as stream:
        stream.write(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(overall=report['overall'], holdout=hold, differences=len(report['differences']), authoredHoldoutCriterionPassed=report['authoredHoldoutCriterionPassed']), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
