"""Bounded, versioned user dictionaries; disk access only at load/apply boundaries."""
import json
import os
from pathlib import Path
import tempfile
import uuid
import fcntl

ROOT = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'typetune'
PATH = ROOT / 'words.json'
LIMIT = 131072
CURRENT = {'version': 1, 'generation': '0', 'words': [], 'exclusions': []}
ERROR = None


def validate(value):
    if not isinstance(value, dict) or set(value) != {'version','generation','words','exclusions'}:
        raise ValueError('Неверный формат пользовательского словаря')
    if type(value['version']) is not int or value['version'] != 1 or not isinstance(value['generation'], str) or not 1 <= len(value['generation']) <= 64:
        raise ValueError('Неподдерживаемая версия словаря')
    result = dict(version=1, generation=value['generation'])
    for key in ('words', 'exclusions'):
        entries = value[key]
        if not isinstance(entries, list) or len(entries) > 500:
            raise ValueError('Допускается не более 500 записей в каждом списке')
        normalized = set()
        for entry in entries:
            if not isinstance(entry,str): raise ValueError('Запись должна быть словом')
            word = entry.strip().lower()
            if not 2 <= len(word) <= 32 or not (all('a' <= c <= 'z' for c in word) or all('а' <= c <= 'я' or c == 'ё' for c in word)):
                raise ValueError('Введите слова из 2–32 букв, отдельно RU или EN, по одному на строку')
            normalized.add(word)
        result[key] = sorted(normalized)
    return result


def load(path=PATH):
    if not path.exists(): return dict(version=1, generation='0', words=[], exclusions=[])
    with path.open('rb') as file: raw=file.read(LIMIT+1)
    if len(raw)>LIMIT: raise ValueError('Файл словаря слишком большой')
    try: return validate(json.loads(raw))
    except (UnicodeError, json.JSONDecodeError): raise ValueError('Файл пользовательского словаря повреждён') from None


def initialize():
    global CURRENT, ERROR
    try: CURRENT=load(); ERROR=None
    except (ValueError,OSError): ERROR='Не удалось загрузить пользовательский словарь; автокоррекция отключена'


def reload(expected):
    global CURRENT, ERROR
    value=load()
    if value['generation'] != expected: raise ValueError('Словарь изменён другим окном; обновите данные')
    CURRENT=value; ERROR=None
    return expected


def save(value, expected, path=PATH):
    value=validate(value)
    path.parent.mkdir(parents=True,exist_ok=True)
    with (path.parent/'words.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if load(path)['generation'] != expected:
            raise ValueError('Словарь изменён другим окном. Закройте редактор и откройте снова')
        value['generation']=uuid.uuid4().hex
        temporary=None
        try:
            with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,delete=False) as file:
                temporary=Path(file.name)
                json.dump(value,file,ensure_ascii=False,indent=2)
                file.flush();os.fsync(file.fileno())
            temporary.replace(path)
        finally:
            if temporary: temporary.unlink(missing_ok=True)
    return value
