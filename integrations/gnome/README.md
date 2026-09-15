# TypeTune GNOME Session Bridge

Расширение метаданных и явного управления источником для **GNOME Shell 50**. Экспортирует `org.typetune.Session1`
на `/org/typetune/Session1` у владельца имени `org.gnome.Shell`.

## Что получает клиент

`GetSnapshot() -> string` возвращает JSON протокола 1: instance UUID,
монотонные generation/source_generation, current input source type/id/xkbId,
непрозрачный token окна, backend окна (wayland/x11/unknown), lock/shield/overview
и режим пользовательской сессии. `Changed(instance, generation)` инвалидирует
предыдущий снимок. Получение снимка и подключение signal subscription не атомарны:
будущий observer должен подписаться до чтения и перепроверять generation.

Token окна действителен только внутри `(D-Bus unique owner, instance)`.
Disable удаляет endpoint; re-enable меняет instance. При lock, screen shield,
overview и вне user mode source/window скрываются. External keymap не подменяется
сохранённым `currentSource`. Generation меняется и при A → B → A между двумя
запросами. Source generation учитывает keymap/group, source settings/options/model.

Это **не текстовый адаптер**: window не идентифицирует поле, input source не
содержит полную keymap/modifier state, selection/sensitivity/IME неизвестны.
Расширение не читает текст, titles или clipboard и не инжектирует текстовый ввод.
`GetTextContext()` дополнительно возвращает application desktop ID для допуска
проверенного профиля; при ограничении сессии он скрывается. `ActivateTypeTune()`
принимает явную команду активации установленного источника; caller проверяет readback.
Пользовательская установка — [preview guide](../../docs/35-user-test.md).
Rust-клиент сохраняет `read_layout`/`read_focus` как Limited, запрет замены остаётся.
API доступен через session bus текущего пользователя; это не security boundary
от других процессов того же UID. Чужие major-версии GNOME не заявлены.

## Сборка и подключение

Из корня репозитория:

```sh
cargo build -p typetune-cli --offline
mkdir -p target/gnome
gnome-extensions pack --force --extra-source=state.js --out-dir=target/gnome integrations/gnome/typetune-session@typetune.local
gnome-extensions install target/gnome/typetune-session@typetune.local.shell-extension.zip
gnome-extensions enable typetune-session@typetune.local
target/debug/typetune doctor --session
```

Если Shell ещё не видит впервые установленное расширение, нужен следующий вход
в пользовательскую сессию, после которого повторяется enable. Не перезапускать
основной Wayland compositor ради загрузки. Диагностика до активации возвращает
`gnome_bridge: failed/unavailable`. При успешной активации возвращается `observed`,
но это не включает snippets/corrector.

Отключение и удаление:

```sh
gnome-extensions disable typetune-session@typetune.local
gnome-extensions uninstall typetune-session@typetune.local
```

## Проверки

```sh
gjs -m integrations/gnome/tests/state_test.js
cargo test -p typetune-session --offline
python3 integrations/gnome/tests/native_stand.py --bundle target/gnome/typetune-session@typetune.local.shell-extension.zip
```

Native stand запускает отдельный headless compositor с private session D-Bus, временными
settings/data/runtime, двумя синтетическими GTK4-окнами и общей аварийной остановкой.
Системные службы хоста (logind) остаются доступны GNOME; отключение system bus
может исключить screenShield, тогда bridge не запускается. Нужны GNOME 50, GJS, Python GI/GTK4, dbus-run-session и собранный CLI. В основной
сессии расширение этим стендом не устанавливается. Аутентификация lock screen,
logout, suspend, hotkey layout switch и per-window layout не входят в этот stand.

[Протокол результатов](../../docs/25-gnome-bridge-checkpoint.md).

## Текстовое поле

Для дополнительной проверки engine/GTK range adapter:

```sh
cargo build -p typetune-gtk --examples --offline
python3 integrations/gnome/tests/native_stand.py --text-stand
```

Этот режим создаёт virtual keyboard во внутреннем Mutter RemoteDesktop session
только на private bus, чтобы headless GTK получал реальный focus и Wayland events.
[Контракт и границы](../../docs/26-controlled-text-checkpoint.md).

## Явное системное переключение US/RU

Обновлённое расширение предоставляет `RequestSource(string) -> string`.
Команда выполняется только при совпадении instance/generation/window и доступном
обычном контексте с настроенными xkb us/ru. После установки обновлённого архива:

```sh
python3 integrations/gnome/switch_source.py ru
python3 integrations/gnome/switch_source.py us
```

`observed` подтверждает раскладку readback-ом. Ошибка после отправки запроса
возвращает `indeterminate`, без автоматического повторения. Команда не исправляет
ранее введённый текст. [Контракт и проверки](../../docs/31-system-layout-checkpoint.md).

## Исследование IBus

Отдельный проходной engine и проверка неизменённого редактора: `python3 integrations/gnome/tests/native_stand.py --ibus-stand`.
[Описание и границы](../ibus/README.md). Основная сессия не меняется.

## Bridge v3 (checkpoint 36)

`GetTextContext` также возвращает PID активного приложения для AT-SPI proof.
`SetTypeTuneMode` принимает ожидаемые instance/generation/window и target us/ru;
выбирает только собственные TypeTune источники в разрешённом контексте.
Принятие запроса не означает завершение: клиент проверяет source readback.
Pointer button/touch begin инвалидируют контекст и незавершённый Double Shift.
После обновления нужен повторный вход в GNOME.

## Bridge v4

`GetCompatContext` добавляет modifiers, XKB model/options и отдельное
interaction_generation. Это позволяет отличать собственную смену источника от
смены окна/клика и проверять профиль обычных US/RU для compatibility runtime.
Текст и selection/sensitivity/composition этот метод не подтверждает.
Тестовые Probe methods добавляются только во временную копию расширения стенда;
в установленном расширении их нет.
