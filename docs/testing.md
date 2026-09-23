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

Платформы: macOS TextEdit, Safari/Chrome, VS Code; Linux — GTK, браузер, (опц.) терминал.

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
