# 37 — Общий ввод без зависимости от IBus: исследование Espanso

2026-09-16. TypeTune HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения.
**Статус: реализован и установлен экспериментальный режим максимальной совместимости.**
Пользователь явно выбрал opt-in замены по истории клавиш без чтения текста.
Проверки и границы готовности ниже; универсальная гарантия всех приложений не заявляется.

## Что проверено в Espanso

Ветка dev на момент проверки: `76a61b87f037e0ce7e84db5891f9968a8fa4059e`.
Прочитаны LICENSE, evdev detector, evdev injector, выбор text injector и Wayland
app-info. Это обновление [reference 15](15-espanso-reference.md), а не утверждение
о native acceptance самого Espanso.

- [Detector](https://github.com/espanso/espanso/blob/76a61b87f037e0ce7e84db5891f9968a8fa4059e/espanso-detect/src/evdev/device.rs)
  открывает evdev read-only/nonblocking без exclusive grab; переводит evdev code
  в XKB на границе декодирования. Обрабатывает Down/Up/Repeat.
- [Injector](https://github.com/espanso/espanso/blob/76a61b87f037e0ce7e84db5891f9968a8fa4059e/espanso-inject/src/evdev/mod.rs)
  использует виртуальную клавиатуру и обратную карту символов. Этот путь не требует
  текстового API конкретного приложения.
- [Выбор вставки](https://github.com/espanso/espanso/blob/76a61b87f037e0ce7e84db5891f9968a8fa4059e/espanso-engine/src/dispatch/executor/text_inject.rs)
  в Auto на Linux предпочитает clipboard для non-ASCII. Клавиатурный метод не
  означает универсальную вставку Unicode.
- [README](https://github.com/espanso/espanso) заявляет almost any program и
  experimental Wayland support, а не гарантии всех приложений/полей.
- [Лицензия](https://github.com/espanso/espanso/blob/76a61b87f037e0ce7e84db5891f9968a8fa4059e/LICENSE)
  GPL-3.0; заголовки исследованных Rust-файлов указывают GPL-3.0-or-later.
  Код Espanso не копировался в MIT-проект TypeTune.

## Проверенная альтернатива для GNOME

Добавлен `--global-input-probe` в существующий isolated GNOME stand. Он меняет
только временную копию расширения; probe methods отсутствуют в устанавливаемом
расширении. Контролируемое GTK-поле, отдельный compositor/private D-Bus/XDG.

Сначала воспроизведён провал предположения: `global.stage::captured-event` не
наблюдает обычные буквы, доставленные native Wayland клиенту. Начальные modifier
события иногда видны, поэтому один Shift не доказывает глобальный захват.
Такой callback нельзя использовать вместо evdev observer.

Дополнительно исследуется Clutter virtual keyboard: ввод на compositor-уровне
не требует IBus. Это не portable Wayland API и не доказательство чтения текста,
selection или password purpose в приложении.

## Реализация

Основной общий путь — **пассивный evdev observer + отдельный uinput executor**.
В TypeTune уже существуют typed evdev events и uinput transport; observer должен
использовать nongrabbing чтение, а не запускать `EvdevSource::run` с grab.
IBus/range adapter остаётся приоритетным подтверждённым способом замены.

Контракты общего backend (часть native acceptance остаётся открытой):

1. Явно выбранные физические устройства, source time/device/origin; запрет
   повторного наблюдения собственного uinput, bounded queue и сброс при loss.
2. Подтверждённая раскладка и focus из session adapter; keymap-inferred история
   только в RAM. Сброс при navigation, mouse, paste, focus/layout change и resync.
3. Отдельный Double Shift detector и общий rule matcher, один executor на замену.
4. Перед удалением подготовить полный RU/US key plan; отдельная политика
   неизвестных selection/sensitivity/composition. Не подделывать `Committed`.
5. Cleanup собственных модификаторов, output failure, shutdown/hotplug/watchdog;
   никакого слепого повтора после возможного удаления.
6. Acceptance отдельно: native GTK/Qt/browser, XWayland и X11. Отдельно terminal
   (Backspace зависит от TTY/программы), custom editors и IME.

## Явный выбор пользователя и способ исполнения

Пользователь выбрал «Максимальная совместимость: добавить такой режим с явным
включением» и повторно указал Espanso основным ориентиром. Это разрешение на
limited profile с неизвестными text/selection/sensitivity/composition. Статус
сохраняет Unknown и `keymap-inferred`; фиктивный committed Snapshot не создаётся.

- `integrations/compat/runtime.py`: отдельный runtime, история, Double Shift,
  fresh GNOME owner/window/interaction/source guards, управляющий D-Bus endpoint.
- `history.py`: ограничение 128 символов, Shift с device identity, сброс при
  навигации/shortcuts/потере контекста. Backspace обновляет предполагаемую историю.
- `typetune_engine::inferred`: использует общий mapper и словарное правило, но
  возвращает Suggestion, а не подтверждённый range Plan. C ABI операция `infer`.
- `compat_transport`: passive evdev reader + отдельное собственное uinput-устройство.
  Выбираются физические клавиатуры; virtual devices исключаются по sysfs, собственный
  output не распознаётся повторно. Exclusive grab не используется.
- Транспорт сохраняет evdev code без offset, Down/Up/Repeat, source monotonic time
  и device identity. При disconnect/resync/hotplug история инвалидируется.
- Устройства с удержанными клавишами не присоединяются до нейтрального состояния.
  Команда замены содержит ожидаемый sequence; новые физические нажатия отменяют
  pending output. Последовательность проверяется целиком, включая баланс клавиш.
- Output идёт по одному edge с интервалом 8 мс. SIGTERM, cancel, error и Drop
  освобождают собственные удержанные клавиши. Независимая lease транспорта — 2 с.
  Bounded channels закрывают transport при зависшем потребителе.
- GNOME extension v4 добавляет `GetCompatContext`: modifiers, model/options и
  interaction generation. Source change отделён от click/focus/lock invalidation.
- RU/US клавиши повторно набираются в целевой штатной раскладке. Источник меняется
  **перед** удалением/набором и проверяется readback: это необходимо для keyboard
  injection кириллицы. При отказе после переключения текст может сохраниться,
  а раскладка уже измениться. Транзакция не атомарна.
- Результат `injected-unverified` означает только отправку событий. Неизвестный
  after-edit результат — `indeterminate`, повторного удаления нет.

Controller: `compat-on` / `compat-off`, общий `pause` / `resume`, `auto-on` /
`auto-off`, `status` и `stop`. IBus и compat не активируются одновременно.
`start`/`browser` переключают обратно на IBus. Автозапуск совместимости не добавлен.
Автоматика вновь включается при новом запуске процесса; словарь прежний: 150 RU / 149 EN.

## Проверки

Ubuntu 26.04.1 / kernel 7.0.0-31-generic; GNOME/Mutter 50.1; GTK 4.22.4;
IBus 1.5.34-rc2; Chrome 153.0.8010.36; Rust 1.98.1.

- `cargo test --workspace --all-targets --offline`: **114 тестов PASS**.
- **30 Python tests PASS**: 23 IBus/gesture/profile + 7 compatibility history/context.
- [Native Wayland](evidence/37-compat-wayland.txt) и
  [XWayland](evidence/37-compat-xwayland.txt): COMPAT-01 PASS. Double Shift обоих
  видов/направлений, auto Space, язык следующего ввода, exact GTK text/caret,
  pause и quit. Никакой IBus engine в этих cases нет.
- [Установленный IBus regression](evidence/37-ibus-regression.txt): прежние
  RUNTIME, SMART, EDITOR, BROWSER и GNOME cases PASS.
- [GLOBAL-PROBE-01](evidence/37-global-probe.txt): ограничение Shell observer
  воспроизведено; compositor keyboard delivery подтверждена без IBus.

**Граница native stand:** physical events в compatibility runtime подаются
контролируемым Feed; output исполняется Clutter virtual keyboard из временной
копии расширения. Это тест runtime/правил/раскладки/доставки приложению, а не
end-to-end приемка physical evdev → uinput в основном desktop. Probe/Feed methods
отсутствуют в обычной установленной службе/расширении.

Тесты Rust транспорта проверяют отказ до output для небалансированных/command
keys и освобождение модификаторов после частичной ошибки. Полная fault/hotplug
матрица этого нового runtime ещё не закрыта.

## Ограничения

- GNOME 50, стандартные US/RU, модели pc105/pc105+inet. Допускаются только пустые
  XKB options или grp_led:*; remapping и другие раскладки приводят к отказу.
- Password/selection/IME могут быть неизвестны. Compatibility сознательно
  допускает такие Unknown; для паролей и важных терминальных команд используйте
  pause/compat-off. На lock/overview/focus change данные сбрасываются.
- Приложение может игнорировать или иначе обработать Backspace/символы, самостоятельно
  изменить текст. Runtime не подтверждает результат и не гарантирует работу в играх,
  custom editors, terminal programs и каждом существующем приложении.
- Нет whitelist приложений и зависимости от IBus/AT-SPI. Наличие общего transport
  не заменяет матрицу native приемки Qt, браузеров, Electron, terminal и IME.
- Other compositors и отдельная X11-сессия пока не приняты; XWayland проверен отдельно.

Инструкция: [пользовательская проверка](35-user-test.md#режим-максимальной-совместимости).

## Основная установка и transport smoke

Пользовательская установка обновлена, совпадение runtime/helper/cdylib с checkout
проверено. GNOME bridge v4 ещё не загружен: status `bridge=false`, оба runtime
`not-running`; требуется повторный вход. Активный US-источник сохранён.

[COMPAT-TRANSPORT-STOP / WATCHDOG](evidence/37-transport-smoke.txt) выполнены на
основной машине без отправки клавиш: две физические клавиатуры открыты без grab,
uinput создан/удалён, штатная остановка и истечение lease завершают процесс с кодом
0, виртуальное устройство исчезает. Входящие key events сразу отбрасывались,
без записи содержимого/кодов в логи или evidence. Это проверка доступа/lifecycle,
**не** приемка реальной замены через uinput в основном приложении.
