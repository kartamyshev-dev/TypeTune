#!/usr/bin/env python3
"""Source-only guard against dropping settings bindings or changing persistence keys."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'research/evidence/ui-implementation-2026-10-21/control-contract.json'


def references(source, owner):
    values = re.findall(r'(?<![\w".])' + owner + r'\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)', source)
    return {'.'.join(v.split('.')[:2 if v.startswith('settings.') else 1]) for v in values}


def check():
    baseline = json.loads(CONTRACT.read_text())
    source = '\n'.join((ROOT / p).read_text() for p in baseline['uiFiles'])
    for owner in ['store', 'keyboard']:
        missing = set(baseline[owner]) - references(source, owner)
        assert not missing, f'Потеряны обращения {owner}: {sorted(missing)}'
    keys = re.findall(r'@AppStorage\("([^"]+)"\)', source)
    assert set(keys) == set(baseline['appStorage']) and len(keys) == 3, keys
    bindings = set(re.findall(r'\$store\.([\w.]+)', source))
    assert set(baseline['directBindings']) <= bindings, 'Потеряна прямая привязка Store'
    for path, digest in baseline['protected'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, f'Изменён {path}'
    sections = (ROOT / 'Sources/LayoutPilot/SettingsSection.swift').read_text()
    for title in ['Основное', 'Клавиши', 'Исключения', 'Сниппеты', 'Оформление', 'Проверка']:
        assert f'"{title}"' in sections, title
    print('Source contract: Store/KeyboardService references, 3 AppStorage keys and protected files retained. No native claim.')


if __name__ == '__main__':
    check()
