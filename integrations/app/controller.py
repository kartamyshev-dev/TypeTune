#!/usr/bin/python3
"""Single user-facing controller for the GNOME compatibility runtime."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

UUID = 'typetune-session@typetune.local'
SOURCE = ('ibus', 'typetune-test')
RU_SOURCE = ('ibus', 'typetune-test-ru')
SOURCES = (SOURCE, RU_SOURCE)
DATA = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
STATE = DATA / 'typetune-test'
HERE = Path(__file__).resolve().parent
PACKAGED = (HERE/'package.json').is_file()
PACKAGE = HERE if PACKAGED else STATE
COMPONENT = DATA / 'ibus/component/typetune-test.xml'
EXTENSION = DATA / 'gnome-shell/extensions' / UUID
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
ENVIRONMENT = CONFIG / 'environment.d/90-typetune-ibus.conf'
DESKTOP = DATA / 'applications/dev.kartamyshev.TypeTune.Preview.desktop'
FILES = ('correction_feedback.py', 'suggestion_editor.py', 'application_rules.py', 'application_editor.py', 'app_settings.py', 'preferences.py', 'word_editor.py', 'tray.py', 'gui.py', 'gui_model.py', 'controller.py', 'test-page.html', 'gesture.py')


def call(name, path, interface, method, parameters=None, timeout=1000):
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    return connection.call_sync(name, path, interface, method, parameters, None,
                                Gio.DBusCallFlags.NONE, timeout, None).unpack()


def bridge(method='GetTextContext'):
    result = call('org.gnome.Shell', '/org/typetune/Session1', 'org.typetune.Session1', method)
    return json.loads(result[0]) if method == 'GetTextContext' else result[0]




def sources():
    return Gio.Settings.new('org.gnome.desktop.input-sources')


def install(repo):
    if PACKAGED:raise RuntimeError('Обновите TypeTune через пакет .deb')
    if repo is None or not (repo / 'Cargo.toml').is_file():
        raise RuntimeError('Установку запускайте из checkout: ./scripts/typetune-test install')
    if (EXTENSION.exists() or ENVIRONMENT.exists()) and not (STATE / 'installed.json').exists():
        raise RuntimeError('Расширение TypeTune уже существует вне этой установки; файлы сохранены.')
    subprocess.run(['cargo', 'build', '-p', 'typetune-bridge', '--release', '--offline'], cwd=repo, check=True)
    subprocess.run(['cargo','build','-p','typetune-cli','--example','compat_transport','--release','--offline'],cwd=repo,check=True)
    PACKAGE.mkdir(parents=True, exist_ok=True)
    # Atomic replacement keeps a loaded shared library's old inode intact.
    for name, source in [(name, repo / 'integrations/app' / name) for name in FILES] + [
            ('libtypetune_bridge.so', repo / 'target/release/libtypetune_bridge.so')]:
        with tempfile.NamedTemporaryFile(dir=PACKAGE, delete=False) as temp:
            temporary = Path(temp.name)
        try:
            shutil.copy2(source, temporary)
            temporary.replace(PACKAGE / name)
        finally:
            temporary.unlink(missing_ok=True)
    shutil.copytree(repo / 'crates/typetune-engine/data/frequency', PACKAGE / 'licenses/frequencywords', dirs_exist_ok=True)
    shutil.copytree(repo / 'integrations/compat', PACKAGE / 'compat', dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__','test_*'))
    shutil.copy2(repo / 'target/release/examples/compat_transport', PACKAGE / 'compat/compat_transport')
    shutil.copytree(repo / 'integrations/gnome' / UUID, EXTENSION, dirs_exist_ok=True)
    register_user()


def register_user():
    STATE.mkdir(parents=True,exist_ok=True)
    cleanup_legacy_registration()
    shell = Gio.Settings.new('org.gnome.shell')
    enabled = shell.get_strv('enabled-extensions')
    disabled = shell.get_strv('disabled-extensions')
    if UUID not in enabled:
        shell.set_strv('enabled-extensions', enabled + [UUID])
    if UUID in disabled:
        shell.set_strv('disabled-extensions', [x for x in disabled if x != UUID])
    Gio.Settings.sync()
    manifest = STATE / 'installed.json'
    metadata=json.loads(manifest.read_text()) if manifest.exists() else dict(extension_was_enabled=UUID in enabled,extension_was_disabled=UUID in disabled,previous_component_path=None)
    if PACKAGED:metadata['package_version']=json.loads((PACKAGE/'package.json').read_text())['version']
    manifest.write_text(json.dumps(metadata))
    DESKTOP.parent.mkdir(parents=True, exist_ok=True)
    gui_path = str(PACKAGE / ('package_launcher.py' if PACKAGED else 'gui.py')).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
    DESKTOP.write_text('[Desktop Entry]\nType=Application\nName=TypeTune\nComment=Переключение раскладки RU/EN\n'
                       + 'Exec=/usr/bin/python3 "' + gui_path + '"\nIcon=input-keyboard\nTerminal=false\n'
                       + 'Categories=Utility;Accessibility;\nStartupNotify=true\n'
                       + 'StartupWMClass=dev.kartamyshev.TypeTune.Preview\n')
    if PACKAGED:
        with DESKTOP.open('a') as desktop:
            desktop.write('TryExec=/usr/bin/typetune-preview\nActions=Setup;\n\n[Desktop Action Setup]\nName=Настроить доступ и сеанс\nExec=/usr/bin/python3 "'+gui_path+'" --setup\n')
    print('Установлено в ' + str(PACKAGE))
    print('После установки или обновления выйдите из сеанса GNOME и войдите снова: Shell должен загрузить новую версию.')
    print('После входа откройте TypeTune из меню приложений.' if PACKAGED else 'После входа: ./scripts/typetune-test start')


def stop_gui():
    # Only this user's known Python GUI processes; no broad process-name matching.
    import signal
    targets={str(STATE/'gui.py'),str(PACKAGE/'gui.py')}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdecimal():continue
        try:
            if entry.stat().st_uid!=os.getuid():continue
            args=(entry/'cmdline').read_bytes().split(b'\0')
            if len(args)>1 and args[0]==b'/usr/bin/python3' and args[1].decode(errors='replace') in targets:
                os.kill(int(entry.name),signal.SIGTERM)
        except (OSError,ProcessLookupError):continue


def configure_package():
    if not PACKAGED:raise RuntimeError('Команда доступна только в установленном пакете')
    if os.getuid()==0:raise RuntimeError('Откройте TypeTune от обычного пользователя')
    if (EXTENSION.exists() or ENVIRONMENT.exists()) and not (STATE/'installed.json').exists():
        raise RuntimeError('Обнаружена другая установка расширения. Её файлы сохранены.')
    stop();stop_gui()
    shutil.copytree(PACKAGE/'gnome'/UUID,EXTENSION,dirs_exist_ok=True)
    register_user()
    import app_settings
    if app_settings.load()['autostart']:
        app_settings.set_autostart(True,PACKAGE/'controller.py')


def package_lifecycle(remove=False):
    manifest=STATE/'installed.json'
    if not manifest.exists() or 'package_version' not in json.loads(manifest.read_text()):return
    stop_gui()
    if remove:uninstall()
    else:stop()


def compat_control(method='GetStatus', enabled=None):
    params=None if enabled is None else GLib.Variant('(b)',(enabled,))
    result=call('org.typetune.Compat','/org/typetune/Compat1','org.typetune.Compat1',method,params)
    return json.loads(result[0]) if method=='GetStatus' else (result[0] if result else None)


def compat_running():
    try:compat_control();return True
    except GLib.Error:return False


def compat_stop():
    if compat_running():
        compat_control('Quit')
        deadline=time.monotonic()+3
        while time.monotonic()<deadline and compat_running():time.sleep(.05)
        if compat_running():raise RuntimeError('Режим совместимости не подтвердил остановку')


def active_runtime_control():
    connection = Gio.bus_get_sync(Gio.BusType.SESSION,None)
    for name, runtime in [('org.typetune.Compat',compat_control)]:
        owned = connection.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus',
            'org.freedesktop.DBus','NameHasOwner',GLib.Variant('(s)',(name,)),None,
            Gio.DBusCallFlags.NONE,1000,None).unpack()[0]
        if owned: return runtime
    return None


def login_marker():
    return Path(os.environ.get('XDG_RUNTIME_DIR',str(CONFIG/'typetune'))) / 'typetune-login-cancel'


def apply_saved_automatic(runtime):
    import app_settings
    with app_settings.locked():
        automatic = app_settings.load()['automatic']
        if runtime('SetAutomatic',automatic) != automatic:
            raise RuntimeError('Runtime не подтвердил сохранённую автокоррекцию')


def compat_start():
    import app_settings
    app_settings.load()  # Validate before starting or changing any source.
    if compat_running():
        compat_control('SetEnabled',True)
        apply_saved_automatic(compat_control)
        app_settings.update({'mode':'compatibility'})
        return
    if not (PACKAGE/'compat/compat_transport').is_file():raise RuntimeError('Сначала выполните install')
    try:
        call('org.gnome.Shell','/org/typetune/Session1','org.typetune.Session1','GetCompatContext')
    except GLib.Error as error:raise RuntimeError('Нужен GNOME bridge TypeTune: install и повторный вход') from error
    stop()  # One active correction executor; return to ordinary XKB sources.
    settings=sources();before=[tuple(s) for s in settings.get_value('sources').unpack()]
    required=[('xkb','us'),('xkb','ru')]
    if any(s not in before for s in required):
        settings.set_value('sources',GLib.Variant('a(ss)',before+[s for s in required if s not in before]));Gio.Settings.sync()
    process=subprocess.Popen(['/usr/bin/python3',str(PACKAGE/'compat/runtime.py')],stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        if process.poll() is not None:raise RuntimeError('Compatibility runtime завершился; проверьте доступ к /dev/input и /dev/uinput')
        if compat_running() and compat_control()['devices']>0:
            apply_saved_automatic(compat_control)
            app_settings.update({'mode':'compatibility'})
            print('Режим максимальной совместимости включён. Double Shift доступен; сохранённая настройка автокоррекции восстановлена.')
            print('Текст, выделение и пароль не подтверждаются. Для паролей/терминальных команд: pause или compat-off.')
            return
        time.sleep(.1)
    compat_stop()
    raise RuntimeError('Нет готовых физических клавиатур: отпустите клавиши; проверьте права input/uinput')




def remove_source():
    settings = sources()
    current = settings.get_value('sources').unpack()
    rest = [s for s in current if tuple(s) not in SOURCES]
    if len(rest) != len(current):
        settings.set_value('sources', GLib.Variant('a(ss)', rest or [('xkb', 'us')]))
        Gio.Settings.sync()


def cleanup_legacy_registration():
    """Remove only this product's old registrations, never other IBus engines."""
    if not (STATE/'installed.json').is_file():return
    try:
        call('org.typetune.IBus','/org/typetune/IBus1','org.typetune.IBus1','Quit')
    except GLib.Error:pass
    remove_source()
    COMPONENT.unlink(missing_ok=True)
    ENVIRONMENT.unlink(missing_ok=True)
    (STATE/'previous-source.json').unlink(missing_ok=True)
    for name in ('runtime_engine.py','probe_engine.py','manual.py','session_guard.py','editor_guard.py','libtypetune_ibus.so'):
        (STATE/name).unlink(missing_ok=True)
    if 'TYPETUNE_NESTED_STAND' not in os.environ:
        subprocess.run(['systemctl','--user','daemon-reload'],check=True)


