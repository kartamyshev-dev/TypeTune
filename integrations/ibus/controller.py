#!/usr/bin/python3
"""Single user-facing controller for the experimental IBus session runtime."""
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
from xml.sax.saxutils import escape
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

UUID = 'typetune-session@typetune.local'
SOURCE = ('ibus', 'typetune-test')
RU_SOURCE = ('ibus', 'typetune-test-ru')
SOURCES = (SOURCE, RU_SOURCE)
DATA = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
PACKAGE = DATA / 'typetune-test'
COMPONENT = DATA / 'ibus/component/typetune-test.xml'
EXTENSION = DATA / 'gnome-shell/extensions' / UUID
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
ENVIRONMENT = CONFIG / 'environment.d/90-typetune-ibus.conf'
FILES = ('runtime_engine.py', 'probe_engine.py', 'session_guard.py', 'manual.py', 'controller.py', 'test-page.html', 'gesture.py', 'editor_guard.py')


def call(name, path, interface, method, parameters=None, timeout=1000):
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    return connection.call_sync(name, path, interface, method, parameters, None,
                                Gio.DBusCallFlags.NONE, timeout, None).unpack()


def bridge(method='GetTextContext'):
    result = call('org.gnome.Shell', '/org/typetune/Session1', 'org.typetune.Session1', method)
    return json.loads(result[0]) if method == 'GetTextContext' else result[0]


def control(method='GetStatus', enabled=None):
    params = None if enabled is None else GLib.Variant('(b)', (enabled,))
    result = call('org.typetune.IBus', '/org/typetune/IBus1', 'org.typetune.IBus1', method, params)
    return json.loads(result[0]) if method == 'GetStatus' else (result[0] if result else None)


def sources():
    return Gio.Settings.new('org.gnome.desktop.input-sources')


