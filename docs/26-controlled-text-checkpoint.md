# G3: статический сниппет в контролируемом GTK-поле — 2026-09-15

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения; commit не создан.
Продолжение [checkpoint 25](25-gnome-bridge-checkpoint.md).

Появилась проверенная вертикаль **для собственного plain GTK4 TextView**:
Space key event → уже доставленный committed text → статическое правило →
одноразовый план диапазона → исполнитель → проверенные текст, каретка и выделение.

Добавлены:

- `typetune-engine`: portable matcher одного immutable static snippet, bounded
  snapshots, range plan и executor. Добавлен в portable default-members.
- `typetune-gtk`: адаптер нового контролируемого TextView, контекст/ревизии,
  preedit/focus/modifier guards, наблюдение конца пользовательской операции и
  Unicode-вставка через TextBuffer. Это не управление чужими GTK-приложениями.
- `snippet_demo`: интерактивное поле, где `:hi` + Space заменяется на приветствие
  с кириллицей, emoji и переносом строки. Пример использует тот же adapter/engine.
- `field_stand`: native проверки, включая получение `:hi ` от виртуальной
  клавиатуры отдельного Mutter через Wayland и автоматическое выполнение правила.

Запуск интерактивного примера из корня проекта:

```sh
cargo run -p typetune-gtk --example snippet_demo --offline
```

## Контракт реализации

Matcher не удерживает физический ввод и не генерирует keycodes. Space уже есть
в приложении до matching. Trigger и Space заменяются вместе, разделитель
добавляется ровно один раз; `abc:hi ` не совпадает. Enter/Tab не являются delimiter.

GTK observer запускает matching после end-user-action только при preceding Space
key event без modifiers. Paste/programmatic changes сами не активируют этот путь.
На собственную замену установлен applying marker: callbacks не создают новые планы.
Другие origin в engine (OwnReplacement/Unknown) отклоняются. No-op matching не
пишет текст. Обработка ограничена одним правилом на поле; shell/renderer workers
и автоматическая коррекция не подключены.

Этот **committed/range profile** использует достоверное содержимое собственного
поля, поэтому ему не нужна предположительная `us,ru` keymap и не применяется
keymap-inferred preflight из checkpoint 24. GNOME window identity не подменяет
identity поля. Layout-correction и global observation остаются другими задачами.

Plan хранится только в RAM, без Debug/Serialize и текстового лога. Он не Clone и
потребляется исполнителем. Проверяются target, epoch, revision, caret/anchor,
focus, normal-field policy, composition, modifiers, range capability, ожидаемый
текст и deadline. Часы передаются исполнителю; native backend перепроверяет
срок непосредственно перед удалением и вставкой. Unknown отклоняется.

Ограничения размеров: полный snapshot собственного поля до 16 KiB, replacement
до 4096 bytes вместе с delimiter, trigger до 64 Unicode scalars. Это ограниченная
модель cooperating editor, не глобальная история произвольного документа.
После навигации/paste следующий запрос читает действительный range; накопленной
предположительной истории нет. Password input purpose отклоняется до чтения текста.
Нулевой символ в replacement отвергается до удаления.

Диапазоны выражены в **Unicode scalar offsets**, соответствующих GtkTextBuffer,
не в UTF-8 bytes или количестве Backspace. Emoji/combining marks проходят как
строка через native buffer API. Существующее содержимое вне диапазона сохраняется.

