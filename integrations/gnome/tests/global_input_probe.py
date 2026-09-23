"""Instrument ONLY the disposable extension copy. Never install this probe."""
def instrument(path):
    text = path.read_text()
    text = text.replace('<method name="GetTextContext">', '<method name="ProbeKeys"><arg type="s" direction="out"/></method>\n<method name="ProbeDisplay"><arg type="s" direction="out"/></method><method name="ProbeCreate"/><method name="ProbeInject"/><method name="ProbeSequence"><arg type="s" direction="in"/><arg type="s" direction="out"/></method><method name="ProbeCancel"/>\n<method name="GetTextContext">', 1)
    text = text.replace('this._connections = [];', '''this._connections = [];
        this._probe = {down: 0, up: 0, aCode: null, devices: 0};
        this._probeDevices = new Set();''', 1)
    text = text.replace("if ([Clutter.EventType.BUTTON_PRESS", '''if ([Clutter.EventType.KEY_PRESS, Clutter.EventType.KEY_RELEASE].includes(event.type())) {
                    this._probe[event.type() === Clutter.EventType.KEY_PRESS ? 'down' : 'up']++;
                    if (event.get_key_symbol() === 97)
                        this._probe.aCode = event.get_key_code();
                    this._probeDevices.add(event.get_source_device());
                    this._probe.devices = this._probeDevices.size;
                }
                if ([Clutter.EventType.BUTTON_PRESS''', 1)
    text = text.replace('    GetSnapshot() {', '''    ProbeKeys() { return JSON.stringify(this._probe); }

    ProbeDisplay() { return JSON.stringify({display: GLib.getenv('DISPLAY'), authority: GLib.getenv('XAUTHORITY')}); }

    ProbeCreate() {
        this._probeKeyboard = Clutter.get_default_backend().get_default_seat().create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        this._probeKeyboard.notify_key(GLib.get_monotonic_time(), 42, Clutter.KeyState.PRESSED);
        this._probeKeyboard.notify_key(GLib.get_monotonic_time(), 42, Clutter.KeyState.RELEASED);
    }

    ProbeCancel() {
        if (this._probeTimer) { GLib.source_remove(this._probeTimer); this._probeTimer = null; }
        for (const code of this._probeHeld ?? [])
            this._probeKeyboard.notify_key(GLib.get_monotonic_time(), code, Clutter.KeyState.RELEASED);
        this._probeHeld = new Set();
        if (this._probeInvocation) {
            this._probeInvocation.return_value(new GLib.Variant('(s)', ['indeterminate']));
            this._probeInvocation = null;
        }
    }

    ProbeSequenceAsync([json], invocation) {
        this.ProbeCancel();
        const keys = JSON.parse(json);
        if (keys.length > 768) throw new Error('fixture sequence too large');
        this._probeInvocation = invocation;
        this._probeTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 8, () => {
            const pair = keys.shift();
            if (!pair) {
                this._probeTimer = null;
                this._probeInvocation = null;
                invocation.return_value(new GLib.Variant('(s)', ['injected-unverified']));
                return GLib.SOURCE_REMOVE;
            }
            const [code, down] = pair;
            if (down) this._probeHeld.add(code); else this._probeHeld.delete(code);
            this._probeKeyboard.notify_key(GLib.get_monotonic_time(), code, down ? Clutter.KeyState.PRESSED : Clutter.KeyState.RELEASED);
            return GLib.SOURCE_CONTINUE;
        });
    }

    ProbeInject() {
        // Evdev codes at the virtual-device boundary, NOT XKB codes.
        for (const code of [14, 14, 34, 35, 48, 32, 20, 49]) {
            this._probeKeyboard.notify_key(GLib.get_monotonic_time(), code, Clutter.KeyState.PRESSED);
            this._probeKeyboard.notify_key(GLib.get_monotonic_time(), code, Clutter.KeyState.RELEASED);
        }
    }

    GetSnapshot() {''', 1)
    path.write_text(text)
