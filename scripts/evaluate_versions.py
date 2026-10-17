#!/usr/bin/env python3
"""Audit the v1->v2 expectation change without overwriting the v1 baseline."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]

def load(version):
    return {r['id']: r for r in map(json.loads, (root / f'corpus/synthetic-v{version}.jsonl').read_text().splitlines())}

before, after = load(1), load(2)
assert set(before) <= set(after), 'Previous fixtures must remain present'
changed = []
for identifier, old in before.items():
    new = after[identifier]
    assert old['split'] == new['split'], 'Do not move holdout into train'
    assert old['input'] == new['input'], 'Do not change previous inputs'
    if old['expected'] != new['expected']:
        changed.append(dict(id=identifier, split=old['split'], input=old['input'], beforeExpected=old['expected'], afterExpected=new['expected']))
report = dict(baselineRows=len(before), currentRows=len(after), unchangedSplitForAllPreviousRows=True,
              addedRows=len(set(after)-set(before)), changedExpectations=changed,
              rationale='Independent semantic review removed ambiguous yo rules: сестры can be genitive singular; звезды can be genitive singular; узнает can be future tense. Old semantic oracle was invalid; changing it invalidates cross-version score comparisons. No holdout examples moved into train; no original observations exist.')
(root / 'corpus/version-diff.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f'Preserved {len(before)} input/split pairs; {report["addedRows"]} added; {len(changed)} corrected semantic expectations.')
