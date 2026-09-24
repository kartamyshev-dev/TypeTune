import unittest
from gi.repository import Gio, GLib
from gui_model import describe
from tray import Tray, ITEM_XML, MENU_XML, MENU, MENU_SPEC, menu_rows
import flag_badge


class Window:
    def __init__(self): self.calls = []
    def present(self): self.calls.append('open')
    def dispatch(self, command): self.calls.append(command)


class Invocation:
    def return_value(self, value): self.value = value
    def return_dbus_error(self, name, message): self.value = ('error', name)


class Checks(unittest.TestCase):
    def setUp(self):
        self.tray = Tray.__new__(Tray)
        self.tray.window = Window()
        self.tray.state = describe(dict(compatibility=dict(enabled=True, automatic=True, available=True, mode='ru'),
                                        settings=dict(manual_switching=True, display_layout_flag=True,
                                                      switch_only_last_word=True, dont_switch_words=False,
                                                      dont_correct_after_layout_change=True,
                                                      play_switching_sound=False, autostart=False)))
        self.tray.error = ''; self.tray.busy = False
        self.tray.revision = 1

    def test_menu_actions_and_busy_guard(self):
        self.tray.click(19, 'clicked'); self.tray.click(21, 'clicked'); self.tray.click(3, 'clicked')
        self.assertEqual(self.tray.window.calls, ['open', 'pause', 'auto-off'])
        self.tray.busy = True
        self.tray.click(21, 'clicked'); self.tray.click(3, 'clicked'); self.tray.click(22, 'clicked')
        self.assertEqual(self.tray.window.calls, ['open', 'pause', 'auto-off'])
        self.assertFalse(self.tray.click(999, 'clicked'))

    def test_policy_toggles_dispatch(self):
        self.tray.click(4, 'clicked')
        self.tray.click(6, 'clicked')
        self.tray.click(7, 'clicked')
        self.tray.click(8, 'clicked')
        self.tray.click(11, 'clicked')
        self.assertEqual(self.tray.window.calls, ['manual-toggle', 'switch-last-toggle',
                                                  'dont-switch-toggle', 'anti-loop-toggle', 'flag-toggle'])

    def test_layout_serialization_and_property_filter(self):
        for xml in [ITEM_XML, MENU_XML]: self.assertTrue(Gio.DBusNodeInfo.new_for_xml(xml).interfaces)
        invocation = Invocation()
        self.tray.method(None, None, None, MENU, 'GetLayout', GLib.Variant('(iias)', (0, -1, ['label'])), invocation)
        revision, root = invocation.value.unpack()
        self.assertEqual(revision, 1)
        # Separators are omitted from the exported children.
        exported = [row[0] for row in MENU_SPEC if row[1] != 'sep']
        self.assertEqual(len(root[2]), len(exported))
        self.assertTrue(all(set(child[1]) == {'label'} for child in root[2]))
        self.tray.method(None, None, None, MENU, 'GetProperty', GLib.Variant('(is)', (999, 'label')), invocation)
        self.assertEqual(invocation.value[0], 'error')

    def test_flag_pixmap_and_header(self):
        self.assertEqual(flag_badge.label('us'), 'us')
        self.assertEqual(flag_badge.label('ru'), 'ru')
        self.assertEqual(flag_badge.label(''), '?')
        pix = flag_badge.pixmap('ru')
        self.assertEqual(len(pix), 1)
        w, h, data = pix[0]
        self.assertEqual((w, h), (41, 16))
        self.assertEqual(len(data), 41 * 16 * 4)
        self.assertIsNone(flag_badge.pixmap('?'))
        icon = self.tray._pixmap()
        self.assertEqual(len(icon), 1)
        self.assertEqual(icon[0][0], 41)

    def test_paused_stopped_unknown_and_toggle(self):
        self.tray.state = describe(dict(compatibility=dict(enabled=False, automatic=False, available=False),
                                        settings=dict()))
        self.assertEqual(self.tray.icon(), 'media-playback-pause-symbolic')
        self.assertEqual(self.tray.props(3)['toggle-state'].unpack(), 0)
        self.assertEqual(menu_rows(self.tray.state, '', False)[21][2], 'resume')
        self.tray.state = describe(dict(installed=True, bridge=True, settings=dict()))
        self.assertEqual(self.tray.icon(), 'media-playback-stop-symbolic')
        self.assertEqual(menu_rows(self.tray.state, '', False)[21][2], 'start')
        self.tray.state = None
        self.assertFalse(menu_rows(None, '', False)[3][1])
        self.assertEqual(self.tray.icon(), 'dialog-warning-symbolic')

    def test_unchanged_status_emits_nothing(self):
        class Connection:
            def __init__(self): self.events = []
            def emit_signal(self, *args): self.events.append(args)
        self.tray.connection = Connection()
        self.tray.update(self.tray.state, '', False)
        self.assertFalse(self.tray.connection.events)
        self.tray.update(self.tray.state, 'failure', False)
        self.assertEqual(len(self.tray.connection.events), 4)

    def test_cached_host_receives_enabled_label_and_checkbox_updates(self):
        # GNOME caches properties separately from layout structure; a structural
        # LayoutUpdated signal alone does not refresh existing rows' enabled flag.
        ready = self.tray.state
        self.tray.state = None
        cache = {i: {k: v.unpack() for k, v in self.tray.props(i).items()}
                 for i, kind, *_ in MENU_SPEC if kind != 'sep'}
        class Host:
            def emit_signal(self, destination, path, interface, signal, parameters):
                if signal == 'ItemsPropertiesUpdated':
                    changed, removed = parameters.unpack()
                    for item, props in changed: cache[item].update(props)
                    for item, names in removed:
                        for name in names: cache[item].pop(name, None)
        self.tray.connection = Host()
        self.assertFalse(cache[21]['enabled'])
        self.tray.update(ready, '', False)
        self.assertTrue(cache[21]['enabled'])
        self.assertEqual(cache[21]['label'], 'Пауза')
        self.assertEqual(cache[3]['toggle-state'], 1)
        self.tray.update(ready, '', True)
        self.assertFalse(cache[21]['enabled'])
        paused = describe(dict(compatibility=dict(enabled=False, automatic=False, available=False), settings=dict()))
        self.tray.update(paused, '', False)
        self.assertTrue(cache[21]['enabled'])
        self.assertEqual(cache[21]['label'], 'Продолжить')
        self.assertEqual(cache[3]['toggle-state'], 0)