GTK begin/end-user-action группирует операцию, но не делает delete+insert атомарными:
[контракт GTK](https://docs.gtk.org/gtk4/method.TextBuffer.begin_user_action.html).
После удаления перепроверяются контекст, content и revision; вмешательство
синхронного callback прекращает дальнейшую вставку. После конца операции executor
считывает текст/каретку/выделение. Результат — Completed, FailedBeforeEdit либо
IndeterminateAfterEdit. Последний не повторяет удаление/вставку и не обещает rollback.
Это контракт cooperating widget с известными callbacks, не произвольного plugin host.

## Проверки и evidence

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell/Mutter 50.1,
GTK 4.22 с Rust gtk4 0.9.7, Rust/Cargo 1.98.1. Backend: отдельный headless GNOME
Wayland, TextView в новом тестовом GTK-окне. Private session bus и временные
config/data/runtime; системные службы GNOME доступны как в checkpoint 25.
Основные приложения, clipboard и физические input devices не использовались.

[Фактический вывод стенда](evidence/26-gtk-text-native-stand.txt).

| Case | Уровень / результат |
|---|---|
| Engine, 9 tests | Unicode prefix/suffix/caret; каждый Unknown guard; target/epoch/revision/caret/selection changes; expiry/future time с fake clock; origins; Space/boundary; partial output; size/NUL; API success с неверным результатом не считается Completed |
| TEXT-01 | Native GTK: trigger виден до matcher; точные RU/EN, регистр, punctuation, emoji, combining mark и multiline; точная каретка и collapsed selection |
| TEXT-02 | Native GTK: prefix и trailing suffix сохранены, delimiter один |
| TEXT-03 | Native GTK: перевод фокуса во второе поле перед исполнением отменяет план, исходный текст цел |
| TEXT-04 | Native GTK: selection, synthetic preedit signal и Unknown modifiers отклоняют замену |
| TEXT-05 | Native GTK: editable=false и пользовательское изменение после подготовки отклоняют замену |
| TEXT-06 | Native GTK: callback изменяет buffer после удаления; insertion остановлен, IndeterminateAfterEdit, текст/каретка проверены, retry нет |
| TEXT-08 | Native GTK: Password input purpose отклоняет snapshot до чтения текста |
| TEXT-07 | Native Wayland events: virtual keyboard → GDK/GTK committed `:hi ` → observer → snippet → Unicode; итоговый buffer/каретка прочитаны, завершение ровно одно |
| Workspace | 95 unit tests + 2 CLI integration tests, 0 failed; нулевые suites не считаются поведенческими проверками |
| Build/static | Workspace build, оба GTK examples, Clippy engine/gtk all-targets с `-D warnings`, fmt/diff |
| GNOME-01…07 | Прежние bridge cases повторно пройдены в том же запуске |

Начальный native запуск отказал на active-focus guard: headless compositor не
имел клавиатурного устройства. Проверка не была ослаблена. В disposable compositor
создаётся внутренний Mutter RemoteDesktop session и сбалансированная пара Shift
для появления virtual keyboard seat. Затем для TEXT-07 отправляются Unicode
keysyms `:`, `h`, `i`, Space с Down/Up. Это **внутренний тестовый API Mutter на
private bus**, не portal permission acceptance и не продуктовый input backend.
Session останавливается после теста; при ошибке compositor завершается стендом.

TEXT-01…06/08 используют synthetic commits/изменения непосредственно в реальном
GTK buffer. Только TEXT-07 проверяет Wayland keyboard delivery. Synthetic preedit
signal не является приёмкой настоящего IME. Подавленные/залипшие физические клавиши
этим text adapter не создаются: он не вызывает uinput/XTest и не делает grab.

Повторение:

```sh
cargo test --workspace --offline
cargo build --workspace --offline
cargo build -p typetune-gtk --examples --offline
python3 integrations/gnome/tests/native_stand.py --text-stand
cargo clippy -p typetune-engine -p typetune-gtk --all-targets --offline -- -D warnings
```

## Границы и следующий этап

Это первый принятый статический snippet **в собственном контролируемом поле**.
Не заявлена работа в Firefox, терминалах, чужих GTK/Qt приложениях или XWayland.
Реальные IME, lock/logout, password widgets и input-origin других приложений не
приняты; Ctrl+Shift+U, clipboard workaround и guessed Backspace не используются.

Daemon по-прежнему physical-relay-only; doctor не объявляет глобальные text
capabilities Available. Legacy snippets/corrector не заменены новым runtime.
Их characterization tests остаются свидетельством прежних дефектов.

Следующий срез: безопасная ручная RU↔EN коррекция в этом же cooperating range
profile либо отдельная интеграция с выбранным реальным приложением. Общий
runtime/config controller, несколько правил, config generation/reload, полноценный
origin ledger и native acceptance иных приложений потребуют самостоятельных проверок.

Продолжение: [ручная коррекция US ↔ RU](27-manual-correction-checkpoint.md).
