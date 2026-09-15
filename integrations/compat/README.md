# Compatibility backend

Explicit opt-in keyboard-history profile inspired by Espanso architecture.
No Espanso source code is copied. Runtime uses its own passive evdev/uinput helper.
Unknown text/selection/sensitivity/composition remain visible in status.

User commands and limitations: [guide](../../docs/35-user-test.md).
Implementation and precise native test boundaries: [checkpoint](../../docs/37-universal-input-investigation.md).

```sh
/usr/bin/python3 -m unittest discover -s integrations/compat -p 'test_*.py'
cargo test -p typetune-cli --example compat_transport --offline
python3 integrations/gnome/tests/native_stand.py --compat-stand
python3 integrations/gnome/tests/native_stand.py --compat-xwayland
```
