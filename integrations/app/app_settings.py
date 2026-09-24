"""Persistent controller settings and explicit XDG login launcher."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import tempfile
import uuid

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config')))
PATH = CONFIG/'typetune/settings.json'
AUTOSTART = CONFIG/'autostart/dev.kartamyshev.TypeTune.Preview.desktop'
DEFAULT = dict(
    version=2,
    generation='0',
    mode='compatibility',
    automatic=True,
    manual_switching=True,
    switch_only_last_word=True,
    dont_switch_words=False,
    dont_correct_after_layout_change=True,
    display_layout_flag=True,
    play_switching_sound=False,
    autostart=False,
    learn_threshold=3,
    active_keyboards=['us', 'ru'],
)
UPDATABLE = frozenset({
    'mode', 'automatic', 'manual_switching', 'switch_only_last_word',
    'dont_switch_words', 'dont_correct_after_layout_change',
    'display_layout_flag', 'play_switching_sound', 'learn_threshold',
    'active_keyboards',
})
BOOL_KEYS = (
    'automatic', 'manual_switching', 'switch_only_last_word',
    'dont_switch_words', 'dont_correct_after_layout_change',
    'display_layout_flag', 'play_switching_sound', 'autostart',
)


def _validate(value):
    if not isinstance(value, dict):
        raise ValueError('Неверный формат настроек TypeTune')
    if value.get('version') not in (1, 2):
        raise ValueError('Неверный формат настроек TypeTune')
    if value.get('mode') not in ('compatibility', 'ibus'):
        raise ValueError('Неверный формат настроек TypeTune')
    for key in BOOL_KEYS:
        if key in value and type(value[key]) is not bool:
            raise ValueError('Неверный формат настроек TypeTune')
    if value.get('switch_only_last_word') and value.get('dont_switch_words'):
        raise ValueError('Нельзя одновременно: «Переключать только последнее слово» и «Не переключать слова»')
    if 'learn_threshold' in value and (type(value['learn_threshold']) is not int or not 1 <= value['learn_threshold'] <= 10):
        raise ValueError('Неверный формат настроек TypeTune')
    boards = value.get('active_keyboards')
    if boards is not None:
        if (not isinstance(boards, list) or len(boards) > 16
                or any(not isinstance(x, str) or not x or len(x) > 32 or any(c.isspace() for c in x) for x in boards)):
            raise ValueError('Неверный формат настроек TypeTune')
        if len(set(boards)) != len(boards):
            raise ValueError('Неверный формат настроек TypeTune')
    if 'generation' in value and (not isinstance(value['generation'], str) or not 1 <= len(value['generation']) <= 64):
        raise ValueError('Неверный формат настроек TypeTune')


def _migrate(raw):
    """v1→v2: fill defaults; keeps reading v1 `automatic`."""
    if not isinstance(raw, dict) or raw.get('version') not in (1, 2):
        raise ValueError('Неверный формат настроек TypeTune')
    out = dict(DEFAULT)
    for key in DEFAULT:
        if key in raw:
            out[key] = raw[key]
    out['version'] = 2
    out['mode'] = 'compatibility'  # Legacy v1 settings never enable another adapter.
    _validate(out)
    return out


def load(path=PATH):
    if not path.exists():
        return dict(DEFAULT)
    with path.open('rb') as file:
        raw = file.read(4097)
    if len(raw) > 4096:
        raise ValueError('Файл настроек слишком большой')
    try:
        value = json.loads(raw)
    except (UnicodeError, ValueError):
        raise ValueError('Файл настроек TypeTune повреждён') from None
    return _migrate(value)


@contextlib.contextmanager
def locked(path=PATH):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix('.lock').open('a') as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        yield


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as file:
            temporary = Path(file.name)
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        temporary.replace(path)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def update(changes, path=PATH, apply=None, expected=None):
    """Apply a mutation. `expected` is the generation UUID for optimistic ACK."""
    unknown = set(changes) - UPDATABLE
    if unknown:
        raise ValueError('Unsupported settings change')
    if 'mode' in changes and changes['mode'] != 'compatibility':
        raise ValueError('Unknown mode')
    for key in BOOL_KEYS:
        if key in changes and key != 'autostart' and type(changes[key]) is not bool:
            raise ValueError(f'Invalid {key} state')
    if 'learn_threshold' in changes and (type(changes['learn_threshold']) is not int or not 1 <= changes['learn_threshold'] <= 10):
        raise ValueError('Порог предложений: целое число от 1 до 10')
    if 'active_keyboards' in changes:
        boards = changes['active_keyboards']
        if (not isinstance(boards, list) or len(boards) > 16
                or any(not isinstance(x, str) or not x or len(x) > 32 or any(c.isspace() for c in x) for x in boards)):
            raise ValueError('Активные раскладки: список идентификаторов xkb')
    with locked(path):
        value = load(path)
        if expected is not None and value.get('generation') != expected:
            raise ValueError('Настройки изменены другим окном; обновите данные')
        next_value = dict(value)
        next_value.update(changes)
        if next_value.get('switch_only_last_word') and next_value.get('dont_switch_words'):
            raise ValueError('Нельзя одновременно: «Переключать только последнее слово» и «Не переключать слова»')
        next_value['version'] = 2
        next_value['generation'] = uuid.uuid4().hex
        _validate(next_value)
        atomic(path, json.dumps(next_value, ensure_ascii=False, indent=2) + '\n')
        if apply is not None:
            apply(next_value)
        return next_value


def launcher(controller):
    argument = str(controller).replace('\\', '\\\\\\\\').replace('"', '\\\\"').replace('`', '\\\\`').replace('$', '\\\\$').replace('%', '%%')
    return ('[Desktop Entry]\nType=Application\nName=TypeTune\n'
            f'Exec=/usr/bin/python3 "{argument}" autostart\n' +
            ('TryExec=/usr/bin/typetune-preview\n' if (controller.parent / 'package.json').is_file() else '') +
            'Icon=input-keyboard\nTerminal=false\nOnlyShowIn=GNOME;\n'
            'X-GNOME-Autostart-enabled=true\n')


def set_autostart(enabled, controller, path=PATH, entry=AUTOSTART):
    with locked(path):
        value = load(path)
        if enabled:
            if not controller.is_file():
                raise ValueError('Сначала установите TypeTune')
            previous = entry.read_text() if entry.exists() else None
            atomic(entry, launcher(controller))
            try:
                value['autostart'] = True
                value['generation'] = uuid.uuid4().hex
                atomic(path, json.dumps(value, ensure_ascii=False, indent=2) + '\n')
            except Exception:
                if previous is None:
                    entry.unlink(missing_ok=True)
                else:
                    atomic(entry, previous)
                raise
        else:
            # The startup command rechecks this flag, even if entry removal fails.
            value['autostart'] = False
            value['generation'] = uuid.uuid4().hex
            atomic(path, json.dumps(value, ensure_ascii=False, indent=2) + '\n')
            entry.unlink(missing_ok=True)
        return value


def effective(controller):
    value = load()
    entry_matches = AUTOSTART.is_file() and AUTOSTART.read_text() == launcher(controller)
    value['autostart_effective'] = value['autostart'] and entry_matches
    value['autostart_mismatch'] = value['autostart'] and not entry_matches
    return value


def initial_automatic():
    try:
        return load()['automatic']
    except (ValueError, OSError):
        return False
