"""StatusNotifierItem and DBusMenu adapter. No keyboard or controller I/O here."""
from gi.repository import Gio, GLib

ITEM = 'org.kde.StatusNotifierItem'
MENU = 'com.canonical.dbusmenu'
PATH = '/StatusNotifierItem'
MENU_PATH = '/TypeTuneMenu'
WATCHER = 'org.kde.StatusNotifierWatcher'


def xml_interface(name, properties, methods, signals):
    def args(items, direction):
        return ''.join(f'<arg type="{kind}" direction="{direction}"/>' for kind in items)
    return ('<node><interface name="' + name + '">' +
            ''.join(f'<property name="{key}" type="{kind}" access="read"/>' for key, kind in properties.items()) +
            ''.join(f'<method name="{key}">{args(ins, "in")}{args(outs, "out")}</method>' for key, (ins, outs) in methods.items()) +
            ''.join(f'<signal name="{key}">{args(kinds, "out")}</signal>' for key, kinds in signals.items()) +
            '</interface></node>')


ITEM_XML = xml_interface(ITEM, {
    'Category':'s', 'Id':'s', 'Title':'s', 'Status':'s', 'IconName':'s', 'IconThemePath':'s',
    'IconPixmap':'a(iiay)', 'OverlayIconName':'s', 'OverlayIconPixmap':'a(iiay)',
    'AttentionIconName':'s', 'AttentionIconPixmap':'a(iiay)', 'AttentionMovieName':'s',
    'WindowId':'i', 'Menu':'o', 'ItemIsMenu':'b', 'ToolTip':'(sa(iiay)ss)',
    'XAyatanaLabel':'s', 'XAyatanaLabelGuide':'s',
}, {'Activate':(['i','i'],[]), 'SecondaryActivate':(['i','i'],[]),
    'ContextMenu':(['i','i'],[]), 'Scroll':(['i','s'],[])},
    {'NewTitle':[], 'NewIcon':[], 'NewToolTip':[], 'NewStatus':['s']})
MENU_XML = xml_interface(MENU, {'Version':'u','TextDirection':'s','Status':'s','IconThemePath':'as'}, {
    'GetLayout':(['i','i','as'],['u','(ia{sv}av)']),
    'GetGroupProperties':(['ai','as'],['a(ia{sv})']), 'GetProperty':(['i','s'],['v']),
    'Event':(['i','s','v','u'],[]), 'EventGroup':(['a(isvu)'],['ai']),
    'AboutToShow':(['i'],['b']), 'AboutToShowGroup':(['ai'],['ai','ai']),
}, {'LayoutUpdated':['u','i'], 'ItemsPropertiesUpdated':['a(ia{sv})','a(ias)']})


def menu_rows(state, error, busy):
    running = bool(state and state.running)
    return {
        1: ('Ошибка — откройте TypeTune' if error else (state.title if state else 'Получение состояния…'), False, None),
        2: ('Открыть TypeTune' + (f' · предложений: {state.suggestion_count}' if state and state.suggestion_count else ''), True, 'open'),
        3: ('Пауза' if state and state.enabled else 'Продолжить', running and not busy,
            'pause' if state and state.enabled else 'resume'),
        4: ('Автокоррекция', running and not busy, 'auto-off' if state and state.automatic else 'auto-on'),
        5: ('Остановить' if running else 'Запустить TypeTune',
            not busy and (running or bool(state and state.can_start)), 'stop' if running else 'start'),
    }


