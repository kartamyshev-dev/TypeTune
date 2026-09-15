# Ручная коррекция через IBus — 2026-09-16

## Результат

Продолжение [browser checkpoint](33-browser-ibus-checkpoint.md).
HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.

В disposable GNOME Wayland сессии реализована ручная замена через общий IBus
engine: F8 исправляет `ghbdtn` → `привет`, F9 выполняет обратную перекладку.
Chrome получает Unicode через штатный input method. Расширение браузера,
clipboard и эксклюзивный grab не используются. DOM тестовой страницы независимо
подтверждает текст и collapsed caret на позиции 6 в обоих направлениях.

Это первая работающая коррекция через исследуемый системный input-method backend,
но пока только в явно ограниченном тестовом профиле. Пользовательская сессия
и конфигурация IBus не изменены; основной daemon остаётся relay-only.

## Реализация

- `typetune-engine::InFlight` выделяет общую авторизацию и проверку результата.
  Синхронный `execute` GTK и асинхронный IBus используют эти же guards.
- Новый `typetune-ibus` — библиотека Rust с ограниченным JSON C ABI для Python GI.
  Она вызывает существующий `prepare_manual`, хранит move-only план и проверяет
  результат. Таблица RU/US и правила слова в Python не дублируются.
- `integrations/ibus/manual.py` выполняет native операции через GI. F8/F9
  запускают запрос по отпусканию; удержание/repeat не создаёт несколько замен.
  Планирование и отправка edit выполняются в GLib idle callbacks. Клавиатурный
  callback не запускает процессы, не читает файлы, не ждёт D-Bus или readback.
- План имеет срок 500 ms; перед первой операцией повторно сравниваются snapshot,
  target/epoch/revision, текст, offsets и guards. После отправки запросов только
  новый surrounding snapshot с точным текстом/кареткой завершает транзакцию.
  Промежуточное состояние удаления не считается успешной заменой.
- Focus/reset/disable, изменение capabilities/purpose и новый ввод отменяют
  незавершённое действие. После неопределённого результата контекст очищается;
  автоматического retry нет. History ограничена 16 KiB и остаётся в памяти.
- В отчёты попадают счётчики исходов, но не содержимое поля или replacement.

IBus `delete_surrounding_text` принимает относительное смещение от каретки и
число символов, затем `commit_text` отправляет Unicode. См. [официальный контракт
IBusInputContext](https://ibus.github.io/docs/ibus-1.5/IBusInputContext.html) и
[IBusEngine](https://ibus.github.io/docs/ibus-1.5/IBusEngine.html).
**Два запроса не атомарны.** Snapshot — последнее уведомление клиента, не
compare-and-swap с полем: изменение приложения вне наблюдаемого протокола
остаётся ограничением этого backend.

## Область разрешения и ограничения

Runner включает `manual-browser-profile` только на время браузерных cases
в собственном private runtime. Это тестовое разрешение с известными клиентом,
полями и последовательностью обычного US-ввода, а не определение приложения
в рабочем runtime. Marker читается таймером вне key callback.

Знание об отсутствии composition ограничено этим профилем простого ввода:
engine сам не создаёт preedit, предшествующий ASCII-ввод подтверждён surrounding
text. Navigation/необычная клавиша сбрасывают допуск; сложный IME/dead keys не
приняты. Этот признак нельзя переносить на произвольный клиент как Known.
Равенство cursor/anchor допускается только в данном профиле Chrome, где
выделение предварительно проверено. GNOME Text Editor и другие приложения
не получают такое разрешение по наличию IBus API.

Unknown purpose, PASSWORD, отсутствие surrounding capability, выделение и
пустой контекст приводят к отказу до edit. Корректность purpose зависит от
клиента; глобальная защита всех password fields не доказана. Прототип нельзя
считать готовым к установке в основную сессию.

Не приняты: JS-изменение текста без IME-события, мышиное выделение внутри поля,
быстрый burst/гонки клиента, сложный Unicode-контекст в native browser case,
IME, Firefox, Qt/Electron, терминалы, XWayland, остальные desktop-ы.
F9 — обратная перекладка, **не условный undo**. Системный источник остаётся IBus
TypeTune с US layout; автоматического перехода на RU после коррекции нет.

## Проверки

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1;
IBus 1.5.34-rc2; Chrome 153.0.8010.36, native Wayland с явным GTK 3.
Профили Chrome: default flags и дополнительно Wayland IME/text-input-v3 flags.
Стек и ограничения fixture описаны в [33](33-browser-ibus-checkpoint.md).

### Native acceptance

[Полный успешный прогон](evidence/34-ibus-manual-native.txt).

| Cases | Результат |
|---|---|
| IBUS-MANUAL-DEFAULT / IME | F8/F9: точный DOM text, caret=anchor=6; два Rust-confirmed edit в каждом профиле; indeterminate не возник |
| IBUS-REFUSE-DEFAULT / IME | Выделение, переход в пустое поле, пароль: исходный DOM сохранён, edit counter не вырос |
| BROWSER-DEFAULT / IME | Прежние ввод/navigation/selection/pointer focus/password checks прошли |
| IBUS-01…03, GNOME-01…07, SWITCH-01…04 | Регрессии observer и session/layout bridge прошли |

Клавиши/клик подаются через внутренний Mutter RemoteDesktop API только
в disposable compositor. Down/Up парные; основная физическая клавиатура не
захватывается. Отказ при фокусе **между подготовкой и edit** проверен отдельно
детерминированно; native case проверяет запрос после смены поля.

### Детерминированные проверки и сборка

- `cargo test --workspace --offline`: **105 unit + 2 integration tests**, 0 failures.
  В том числе 15 общего engine и 4 нового bridge. Группы с `0 tests` не являются
  проверкой поведения. Bridge tests используют передаваемый Instant и виртуальное
  продвижение времени, без sleep.
- `cargo build -p typetune-ibus --offline`: cdylib собрана.
- `/usr/bin/python3 integrations/ibus/test_manual.py`: **7 tests**. Проверены
  точные текст/каретка, before-edit focus loss, новый ввод, selection/Unknown/
  password, отзыв профиля, частичный сбой без retry и repeat shortcut.
- Python syntax, локальные ссылки и `git diff --check`.

## Повторение и следующий этап

```sh
cargo build -p typetune-cli -p typetune-ibus --offline
cargo test --workspace --offline
/usr/bin/python3 integrations/ibus/test_manual.py
python3 integrations/gnome/tests/native_stand.py --ibus-stand
```

Следующий срез: заменить тестовое разрешение полноценным runtime-контролем
профиля/focus identity, проверить мышиные изменения и быстрый ввод, добавить
согласованные RU/US режимы IBus. После этого — управляемый запуск/остановка
и установка для поддержанных приложений. Автокоррекция и словари остаются
следующим уровнем после устойчивой ручной коррекции.