def stop():
    compat_stop()
    cleanup_legacy_registration()
    print('TypeTune остановлен; обычный ввод продолжается.')


def uninstall():
    manifest = STATE / 'installed.json'
    if not manifest.is_file():
        raise RuntimeError('Нет манифеста этой установки; неизвестные файлы не удалены.')
    previous = json.loads(manifest.read_text())
    import app_settings
    app_settings.AUTOSTART.unlink(missing_ok=True)
    stop()
    shell = Gio.Settings.new('org.gnome.shell')
    enabled = shell.get_strv('enabled-extensions')
    if not previous['extension_was_enabled']:
        shell.set_strv('enabled-extensions', [x for x in enabled if x != UUID])
    if previous['extension_was_disabled']:
        values = shell.get_strv('disabled-extensions')
        if UUID not in values:
            shell.set_strv('disabled-extensions', values + [UUID])
    Gio.Settings.sync()
    DESKTOP.unlink(missing_ok=True)
    COMPONENT.unlink(missing_ok=True)
    ENVIRONMENT.unlink(missing_ok=True)
    if EXTENSION.exists():shutil.rmtree(EXTENSION)
    if STATE.exists():shutil.rmtree(STATE)
    print('Пользовательская установка удалена. Настройки сохранены.')


def status():
    result = {'installed': (STATE / 'installed.json').exists()}
    import app_settings
    try: result['settings'] = app_settings.effective(PACKAGE/'controller.py')
    except (ValueError,OSError) as error: result['settings_error'] = str(error)
    result['compatibility'] = compat_control() if compat_running() else 'not-running'
    try:
        state = bridge()['snapshot']
        result['bridge'] = True
        result['source_active'] = (state['source_type'], state['source_id']) in SOURCES
    except GLib.Error:
        result['bridge'] = False
        result['action'] = 'install / logout / login'
    print(json.dumps(result, ensure_ascii=False, indent=2))