class Tray:
    def __init__(self, connection, window):
        self.connection = connection
        self.window = window
        self.state = None
        self.error = ''
        self.busy = False
        self.revision = 1
        self.registered = False
        self.registrations = []
        for path, xml in [(PATH, ITEM_XML), (MENU_PATH, MENU_XML)]:
            info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
            self.registrations.append(connection.register_object(path, info, self.method, self.property, None))
        self.watch = Gio.bus_watch_name_on_connection(connection, WATCHER, Gio.BusNameWatcherFlags.NONE,
                                                     self.appeared, self.vanished)

    def appeared(self, connection, name, owner):
        connection.call(WATCHER, '/StatusNotifierWatcher', WATCHER, 'RegisterStatusNotifierItem',
                        GLib.Variant('(s)', (PATH,)), None, Gio.DBusCallFlags.NONE, 3000, None, self.registered_reply)

    def registered_reply(self, connection, result):
        try:
            connection.call_finish(result)
            self.registered = True
        except GLib.Error:
            self.registered = False

    def vanished(self, *_):
        self.registered = False

    def close(self):
        Gio.bus_unwatch_name(self.watch)
        for registration in self.registrations:
            self.connection.unregister_object(registration)

    def update(self, state, error, busy):
        if (state, error, busy) == (self.state, self.error, self.busy): return
        self.state, self.error, self.busy = state, error, busy
        self.revision += 1
        for signal in ['NewTitle', 'NewIcon', 'NewToolTip']:
            self.connection.emit_signal(None, PATH, ITEM, signal, None)
        # The tree is stable. GNOME caches row properties separately and needs
        # this signal to refresh enabled/label/toggle-state on existing items.
        properties = [(i, self.props(i)) for i in range(1, 6)]
        self.connection.emit_signal(None, MENU_PATH, MENU, 'ItemsPropertiesUpdated',
                                    GLib.Variant('(a(ia{sv})a(ias))', (properties, [])))

    def icon(self):
        if self.error or self.state is None: return 'dialog-warning-symbolic'
        if not self.state.running: return 'media-playback-stop-symbolic'
        if not self.state.enabled: return 'media-playback-pause-symbolic'
        if self.state.title == 'Ожидает подходящее поле': return 'dialog-warning-symbolic'
        return 'input-keyboard-symbolic'

    def property(self, connection, sender, path, interface, name):
        if interface == MENU:
            return {'Version':GLib.Variant('u',3), 'TextDirection':GLib.Variant('s','ltr'),
                    'Status':GLib.Variant('s','normal'), 'IconThemePath':GLib.Variant('as',[])}.get(name)
        title = 'TypeTune · ' + (self.state.title if self.state else 'Нет связи')
        values = {
            'Category':('s','ApplicationStatus'), 'Id':('s','typetune'), 'Title':('s',title),
            'Status':('s','Active'), 'IconName':('s',self.icon()), 'IconThemePath':('s',''),
            'IconPixmap':('a(iiay)',[]), 'OverlayIconName':('s',''), 'OverlayIconPixmap':('a(iiay)',[]),
            'AttentionIconName':('s','dialog-warning-symbolic'), 'AttentionIconPixmap':('a(iiay)',[]),
            'AttentionMovieName':('s',''), 'WindowId':('i',0), 'Menu':('o',MENU_PATH), 'ItemIsMenu':('b',True),
            'ToolTip':('(sa(iiay)ss)',(self.icon(), [], title, self.error or 'Double Shift — переключить слово')),
            'XAyatanaLabel':('s','TT'), 'XAyatanaLabelGuide':('s','TT'),
        }
        return GLib.Variant(*values[name]) if name in values else None

    def props(self, item, names=()):
        if item == 0: props = {'children-display': GLib.Variant('s','submenu')}
        else:
            label, enabled, _ = menu_rows(self.state, self.error, self.busy)[item]
            props = {'label':GLib.Variant('s',label), 'enabled':GLib.Variant('b',enabled), 'visible':GLib.Variant('b',True)}
            if item == 4:
                props.update({'toggle-type':GLib.Variant('s','checkmark'),
                              'toggle-state':GLib.Variant('i',int(bool(self.state and self.state.automatic)))})
        return {k:v for k,v in props.items() if not names or k in names}

    def click(self, item, event):
        row = menu_rows(self.state, self.error, self.busy).get(item)
        if not row: return False
        if event == 'clicked' and row[1]:
            if row[2] == 'open': self.window.present()
            elif row[2]: self.window.dispatch(row[2])
        return True

    def method(self, connection, sender, path, interface, method, params, invocation):
        args = params.unpack()
        try:
            if interface == ITEM:
                if method in ('Activate', 'SecondaryActivate', 'ContextMenu'): self.window.present()
                invocation.return_value(None); return
            if method == 'GetLayout':
                parent, depth, names = args
                children = [GLib.Variant('(ia{sv}av)', (i,self.props(i,names),[])) for i in range(1,6)] if parent == 0 and depth != 0 else []
                result = GLib.Variant('(u(ia{sv}av))',(self.revision,(parent,self.props(parent,names),children)))
            elif method == 'GetGroupProperties':
                ids, names = args
                result = GLib.Variant('(a(ia{sv}))',([(i,self.props(i,names)) for i in ids if i in range(6)],))
            elif method == 'GetProperty': result = GLib.Variant('(v)', (self.props(args[0])[args[1]],))
            elif method == 'Event': self.click(args[0],args[1]); result = None
            elif method == 'EventGroup':
                result = GLib.Variant('(ai)',([e[0] for e in args[0] if not self.click(e[0],e[1])],))
            elif method == 'AboutToShow': result = GLib.Variant('(b)', (False,))
            elif method == 'AboutToShowGroup': result = GLib.Variant('(aiai)',([],[]))
            else: raise ValueError('Unknown method')
            invocation.return_value(result)
        except (KeyError, ValueError, TypeError) as exc:
            invocation.return_dbus_error('com.canonical.dbusmenu.Error', str(exc))
