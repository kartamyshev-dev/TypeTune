"""StatusNotifierItem and DBusMenu adapter. No keyboard or controller I/O here."""
from gi.repository import Gio, GLib
import flag_badge

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

# Stable IDs (GNOME caches them). kind: header | sep | check | action
# action is dispatched to the window; toggle key maps to app_settings.
MENU_SPEC = (
    (1,  'header', 'flag',                 None,                          None),
    (2,  'sep',    None,                   None,                          None),
    (3,  'check',  'Автопереключение',     'automatic',                   'auto-toggle'),
    (4,  'check',  'Ручное переключение (Double Shift)', 'manual_switching', 'manual-toggle'),
    (5,  'sep',    None,                   None,                          None),
    (6,  'check',  'Переключать только последнее слово', 'switch_only_last_word', 'switch-last-toggle'),
    (7,  'check',  'Не переключать слова', 'dont_switch_words',           'dont-switch-toggle'),
    (8,  'check',  'Не исправлять после смены раскладки', 'dont_correct_after_layout_change', 'anti-loop-toggle'),
    (9,  'sep',    None,                   None,                          None),
    (10, 'check',  'Звук переключения',    'play_switching_sound',        'sound-toggle'),
    (11, 'check',  'Показывать флаг раскладки', 'display_layout_flag',    'flag-toggle'),
    (12, 'sep',    None,                   None,                          None),
    (13, 'action', 'Выученные слова…',     None,                          'learned'),
    (14, 'action', 'Отключить автопереключение в…', None,                  'auto-disabled'),
    (15, 'action', 'Активные раскладки…',  None,                          'active-keyboards'),
    (16, 'sep',    None,                   None,                          None),
    (17, 'action', 'Разрешения',           None,                          'permissions'),
    (18, 'check',  'Автозапуск',           'autostart',                   'autostart-toggle'),
    (19, 'action', 'Открыть настройки',    None,                          'open'),
    (20, 'sep',    None,                   None,                          None),
    (21, 'check',  'Все выключено',        None,                          'pause'),
    (22, 'action', 'Выйти',                None,                          'quit'),
)
TOGGLE_KEYS = {item_id: key for item_id, kind, _, key, _ in MENU_SPEC if kind == 'check' and key}


def _state_flag(state):
    if not state:
        return '?'
    if not state.running:
        return 'paused'
    return getattr(state, 'flag', '?') or '?'


def _state_bool(state, key, default=True):
    if state is None:
        return default
    return bool(getattr(state, key, default))


