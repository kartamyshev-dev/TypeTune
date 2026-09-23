#!/usr/bin/env python3
"""Explicit source command. Requires the enabled TypeTune GNOME bridge."""
import argparse
import json
import time
import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib


def switch(target):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    owner = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                          'org.freedesktop.DBus', 'GetNameOwner',
                          GLib.Variant('(s)', ('org.gnome.Shell',)), None,
                          Gio.DBusCallFlags.NONE, 750, None).unpack()[0]

    def call(method, args=None):
        value = bus.call_sync(owner, '/org/typetune/Session1', 'org.typetune.Session1',
                              method, args, None, Gio.DBusCallFlags.NONE, 750, None).unpack()[0]
        if len(value) > 4096:
            raise ValueError('oversized reply')
        return json.loads(value)

    before = call('GetSnapshot')
    request = {key: before[key] for key in ('instance', 'generation', 'window')}
    request['target'] = target
    try:
        result = call('RequestSource', GLib.Variant('(s)', (json.dumps(request),)))
        if result.get('status') not in ('requested', 'unchanged'):
            return result
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            after = call('GetSnapshot')
            if (after['instance'] != before['instance'] or after['window'] != before['window'] or
                    after['locked'] or after['shield_active'] or after['overview'] or
                    not after['user_session'] or after['external_source'] or
                    after['generation'] - before['generation'] !=
                    after['source_generation'] - before['source_generation']):
                return {'status': 'indeterminate', 'reason': 'context_changed'}
            if after['source_type'] == 'xkb' and after['source_id'] == target and after['xkb_id'] == target:
                return {'status': 'observed', 'source': target}
            time.sleep(.02)
        return {'status': 'indeterminate', 'reason': 'readback_timeout'}
    except (GLib.Error, ValueError, KeyError):
        return {'status': 'indeterminate', 'reason': 'request_or_readback_failed'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', choices=('us', 'ru'))
    args = parser.parse_args()
    try:
        result = switch(args.source)
    except (GLib.Error, ValueError, KeyError):
        result = {'status': 'unavailable', 'reason': 'bridge_unavailable'}
    print(json.dumps(result))
    return 0 if result.get('status') == 'observed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
