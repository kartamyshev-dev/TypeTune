import unittest
from gi.repository import Gio, GLib
from gui_model import describe
from tray import Tray, ITEM_XML, MENU_XML, MENU, menu_rows


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
        self.tray.state = describe(dict(compatibility=dict(enabled=True, automatic=True, available=True, mode='ru')))
        self.tray.error = ''; self.tray.busy = False
        self.tray.revision = 1

    def test_menu_actions_and_busy_guard(self):
        self.tray.click(2,'clicked'); self.tray.click(3,'clicked'); self.tray.click(4,'clicked')
        self.assertEqual(self.tray.window.calls, ['open','pause','auto-off'])
        self.tray.busy = True
        self.tray.click(3,'clicked'); self.tray.click(4,'clicked'); self.tray.click(5,'clicked')
        self.assertEqual(self.tray.window.calls, ['open','pause','auto-off'])
        self.assertFalse(self.tray.click(999,'clicked'))

    def test_layout_serialization_and_property_filter(self):
        for xml in [ITEM_XML, MENU_XML]: self.assertTrue(Gio.DBusNodeInfo.new_for_xml(xml).interfaces)
        invocation = Invocation()
        self.tray.method(None,None,None,MENU,'GetLayout',GLib.Variant('(iias)',(0,-1,['label'])),invocation)
        revision, root = invocation.value.unpack()
        self.assertEqual(revision,1)
        self.assertEqual(len(root[2]),5)
        self.assertTrue(all(set(child[1]) == {'label'} for child in root[2]))
        self.tray.method(None,None,None,MENU,'GetProperty',GLib.Variant('(is)',(999,'label')),invocation)
        self.assertEqual(invocation.value[0],'error')

    def test_paused_stopped_unknown_and_toggle(self):
        self.tray.state = describe(dict(compatibility=dict(enabled=False,automatic=False,available=False)))
        self.assertEqual(self.tray.icon(),'media-playback-pause-symbolic')
        self.assertEqual(self.tray.props(4)['toggle-state'].unpack(),0)
        self.assertEqual(menu_rows(self.tray.state,'',False)[3][2],'resume')
        self.tray.state = describe(dict(installed=True,bridge=True))
        self.assertEqual(self.tray.icon(),'media-playback-stop-symbolic')
        self.assertEqual(menu_rows(self.tray.state,'',False)[5][2],'start')
        self.tray.state = None
        self.assertFalse(menu_rows(None,'',False)[3][1])
        self.assertEqual(self.tray.icon(),'dialog-warning-symbolic')

    def test_unchanged_status_emits_nothing(self):
        class Connection:
            def __init__(self): self.events=[]
            def emit_signal(self,*args): self.events.append(args)
        self.tray.connection=Connection()
        self.tray.update(self.tray.state,'',False)
        self.assertFalse(self.tray.connection.events)
        self.tray.update(self.tray.state,'failure',False)
        self.assertEqual(len(self.tray.connection.events),4)

    def test_cached_host_receives_enabled_label_and_checkbox_updates(self):
        # GNOME caches properties separately from layout structure; a structural
        # LayoutUpdated signal alone does not refresh existing rows' enabled flag.
        ready = self.tray.state
        self.tray.state = None
        cache = {i: {k:v.unpack() for k,v in self.tray.props(i).items()} for i in range(1,6)}
        class Host:
            def emit_signal(self, destination, path, interface, signal, parameters):
                if signal == 'ItemsPropertiesUpdated':
                    changed, removed = parameters.unpack()
                    for item, props in changed: cache[item].update(props)
                    for item, names in removed:
                        for name in names: cache[item].pop(name, None)
        self.tray.connection = Host()
        self.assertFalse(cache[3]['enabled'])
        self.tray.update(ready, '', False)
        self.assertTrue(cache[3]['enabled'])
        self.assertEqual(cache[3]['label'], 'Пауза')
        self.assertEqual(cache[4]['toggle-state'], 1)
        self.tray.update(ready, '', True)
        self.assertFalse(cache[3]['enabled'])
        paused = describe(dict(compatibility=dict(enabled=False,automatic=False,available=False)))
        self.tray.update(paused, '', False)
        self.assertTrue(cache[3]['enabled'])
        self.assertEqual(cache[3]['label'], 'Продолжить')
        self.assertEqual(cache[4]['toggle-state'], 0)
