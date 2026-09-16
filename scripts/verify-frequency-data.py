#!/usr/bin/env python3
"""Verify vendored upstream bytes; optionally reproduce them from pinned URLs."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--download', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'crates/typetune-engine/data/frequency'
manifest = json.loads((root / 'manifest.json').read_text())
for lang, entry in manifest['files'].items():
    path = root / f'{lang}_50k.txt'
    if args.download:
        url = f"https://raw.githubusercontent.com/hermitdave/FrequencyWords/{manifest['revision']}/{entry['path']}"
        data = urlopen(url, timeout=60).read()
    else:
        data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise SystemExit(f'{lang}: checksum mismatch; no file written')
    if args.download:
        path.write_bytes(data)
    print(f'{lang}: verified {len(data)} bytes')
