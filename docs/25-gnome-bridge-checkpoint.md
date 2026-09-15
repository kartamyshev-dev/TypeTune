# G2B: GNOME compositor bridge — 2026-09-15

Продолжение: [сниппет в контролируемом поле](26-controlled-text-checkpoint.md).

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.
Продолжение [checkpoint 24](24-session-capability-checkpoint.md).

Реализовано расширение для GNOME Shell 50 и Rust-клиент его D-Bus-протокола.
Получаем live current input source, непрозрачную identity окна и его backend,
lock/shield/overview state, generation контекста и source generation.
При активации расширения `doctor --session` показывает `gnome_bridge` и ограниченные
возможности read_layout/read_focus. В основной сессии расширение не установлено:
проверено `failed/unavailable`, семь причин запрета текстовой замены сохраняются.

Архив собран в `target/gnome/typetune-session@typetune.local.shell-extension.zip`.
Содержимое архива сверено с исходниками; этот же архив прошёл отдельную стендовую
установку в headless GNOME. [Сборка, установка, отключение](../integrations/gnome/README.md).

## Контракты

- Экспорт под владельцем `org.gnome.Shell`, object `/org/typetune/Session1`,
  interface `org.typetune.Session1`. GetSnapshot возвращает versioned JSON до 4096 bytes;
  неизвестные поля/версии, некорректные IDs, противоречивое restricted state отклоняются.
- Rust разрешает unique owner перед запросом, обращается к нему напрямую и
  повторно проверяет владельца после ответа. Потеря имени во время запроса
  не позволяет использовать ответ прежнего owner. Весь read ограничен 750 ms.
- `(owner, instance, generation)` — граница достоверности. Re-enable меняет UUID;
  `Tracker` инвалидирует epoch при изменении данных или отказе. Ответ с меньшей
  generation либо изменёнными данными при той же generation отклоняется.
- Changed signal сообщает только instance/generation. Shell callbacks не вызывают
  subprocess, сеть или renderer. Metadata не подключены к physical helper.
- Window token не является target текстового поля. Source descriptor не является
  полной XKB keymap/group/modifier state. Поэтому capabilities остаются Limited,
  а field context, composition, sensitivity, selection и Unicode — неизвестны/недоступны.
- На screen shield, lock, overview и вне user session source/window редактируются
  до пустого/нулевого значения. External keymap тоже скрывает source: GNOME 50
  может использовать внешнюю карту вместо сохранённого input source manager state.
- Расширение не читает пользовательский текст, clipboard, app names или titles.
  Настройки основной сессии, input devices и физические клавиатуры не изменялись.

## Evidence и среда

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell/Mutter 50.1, GJS 1.88.0,
GTK 4.22, Python GI, Rust/Cargo 1.98.1. Native backend: **отдельный headless GNOME
Wayland**, virtual monitor 800×600, без XWayland. Два тестовых окна GTK4 содержат
только заранее заданную строку. Private session D-Bus не имеет activation directories. GNOME использует системные
службы хоста (в частности logind); полная изоляция system bus не заявляется.
При попытке отключить также system bus Shell не создал screenShield, поэтому
расширение не экспортировало endpoint. Успешный стенд требует доступных системных
служб и управляет shield только своего compositor.

API сверены с установленным `/usr/lib/gnome-shell/libshell-18.so`:
SHA256 `ecfc54870304193f14e9bd1a2e61d274d9b16b43d7e6b3165b39f5a4dc9a9ede`.
Из gresource прочитаны ui/status/keyboard.js, misc/keyboardManager.js,
ui/screenShield.js, ui/sessionMode.js и ui/shellDBus.js. Это проверка API, не
копирование исходников GNOME. Формат расширения:
[официальное руководство GJS](https://gjs.guide/extensions/overview/anatomy.html).

[Вывод native stand](evidence/25-gnome-native-stand.txt).

| Cases | Уровень / проверенный результат |
|---|---|
| BRIDGE-JS | GJS deterministic: A→B→A сохраняет window token, но меняет generation; source change; redaction при lock/shield/overview; external map; новый instance |
| Rust bridge, 4 tests | Строгий JSON, версия/поля/размер, restricted metadata; generation/instance; loss/contradictory replies |
| BRIDGE-BUS-01 | Private D-Bus: валидный ответ принят, malformed JSON отклонён |
| BRIDGE-BUS-02 | Private D-Bus: сервис освобождает имя внутри GetSnapshot; ответ старого owner отклоняется |
| SES-BUS-01…04 | Повторно: missing interface, AccessDenied, timeout и исчезновение сервиса |
| GNOME-01 | Настоящий Shell загрузил расширение и экспортировал endpoint |
| GNOME-02 | Изменение sources settings US→RU отразилось в current source и увеличило source generation |
| GNOME-03 | Два native GTK окна: разные window tokens, backend=wayland, generation меняется |
| GNOME-04 | Настоящий Rust CLI читает extension; target поля остаётся Unknown, Unicode запрещён |
| GNOME-05 | Disable удаляет endpoint; enable создаёт другой instance |
| GNOME-06/07 | Screen shield activation скрывает source/window; deactivation возвращает источник с новой generation |
| Workspace | 86 unit tests + 2 CLI integration tests, 0 failed |
| Build/static | Workspace build, Clippy session/CLI all-targets `-D warnings`, fmt/diff |

Первый native запуск воспроизвёл отсутствующий `org.gnome.ScreenSaver` proxy в
private bus после успешных GNOME-01…05. Стенд исправлен на реальный Shell-owned
`org.gnome.Shell.ScreenShield`; последующий полный прогон прошёл. Активация shield
не называется проверкой password authentication или возврата после настоящего logout.

## Оставшиеся ограничения и следующий срез

G2B не закрыт полностью. Не приняты основная desktop-сессия после установки,
переключение через UI/hotkey, per-window mapping, password lock/unlock, suspend,
logout, KDE или XWayland-приложения. Input source manager может объявить source
раньше завершения асинхронной установки keymap — source ID не разрешает key decoding.

Следующий срез — интеграция с **контролируемым текстовым полем**: committed text,
caret/selection, sensitivity/composition и Unicode range operation. После неё
можно реализовать один статический сниппет с единым executor, проверкой содержимого,
каретки и отказом при смене контекста. Оконная GNOME metadata сама по себе этих
гарантий не даёт. История текста, snippets и corrector пока не включены.
