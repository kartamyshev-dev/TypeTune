#!/usr/bin/python3
"""Opt-in IBus runtime for guarded native Wayland text fields."""
import json
import os
from pathlib import Path
import gi
gi.require_version('IBus', '1.0')
from gi.repository import IBus, Gio, GLib
import probe_engine as shared
from session_guard import SessionGuard


def cancel_all():
    for engine in tuple(shared.ENGINES):
        engine.manual.cancel()


guard = SessionGuard(cancel_all)
shared.PROFILE = guard.allows
shared.VALIDATE_STATE = guard.validate_state
shared.OBSERVE_FIXTURE = False
import preferences
preferences.initialize()
import application_rules
application_rules.initialize()
import app_settings
import correction_feedback
automatic = app_settings.initial_automatic()
shared.AUTOMATIC = lambda: automatic and not preferences.ERROR and guard.allows() and application_rules.allows(guard.application)
shared.SWITCH_MODE = guard.switch_mode
IBus.init()
bus = IBus.Bus.new()
if not bus.is_connected():
    raise SystemExit('IBus недоступен')
factory = IBus.Factory.new(bus.get_connection())
factory.add_engine('typetune-test', shared.ProbeEngine)
factory.add_engine('typetune-test-ru', shared.ProbeEngine)
bus.request_name('org.freedesktop.IBus.TypeTuneTest', 0)
loop = GLib.MainLoop()
bus.connect('disconnected', lambda *_: loop.quit())


def status():
    return dict(suggestion_count=len(correction_feedback.FEEDBACK.pending()),**application_rules.status(guard.application if guard.allows() else None), words_generation=preferences.CURRENT['generation'], words_error=preferences.ERROR, automatic=automatic and not preferences.ERROR and not application_rules.ERROR, mode=guard.source_id, mode_result=guard.mode_result, enabled=guard.enabled, available=guard.allows(), reason=guard.reason,
                **{key: value for key, value in shared.STATS.items() if key.startswith(('manual_', 'auto_'))})


def method(connection, sender, path, interface, name, parameters, invocation):
    global automatic
    if correction_feedback.method(correction_feedback.FEEDBACK,name,parameters,invocation):return
    if name == 'GetStatus':
        invocation.return_value(GLib.Variant('(s)', (json.dumps(status()),)))
    elif name in ('ReloadWords', 'ReloadApplications'):
        try:
            config = preferences if name == 'ReloadWords' else application_rules
            generation = config.reload(parameters.unpack()[0])
            cancel_all()
            invocation.return_value(GLib.Variant('(s)', (generation,)))
        except (ValueError, OSError) as error:
            invocation.return_dbus_error('org.typetune.Error.Words', str(error))
    elif name == 'SetEnabled':
        guard.set_enabled(parameters.unpack()[0])
        invocation.return_value(GLib.Variant('(b)', (guard.enabled,)))
    elif name == 'SetAutomatic':
        automatic = parameters.unpack()[0]
        cancel_all()
        invocation.return_value(GLib.Variant('(b)', (automatic,)))
    elif name == 'Quit':
        guard.set_enabled(False)
        invocation.return_value(None)
        GLib.idle_add(loop.quit)
    else:
        invocation.return_dbus_error('org.typetune.Error.UnknownMethod', 'Unknown method')


xml = '''<node><interface name="org.typetune.IBus1">
<method name="SetAutomatic"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
<method name="ReloadApplications"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="ReloadWords"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="Quit"/>
<method name="GetStatus"><arg type="s" direction="out"/></method>
<method name="SetEnabled"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
</interface></node>'''
xml=xml.replace('</interface>',correction_feedback.XML+'</interface>')
interface = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
guard.connection.register_object('/org/typetune/IBus1', interface, method, None, None)
Gio.bus_own_name_on_connection(guard.connection, 'org.typetune.IBus', Gio.BusNameOwnerFlags.NONE, None, None)

# Native acceptance may request the same aggregates as the older probe. This
# branch is unavailable in a normal login and never records actual field text.
if 'TYPETUNE_NESTED_STAND' in os.environ:
    base = Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
    assert Path(os.environ['XDG_RUNTIME_DIR']).resolve() == base / 'runtime'
    def publish():
        temp = base / 'ibus-stats.tmp'
        temp.write_text(json.dumps(shared.STATS))
        temp.replace(base / 'ibus-stats.json')
        return True
    GLib.timeout_add(50, publish)
loop.run()
