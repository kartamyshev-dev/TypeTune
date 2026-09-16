"""Application exclusions for automatic correction; cached outside key callbacks."""
import json
import uuid
import app_settings

PATH = app_settings.CONFIG/'typetune/applications.json'
LIMIT = 131072
CURRENT = dict(version=1, generation='0', excluded=[])
ERROR = None


def valid_id(value):
    return (isinstance(value, str) and 8 < len(value) <= 255 and value.endswith('.desktop')
            and not any(c.isspace() or ord(c) < 32 or c in '/\\' for c in value))


def validate(value):
    if (not isinstance(value, dict) or set(value) != {'version', 'generation', 'excluded'}
            or type(value['version']) is not int or value['version'] != 1
            or not isinstance(value['generation'], str) or not 1 <= len(value['generation']) <= 64
            or not isinstance(value['excluded'], list) or len(value['excluded']) > 500
            or not all(valid_id(entry) for entry in value['excluded'])):
        raise ValueError('Неверный список приложений: допустимо до 500 идентификаторов .desktop')
    return dict(version=1, generation=value['generation'], excluded=sorted(set(value['excluded'])))


def load(path=PATH):
    if not path.exists(): return dict(version=1, generation='0', excluded=[])
    with path.open('rb') as file: raw=file.read(LIMIT+1)
    if len(raw)>LIMIT: raise ValueError('Список приложений слишком большой')
    try: return validate(json.loads(raw))
    except (UnicodeError, json.JSONDecodeError): raise ValueError('Список приложений повреждён') from None


def save(value, expected, path=PATH):
    value=validate(value)
    with app_settings.locked(path):
        if load(path)['generation'] != expected:
            raise ValueError('Список изменён другим окном. Закройте редактор и откройте снова')
        value['generation']=uuid.uuid4().hex
        app_settings.atomic(path,json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    return value


def initialize():
    global CURRENT, ERROR
    try: CURRENT=load(); ERROR=None
    except (ValueError,OSError): ERROR='Не удалось загрузить исключения приложений; автокоррекция отключена'


def reload(expected):
    global CURRENT, ERROR
    value=load()
    if value['generation'] != expected: raise ValueError('Список приложений изменён; откройте редактор снова')
    CURRENT=value; ERROR=None
    return expected


def reason(app_id):
    if ERROR: return 'config-error'
    if not CURRENT['excluded']: return None
    if not valid_id(app_id): return 'unknown-application'
    if app_id in CURRENT['excluded']: return 'excluded-application'
    return None


def allows(app_id):
    return reason(app_id) is None


def status(app_id):
    return dict(applications_generation=CURRENT['generation'], applications_error=ERROR,
                application=app_id if valid_id(app_id) else None,
                automatic_blocked=reason(app_id), application_exclusions=len(CURRENT['excluded']))
