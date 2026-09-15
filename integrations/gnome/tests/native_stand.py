#!/usr/bin/env python3
"""Isolated headless GNOME 50 + test GTK windows, never the user's desktop bus."""
import json
import ast
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
import signal

ROOT = Path(__file__).resolve().parents[3]
UUID = 'typetune-session@typetune.local'


def outer():
    runtime_stand = '--runtime-stand' in sys.argv
    ibus_stand = '--ibus-stand' in sys.argv or runtime_stand
    if ibus_stand and any(flag in sys.argv for flag in ('--text-stand', '--editor-stand')):
        raise SystemExit('--ibus-stand runs separately from text/editor stands')
    with tempfile.TemporaryDirectory(prefix='typetune-gnome-') as temp:
        base = Path(temp)
        for name in ('data', 'config', 'runtime', 'cache'):
            (base / name).mkdir(mode=0o700)
        extension_dir = base / 'data/gnome-shell/extensions' / UUID
        if runtime_stand:
            pass  # The real installer supplies the extension below.
        elif '--bundle' in sys.argv:
            extension_dir.mkdir(parents=True)
            with zipfile.ZipFile(sys.argv[sys.argv.index('--bundle') + 1]) as archive:
                for name in ('metadata.json', 'extension.js', 'state.js'):
                    (extension_dir / name).write_bytes(archive.read(name))
        else:
            shutil.copytree(ROOT / 'integrations/gnome' / UUID, extension_dir)
        if '--global-input-probe' in sys.argv or '--compat-stand' in sys.argv or '--compat-xwayland' in sys.argv:
            if runtime_stand or ibus_stand or '--bundle' in sys.argv:
                raise SystemExit('global input probe must run separately')
            from global_input_probe import instrument
            instrument(extension_dir / 'extension.js')
        env = os.environ.copy()
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS',
                    'IBUS_ADDRESS', 'IBUS_COMPONENT_PATH', 'AT_SPI_BUS_ADDRESS',
                    'GTK_IM_MODULE', 'QT_IM_MODULE', 'XMODIFIERS'):
            env.pop(key, None)
        if ibus_stand:
            from xml.sax.saxutils import escape
            component_dir = base / 'components'
            component_dir.mkdir()
            engine_path = ROOT / 'integrations/ibus/probe_engine.py'
            (component_dir / 'typetune.xml').write_text(f"""<component>
<name>org.freedesktop.IBus.TypeTuneProbe</name><description>TypeTune isolated probe</description>
<exec>{escape(sys.executable)} {escape(str(engine_path))}</exec><version>0.1</version>
<author>TypeTune</author><license>MIT</license><homepage></homepage><textdomain></textdomain>
<engines><engine><name>typetune-probe</name><longname>TypeTune Probe</longname>
<description>Isolated pass-through probe</description><language>en</language>
<license>MIT</license><author>TypeTune</author><layout>us</layout></engine></engines></component>""")
            env['TYPETUNE_IBUS_STAND'] = '1'
            env['IBUS_ADDRESS'] = 'unix:path=' + str(base / 'runtime/ibus')
            env['IBUS_COMPONENT_PATH'] = str(component_dir) + ':/usr/share/ibus/component'
        if '--compat-xwayland' in sys.argv:
            env['TYPETUNE_COMPAT_XWAYLAND'] = '1'
        if '--compat-stand' in sys.argv or '--compat-xwayland' in sys.argv:
            env['TYPETUNE_COMPAT_STAND'] = '1'
        if '--global-input-probe' in sys.argv:
            env['TYPETUNE_GLOBAL_INPUT_PROBE'] = '1'
        if '--editor-stand' in sys.argv:
            env['TYPETUNE_EDITOR_STAND'] = '1'
        if '--text-stand' in sys.argv:
            env['TYPETUNE_TEXT_STAND_PATH'] = str(ROOT / 'target/debug/examples/field_stand')
        env.update(XDG_DATA_HOME=str(base / 'data'), XDG_CONFIG_HOME=str(base / 'config'),
                   XDG_RUNTIME_DIR=str(base / 'runtime'), XDG_CACHE_HOME=str(base / 'cache'),
                   GSETTINGS_BACKEND='keyfile', XDG_SESSION_TYPE='wayland',
                   XDG_CURRENT_DESKTOP='GNOME', GNOME_SHELL_SESSION_MODE='user',
                   TYPETUNE_NESTED_STAND=str(base))
        if runtime_stand:
            env['TYPETUNE_RUNTIME_STAND'] = '1'
            env.pop('IBUS_COMPONENT_PATH', None)
            subprocess.run(['/usr/bin/python3', str(ROOT / 'integrations/ibus/controller.py'), 'install'],
                           env=env, check=True)
            generated = subprocess.check_output(['/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator'], env=env, text=True)
            line = next(line for line in generated.splitlines() if line.startswith('IBUS_COMPONENT_PATH='))
            env['IBUS_COMPONENT_PATH'] = line.partition('=')[2].strip('"')
            assert str(base / 'data/ibus/component') in env['IBUS_COMPONENT_PATH']
        with subprocess.Popen(['dbus-run-session', '--config-file',
                               str(ROOT / 'crates/typetune-session/examples/private-bus.conf'),
                               '--', sys.executable, __file__, '--inside'], env=env,
                              start_new_session=True) as task:
            try:
                code = task.wait(timeout=90)
                if code:
                    raise RuntimeError(f'native stand exited {code}')
            except subprocess.TimeoutExpired:
                os.killpg(task.pid, signal.SIGKILL)
                task.wait()
                raise
            finally:
                # Daemon-activated engines may outlive their direct parent. This is
                # only the new process group created above, never the desktop group.
                try:
                    os.killpg(task.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


def inside():
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
    base = Path(os.environ['TYPETUNE_NESTED_STAND'])
    assert str(base / 'runtime') == os.environ['XDG_RUNTIME_DIR']
    children = []
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def call(path, interface, method, params=None, destination='org.gnome.Shell'):
        return bus.call_sync(destination, path, interface, method, params,
                             None, Gio.DBusCallFlags.NONE, 1000, None).unpack()

    def snapshot():
        return json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'GetSnapshot')[0])

    def wait(predicate, label, seconds=15):
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            try:
                result = predicate()
                if result:
                    return result
            except Exception as error:
                last = type(error).__name__
            if children and children[0].poll() is not None:
                raise RuntimeError('nested Shell exited before ' + label)
            time.sleep(.1)
        raise RuntimeError(f'timeout: {label}; last error type={last}')

    def current_sources():
        return ast.literal_eval(subprocess.check_output(['gsettings', 'get', 'org.gnome.desktop.input-sources', 'sources'], text=True).strip())

    def setting(schema, key, value):
        subprocess.run(['gsettings', 'set', schema, key, value], check=True)

    log = open(base / 'shell.log', 'w+')
    try:
        setting('org.gnome.shell', 'enabled-extensions', "['" + UUID + "']")
        setting('org.gnome.shell', 'disable-user-extensions', 'false')
        setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'us')]")
        ibus_daemon = None
        if 'TYPETUNE_IBUS_STAND' in os.environ:
            ibus_daemon = subprocess.Popen(['ibus-daemon', '--single', '--panel=disable',
                                           '--emoji-extension=disable', '--config=disable',
                                           '--address=' + os.environ['IBUS_ADDRESS']],
                                          stdout=log, stderr=log)
        shell = subprocess.Popen(['gnome-shell' , '--headless', '--wayland', *([] if 'TYPETUNE_COMPAT_XWAYLAND' in os.environ else ['--no-x11']),
                                  '--virtual-monitor', '800x600', '--wayland-display', 'typetune-test'],
                                 stdout=log, stderr=log)
        children.append(shell)
        if ibus_daemon is not None:
            children.append(ibus_daemon)
        first = wait(snapshot, 'bridge startup')
        assert first['protocol'] == 1
        print('PASS GNOME-01: real Shell exported bridge', flush=True)
        call('/org/gnome/Shell', 'org.freedesktop.DBus.Properties', 'Set',
             GLib.Variant('(ssv)', ('org.gnome.Shell', 'OverviewActive', GLib.Variant('b', False))))
        wait(lambda: snapshot()['source_id'] == 'us', 'US source')
        before = snapshot()
        setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'ru')]")
        wait(lambda: snapshot()['source_id'] == 'ru', 'RU source')
        assert snapshot()['source_generation'] > before['source_generation']
        print('PASS GNOME-02: US to RU from real input source manager; generation changed', flush=True)

        gtk = """import gi
from gi.repository import GLib
gi.require_version('Gtk','4.0')
from gi.repository import Gtk
w=Gtk.Window(title='TypeTune synthetic fixture'); w.set_default_size(320,180)
e=Gtk.Entry(); e.set_text(''); e.set_position(-1); w.set_child(e); w.present()
import os
from pathlib import Path
output=Path(os.environ['TYPETUNE_NESTED_STAND']) / ('input-' + str(os.getpid()))
def changed(entry):
    temp=output.with_suffix('.tmp'); temp.write_text(entry.get_text()); temp.replace(output)
e.connect('changed', changed)
import json
def capture(*_):
    def save():
        target=output.with_suffix('.state');temp=target.with_suffix('.tmpstate')
        temp.write_text(json.dumps(dict(caret=e.get_position(),selection=list(e.get_selection_bounds()))));temp.replace(target)
        return False
    GLib.idle_add(save)
e.connect('notify::cursor-position',capture)
e.connect('notify::selection-bound',capture)
capture()
changed(e)
GLib.MainLoop().run()
"""
        child_env = dict(os.environ, WAYLAND_DISPLAY='typetune-test', GDK_BACKEND='wayland')
        children.append(subprocess.Popen([sys.executable, '-c', gtk], env=child_env, stdout=log, stderr=log))
        wait(lambda: snapshot()['window'] != 0, 'first GTK focus')
        window_a = snapshot()
        children.append(subprocess.Popen([sys.executable, '-c', gtk], env=child_env, stdout=log, stderr=log))
        wait(lambda: snapshot()['window'] not in (0, window_a['window']), 'second GTK focus')
        window_b = snapshot()
        assert window_b['window_backend'] == 'wayland'
        assert window_b['generation'] > window_a['generation']
        print('PASS GNOME-03: two native GTK windows, distinct focus tokens and generation', flush=True)
        def request_source(expected, target):
            request = {key: expected[key] for key in ('instance', 'generation', 'window')}
            request['target'] = target
            return json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'RequestSource',
                                   GLib.Variant('(s)', (json.dumps(request),)))[0])
        assert request_source(snapshot(), 'us') == {'status': 'rejected', 'reason': 'source_unavailable'}
        setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'us'), ('xkb', 'ru')]")
        wait(lambda: snapshot()['source_id'] in ('us', 'ru') and
             snapshot()['source_generation'] > window_b['source_generation'], 'two configured sources')
        stale = window_a
        assert request_source(stale, 'ru')['status'] == 'rejected'
        remote_switch = call('/org/gnome/Mutter/RemoteDesktop', 'org.gnome.Mutter.RemoteDesktop',
                             'CreateSession', destination='org.gnome.Mutter.RemoteDesktop')[0]
        def switch_event(method, signature, values):
            return call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', method,
                        GLib.Variant(signature, values), destination='org.gnome.Mutter.RemoteDesktop')
        call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', 'Start',
             destination='org.gnome.Mutter.RemoteDesktop')
        for down in (True, False):
            switch_event('NotifyKeyboardKeycode', '(ub)', (42, down))
        # Same physical evdev key A=30 must reach the client as Russian/US text.
        expected_text = ''
        output = base / ('input-' + str(children[-1].pid))
        for source, character in [('ru', 'ф'), ('us', 'a')]:
            command = json.loads(subprocess.check_output(
                [sys.executable, str(ROOT / 'integrations/gnome/switch_source.py'), source]))
            assert command == {'status': 'observed', 'source': source}
            for down in (True, False):
                switch_event('NotifyKeyboardKeycode', '(ub)', (30, down))
            expected_text += character
            wait(lambda: output.exists() and output.read_text() == expected_text, 'client layout delivery')
        call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', 'Stop',
             destination='org.gnome.Mutter.RemoteDesktop')
        assert request_source(snapshot(), 'us')['status'] == 'unchanged'
        assert request_source(window_b, 'ru')['status'] == 'rejected'
        print('PASS SWITCH-01: guarded RU/US command and readback; same evdev key yields Cyrillic/Latin in client', flush=True)
        print('PASS SWITCH-02: unavailable source, stale focus/generation refuse; current source no-op', flush=True)
        if 'TYPETUNE_GLOBAL_INPUT_PROBE' in os.environ:
            observed = json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'ProbeKeys')[0])
            # Client keyboard events bypass the Shell stage callback. Do not
            # advertise this signal as a global keyboard observer.
            assert observed['aCode'] is None, observed
            assert observed['down'] < 3 and observed['up'] < 3, observed
            call('/org/typetune/Session1', 'org.typetune.Session1', 'ProbeCreate')
            time.sleep(.2)
            assert request_source(snapshot(), 'ru')['status'] in ('requested', 'unchanged')
            wait(lambda: snapshot()['source_id'] == 'ru', 'probe RU layout')
            time.sleep(.2)
            call('/org/typetune/Session1', 'org.typetune.Session1', 'ProbeInject')
            wait(lambda: output.read_text() == 'привет', 'compositor keyboard replacement without IBus')
            time.sleep(.1)
            final_keys = json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'ProbeKeys')[0])
            print('PASS GLOBAL-PROBE-01: Shell stage cannot observe client letters; compositor virtual keyboard replaces exact GTK text with RU without IBus', flush=True)

        if 'TYPETUNE_COMPAT_STAND' in os.environ:
            if 'TYPETUNE_COMPAT_XWAYLAND' in os.environ:
                display=json.loads(call('/org/typetune/Session1','org.typetune.Session1','ProbeDisplay')[0])
                assert display['display'] and display['authority']
                client=subprocess.Popen([sys.executable,'-c',gtk],env=dict(child_env,GDK_BACKEND='x11',DISPLAY=display['display'],XAUTHORITY=display['authority']),stdout=log,stderr=log)
                children.append(client)
                wait(lambda: snapshot()['window_backend']=='x11','XWayland client focus')
                output=base/('input-'+str(client.pid))
            call('/org/typetune/Session1', 'org.typetune.Session1', 'ProbeCreate')
            time.sleep(.2)
            request_source(snapshot(), 'us')
            wait(lambda: snapshot()['source_id']=='us', 'compat US')
            runtime = subprocess.Popen([sys.executable, str(ROOT / 'integrations/compat/runtime.py'), '--stand'], env=child_env)
            children.append(runtime)
            def compat(method='GetStatus', params=None):
                result=call('/org/typetune/Compat1','org.typetune.Compat1',method,params,destination='org.typetune.Compat')
                return json.loads(result[0]) if method=='GetStatus' else result
            wait(lambda: compat()['available'], 'compat context without IBus')
            remote_switch = call('/org/gnome/Mutter/RemoteDesktop', 'org.gnome.Mutter.RemoteDesktop', 'CreateSession', destination='org.gnome.Mutter.RemoteDesktop')[0]
            call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', 'Start', destination='org.gnome.Mutter.RemoteDesktop')
            sequence=0
            def edge(code,down):
                nonlocal sequence
                sequence+=1
                switch_event('NotifyKeyboardKeycode','(ub)',(code,down))
                event=dict(kind='key',code=code,value=1 if down else 0,device=1,time=sequence*.03,seq=sequence)
                compat('Feed',GLib.Variant('(s)',(json.dumps(event),)))
                time.sleep(.03)
            def tap(code):edge(code,True);edge(code,False)
            edge(29,True);tap(30);edge(29,False);tap(14)
            wait(lambda: output.read_text()=='', 'compat cleared fixture')
            time.sleep(.2)
            for code in [34,35,48,32,20,49]:tap(code)
            wait(lambda: output.read_text()=='ghbdtn','compat original')
            tap(42);tap(42)
            wait(lambda: output.read_text()=='привет','compat Double Shift text')
            wait(lambda: compat()['last_result']=='injected-unverified','compat explicit unverified status')
            assert snapshot()['source_id']=='ru'
            for expected, mode, shift in [('ghbdtn','us',54),('привет','ru',42)]:
                tap(shift);tap(shift)
                wait(lambda: output.read_text()==expected,'compat repeat toggle text')
                wait(lambda: compat()['last_result']=='injected-unverified','compat repeat toggle finish')
                assert snapshot()['source_id']==mode
            print('PASS COMPAT-RETOGGLE: same word RU → US → RU, each gesture changes source; no new typing',flush=True)
            tap(57)
            for code in [35,18,38,38,24]:tap(code)
            tap(54);tap(54)
            wait(lambda: output.read_text()=='привет hello','compat reverse direction')
            wait(lambda: compat()['last_result']=='injected-unverified','compat reverse finish')
            tap(57)
            for code in [34,35,48,32,20,49]:tap(code)
            edge(57,True);time.sleep(.12);edge(57,False)
            wait(lambda: output.read_text()=='привет hello привет ','compat auto Space')
            wait(lambda: compat()['last_result']=='injected-unverified','compat auto finish')
            for expected,mode in [('привет hello ghbdtn ','us'),('привет hello привет ','ru')]:
                tap(42);tap(42)
                wait(lambda: output.read_text()==expected,'compat repeat after auto preserves Space')
                wait(lambda: compat()['last_result']=='injected-unverified','compat auto repeat finish')
                assert snapshot()['source_id']==mode
            print('PASS COMPAT-RETOGGLE-AUTO: toggle after automatic correction preserves trailing Space',flush=True)
            tap(34)
            wait(lambda: output.read_text()=='привет hello привет п','compat following RU input')
            assert compat('SetEnabled',GLib.Variant('(b)',(False,)))==(False,)
            assert not compat()['available']
            caret_state=output.with_suffix('.state')
            wait(lambda: json.loads(caret_state.read_text())['caret']==len('привет hello привет п'),'compat exact caret')
            before_pause=output.read_text()
            tap(42);tap(42)
            time.sleep(.2)
            assert output.read_text()==before_pause
            compat('Quit')
            runtime.wait(timeout=3)
            call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', 'Stop', destination='org.gnome.Mutter.RemoteDesktop')
            print('PASS COMPAT-01: no IBus; Double Shift both directions, auto Space, subsequent RU input, pause/quit; exact native GTK text/caret; paused gesture preserves text; result remains unverified',flush=True)
        report = json.loads(subprocess.check_output([str(ROOT / 'target/debug/typetune'), 'doctor', '--session']))
        assert report['gnome_bridge']['status'] == 'observed'
        assert report['context']['target']['state'] == 'unknown'
        assert 'unicode_unavailable' in report['replacement_blockers']
        print('PASS GNOME-04: Rust client reads real bridge; field/Unicode guards still refuse', flush=True)

        if 'TYPETUNE_IBUS_STAND' in os.environ:
            runtime_stand = 'TYPETUNE_RUNTIME_STAND' in os.environ
            engine_name = 'typetune-test' if runtime_stand else 'typetune-probe'
            controller = ['/usr/bin/python3', str(base / 'data/typetune-test/controller.py')]
            if runtime_stand:
                subprocess.run(controller + ['start'], check=True)
                assert ('xkb', 'us') in current_sources()
                print('PASS RUNTIME-01: installed component starts; existing source preserved', flush=True)
            else:
                setting('org.gnome.desktop.input-sources', 'sources', repr([('ibus', engine_name)]))
            wait(lambda: snapshot()['source_id'] == engine_name, 'IBus probe source')
            stats_file = base / 'ibus-stats.json'
            wait(stats_file.exists, 'IBus engine startup')
            def stats():
                return json.loads(stats_file.read_text())
            wait(lambda: stats()['focus_in'] > 0, 'IBus input focus')
            time.sleep(.5)  # Fixture setup: allow asynchronous Shell engine selection to settle.
            before_ibus = stats()
            remote_ibus = call('/org/gnome/Mutter/RemoteDesktop', 'org.gnome.Mutter.RemoteDesktop',
                               'CreateSession', destination='org.gnome.Mutter.RemoteDesktop')[0]
            call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'Start',
                 destination='org.gnome.Mutter.RemoteDesktop')
            for down in (True, False):
                call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                     GLib.Variant('(ub)', (42, down)), destination='org.gnome.Mutter.RemoteDesktop')
            time.sleep(.1)
            for key in (34, 35, 48, 32, 20, 49):  # evdev: ghbdtn
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                         GLib.Variant('(ub)', (key, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.03)
            time.sleep(.3)
            wait(lambda: output.read_text() == expected_text + 'ghbdtn', 'IBus normal input delivered')
            wait(lambda: stats()['down'] > before_ibus['down'], 'IBus observes keys')
            assert stats()['down'] - before_ibus['down'] >= 6
            assert stats()['surrounding'] > before_ibus['surrounding']
            print('PASS IBUS-01: pass-through GTK input and surrounding text; ' + json.dumps(stats()), flush=True)
            launcher = subprocess.Popen(['/usr/libexec/at-spi-bus-launcher', '--launch-immediately'],
                                        stdout=log, stderr=log)
            children.append(launcher)
            address = wait(lambda: call('/org/a11y/bus', 'org.a11y.Bus', 'GetAddress',
                                        destination='org.a11y.Bus')[0], 'IBus oracle accessibility bus')
            editor_env = dict(child_env, AT_SPI_BUS_ADDRESS=address, GTK_A11Y='atspi')
            editor = subprocess.Popen([sys.executable, str(ROOT / 'integrations/ibus/editor_client.py')],
                                      env=editor_env)
            children.append(editor)
            wait(lambda: (base / 'ibus-editor-ready').exists(), 'IBus editor ready')
            before_editor = stats()
            for key in (34, 35, 48, 32, 20, 49):
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                         GLib.Variant('(ub)', (key, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.03)
            if runtime_stand:
                wait(lambda: (base / 'ibus-editor-correct').exists(), 'editor correction ready')
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                         GLib.Variant('(ub)', (66, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.03)
            wait(lambda: (base / 'ibus-editor-selected').exists(), 'IBus editor readback')
            wait(lambda: stats()['down'] >= before_editor['down'] + 6, 'IBus editor observation')
            for down in (True, False):
                call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                     GLib.Variant('(ub)', (42, down)), destination='org.gnome.Mutter.RemoteDesktop')
            time.sleep(.2)
            if runtime_stand:
                selected_editor = stats()
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                         GLib.Variant('(ub)', (66, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.03)
                wait(lambda: stats()['manual_rejected'] > selected_editor['manual_rejected'], 'AT-SPI selection guard refusal')
                assert stats()['manual_edits'] == selected_editor['manual_edits']
                print('PASS EDITOR-SELECTION: hidden IBus selection refused by AT-SPI, no edit calls', flush=True)
            print('IBUS editor context evidence ' + json.dumps(stats()), flush=True)
            (base / 'ibus-editor-finish').write_text('done')
            assert editor.wait(timeout=5) == 0
            password_gtk = gtk.replace("e.set_text('');", "e.set_input_purpose(Gtk.InputPurpose.PASSWORD); e.set_visibility(False); e.set_text('');")
            before_password = stats()
            old_window = snapshot()['window']
            password = subprocess.Popen([sys.executable, '-c', password_gtk], env=child_env,
                                        stdout=log, stderr=log)
            children.append(password)
            password_output = base / ('input-' + str(password.pid))
            wait(lambda: snapshot()['window'] not in (0, old_window), 'password fixture focus')
            for key in (34, 35, 48, 32, 20, 49):
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                         GLib.Variant('(ub)', (key, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.03)
            wait(lambda: password_output.exists() and password_output.read_text() == 'ghbdtn',
                 'password fixture ordinary input')
            time.sleep(.1)
            assert stats()['sensitive'] > before_password['sensitive']
            print('PASS IBUS-03: password fixture ordinary input intact; observer delta ' +
                  json.dumps({key: stats()[key] - before_password[key]
                              for key in ('down', 'up', 'surrounding', 'sensitive', 'content_type_events')}), flush=True)

            def browser_key(code, down):
                call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyKeyboardKeycode',
                     GLib.Variant('(ub)', (code, down)), destination='org.gnome.Mutter.RemoteDesktop')
                time.sleep(.03)
            def type_fixture():
                for key in (34, 35, 48, 32, 20, 49):
                    browser_key(key, True)
                    browser_key(key, False)
            for profile in (('default', 'ime', 'smart') if runtime_stand else ('default', 'ime')):
                if not runtime_stand:
                    (base / 'manual-browser-profile').touch()
                time.sleep(.1)
                folder = base / ('browser-' + profile)
                browser = subprocess.Popen([sys.executable, str(ROOT / 'integrations/ibus/browser_client.py'), profile],
                                           env=child_env)
                children.append(browser)
                def page():
                    return json.loads((folder / 'state.json').read_text())
                wait(lambda: page()['focused'] and page()['active'] == 'a', 'browser field focus')
                assert snapshot()['window_backend'] == 'wayland'
                time.sleep(.2)
                if runtime_stand:
                    def runtime_status():
                        return json.loads(call('/org/typetune/IBus1', 'org.typetune.IBus1', 'GetStatus',
                                               destination='org.typetune.IBus')[0])
                    def context_status():
                        return json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'GetTextContext')[0])
                    print('Runtime app identity: ' + context_status()['app_id'], flush=True)
                    wait(lambda: runtime_status()['available'], 'runtime Chrome profile')
                initial = stats()
                type_fixture()
                wait(lambda: page()['text_ok'] and page()['caret'] == page()['anchor'] == 6, 'browser typed text/caret')
                time.sleep(.15)
                typed = stats()
                def manual_key(code):
                    browser_key(code, True)
                    browser_key(code, False)
                if profile == 'smart':
                    def double_shift(code):
                        for _ in range(2):
                            browser_key(code, True)
                            browser_key(code, False)
                    # Same-field mouse click between Shift taps must cancel the
                    # gesture even when text and caret do not change.
                    target = page()['target_a']
                    move(-10000., -10000.)
                    move(target['x'], target['y'])
                    wait(lambda: page()['pointer'] is not None, 'smart pointer ready')
                    for _ in range(8):
                        pointer = page()['pointer']
                        dx, dy = target['x'] - pointer['x'], target['y'] - pointer['y']
                        if abs(dx) < 2 and abs(dy) < 2:
                            break
                        move(dx, dy)
                    before_mouse = stats()
                    manual_key(42)
                    for down in (True, False):
                        call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyPointerButton',
                             GLib.Variant('(ib)', (272, down)), destination='org.gnome.Mutter.RemoteDesktop')
                    manual_key(42)
                    time.sleep(.6)
                    assert page()['text_ok'] and stats()['manual_edits'] == before_mouse['manual_edits']
                    assert page()['caret'] == page()['anchor'] == 6
                    manual_key(14)
                    manual_key(49)
                    wait(lambda: page()['text_ok'], 'retype after pointer invalidation')
                    print('PASS SMART-MOUSE: same-field pointer click between Shift taps preserves original text and cancels gesture', flush=True)
                    double_shift(42)
                    wait(lambda: page()['smart_ru'] and snapshot()['source_id'] == 'typetune-test-ru', 'double left Shift RU correction and layout')
                    manual_key(57)
                    for key in (35, 18, 38, 38, 24):
                        manual_key(key)  # Physical hello in RU -> руддщ.
                    double_shift(54)
                    wait(lambda: page()['smart_us'] and snapshot()['source_id'] == 'typetune-test', 'double right Shift US correction and layout')
                    manual_key(57)
                    type_fixture()
                    manual_key(57)
                    wait(lambda: page()['auto_ok'] and snapshot()['source_id'] == 'typetune-test-ru', 'automatic correction with one Space and RU layout')
                    manual_key(34)
                    wait(lambda: page()['next_ru'], 'next physical letter follows new RU layout')
                    assert stats().get('auto_completed', 0) > 0
                    subprocess.run(controller + ['auto-off'], check=True)
                    assert runtime_status()['automatic'] is False
                    subprocess.run(controller + ['auto-on'], check=True)
                    assert runtime_status()['automatic'] is True
                    print('PASS SMART-01: both Shift keys; RU/US correction and layout; Space auto; subsequent native Cyrillic input; auto setting acknowledged', flush=True)
                    (folder / 'finish').write_text('done')
                    assert browser.wait(timeout=5) == 0
                    continue
                manual_key(66)  # F8: common engine US -> RU through IBus.
                wait(lambda: page()['corrected'] and page()['caret'] == page()['anchor'] == 6, 'IBus manual correction DOM readback')
                wait(lambda: stats()['manual_completed'] == typed['manual_completed'] + 1, 'IBus Rust completion')
                manual_key(67)  # F9: inverse mapping; leave the observation fixture intact.
                wait(lambda: page()['text_ok'] and page()['caret'] == page()['anchor'] == 6, 'IBus inverse correction')
                wait(lambda: stats()['manual_completed'] == typed['manual_completed'] + 2, 'IBus inverse Rust completion')
                assert stats()['manual_edits'] == typed['manual_edits'] + 2
                assert stats()['manual_indeterminate'] == typed['manual_indeterminate']
                print('PASS IBUS-MANUAL-' + profile.upper() + ': F8/F9 exact DOM text and caret; two Rust-confirmed edits', flush=True)
                browser_key(105, True)  # Left: ordinary navigation, no DOM editing.
                browser_key(105, False)
                wait(lambda: page()['caret'] == page()['anchor'] == 5, 'browser left navigation')
                time.sleep(.15)
                navigated = stats()
                browser_key(42, True)
                browser_key(105, True)
                browser_key(105, False)
                browser_key(42, False)
                wait(lambda: page()['caret'] == 4 and page()['anchor'] == 5, 'browser keyboard selection')
                time.sleep(.15)
                selected = stats()
                manual_key(66)
                wait(lambda: stats()['manual_rejected'] > selected['manual_rejected'], 'IBus selection refusal')
                assert page()['text_ok'] and page()['caret'] == 4 and page()['anchor'] == 5
                assert stats()['manual_edits'] == selected['manual_edits']
                (folder / 'phase').write_text('focus')
                target = page()['target_b']
                def move(dx, dy):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyPointerMotionRelative',
                         GLib.Variant('(dd)', (dx, dy)), destination='org.gnome.Mutter.RemoteDesktop')
                    time.sleep(.1)
                move(-10000., -10000.)
                move(target['x'], target['y'])
                wait(lambda: page()['pointer'] is not None, 'browser pointer on page')
                for _ in range(8):
                    pointer = page()['pointer']
                    dx, dy = target['x'] - pointer['x'], target['y'] - pointer['y']
                    if abs(dx) < 2 and abs(dy) < 2:
                        break
                    move(dx, dy)
                assert abs(page()['pointer']['x'] - target['x']) < 2
                assert abs(page()['pointer']['y'] - target['y']) < 2
                for down in (True, False):
                    call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'NotifyPointerButton',
                         GLib.Variant('(ib)', (272, down)), destination='org.gnome.Mutter.RemoteDesktop')
                wait(lambda: page()['active'] == 'b' and page()['second_empty'], 'browser field change')
                time.sleep(.15)
                focused = stats()
                manual_key(66)
                wait(lambda: stats()['manual_rejected'] > focused['manual_rejected'], 'IBus new-field refusal')
                assert page()['second_empty'] and page()['text_ok']
                assert stats()['manual_edits'] == focused['manual_edits']
                (folder / 'phase').write_text('password')
                wait(lambda: page()['active'] == 'p', 'browser password focus')
                time.sleep(.15)
                password_before = stats()
                type_fixture()
                wait(lambda: page()['password_ok'] and page()['text_ok'], 'browser password input')
                time.sleep(.15)
                password_after = stats()
                manual_key(66)
                if runtime_stand:
                    # With US also configured, GNOME switches away from the IBus
                    # engine in password fields; no shortcut reaches it.
                    assert not runtime_status()['available']
                else:
                    wait(lambda: stats()['manual_rejected'] > password_after['manual_rejected'], 'IBus password refusal')
                assert page()['password_ok'] and page()['text_ok']
                assert stats()['manual_edits'] == password_after['manual_edits']
                print('PASS IBUS-REFUSE-' + profile.upper() + ': selection, new field and password preserve DOM text; no edit calls', flush=True)
                evidence = {
                    'keys_seen': typed['down'] - initial['down'],
                    'surrounding_updates': typed['surrounding'] - initial['surrounding'],
                    'purpose': typed['purpose'],
                    'navigation_seen': navigated['navigation'] - typed['navigation'],
                    'selection_events': selected['selection_events'] - navigated['selection_events'],
                    'selection_cursor': selected['last_cursor'], 'selection_anchor': selected['last_anchor'],
                    'field_focus_in': focused['focus_in'] - selected['focus_in'],
                    'field_resets': focused['reset'] - selected['reset'],
                    'password_keys_seen': password_after['down'] - password_before['down'],
                    'password_purpose': password_after['purpose'],
                    'password_source': snapshot()['source_id'],
                }
                assert evidence['keys_seen'] == 6
                assert typed['up'] - initial['up'] == 6
                assert evidence['surrounding_updates'] > 0 and evidence['purpose'] == 0
                assert evidence['navigation_seen'] >= 1
                assert evidence['selection_events'] >= 1
                assert {evidence['selection_cursor'], evidence['selection_anchor']} == {4, 5}
                assert evidence['field_focus_in'] > 0 or evidence['field_resets'] > 0
                if runtime_stand:
                    assert evidence['password_source'] == 'us'
                else:
                    assert evidence['password_purpose'] == 8
                print('PASS BROWSER-' + profile.upper() + ': DOM text/caret/navigation/selection/focus/password intact; IBus ' + json.dumps(evidence), flush=True)
                (folder / 'finish').write_text('done')
                assert browser.wait(timeout=5) == 0
                if not runtime_stand:
                    (base / 'manual-browser-profile').unlink()

            if runtime_stand:
                subprocess.run(controller + ['browser'], env=child_env, check=True)
                wait(lambda: runtime_status()['available'], 'user test browser ready')
                time.sleep(.3)
                before_preview = stats()
                type_fixture()
                manual_key(66)
                wait(lambda: stats()['manual_completed'] == before_preview['manual_completed'] + 1, 'installed user page correction')
                print('PASS RUNTIME-04: browser command opens installed local page; native F8 confirmed by common engine readback', flush=True)
                subprocess.run(controller + ['pause'], check=True)
                assert not runtime_status()['enabled']
                subprocess.run(controller + ['resume'], check=True)
                assert runtime_status()['enabled']
                subprocess.run(controller + ['stop'], check=True)
                assert ('ibus', 'typetune-test') not in current_sources()
                wait(lambda: snapshot()['source_id'] == 'us', 'runtime stop restores ordinary source')
                print('PASS RUNTIME-02: effective pause/resume/stop, TypeTune source removed, normal source restored', flush=True)
                setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'us'), ('xkb', 'ru')]")
                wait(lambda: request_source(snapshot(), 'ru')['status'] in ('requested', 'unchanged'), 'runtime initial RU source')
                wait(lambda: snapshot()['source_id'] == 'ru', 'runtime initial RU readback')
                subprocess.run(controller + ['start'], check=True)
                subprocess.run(controller + ['stop'], check=True)
                wait(lambda: snapshot()['source_id'] == 'ru', 'runtime stop restores previous RU source')
                print('PASS RUNTIME-05: second start after shutdown works; stop restores prior RU source', flush=True)
            call(remote_ibus, 'org.gnome.Mutter.RemoteDesktop.Session', 'Stop',
                 destination='org.gnome.Mutter.RemoteDesktop')
            setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'us')]")
            wait(lambda: snapshot()['source_id'] == 'us', 'restore source after IBus probe')
        if 'TYPETUNE_TEXT_STAND_PATH' in os.environ:
            setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'us')]")
            wait(lambda: snapshot()['source_id'] == 'us', 'text keyboard layout')
            remote = call('/org/gnome/Mutter/RemoteDesktop', 'org.gnome.Mutter.RemoteDesktop',
                          'CreateSession', destination='org.gnome.Mutter.RemoteDesktop')[0]
            remote_interface = 'org.gnome.Mutter.RemoteDesktop.Session'
            remote_destination = 'org.gnome.Mutter.RemoteDesktop'
            call(remote, remote_interface, 'Start', destination=remote_destination)
            # Headless compositor has no keyboard seat until a virtual device exists.
            # One balanced Shift pair creates it, entirely on the private display.
            for down in (True, False):
                call(remote, remote_interface, 'NotifyKeyboardKeycode',
                     GLib.Variant('(ub)', (42, down)), destination=remote_destination)
            for fixture in children[1:]:
                fixture.terminate()
                fixture.wait(timeout=3)
            text_child = subprocess.Popen([os.environ['TYPETUNE_TEXT_STAND_PATH']], env=child_env)
            children.append(text_child)
            wait(lambda: (base / 'text-ready').exists(), 'text fixture ready')
            # Unicode keysyms, not evdev/XKB offsets. All events target private compositor.
            for keysym in (ord(':'), ord('h'), ord('i'), ord(' ')):
                for down in (True, False):
                    call(remote, remote_interface, 'NotifyKeyboardKeysym',
                         GLib.Variant('(ub)', (keysym, down)), destination=remote_destination)
            def remote_event(method, signature, values):
                call(remote, remote_interface, method, GLib.Variant(signature, values),
                     destination=remote_destination)
            for index in range(2):
                marker = base / f'pointer-{index}'
                wait(marker.exists, 'pointer fixture ready')
                x, y = map(float, marker.read_text().split())
                remote_event('NotifyPointerMotionRelative', '(dd)', (-10000., -10000.))
                time.sleep(0.05)
                remote_event('NotifyPointerMotionRelative', '(dd)', (x, y))
                time.sleep(0.05)
                position = base / 'pointer-position'
                wait(position.exists, 'pointer reached GTK surface')
                for _ in range(5):
                    actual_x, actual_y = map(float, position.read_text().split())
                    if abs(actual_x - x) < 2 and abs(actual_y - y) < 2:
                        break
                    remote_event('NotifyPointerMotionRelative', '(dd)', (x - actual_x, y - actual_y))
                    time.sleep(0.05)
                actual_x, actual_y = map(float, position.read_text().split())
                assert abs(actual_x - x) < 2 and abs(actual_y - y) < 2
                for down in (True, False):
                    remote_event('NotifyPointerButton', '(ib)', (272, down))
            for index in range(6):
                wait(lambda: (base / f'shortcut-{index}').exists(), 'shortcut fixture ready')
                key = 0xffc6 if index == 1 else 0xffc5  # XKB keysyms F9 / F8
                if index == 2:
                    remote_event('NotifyKeyboardKeycode', '(ub)', (42, True))
                remote_event('NotifyKeyboardKeysym', '(ub)', (key, True))
                time.sleep(1.1 if index == 4 else 0.65 if index == 0 else 0.1)
                (base / f'held-{index}').write_text('ready')
                wait(lambda: (base / f'release-{index}').exists(), 'release fixture ready')
                remote_event('NotifyKeyboardKeysym', '(ub)', (key, False))
                if index == 2:
                    remote_event('NotifyKeyboardKeycode', '(ub)', (42, False))
            if text_child.wait(timeout=10):
                raise RuntimeError('text fixture failed')
            call(remote, remote_interface, 'Stop', destination=remote_destination)
            setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'ru')]")
            wait(lambda: snapshot()['source_id'] == 'ru', 'restore fixture layout')
        if 'TYPETUNE_EDITOR_STAND' in os.environ:
            launcher = subprocess.Popen(['/usr/libexec/at-spi-bus-launcher', '--launch-immediately'],
                                        stdout=log, stderr=log)
            children.append(launcher)
            address = wait(lambda: call('/org/a11y/bus', 'org.a11y.Bus', 'GetAddress',
                                        destination='org.a11y.Bus')[0], 'private accessibility bus')
            probe_env = dict(child_env, AT_SPI_BUS_ADDRESS=address, GTK_A11Y='atspi')
            subprocess.run([sys.executable, str(ROOT / 'integrations/gnome-text-editor/probe.py')],
                           env=probe_env, check=True, timeout=25)
        setting('org.gnome.desktop.input-sources', 'sources', "[('xkb', 'ru')]")
        wait(lambda: snapshot()['source_id'] == 'ru', 'restore source before lifecycle cases')
        if snapshot()['window'] == 0:
            children.append(subprocess.Popen([sys.executable, '-c', gtk], env=child_env,
                                             stdout=log, stderr=log))
            wait(lambda: snapshot()['window'] != 0, 'focus for restart guard')
        before_restart = snapshot()
        subprocess.run(['gnome-extensions', 'disable', UUID], check=True)
        def absent():
            try: snapshot(); return False
            except GLib.Error: return True
        wait(absent, 'disable')
        subprocess.run(['gnome-extensions', 'enable', UUID], check=True)
        wait(lambda: snapshot()['instance'] != first['instance'], 're-enable')
        assert request_source(before_restart, 'ru') == {'status': 'rejected', 'reason': 'changed'}
        print('PASS SWITCH-04: extension restart rejects previous instance', flush=True)
        print('PASS GNOME-05: disable removes endpoint; re-enable changes instance', flush=True)
        # Shield activation only inside disposable headless compositor.
        call('/org/gnome/ScreenSaver', 'org.gnome.ScreenSaver', 'SetActive', GLib.Variant('(b)', (True,)),
             destination='org.gnome.Shell.ScreenShield')
        wait(lambda: snapshot()['shield_active'] or snapshot()['locked'], 'screen shield')
        locked = snapshot()
        assert locked['window'] == 0 and locked['source_id'] == ''
        assert json.loads(call('/org/typetune/Session1', 'org.typetune.Session1', 'GetTextContext')[0])['app_id'] == ''
        assert request_source(locked, 'us') == {'status': 'rejected', 'reason': 'context'}
        print('PASS SWITCH-03: screen shield rejects switching', flush=True)
        print('PASS GNOME-06: screen shield redacts window and source', flush=True)
        call('/org/gnome/ScreenSaver', 'org.gnome.ScreenSaver', 'SetActive', GLib.Variant('(b)', (False,)),
             destination='org.gnome.Shell.ScreenShield')
        wait(lambda: not snapshot()['shield_active'] and snapshot()['source_id'] == 'ru', 'shield deactivate')
        assert snapshot()['generation'] > locked['generation']
        print('PASS GNOME-07: shield deactivation restores source with new generation', flush=True)
        if 'TYPETUNE_RUNTIME_STAND' in os.environ:
            before_uninstall = current_sources()
            subprocess.run(controller + ['uninstall'], check=True)
            assert current_sources() == before_uninstall
            assert not (base / 'config/environment.d/90-typetune-ibus.conf').exists()
            assert not (base / 'data/typetune-test').exists()
            assert not (base / 'data/ibus/component/typetune-test.xml').exists()
            assert not (base / 'data/gnome-shell/extensions' / UUID).exists()
            print('PASS RUNTIME-03: uninstall removes owned files and preserves ordinary sources', flush=True)
        print('GNOME NATIVE STAND PASS (isolated headless compositor)', flush=True)
    except Exception:
        log.flush()
        # Only isolated synthetic-session log, never main desktop/user text.
        print((base / 'shell.log').read_text()[-6000:], file=sys.stderr)
        raise
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=3)
                except subprocess.TimeoutExpired: child.kill(); child.wait()
        log.close()

if __name__ == '__main__':
    inside() if '--inside' in sys.argv else outer()
