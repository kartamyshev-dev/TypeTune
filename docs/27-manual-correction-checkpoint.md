# Ручная коррекция US ↔ RU в контролируемом поле — 2026-09-15

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без нового commit.
Продолжение [checkpoint 26](26-controlled-text-checkpoint.md).

В `typetune-engine` добавлен явный `prepare_manual`, создающий обычный одноразовый
Plan для существующего executor. В GTK-примере две кнопки выбора направления:
«Исправить US → RU» и «Исправить RU → US». Пример запускается командой:

```sh
cargo run -p typetune-gtk --example snippet_demo --offline
```

Введите `ghbdtn`, оставьте каретку в конце и нажмите US → RU: получится `привет`.
Системная раскладка не меняется. Кнопка при клике сохраняет фокус поля; состояние
модификаторов берётся из GDK event, маски кнопок мыши исключаются. Клавиатурная
активация кнопки с фокусом вне поля отклоняется обычным guard.

Профиль строго ограничен буквенными клавишами стандартных US/Russian:
33 буквы в двух регистрах, включая ё/Ё и US punctuation на соответствующих
клавишах. Это посимвольное соответствие, не транслитерация и не языковой детектор.
Направление указывает пользователь; словарь не нужен. Lower/title/upper/mixed case
сохраняются согласно физическому mapping (например, `Х` → `{`).

Исправляется весь whitespace-delimited token непосредственно слева от каретки
или перед последовательностью ASCII Space. Пробелы включены в заменяемый range
и сохраняются в точности; текст справа и слева остаётся прежним. Каретка внутри
слова отклоняется. Enter/Tab после слова не считаются завершающим delimiter.
Цифры, смешанный алфавит, emoji, combining marks и иные символы вне таблицы
отклоняют весь token. Пунктуация из таблицы трактуется как буква целевой раскладки;
это явная команда, без эвристики распознавания URL/кода.

Существующие guards, ограничения размеров, deadline, revision/epoch, sensitive
field policy, проверка результата и запрет retry после частичной замены сохранены.
Новый путь не генерирует keycodes, не удерживает ввод и не вызывает clipboard.

## Проверки

Среда: Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1;
GTK 4.22 / gtk4-rs 0.9.7; Rust/Cargo 1.98.1. Native backend: отдельный headless
GNOME Wayland с private session bus, как в checkpoint 26. Основная клавиатура
не захватывалась, пользовательский текст не записывался.

- Workspace: 100 unit tests + 2 CLI integration tests, успешно.
- Engine: 14 tests, из них 5 новых: направления/регистр/окружение; неподдерживаемые
  tokens и середина слова; stale/expiry/partial с FakeClock; граница перед следующим
  словом; размер и однозначность таблицы.
- MANUAL-01: реальный GTK buffer, callback кнопки через `emit_clicked`, mixed case,
  два пробела, окружающий текст, точная каретка и отсутствие выделения.
- MANUAL-02: тот же callback при фокусе другого поля отказывает, текст сохранён.
- TEXT-01…08 и GNOME-01…07 повторно успешно пройдены.
- GTK examples собраны; Clippy engine/gtk all-targets `-D warnings`, fmt и diff пройдены.

[Вывод успешного native-стенда](evidence/27-manual-native-stand.txt).
Первый запуск воспроизвёл ошибку границы каретки после пробелов прямо перед следующим
словом. Добавлен deterministic regression, условие исправлено, native повтор пройден.

Повторение:

```sh
cargo test --workspace --offline
cargo build -p typetune-gtk --examples --offline
python3 integrations/gnome/tests/native_stand.py --text-stand
cargo clippy -p typetune-engine -p typetune-gtk --all-targets --offline -- -D warnings
cargo fmt --all -- --check
```

## Ограничения и следующий этап

MANUAL cases используют синтетический buffer input и программную активацию кнопки,
не физический клик мышью. Доставка pointer events к кнопке отдельно не принята.
Реальная Wayland keyboard delivery проверена прежним TEXT-07 для сниппета.
RU → US проверен portable-тестом; отдельная native-приёмка обратного направления
не выполнялась. IME и глобальный shortcut не реализованы этим срезом.

Работает только собственное plain TextView; это не исправление текста в чужих
приложениях. Daemon остаётся physical-relay-only; doctor не повышает capabilities.
Legacy corrector не подключён, автоматическая коррекция не включена.

Следующий этап: локальное горячее сочетание с проверкой отпускания modifiers,
реальные pointer/shortcut cases в disposable compositor, затем отдельный профиль
интеграции с выбранным приложением. Общая готовность G3 пока не заявлена.

Продолжение: [локальные клавиши и настоящие клики](28-local-shortcuts-checkpoint.md).