def login_start():
    """XDG login entry: bounded wait for GNOME; no backend retries after edits."""
    import app_settings
    import fcntl
    lock_path = Path(os.environ.get('XDG_RUNTIME_DIR',str(CONFIG/'typetune'))) / 'typetune-login.lock'
    lock_path.parent.mkdir(parents=True,exist_ok=True)
    with lock_path.open('a') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: return 0
        marker=login_marker()
        stamp=marker.stat().st_mtime_ns if marker.exists() else None
        deadline = time.monotonic()+45
        while time.monotonic()<deadline:
            settings=app_settings.load()
            if not settings['autostart']:return 0
            if (marker.stat().st_mtime_ns if marker.exists() else None) != stamp:return 0
            try:
                snapshot=bridge()['snapshot']
                ready=all(snapshot.get(key) is False for key in ('locked','shield_active','overview')) and snapshot.get('user_session') is True
            except GLib.Error:ready=False
            if ready:
                if active_runtime_control() is None:
                    compat_start()
                subprocess.Popen(['/usr/bin/python3',str(PACKAGE/'gui.py'),'--background'],
                    stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
                return 0
            time.sleep(1)
        # Show actionable status if GNOME or the bridge did not become ready.
        subprocess.Popen(['/usr/bin/python3',str(PACKAGE/'gui.py')],
            stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        raise RuntimeError('Автозапуск: GNOME bridge не готов; откройте состояние TypeTune')


def application_catalog():
    import application_rules
    entries = {}
    for app in Gio.AppInfo.get_all():
        identifier = app.get_id()
        if application_rules.valid_id(identifier):
            entries[identifier] = dict(id=identifier, name=app.get_display_name() or identifier)
    return sorted(entries.values(), key=lambda item: (item['name'].casefold(), item['id']))


def user_words(command):
    if command.startswith('apps-'):
        import application_rules as preferences
        method, field = 'ReloadApplications', 'applications_generation'
    else:
        import preferences
        method, field = 'ReloadWords', 'words_generation'
    if command.endswith('-get'):
        document = preferences.load()
        result = dict(document=document, catalog=application_catalog()) if command=='apps-get' else document
        print(json.dumps(result, ensure_ascii=False))
        return
    payload = sys.stdin.read(preferences.LIMIT + 1)
    if len(payload.encode('utf-8')) > preferences.LIMIT:
        raise ValueError('Слишком много данных')
    value = json.loads(payload)
    result=save_list(value,preferences,method,field)
    print(json.dumps(result,ensure_ascii=False))


def save_list(value, preferences, method, field):
    saved = preferences.save(value, value['generation'])
    applied = []
    errors = []
    for name, path, interface in [
        ('org.typetune.Compat','/org/typetune/Compat1','org.typetune.Compat1')]:
        try:
            connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            exists = connection.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus',
                'org.freedesktop.DBus','NameHasOwner',GLib.Variant('(s)',(name,)),None,
                Gio.DBusCallFlags.NONE,1000,None).unpack()[0]
            if not exists: continue
            result = call(name,path,interface,method,GLib.Variant('(s)',(saved['generation'],)))
            effective = json.loads(call(name,path,interface,'GetStatus')[0])
            if result[0] != saved['generation'] or effective.get(field) != saved['generation']:
                raise RuntimeError('Runtime не подтвердил применение')
            applied.append(name)
        except (RuntimeError,GLib.Error) as error:
            errors.append('Сохранено, но не применено. Перезапустите режим коррекции')
    return dict(document=saved, applied=bool(applied) and not errors,
        message=errors[0] if errors else ('Сохранено и применено' if applied else 'Сохранено. Применится при запуске коррекции'),
        error=bool(errors))


SUGGESTION_BACKENDS = {
    'compatibility': ('org.typetune.Compat','/org/typetune/Compat1','org.typetune.Compat1'),
}


def suggestions(command):
    if command == 'suggestions-get':
        entries=[]
        for backend, endpoint in SUGGESTION_BACKENDS.items():
            try: values=json.loads(call(*endpoint,'GetSuggestions')[0])
            except GLib.Error:continue
            entries.extend(dict(value,backend=backend) for value in values)
        return dict(proposals=entries)
    raw=sys.stdin.read(2049)
    if len(raw)>2048:raise ValueError('Слишком много данных')
    value=json.loads(raw)
    if not isinstance(value,dict) or set(value)!={'id','backend','action'} or value['backend'] not in SUGGESTION_BACKENDS or value['action'] not in ('accept','dismiss'):
        raise ValueError('Неверная команда предложения')
    endpoint=SUGGESTION_BACKENDS[value['backend']]
    proposals=json.loads(call(*endpoint,'GetSuggestions')[0])
    selected=next((p for p in proposals if p['id']==value['id']),None)
    if selected is None:raise ValueError('Предложение устарело. Обновите список')
    if value['action']=='accept':
        import preferences
        document=preferences.load()
        field='words' if selected.get('kind')=='word' else 'exclusions'
        if field=='words' and any(w in document['exclusions'] for w in (selected['source'],selected['word'])):
            raise ValueError('Слово уже исключено. Сначала измените «Слова и исключения»')
        if selected['word'] not in document[field]:
            document[field].append(selected['word'])
        result=save_list(document,preferences,'ReloadWords','words_generation')
        if result['error']:return dict(error=True,message=result['message'])
    try:
        acknowledged=call(*endpoint,'DismissSuggestion',GLib.Variant('(s)',(value['id'],)))[0]
        if acknowledged is not True:raise RuntimeError('Не подтверждено')
    except (GLib.Error,RuntimeError):
        return dict(error=True,message='Изменение сохранено; обновите список предложений.' if value['action']=='accept' else 'Отклонение не подтверждено. Обновите список.')
    return dict(error=False,message='Добавлено в «Слова и исключения».' if value['action']=='accept' else 'Предложение отклонено до перезапуска TypeTune.')


def main():
    parser = argparse.ArgumentParser(description='TypeTune: общесистемная коррекция раскладки (GNOME 50 / Wayland)')
    parser.add_argument('command', choices=['package-configure', 'package-stop', 'package-remove', 'install', 'start', 'pause', 'resume', 'stop', 'status', 'uninstall', 'auto-on', 'auto-off', 'compat-on', 'compat-off', 'gui', 'words-get', 'words-save', 'apps-get', 'apps-save', 'suggestions-get', 'suggestions-resolve', 'autostart-on', 'autostart-off', 'autostart'])
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    try:
        if args.command=='package-configure':configure_package()
        elif args.command in ('package-stop','package-remove'):package_lifecycle(args.command=='package-remove')
        elif args.command in ('suggestions-get','suggestions-resolve'):
            print(json.dumps(suggestions(args.command),ensure_ascii=False))
        elif args.command == 'autostart': return login_start()
        elif args.command in ('autostart-on','autostart-off'):
            import app_settings
            app_settings.set_autostart(args.command=='autostart-on',PACKAGE/'controller.py')
        elif args.command in ('words-get', 'words-save', 'apps-get', 'apps-save'): user_words(args.command)
        elif args.command == 'gui':
            from gui import main as gui_main
            return gui_main()
        elif args.command == 'install': install(repo)
        elif args.command == 'compat-on': compat_start()
        elif args.command == 'compat-off': compat_stop(); print('Режим совместимости выключен.')
        elif args.command == 'start': compat_start()
        elif args.command in ('pause', 'resume'):
            enabled = args.command == 'resume'
            if compat_control('SetEnabled', enabled) != enabled:
                raise RuntimeError('Runtime не подтвердил настройку')
            print('Коррекция включена.' if enabled else 'Коррекция на паузе; обычный ввод продолжается.')
        elif args.command in ('auto-on', 'auto-off'):
            enabled = args.command == 'auto-on'
            import app_settings
            def apply_automatic(value):
                try:
                    runtime = active_runtime_control()
                    if runtime is not None and runtime('SetAutomatic', value['automatic']) != value['automatic']:
                        raise RuntimeError('Runtime не подтвердил настройку')
                except (GLib.Error,RuntimeError) as error:
                    raise RuntimeError('Настройка сохранена, но не применена. Обновите состояние или перезапустите режим.') from error
            app_settings.update({'automatic':enabled},apply=apply_automatic)
            print('Настройка автокоррекции сохранена.')
        elif args.command == 'stop':
            marker=login_marker();marker.parent.mkdir(parents=True,exist_ok=True);marker.touch()
            stop()
        elif args.command == 'uninstall': uninstall()
        else: status()
        if args.command in ('compat-on', 'start') and 'TYPETUNE_NESTED_STAND' not in os.environ:
            gui_path = PACKAGE / 'gui.py'
            if gui_path.exists():
                subprocess.Popen(['/usr/bin/python3', str(gui_path), '--background'],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
    except (ValueError, KeyError, RuntimeError, GLib.Error, subprocess.CalledProcessError, OSError) as error:
        print('TypeTune: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
