# Тестирование

## Уровни проверки

| Уровень | Что это | Где |
|---|---|---|
| Unit / fixtures | Engine, bridge, gesture, scoring, Swift helpers | CI, локально |
| Smoke | GTK-фикстуры, packaging checks | CI (Linux, Xvfb) |
| Package lifecycle | Сборка `.deb` / `.app`, checksum, codesign | CI |
| **Native acceptance** | Живой физический ввод в приложениях | **Вручную**, не CI |

**Зелёный CI ≠ полная приёмка клавиатуры.** В CI нет физической клавиатуры и реальных TCC-диалогов.

## Что гоняет CI

- `cargo fmt` / `clippy -D warnings` / `cargo test --workspace`
- Python-тесты app / compat / packaging
- GTK smoke под Xvfb
- `scripts/test-macos.sh` (Rust engine/bridge + Swift Testing)
- Сборка и verify пакетов

## Что проверять вручную (native matrix)

Минимальный набор после изменений ввода/исполнителя:

| ID | Сценарий |
|---|---|
| N-01 | Double Shift: `ghbdtn` → `привет`, повтор → обратно; язык следующего слова |
| N-02 | Авто на пробеле: частотные случаи и **отказ** на URL/коде |
| N-03 | Пауза: правок нет, история сбрасывается |
| N-04 | Исключение приложения: авто выключено, Double Shift работает |
| N-05 | Password / secure field: без правок и без обучения |
| N-06 | Смена раскладки вручную: следующее слово не «перекатывается» |
| N-07 | Быстрый набор, зажатые модификаторы, мышь между словами |
| N-08 | Терминал / браузер / простой редактор — отдельно, различия записать |
| N-09 | Caps Lock / Super+Space как переключатель раскладки: слово сохраняется, Double Shift работает, одно авто-слово пропускается |
| N-10 | Ctrl/Alt/Super сами по себе и клик мыши между словами: слово сохраняется; Ctrl+буква по-прежнему очищает |
| N-11 | Флаг в трее/меню: 🇺🇸/🇷🇺 следует раскладке, `?` при неизвестной, `✕` на паузе; «Показывать флаг» скрывает бейдж |
| N-12 | Каждый тумблер меню переживает перезапуск (generation ACK; tray+окно не теряют обновления) |
| N-13 | Быстрый повтор Double Shift (retoggle) без искусственной задержки |
| N-14 | Нет доступа к `/dev/input` / uinput: UI показывает «Нужны разрешения…», нет зависания |
| N-15 | `Переключать только последнее слово` / `Не переключать слова` / `Не исправлять после смены раскладки` — как в таблице руководства |
| N-16 | Doctor/разрешения: расширение GNOME, udev, polkit, helper |

Платформы: macOS TextEdit, Safari/Chrome, VS Code; Linux — GTK, браузер, (опц.) терминал.

### Что уже проверено на Linux (2026-09-24, автотесты + smoke)

- N-01 / N-06 / N-07: unit-тесты `integrations/compat/test_history.py`, `test_context.py`, `test_retoggle.py` (Caps/mouse/modifiers/layout/flicker).
- N-09: `test_history.test_caps_lock_latch_keeps_word_and_double_shift`, `test_context.test_source_only_keeps_history_and_arms_skip`.
- NEW (флаг/меню): `integrations/app/test_tray.py` (IconPixmap, 22-id MENU_SPEC).
- Нативная оболочка: `cargo test -p typetune-gui -p typetune-cli`, `typetune doctor --session` (protocol/os/permissions/input_source/autostart).
- Ручные N-02…N-08 и свежий пользователь (до/после polkit) — **не** перепроверялись в этой сессии.

Фиксируйте: commit, ОС/build, session/backend, версии приложений, permissions, номера cases и ограничения. **Не** прикладывайте образцы личного текста.

## Корпус автокоррекции

- `crates/typetune-engine/data/auto-corpus.tsv` + baseline-метрики.
- Локально: `cargo test -p typetune-engine autocorrection_corpus`.
- Gate: ноль ложных срабатываний на negative-строках; пропуски фиксируются в baseline.

## Чего CI не закрывает

- Отзыв и повторную выдачу системных разрешений (macOS TCC).
- Secure Input, sleep/wake, lock/unlock.
- Игры, кастомные редакторы, удалённые сессии, elevated-приложения.
- Notarization / SmartScreen.
