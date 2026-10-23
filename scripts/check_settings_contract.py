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
        removed = {'headerImage', 'headerImagePath', 'chooseHeaderImage', 'resetHeaderImage', 'importHeaderImage'} if owner == 'store' else set()
        missing = set(baseline[owner]) - removed - references(source, owner)
        assert not missing, f'Потеряны обращения {owner}: {sorted(missing)}'
    keys = re.findall(r'@AppStorage\("([^"]+)"\)', source)
    assert not keys, 'Оформление больше не должно переопределять тему или цвет'
    bindings = set(re.findall(r'\$store\.([\w.]+)', source))
    # Pause moved to the header button, with the same Store setting.
    required = set(baseline['directBindings']) - {'settings.paused'}
    assert required <= bindings, 'Потеряна прямая привязка Store'
    assert 'store.settings.paused.toggle()' in source, 'Потеряна пауза'
    for path, digest in baseline['protected'].items():
        # Store changed only to remove the retired header image feature.
        if path == 'Sources/LayoutPilot/Store.swift':
            digest = '395c0ba5e1c9a838aa8407ebfbade5a153866207f78ee705567206ffab98abfa'
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, f'Изменён {path}'
    sections = (ROOT / 'Sources/LayoutPilot/SettingsSection.swift').read_text()
    for title in ['Основное', 'Клавиши', 'Исключения', 'Сниппеты', 'Проверка']:
        assert f'"{title}"' in sections, title
    assert 'appearance' not in sections
    print('Source contract: Store/KeyboardService references, appearance removed, other bindings and protected files retained. No native claim.')


if __name__ == '__main__':
    check()
