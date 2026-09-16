import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Keyboard from 'resource:///org/gnome/shell/ui/status/keyboard.js';
import {BridgeState, sourceRequest} from './state.js';

const XML = `<node><interface name="org.typetune.Session1">
<method name="GetCompatContext"><arg type="s" direction="out"/></method>
<method name="GetTextContext"><arg type="s" direction="out" name="context"/></method>
<method name="GetSnapshot"><arg type="s" direction="out" name="snapshot"/></method>
<method name="RequestSource"><arg type="s" direction="in" name="request"/><arg type="s" direction="out" name="result"/></method>
<signal name="Changed"><arg type="s" name="instance"/><arg type="t" name="generation"/></signal>
</interface></node>`;

export default class TypeTuneSessionBridge extends Extension {
    enable() {
        this._connections = [];
        this._interaction = 1;
        this._state = new BridgeState(GLib.uuid_string_random());
        try {
            if (!Main.screenShield)
                throw new Error('TypeTune bridge requires GNOME screen shield');
            this._sources = Keyboard.getInputSourceManager();
            this._settings = new Gio.Settings({schema_id: 'org.gnome.desktop.input-sources'});
            const connect = (object, signal, source = false) => {
                const id = object.connect(signal, () => this._changed(source));
                this._connections.push([object, id]);
            };
            connect(global.display, 'notify::focus-window');
            const pointer = global.stage.connect('captured-event', (_actor, event) => {
                if ([Clutter.EventType.BUTTON_PRESS, Clutter.EventType.TOUCH_BEGIN].includes(event.type()))
                    this._changed(false);
                return Clutter.EVENT_PROPAGATE;
            });
            this._connections.push([global.stage, pointer]);
            connect(this._sources, 'current-source-changed', true);
            connect(this._sources, 'sources-changed', true);
            connect(global.backend, 'keymap-changed', true);
            connect(global.backend, 'keymap-layout-group-changed', true);
            for (const key of ['xkb-options', 'xkb-model', 'per-window'])
                connect(this._settings, `changed::${key}`, true);
            connect(Main.screenShield, 'locked-changed');
            connect(Main.screenShield, 'active-changed');
            connect(Main.sessionMode, 'updated');
            connect(Main.overview, 'showing');
            connect(Main.overview, 'hidden');
            this._dbus = Gio.DBusExportedObject.wrapJSObject(XML, this);
            this._dbus.export(Gio.DBus.session, '/org/typetune/Session1');
        } catch (error) {
            this.disable();
            throw error;
        }
    }

    _changed(source) {
        if (!source) this._interaction++;
        this._state.invalidate(source);
        this._dbus?.emit_signal('Changed', new GLib.Variant('(st)',
            [this._state.instance, this._state.generation]));
    }

    GetSnapshot() {
        const window = global.display.focus_window;
        const clientType = window?.get_client_type();
        return JSON.stringify(this._state.snapshot({
            source: this._sources.currentSource,
            externalSource: this._sources.keyboardManager.isExternal(),
            window,
            windowBackend: clientType === Meta.WindowClientType.WAYLAND ? 'wayland' :
                clientType === Meta.WindowClientType.X11 ? 'x11' : 'unknown',
            locked: Main.screenShield.locked,
            shieldActive: Main.screenShield.active,
            overview: Main.overview.visible,
            userSession: !Main.sessionMode.isLocked && !Main.sessionMode.isGreeter &&
                (Main.sessionMode.currentMode === 'user' || Main.sessionMode.parentMode === 'user'),
        }));
    }

    GetCompatContext() {
        return JSON.stringify({
            ...JSON.parse(this.GetTextContext()),
            modifiers: global.get_pointer()[2],
            interaction_generation: this._interaction,
            options: this._settings.get_strv('xkb-options'),
            model: this._settings.get_string('xkb-model'),
        });
    }

    GetTextContext() {
        const snapshot = JSON.parse(this.GetSnapshot());
        const window = global.display.focus_window;
        const app = snapshot.window ? Shell.WindowTracker.get_default().get_window_app(window) : null;
        // Desktop identity only: never a title, URL or document name.
        return JSON.stringify({snapshot, app_id: app?.get_id() ?? '', pid: snapshot.window ? window.get_pid() : 0});
    }

    RequestSource(json) {
        const reject = reason => JSON.stringify({status: 'rejected', reason});
        if (json.length > 1024)
            return reject('invalid_request');
        let request;
        try { request = JSON.parse(json); } catch (_) { return reject('invalid_request'); }
        const current = JSON.parse(this.GetSnapshot());
        const reason = sourceRequest(request, current);
        if (reason)
            return reject(reason);
        const sources = Object.values(this._sources.inputSources).filter(source =>
            source.type === 'xkb' && source.id === request.target && source.xkbId === request.target);
        if (sources.length !== 1)
            return reject('source_unavailable');
        if (current.source_id === request.target)
            return JSON.stringify({status: 'unchanged'});
        try {
            sources[0].activate(true);
            // Activation is not confirmation that a client's subsequent input used it.
            // Caller must read back state; errors after this point cannot be retried blindly.
            return JSON.stringify({status: 'requested'});
        } catch (_) {
            return JSON.stringify({status: 'indeterminate'});
        }
    }

    disable() {
        // Unexport first: callers must fail, not consume a last-known snapshot.
        this._dbus?.unexport();
        this._dbus = null;
        for (const [object, id] of this._connections ?? [])
            object.disconnect(id);
        this._connections = [];
        this._sources = null;
        this._settings = null;
        this._state = null;
    }
}
