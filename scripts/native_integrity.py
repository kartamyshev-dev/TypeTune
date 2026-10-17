"""Integrity oracle for a fixed alternating physical ghbdtn/hello test phrase only.
Uncorrected input is distinct from corruption; this is not a language-quality oracle.
"""
import hashlib
import json
import math
from pathlib import Path


def load_corpus_oracle(native_path, synthetic_path):
    """Two exact authored outcomes only; neither outcome proves correction quality."""
    def indexed(rows, label):
        result = {}
        for row in rows:
            identifier = row.get('id')
            if not isinstance(identifier, str) or identifier in result:
                raise ValueError(label + ': missing/duplicate ID')
            result[identifier] = row
        return result
    native_bytes = Path(native_path).read_bytes()
    synthetic_bytes = Path(synthetic_path).read_bytes()
    native = indexed(json.loads(native_bytes), 'native corpus')
    synthetic = indexed([json.loads(line) for line in synthetic_bytes.decode().splitlines()], 'synthetic corpus')
    oracle = {}
    for identifier, row in native.items():
        source = synthetic.get(identifier)
        if source is None or not isinstance(source.get('input'), str) or not isinstance(source.get('expected'), str):
            raise ValueError(identifier + ': missing synthetic identity/input')
        expected = row.get('expected')
        if not isinstance(expected, str) or expected != source['expected'] + ' ':
            raise ValueError(identifier + ': authored expected identity mismatch')
        oracle[identifier] = frozenset((source['input'] + ' ', expected))
    if not oracle:
        raise ValueError('Empty corpus oracle')
    return oracle, {'nativeSha256': hashlib.sha256(native_bytes).hexdigest(),
                    'syntheticSha256': hashlib.sha256(synthetic_bytes).hexdigest()}


def unknown_corpus_rows(rows, oracle, expected_ids):
    """Reject incomplete/duplicate provenance; return unknown text IDs without a cause claim."""
    seen = set()
    unknown = []
    for row in rows:
        identifier = row.get('id')
        if identifier in seen or identifier not in oracle:
            raise ValueError('Duplicate/unknown corpus result ID')
        seen.add(identifier)
        if row.get('text') not in oracle[identifier]:
            unknown.append(identifier)
    if seen != set(expected_ids):
        raise ValueError('Incomplete corpus result IDs')
    return unknown


def preserved_alternating(text, pairs=8):
    tokens=text.split(' ')
    if len(tokens)!=pairs*2+2 or tokens[-2:]!=['','']:
        return False
    return all(token in ({'привет','ghbdtn'} if i%2==0 else {'hello','руддщ'})
               for i,token in enumerate(tokens[:-2]))


def correction_failures(rows, fixtures):
    """Exact authored text and any declared source/caret; raw input is a miss."""
    expected = {row['id']: row for row in fixtures}
    if not expected or len(expected) != len(fixtures):
        raise ValueError('Missing/duplicate correction fixture IDs')
    seen, failures = set(), []
    for row in rows:
        identifier = row.get('id')
        if identifier in seen or identifier not in expected:
            raise ValueError('Duplicate/unknown correction result ID')
        seen.add(identifier)
        fixture = expected[identifier]
        if not isinstance(fixture.get('expected'), str):
            raise ValueError('Missing exact correction expectation')
        if any(row.get(actual) != fixture[wanted] for actual, wanted in
               [('text', 'expected'), ('inputSource', 'expectedSource'), ('selection', 'expectedSelection')]
               if wanted in fixture):
            failures.append(identifier)
    if seen != set(expected):
        raise ValueError('Incomplete correction result IDs')
    return failures


def validate_regression_timing(row, fixture):
    """Requested timing modes need actual helper acknowledgement and measurements."""
    timing = row.get('timing', {})
    if not isinstance(timing, dict):
        raise ValueError('invalid_timing_record')
    if fixture.get('firstWordAfterFocus') is True:
        if timing.get('firstWordAfterFocus') is not True:
            raise ValueError('first_word_timing_not_verified')
        value = timing.get('firstInputAfterFocusMilliseconds')
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ValueError('first_word_measurement_missing')
    if 'preGestureDelayMilliseconds' in fixture:
        delay = timing.get('preGestureDelayMilliseconds')
        if type(delay) not in (int, float) or delay != fixture['preGestureDelayMilliseconds']:
            raise ValueError('gesture_delay_not_verified')
        value = timing.get('gestureAfterTypingMilliseconds')
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ValueError('gesture_delay_measurement_missing')

if __name__=='__main__':
    cases=[('привет hello '*8+' ',True),('ghbdtn руддщ '*8+' ',True),
           ('привет lhelo '*8+' ',False),('вприет hello '*8+' ',False),
           ('привет hello '*7+' ',False),('привет hello '*9+' ',False),
           ('привет hello '*8,False),('hello привет '*8+' ',False)]
    if not all(preserved_alternating(text)==expected for text,expected in cases):
        raise SystemExit('Integrity oracle failure')
    print('8/8 integrity oracle cases; no native acceptance claim')
