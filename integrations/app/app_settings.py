"""Persistent controller settings and explicit XDG login launcher."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import tempfile

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config')))
PATH = CONFIG/'typetune/settings.json'
AUTOSTART = CONFIG/'autostart/dev.kartamyshev.TypeTune.Preview.desktop'
DEFAULT = dict(version=1, mode='compatibility', automatic=True, autostart=False)


def load(path=PATH):
    if not path.exists(): return dict(DEFAULT)
    with path.open('rb') as file: raw=file.read(4097)
    if len(raw)>4096: raise ValueError('Файл настроек слишком большой')
    try: value=json.loads(raw)
    except (UnicodeError,ValueError): raise ValueError('Файл настроек TypeTune повреждён') from None
    if not isinstance(value,dict) or set(value)!=set(DEFAULT) or type(value['version']) is not int or value['version']!=1 or value['mode'] not in ('compatibility','ibus') or any(type(value[k]) is not bool for k in ('automatic','autostart')):
        raise ValueError('Неверный формат настроек TypeTune')
    value['mode']='compatibility'  # Read legacy v1 settings without enabling another adapter.
    return value


@contextlib.contextmanager
def locked(path=PATH):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.with_suffix('.lock').open('a') as file:
        fcntl.flock(file,fcntl.LOCK_EX)
        yield


def atomic(path, text):
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,delete=False) as file:
            temporary=Path(file.name);file.write(text);file.flush();os.fsync(file.fileno())
        temporary.replace(path)
    finally:
        if temporary:temporary.unlink(missing_ok=True)


def update(changes, path=PATH, apply=None):
    if set(changes)-{'mode','automatic'}: raise ValueError('Unsupported settings change')
    if 'mode' in changes and changes['mode'] != 'compatibility':raise ValueError('Unknown mode')
    if 'automatic' in changes and type(changes['automatic']) is not bool:raise ValueError('Invalid automatic state')
    with locked(path):
        value=load(path);value.update(changes)
        atomic(path,json.dumps(value,ensure_ascii=False,indent=2)+'\n')
        if apply is not None: apply(value)
        return value


def launcher(controller):
    argument=str(controller).replace('\\','\\\\\\\\').replace('"','\\\\"').replace('`','\\\\`').replace('$','\\\\$').replace('%','%%')
    return ('[Desktop Entry]\nType=Application\nName=TypeTune\n'
            f'Exec=/usr/bin/python3 "{argument}" autostart\n' +
            ('TryExec=/usr/bin/typetune-preview\n' if (controller.parent/'package.json').is_file() else '') +
            'Icon=input-keyboard\nTerminal=false\nOnlyShowIn=GNOME;\n'
            'X-GNOME-Autostart-enabled=true\n')


def set_autostart(enabled, controller, path=PATH, entry=AUTOSTART):
    with locked(path):
        value=load(path)
        if enabled:
            if not controller.is_file():raise ValueError('Сначала установите TypeTune')
            previous=entry.read_text() if entry.exists() else None
            atomic(entry,launcher(controller))
            try:
                value['autostart']=True
                atomic(path,json.dumps(value,indent=2)+'\n')
            except Exception:
                if previous is None:entry.unlink(missing_ok=True)
                else:atomic(entry,previous)
                raise
        else:
            # The startup command rechecks this flag, even if entry removal fails.
            value['autostart']=False
            atomic(path,json.dumps(value,indent=2)+'\n')
            entry.unlink(missing_ok=True)
        return value


def effective(controller):
    value=load()
    entry_matches=AUTOSTART.is_file() and AUTOSTART.read_text()==launcher(controller)
    value['autostart_effective']=value['autostart'] and entry_matches
    value['autostart_mismatch']=value['autostart'] and not entry_matches
    return value


def initial_automatic():
    try:return load()['automatic']
    except (ValueError,OSError):return False
