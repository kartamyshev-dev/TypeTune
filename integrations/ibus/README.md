# IBus: пользовательский preview

US↔RU коррекция через общий Rust engine для GNOME 50 / Wayland: Double Shift,
автокоррекция на Space и смена источника для следующего ввода.
Chrome и GNOME Text Editor приняты; для других приложений нужен IBus + AT-SPI proof.
[Установка, запуск, остановка и ограничения](../../docs/35-user-test.md).

```sh
./scripts/typetune-test install
# После первого повторного входа в GNOME:
./scripts/typetune-test browser
./scripts/typetune-test stop
```

`runtime_engine.py` использует реальный `SessionGuard` вместо стендового marker.
Неизвестный контекст, неподдержанный app ID/backend/source, пароль и выделение
не разрешают edit. Control API подтверждает effective pause/resume; stop удаляет
только собственный источник. Ordinary keys проходят без ожидания D-Bus.

Проверки из корня репозитория:

```sh
cargo build -p typetune-cli -p typetune-ibus --offline
/usr/bin/python3 integrations/ibus/test_gesture.py
/usr/bin/python3 integrations/ibus/test_manual.py
/usr/bin/python3 integrations/ibus/test_session_guard.py
python3 integrations/gnome/tests/native_stand.py --runtime-stand
python3 integrations/gnome/tests/native_stand.py --ibus-stand
```

`--runtime-stand` действительно устанавливает release-сборку в private XDG dirs,
использует environment.d generator и проверяет запуск, браузер, pause/resume,
stop, повторный запуск, восстановление RU и uninstall. Основная сессия не меняется.
Нужны GNOME 50, IBus + Python GI IBus/Atspi, GNOME Text Editor, google-chrome.

`probe_engine.py` сохранён для прежнего исследовательского стенда. В обычном runtime
его fixture-text instrumentation отключён. В диагностике runtime — только исходы
операций, без text/key values, clipboard и заголовков окон. Максимум контекста в RAM
16 KiB. Delete/commit не атомарны; неопределённый результат не повторяется.

Предыдущие checkpoints: [32](../../docs/32-ibus-observation-checkpoint.md),
[33](../../docs/33-browser-ibus-checkpoint.md), [34](../../docs/34-ibus-manual-checkpoint.md).
