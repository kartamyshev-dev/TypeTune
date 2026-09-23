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

# Leeds secondary frequency list (RU only)
leeds_entry = manifest['leeds']
leeds_path = root / 'leeds_ru_50k.txt'
if args.download:
    data = urlopen(leeds_entry['url'], timeout=60).read()
else:
    data = leeds_path.read_bytes()
if hashlib.sha256(data).hexdigest() != leeds_entry['sha256']:
    raise SystemExit('leeds: checksum mismatch')
if args.download:
    leeds_path.write_bytes(data)
print(f"leeds: verified {len(data)} bytes")

# Tech vocabulary (MIT, TypeTune-owned)
tech_root = Path(__file__).resolve().parents[1] / 'crates/typetune-engine/data/tech'
for name, entry in manifest['tech'].items():
    path = tech_root / f'{name}.txt'
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise SystemExit(f'tech/{name}: checksum mismatch')
    print(f"tech/{name}: verified {len(data)} bytes")
