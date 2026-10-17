#!/usr/bin/env python3
"""Validate fixture integrity and run offline CLI checks without retuning holdout."""
import argparse
import hashlib
import json
import subprocess
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--cli', default=str(root / '.build/debug/layoutpilot-cli'))
parser.add_argument('--corpus', default='corpus/synthetic-v2.jsonl')
parser.add_argument('--manifest', default='corpus/manifest-v2.json')
parser.add_argument('--report-prefix', default='evaluation-v2')
args = parser.parse_args()
corpus = root / args.corpus
rows = [json.loads(line) for line in corpus.read_text().splitlines()]
manifest = json.loads((root / args.manifest).read_text())
assert hashlib.sha256(corpus.read_bytes()).hexdigest() == manifest['sha256'], 'corpus digest drift'
assert len(rows) >= 1000
assert len({r['id'] for r in rows}) == len(rows)
assert Counter(r['split'] for r in rows) == Counter(train=len(rows) * 7 // 10, holdout=len(rows) * 3 // 10)
groups = {}
for row in rows:
    assert row['schemaVersion'] == 1
    assert row['originalResult'] is None, 'Synthetic fixtures must not invent original observations'
    group = row['provenance'].split('root=', 1)[1]
    groups.setdefault(group, set()).add(row['split'])
assert all(len(splits) == 1 for splits in groups.values()), 'root leakage'
failed = False
for split in ['train', 'holdout']:
    result = subprocess.run([args.cli, 'evaluate', str(corpus), '--split', split], text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise SystemExit(result.stderr)
    report = json.loads(result.stdout)
    report['corpusSha256'] = manifest['sha256']
    report['fixtureLexiconSha256'] = manifest['lexiconSha256']
    report['currentSourceLexiconSha256'] = hashlib.sha256((root / 'Sources/LayoutPilotCore/Resources/lexicon.json').read_bytes()).hexdigest()
    (root / f'corpus/{args.report_prefix}-{split}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(split + ': ' + str(report['total']))
    failed |= bool(report['failures'])
print(f'Integrity: {len(rows)} rows; {len(groups)} disjoint root groups; exact 70/30; no original observations.')
raise SystemExit(1 if failed else 0)