def menu_rows(state, error, busy):
    running = bool(state and state.running)
    enabled = bool(state and state.enabled)
    flag = _state_flag(state)
    header = (flag_badge.status_title(getattr(state, 'flag', '?') if state else '?',
                                      _state_bool(state, 'display_layout_flag', True),
                                      running) if state else 'Получение состояния…')
    if error:
        header = 'Ошибка — откройте TypeTune'
    rows = {
        1: (header, False, None),
        3: ('Автопереключение', running and not busy, 'auto-off' if state and state.automatic else 'auto-on'),
        4: ('Ручное переключение (Double Shift)', running and not busy, 'manual-toggle'),
        6: ('Переключать только последнее слово', running and not busy, 'switch-last-toggle'),
        7: ('Не переключать слова', running and not busy, 'dont-switch-toggle'),
        8: ('Не исправлять после смены раскладки', running and not busy, 'anti-loop-toggle'),
        10: ('Звук переключения', running and not busy, 'sound-toggle'),
        11: ('Показывать флаг раскладки', running and not busy, 'flag-toggle'),
        13: ('Выученные слова…', running and not busy, 'learned'),
        14: ('Отключить автопереключение в…', running and not busy, 'auto-disabled'),
        15: ('Активные раскладки…', running and not busy, 'active-keyboards'),
        17: ('Разрешения', True, 'permissions'),
        18: ('Автозапуск', not busy and (running or bool(state and state.can_start) or bool(state and state.configurable)),
             'autostart-toggle'),
        19: ('Открыть TypeTune' + (f' · предложений: {state.suggestion_count}' if state and state.suggestion_count else ''),
             True, 'open'),
        22: ('Выйти', not busy, 'quit'),
    }
    if running:
        rows[21] = ('Пауза' if enabled else 'Продолжить', not busy, 'pause' if enabled else 'resume')
    else:
        rows[21] = ('Запустить TypeTune', not busy and bool(state and state.can_start), 'start')
    if state is None:
        for item_id in rows:
            if item_id != 1:
                rows[item_id] = (rows[item_id][0], False, rows[item_id][2])
    return rows


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
        if (state, error, busy) == (self.state, self.error, self.busy):
            return
        self.state, self.error, self.busy = state, error, busy
        self.revision += 1
        for signal in ['NewTitle', 'NewIcon', 'NewToolTip']:
            self.connection.emit_signal(None, PATH, ITEM, signal, None)
        # The tree is stable. GNOME caches row properties separately and needs
        # this signal to refresh enabled/label/toggle-state on existing items.
        properties = [(i, self.props(i)) for i, kind, *_ in MENU_SPEC if kind != 'sep']
        self.connection.emit_signal(None, MENU_PATH, MENU, 'ItemsPropertiesUpdated',
                                    GLib.Variant('(a(ia{sv})a(ias))', (properties, [])))

    def icon(self):
        if self.error or self.state is None:
            return 'dialog-warning-symbolic'
        if getattr(self.state, 'needs_permissions', False):
            return 'dialog-warning-symbolic'
        flag = _state_flag(self.state)
        if flag in ('us', 'ru') and _state_bool(self.state, 'display_layout_flag', True):
            # Theme SVG shipped in the .deb; hosts that ignore IconPixmap still show it.
            return 'typetune-flag-' + flag
        if not self.state.running:
            return 'media-playback-stop-symbolic'
        if not self.state.enabled:
            return 'media-playback-pause-symbolic'
        if self.state.title == 'Ожидает подходящее поле':
            return 'dialog-warning-symbolic'
        return 'input-keyboard-symbolic'

    def _pixmap(self):
        if self.error or self.state is None or not self.state.running:
            return []
        # Permission warning must win over the flag pixmap (IconName is the warning).
        if getattr(self.state, 'needs_permissions', False):
            return []
        if not _state_bool(self.state, 'display_layout_flag', True):
            return []
        return flag_badge.pixmap(getattr(self.state, 'flag', '?')) or []

    def property(self, connection, sender, path, interface, name):
        if interface == MENU:
            return {'Version':GLib.Variant('u',3), 'TextDirection':GLib.Variant('s','ltr'),
                    'Status':GLib.Variant('s','normal'), 'IconThemePath':GLib.Variant('as',[])}.get(name)
        title = 'TypeTune · ' + (self.state.title if self.state else 'Нет связи')
        label = flag_badge.status_title(getattr(self.state, 'flag', '?') if self.state else '?',
                                        _state_bool(self.state, 'display_layout_flag', True),
                                        bool(self.state and self.state.running))
        values = {
            'Category':('s','ApplicationStatus'), 'Id':('s','typetune'), 'Title':('s',title),
            'Status':('s','Active'), 'IconName':('s',self.icon()), 'IconThemePath':('s',''),
            'IconPixmap':('a(iiay)',self._pixmap()), 'OverlayIconName':('s',''), 'OverlayIconPixmap':('a(iiay)',[]),
            'AttentionIconName':('s','dialog-warning-symbolic'), 'AttentionIconPixmap':('a(iiay)',[]),
            'AttentionMovieName':('s',''), 'WindowId':('i',0), 'Menu':('o',MENU_PATH), 'ItemIsMenu':('b',True),
            'ToolTip':('(sa(iiay)ss)',(self.icon(), self._pixmap(), title, self.error or 'Double Shift — переключить слово')),
            'XAyatanaLabel':('s',label), 'XAyatanaLabelGuide':('s',label),
        }
        return GLib.Variant(*values[name]) if name in values else None

    def props(self, item, names=()):
        if item == 0:
            props = {'children-display': GLib.Variant('s','submenu')}
        else:
            spec = next((row for row in MENU_SPEC if row[0] == item), None)
            if spec is None or spec[1] == 'sep':
                props = {'visible': GLib.Variant('b', False)}
            elif spec[1] == 'header':
                label, _, _ = menu_rows(self.state, self.error, self.busy).get(item, ('', False, None))
                props = {'label': GLib.Variant('s', label), 'enabled': GLib.Variant('b', False),
                         'visible': GLib.Variant('b', True)}
                icon = flag_badge.menu_pixmap(_state_flag(self.state) if self.state and self.state.running
                                              and _state_bool(self.state, 'display_layout_flag', True) else '?')
                if icon:
                    props['icon-data'] = GLib.Variant('(iiay)', icon[0])
            else:
                label, enabled, _ = menu_rows(self.state, self.error, self.busy).get(item, (spec[2], False, None))
                props = {'label': GLib.Variant('s', label or spec[2] or ''),
                         'enabled': GLib.Variant('b', enabled), 'visible': GLib.Variant('b', True)}
                if spec[1] == 'check':
                    key = TOGGLE_KEYS.get(item)
                    if key == 'autostart':
                        on = bool(self.state and getattr(self.state, 'autostart', False))
                    elif key:
                        on = _state_bool(self.state, key, key in ('automatic', 'manual_switching',
                                                                  'switch_only_last_word',
                                                                  'dont_correct_after_layout_change',
                                                                  'display_layout_flag'))
                    else:
                        on = bool(self.state and self.state.enabled)
                    props.update({'toggle-type': GLib.Variant('s','checkmark'),
                                  'toggle-state': GLib.Variant('i', int(on))})
        return {k:v for k,v in props.items() if not names or k in names}

    def click(self, item, event):
        row = menu_rows(self.state, self.error, self.busy).get(item)
        if not row:
            return False
        if event == 'clicked' and row[1]:
            action = row[2]
            if action in ('open', 'learned', 'auto-disabled', 'active-keyboards', 'permissions'):
                self.window.present()
                if action != 'open' and hasattr(self.window, 'show_page'):
                    self.window.show_page(action)
            elif action in ('auto-toggle',):
                self.window.dispatch('auto-off' if (self.state and self.state.automatic) else 'auto-on')
            elif action == 'manual-toggle':
                self.window.dispatch('manual-toggle')
            elif action == 'switch-last-toggle':
                self.window.dispatch('switch-last-toggle')
            elif action == 'dont-switch-toggle':
                self.window.dispatch('dont-switch-toggle')
            elif action == 'anti-loop-toggle':
                self.window.dispatch('anti-loop-toggle')
            elif action == 'sound-toggle':
                self.window.dispatch('sound-toggle')
            elif action == 'flag-toggle':
                self.window.dispatch('flag-toggle')
            elif action == 'autostart-toggle':
                self.window.dispatch('autostart-off' if (self.state and self.state.autostart) else 'autostart-on')
            elif action:
                self.window.dispatch(action)
        return True

    def method(self, connection, sender, path, interface, method, params, invocation):
        args = params.unpack()
        try:
            if interface == ITEM:
                if method in ('Activate', 'SecondaryActivate', 'ContextMenu'):
                    self.window.present()
                invocation.return_value(None)
                return
            if method == 'GetLayout':
                parent, depth, names = args
                children = [GLib.Variant('(ia{sv}av)', (i, self.props(i, names), []))
                            for i, kind, *_ in MENU_SPEC if kind != 'sep'] if parent == 0 and depth != 0 else []
                result = GLib.Variant('(u(ia{sv}av))', (self.revision, (parent, self.props(parent, names), children)))
            elif method == 'GetGroupProperties':
                ids, names = args
                known = {row[0] for row in MENU_SPEC}
                result = GLib.Variant('(a(ia{sv}))', ([(i, self.props(i, names)) for i in ids if i in known],))
            elif method == 'GetProperty':
                result = GLib.Variant('(v)', (self.props(args[0])[args[1]],))
            elif method == 'Event':
                self.click(args[0], args[1]); result = None
            elif method == 'EventGroup':
                result = GLib.Variant('(ai)', ([e[0] for e in args[0] if not self.click(e[0], e[1])],))
            elif method == 'AboutToShow':
                result = GLib.Variant('(b)', (False,))
            elif method == 'AboutToShowGroup':
                result = GLib.Variant('(aiai)', ([], []))
            else:
                raise ValueError('Unknown method')
            invocation.return_value(result)
        except (KeyError, ValueError, TypeError) as exc:
            invocation.return_dbus_error('com.canonical.dbusmenu.Error', str(exc))
