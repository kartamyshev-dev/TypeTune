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
    if '--ibus-stand' in sys.argv or '--runtime-stand' in sys.argv:
        raise SystemExit('IBus adapter was removed; use --compat-stand or --compat-xwayland')
    with tempfile.TemporaryDirectory(prefix='typetune-gnome-') as temp:
        base = Path(temp)
        for name in ('data', 'config', 'runtime', 'cache'):
            (base / name).mkdir(mode=0o700)
        extension_dir = base / 'data/gnome-shell/extensions' / UUID
        if '--bundle' in sys.argv:
            extension_dir.mkdir(parents=True)
            with zipfile.ZipFile(sys.argv[sys.argv.index('--bundle') + 1]) as archive:
                for name in ('metadata.json', 'extension.js', 'state.js'):
                    (extension_dir / name).write_bytes(archive.read(name))
        else:
            shutil.copytree(ROOT / 'integrations/gnome' / UUID, extension_dir)
        if '--global-input-probe' in sys.argv or '--compat-stand' in sys.argv or '--compat-xwayland' in sys.argv:
            if '--bundle' in sys.argv:
                raise SystemExit('global input probe must run separately')
            from global_input_probe import instrument
            instrument(extension_dir / 'extension.js')
        env = os.environ.copy()
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS',
                    'IBUS_ADDRESS', 'IBUS_COMPONENT_PATH', 'AT_SPI_BUS_ADDRESS',
                    'GTK_IM_MODULE', 'QT_IM_MODULE', 'XMODIFIERS'):
            env.pop(key, None)
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
        with subprocess.Popen(['dbus-run-session', '--config-file',
                               str(ROOT / 'crates/typetune-session/examples/private-bus.conf'),
                               '--', sys.executable, __file__, '--inside'], env=env,
                              start_new_session=True) as task:
            try:
                code = task.wait(timeout=180)
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
        shell = subprocess.Popen(['gnome-shell' , '--headless', '--wayland', *([] if 'TYPETUNE_COMPAT_XWAYLAND' in os.environ else ['--no-x11']),
                                  '--virtual-monitor', '800x600', '--wayland-display', 'typetune-test'],
                                 stdout=log, stderr=log)
        children.append(shell)
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
            compat('SetEnabled',GLib.Variant('(b)',(True,)))
            for occurrence in range(3):
                edge(29,True);tap(30);edge(29,False);tap(14)
                wait(lambda: output.read_text()=='','learning cleared fixture')
                request_source(snapshot(),'ru')
                wait(lambda:snapshot()['source_id']=='ru','learning RU source')
                time.sleep(.2)
                for code in [34,23,20,35,22,48]:tap(code)
                wait(lambda:output.read_text()=='пшерги','learning source word')
                if occurrence:tap(57)  # A word already ended before the gesture counts immediately.
                tap(42);tap(42)
                wait(lambda:output.read_text()==('github ' if occurrence else 'github'),'learning corrected word')
                wait(lambda:compat()['last_result']=='injected-unverified','learning output completed')
                if not occurrence:tap(57)
                wait(lambda:output.read_text()=='github ','learning retained word')
                wait(lambda:compat()['suggestion_count']==int(occurrence==2),'learning proposal threshold')
            tap(42);tap(42)
            wait(lambda:output.read_text()=='пшерги ','learning inverse edit')
            wait(lambda:compat()['suggestion_count']==0,'learning inverse withdraws proposal')
            tap(42);tap(42)
            wait(lambda:output.read_text()=='github ','learning retoggle edit')
            wait(lambda:compat()['last_result']=='injected-unverified','learning retoggle completed')
            assert compat()['suggestion_count']==0
            print('PASS LEARN-GITHUB: Space before/after gesture counts once; inverse withdraws; retoggle never counts again',flush=True)
            # D7 plan 57: synthetic fixture words only; no user text.
            d7_codes = [41,16,17,18,19,20,21,22,23,24,25,26,27,30,31,32,33,34,35,36,37,38,39,40,44,45,46,47,48,49,50,51,52]
            d7_us = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
            def type_us(text):
                for character in text:
                    index = d7_us.index(character)
                    tap(d7_codes[index])
            def clear_d7():
                edge(29,True);tap(30);edge(29,False);tap(14)
                wait(lambda: output.read_text()=='','D7 clear')
            def ensure_us():
                request_source(snapshot(),'us')
                wait(lambda: snapshot()['source_id']=='us','D7 US source')
            def auto_space():
                edge(57,True);time.sleep(.12);edge(57,False)
            d7_cases = [
                ('rkfdbfnehs','клавиатуры ','positive'),
                ('yfcnhjqrfvb','настройками ','positive'),
                ('gthtrk.xtybt','переключение ','positive'),
                ('bcghfdktybt','исправление ','positive'),
                ('cj[hfytybt','сохранение ','positive'),
                ('ghbdtn,','привет, ','positive'),
                ('ghbdtn.','привет. ','positive'),
                ('rfr','как ','positive'),
                (',s','бы ','positive'),
                ('example.com','example.com ','negative'),
                ('keyboards','keyboards ','negative'),
            ]
            assert compat()['automatic'] is True
            clear_d7(); ensure_us()
            for d7_index, (d7_source, d7_expected, d7_kind) in enumerate(d7_cases):
                if d7_index:
                    clear_d7(); ensure_us()
                type_us(d7_source)
                wait(lambda text=d7_source: output.read_text()==text,'D7 typed '+d7_source)
                auto_space()
                try:
                    wait(lambda expected=d7_expected: output.read_text()==expected,'D7 text '+d7_source)
                except RuntimeError as error:
                    status=compat()
                    raise RuntimeError(f'{error}; actual={output.read_text()!r}; last_result={status.get("last_result")!r}; mode={status.get("mode")!r}; suggestion_count={status.get("suggestion_count")!r}; automatic={status.get("automatic")!r}; available={status.get("available")!r}') from None
                if d7_kind=='positive':
                    wait(lambda: compat()['last_result']=='injected-unverified','D7 inject '+d7_source)
                else:
                    wait(lambda: compat()['last_result']=='no-candidate','D7 negative '+d7_source)
            print('PASS DICT-D7-NATIVE: 9 positives (D2/D3 short+punct) corrected, 2 negatives unchanged in isolated GTK fixture',flush=True)
            compat('Quit')
            runtime.wait(timeout=3)
            call(remote_switch, 'org.gnome.Mutter.RemoteDesktop.Session', 'Stop', destination='org.gnome.Mutter.RemoteDesktop')
            print('PASS COMPAT-01: no IBus; Double Shift both directions, auto Space, subsequent RU input, pause/quit; exact native GTK text/caret; paused gesture preserves text; result remains unverified',flush=True)
        report = json.loads(subprocess.check_output([str(ROOT / 'target/debug/typetune'), 'doctor', '--session']))
        assert report['gnome_bridge']['status'] == 'observed'
        assert report['context']['target']['state'] == 'unknown'
        assert 'unicode_unavailable' in report['replacement_blockers']
        print('PASS GNOME-04: Rust client reads real bridge; field/Unicode guards still refuse', flush=True)

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