def install(repo):
    if repo is None or not (repo / 'Cargo.toml').is_file():
        raise RuntimeError('Установку запускайте из checkout: ./scripts/typetune-test install')
    if (EXTENSION.exists() or ENVIRONMENT.exists()) and not (PACKAGE / 'installed.json').exists():
        raise RuntimeError('Расширение TypeTune уже существует вне этой установки; файлы сохранены.')
    subprocess.run(['cargo', 'build', '-p', 'typetune-ibus', '--release', '--offline'], cwd=repo, check=True)
    subprocess.run(['cargo','build','-p','typetune-cli','--example','compat_transport','--release','--offline'],cwd=repo,check=True)
    PACKAGE.mkdir(parents=True, exist_ok=True)
    # Atomic replacement keeps a loaded shared library's old inode intact.
    for name, source in [(name, repo / 'integrations/ibus' / name) for name in FILES] + [
            ('libtypetune_ibus.so', repo / 'target/release/libtypetune_ibus.so')]:
        with tempfile.NamedTemporaryFile(dir=PACKAGE, delete=False) as temp:
            temporary = Path(temp.name)
        try:
            shutil.copy2(source, temporary)
            temporary.replace(PACKAGE / name)
        finally:
            temporary.unlink(missing_ok=True)
    shutil.copytree(repo / 'integrations/compat', PACKAGE / 'compat', dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__','test_*'))
    shutil.copy2(repo / 'target/release/examples/compat_transport', PACKAGE / 'compat/compat_transport')
    shutil.copytree(repo / 'integrations/gnome' / UUID, EXTENSION, dirs_exist_ok=True)
    command = '/usr/bin/python3 ' + shlex.quote(str(PACKAGE / 'runtime_engine.py'))
    COMPONENT.parent.mkdir(parents=True, exist_ok=True)
    COMPONENT.write_text(f'''<component>
<name>org.freedesktop.IBus.TypeTuneTest</name><description>TypeTune layout correction preview</description>
<exec>{escape(command)}</exec><version>0.1</version><author>TypeTune</author>
<license>MIT</license><homepage></homepage><textdomain></textdomain>
<engines><engine><name>typetune-test</name><longname>TypeTune — US</longname>
<description>Double Shift correction; automatic correction on Space.</description>
<language>en</language><license>MIT</license><author>TypeTune</author><layout>us</layout>
<symbol>TT EN</symbol></engine>
<engine><name>typetune-test-ru</name><longname>TypeTune — RU</longname>
<description>Double Shift correction; automatic correction on Space.</description>
<language>ru</language><license>MIT</license><author>TypeTune</author><layout>ru</layout>
<symbol>TT RU</symbol></engine></engines></component>''')
    previous_component_path = os.environ.get('IBUS_COMPONENT_PATH')
    component_paths = list(dict.fromkeys([*(previous_component_path or '/usr/share/ibus/component').split(':'), str(COMPONENT.parent)]))
    component_path = ':'.join(component_paths)
    if any(char in component_path for char in ('\n', '\r', '$', '"', '\\')):
        raise RuntimeError('Путь компонентов нельзя записать в environment.d без изменения смысла')
    ENVIRONMENT.parent.mkdir(parents=True, exist_ok=True)
    ENVIRONMENT.write_text('# TypeTune user IBus component discovery; managed by typetune-test\nIBUS_COMPONENT_PATH="' + component_path + '"\n')
    subprocess.run(['ibus', 'write-cache'], env=dict(os.environ, IBUS_COMPONENT_PATH=component_path), check=True)
    if 'TYPETUNE_NESTED_STAND' not in os.environ:
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    shell = Gio.Settings.new('org.gnome.shell')
    enabled = shell.get_strv('enabled-extensions')
    disabled = shell.get_strv('disabled-extensions')
    if UUID not in enabled:
        shell.set_strv('enabled-extensions', enabled + [UUID])
    if UUID in disabled:
        shell.set_strv('disabled-extensions', [x for x in disabled if x != UUID])
    Gio.Settings.sync()
    manifest = PACKAGE / 'installed.json'
    if not manifest.exists():
        manifest.write_text(json.dumps({'extension_was_enabled': UUID in enabled,
                                        'extension_was_disabled': UUID in disabled,
                                        'previous_component_path': previous_component_path}))
    print('Установлено в ' + str(PACKAGE))
    print('После установки или обновления выйдите из сеанса GNOME и войдите снова: Shell и IBus должны загрузить новую версию.')
    print('После входа: ./scripts/typetune-test browser')


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


def compat_start():
    if compat_running():
        compat_control('SetEnabled',True)
        return
    if not (PACKAGE/'compat/compat_transport').is_file():raise RuntimeError('Сначала выполните install')
    try:
        call('org.gnome.Shell','/org/typetune/Session1','org.typetune.Session1','GetCompatContext')
    except GLib.Error as error:raise RuntimeError('Нужен GNOME bridge v4: install и повторный вход') from error
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
            print('Режим максимальной совместимости включён: Double Shift и автокоррекция на пробеле.')
            print('Текст, выделение и пароль не подтверждаются. Для паролей/терминальных команд: pause или compat-off.')
            return
        time.sleep(.1)
    compat_stop()
    raise RuntimeError('Нет готовых физических клавиатур: отпустите клавиши; проверьте права input/uinput')


def start():
    compat_stop()
    # Fail before modifying source settings if the mandatory guard is absent.
    try:
        initial_context = bridge()['snapshot']
    except GLib.Error as error:
        raise RuntimeError('GNOME bridge не загружен. Выполните install, затем выйдите из сеанса и войдите снова.') from error
    import gi
    gi.require_version('IBus', '1.0')
    from gi.repository import IBus
    IBus.init()
    bus = IBus.Bus.new()
    if not bus.is_connected() or not {SOURCE[1], RU_SOURCE[1]}.issubset({e.get_name() for e in bus.list_engines()}):
        raise RuntimeError('IBus ещё не обнаружил TypeTune. После install нужен повторный вход в сеанс.')
    settings = sources()
    before = [tuple(item) for item in settings.get_value('sources').unpack()]
    if any(source not in before for source in SOURCES):
        settings.set_value('sources', GLib.Variant('a(ss)', before + [s for s in SOURCES if s not in before]))
        Gio.Settings.sync()
    deadline = time.monotonic() + 4
    activated = False
    while time.monotonic() < deadline:
        if not activated:
            activated = bridge('ActivateTypeTune')
        state = bridge()['snapshot']
        if (state['source_type'], state['source_id']) == SOURCE:
            try:
                assert control('SetEnabled', True)
                restore = PACKAGE / 'previous-source.json'
                if not restore.exists() and initial_context['source_type'] == 'xkb' and initial_context['source_id'] in ('us', 'ru'):
                    temporary = restore.with_suffix('.tmp')
                    temporary.write_text(json.dumps({'source': initial_context['source_id']}))
                    temporary.replace(restore)
                print('TypeTune включён: двойной Shift исправляет слово и меняет язык дальнейшего ввода.')
                print('Обычный ввод: US. Пауза: ./scripts/typetune-test pause. Остановка: ./scripts/typetune-test stop')
                return
            except GLib.Error:
                pass  # Runtime has not acquired its control name yet.
        time.sleep(.1)
    # Roll back only our entry, preserving edits made by other settings clients.
    if SOURCE not in before:
        remove_source()
    raise RuntimeError('Источник не активировался. Закройте overview/экран блокировки и повторите start; проверьте status.')


def remove_source():
    settings = sources()
    current = settings.get_value('sources').unpack()
    rest = [s for s in current if tuple(s) not in SOURCES]
    if len(rest) != len(current):
        settings.set_value('sources', GLib.Variant('a(ss)', rest or [('xkb', 'us')]))
        Gio.Settings.sync()


def stop():
    compat_stop()
    try:
        before = bridge()['snapshot']
        was_active = (before['source_type'], before['source_id']) in SOURCES
    except GLib.Error:
        was_active = False
    try:
        control('SetEnabled', False)
    except GLib.Error:
        pass
    remove_source()
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            state = bridge()['snapshot']
            if (state['source_type'], state['source_id']) not in SOURCES:
                break
        except GLib.Error:
            break
        time.sleep(.05)
    restore = PACKAGE / 'previous-source.json'
    if restore.exists():
        try:
            previous = json.loads(restore.read_text()).get('source')
            if was_active and previous in ('us', 'ru'):
                state = bridge()['snapshot']
                if state['source_type'] == 'xkb' and state['source_id'] in ('us', 'ru') and state['source_id'] != previous:
                    request = {key: state[key] for key in ('instance', 'generation', 'window')}
                    request['target'] = previous
                    answer = json.loads(call('org.gnome.Shell', '/org/typetune/Session1', 'org.typetune.Session1',
                                             'RequestSource', GLib.Variant('(s)', (json.dumps(request),)))[0])
                    if answer.get('status') in ('requested', 'unchanged'):
                        deadline = time.monotonic() + 1
                        while time.monotonic() < deadline and bridge()['snapshot']['source_id'] != previous:
                            time.sleep(.05)
                    if bridge()['snapshot']['source_id'] != previous:
                        print('Коррекция отключена; прежнюю раскладку ' + previous + ' выберите вручную.')
        except (GLib.Error, ValueError, OSError):
            print('Коррекция отключена; восстановление прежнего источника не подтверждено.')
        restore.unlink(missing_ok=True)
    try:
        control('Quit')
    except GLib.Error:
        pass
    print('TypeTune остановлен; его источник убран, остальные раскладки сохранены.')


def uninstall():
    manifest = PACKAGE / 'installed.json'
    if not manifest.is_file():
        raise RuntimeError('Нет манифеста этой установки; неизвестные файлы не удалены.')
    previous = json.loads(manifest.read_text())
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
    COMPONENT.unlink(missing_ok=True)
    ENVIRONMENT.unlink(missing_ok=True)
    env = os.environ.copy()
    env['IBUS_COMPONENT_PATH'] = previous.get('previous_component_path') or '/usr/share/ibus/component'
    subprocess.run(['ibus', 'write-cache'], env=env, check=True)
    if 'TYPETUNE_NESTED_STAND' not in os.environ:
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    shutil.rmtree(EXTENSION)
    shutil.rmtree(PACKAGE)
    print('Пользовательская установка удалена. Перезагрузка списка IBus завершится при следующем входе.')


def status():
    result = {'installed': (PACKAGE / 'installed.json').exists()}
    result['compatibility'] = compat_control() if compat_running() else 'not-running'
    try:
        state = bridge()['snapshot']
        result['bridge'] = True
        result['source_active'] = (state['source_type'], state['source_id']) in SOURCES
    except GLib.Error:
        result['bridge'] = False
        result['action'] = 'install / logout / login'
    try:
        result['runtime'] = control()
    except GLib.Error:
        result['runtime'] = 'not-running'
    print(json.dumps(result, ensure_ascii=False, indent=2))


def browser():
    if not os.environ.get('WAYLAND_DISPLAY'):
        raise RuntimeError('Команду browser нужно выполнять в терминале вашего Wayland-сеанса.')
    if not (PACKAGE / 'test-page.html').exists():
        raise RuntimeError('Сначала выполните install')
    executable = shutil.which('google-chrome')
    if not executable:
        raise RuntimeError('Нужен установленный Google Chrome; остальные браузеры ещё не приняты')
    try:
        bridge()
    except GLib.Error as error:
        raise RuntimeError('После install выйдите из сеанса GNOME и войдите снова, затем повторите browser.') from error
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'typetune-test/chrome'
    cache.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # Match the tested native Wayland route, not a forced GTK/XIM module.
    for key in ('GTK_IM_MODULE', 'QT_IM_MODULE', 'XMODIFIERS'):
        env.pop(key, None)
    app = subprocess.Popen([executable, '--ozone-platform=wayland', '--gtk-version=3',
                      '--user-data-dir=' + str(cache), '--no-first-run', '--no-default-browser-check',
                      '--password-store=basic', '--new-window', (PACKAGE / 'test-page.html').as_uri()],
                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session='TYPETUNE_NESTED_STAND' not in os.environ)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if app.poll() not in (None, 0):
            raise RuntimeError('Chrome завершился с ошибкой запуска')
        context = bridge()
        if context['app_id'] == 'google-chrome.desktop' and context['snapshot']['window_backend'] == 'wayland':
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Окно Chrome не прошло проверку профиля. Выполните status; коррекция остаётся запрещена.')
    start()
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if control()['available']:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('IBus не подтвердил профиль Chrome; проверьте status.')
    print('Открыта локальная страница проверки в отдельном профиле Chrome.')


def main():
    parser = argparse.ArgumentParser(description='TypeTune: коррекция раскладки через IBus (GNOME 50 / Wayland)')
    parser.add_argument('command', choices=['install', 'start', 'pause', 'resume', 'stop', 'status', 'uninstall', 'browser', 'auto-on', 'auto-off', 'compat-on', 'compat-off'])
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    try:
        if args.command == 'install': install(repo)
        elif args.command == 'compat-on': compat_start()
        elif args.command == 'compat-off': compat_stop(); print('Режим совместимости выключен.')
        elif args.command == 'start': start()
        elif args.command == 'browser': browser()
        elif args.command in ('pause', 'resume'):
            enabled = args.command == 'resume'
            if (compat_control if compat_running() else control)('SetEnabled', enabled) != enabled:
                raise RuntimeError('Runtime не подтвердил настройку')
            print('Коррекция включена.' if enabled else 'Коррекция на паузе; обычный ввод продолжается.')
        elif args.command in ('auto-on', 'auto-off'):
            enabled = args.command == 'auto-on'
            if (compat_control if compat_running() else control)('SetAutomatic', enabled) != enabled:
                raise RuntimeError('Runtime не подтвердил автокоррекцию')
            print('Автокоррекция включена.' if enabled else 'Автокоррекция выключена.')
        elif args.command == 'stop': stop()
        elif args.command == 'uninstall': uninstall()
        else: status()
    except (RuntimeError, GLib.Error, subprocess.CalledProcessError, OSError) as error:
        print('TypeTune: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
