# 54 — единый runtime без IBus-адаптера

Base: `9831bb8bab16df4b128594f226e8a325cdc9f52b` + локальные этапы 53–54.
Ubuntu 26.04.1 / GNOME Shell 50.1 / Wayland, GTK 4.22.4, amd64.

## Результат

Из TypeTune удалены IBus engines, surrounding-text/AT-SPI adapter, его Python
тесты и native-стенды, регистрация component XML, команды browser/mode-ibus,
переключатель режимов в GUI и ветвления трея/автозапуска. `start` теперь запускает
единственный compatibility runtime; compat-on/off оставлены как CLI aliases.
Shell extension v5 больше не экспортирует ActivateTypeTune/SetTypeTuneMode.
GetCompatContext и RequestSource для обычных XKB US/RU сохранены.

Общий frontend перенесён из integrations/ibus в integrations/app.
Общий Rust C ABI переименован из typetune-ibus в typetune-bridge,
включая crate, Cargo.lock, библиотеку и экспортируемые функции.
Rust planning/executor и его поведенческие тесты сохранены: это общий код.
CI, сборщик .deb и GTK/compat fixtures используют новые пути.
Пакет больше не зависит от ibus, gir1.2-ibus-1.0, gir1.2-atspi-2.0.

Предложения словаря из этапа 53 сохранены: три отдельных ручных исправления
с продолжением печати и явное подтверждение. Возможности compatibility и
ограничения inferred history не изменены.

## Переход со старой версии

Настройки v1 с mode=ibus читаются как compatibility, сохраняя automatic/autostart;
последующая запись сохраняет нормализованное значение. Выбрать ibus заново нельзя.
При настройке пакета/остановке прежний TypeTune engine получает Quit, удаляются
только его источники, component XML, environment.d и прежние runtime-файлы
пользовательской установки. Другие раскладки/IBus engines сохраняются.
Системный IBus не удаляется и не перенастраивается.

Миграционный cleanup разрешён только при наличии манифеста этой установки.
Старый список engines/environment может оставаться в памяти пользовательского
сеанса до повторного входа. Новая установка не регистрирует IBus-компоненты.
Обновление расширения GNOME до v5 также требует повторного входа.

## Проверки

- REMOVE-54-UNIT: сначала воспроизведено отсутствие миграции старого mode=ibus.
  43 frontend + 20 compatibility + 3 packaging = **66 Python tests PASS**.
  Меньшее число относительно этапа 53 связано с удалением 25 adapter-only тестов
  и добавлением migration regression; сохранённые тесты исполняются по новым путям.
- REMOVE-54-RUST: **120 tests PASS**, workspace/all-targets/locked/offline;
  cargo fmt и workspace clippy с -D warnings PASS. Нулевые suites не считались поведением.
- REMOVE-54-GTK: пять fixtures (main/words/apps/suggestions/package) PASS;
  главное окно без выбора режима просмотрено на screenshot собственного fixture.
- REMOVE-54-WAYLAND / REMOVE-54-XWAYLAND: два отдельных nested GNOME compositor
  runs PASS. COMPAT-01 проверяет точный текст/каретку, Double Shift в обе стороны,
  автокоррекцию, дальнейший RU-ввод, паузу/quit; GNOME/SWITCH guards также PASS.
  Основная клавиатура не захватывалась: используется compositor test injection.
- REMOVE-54-PACKAGE: локальный `0.1.0~preview54-1` собран. Реальный dpkg в isolated
  root: установка старого preview53 → обновление на preview54 → повторное обновление,
  remove/purge/reinstall PASS. Старые .so/engine-файлы отсутствуют, IBus/AT-SPI
  Dependencies отсутствуют, пользовательские настройки сохранены. Проверка
  регистрации отдельно подтверждает сохранение чужого IBus engine и XKB US/RU.

Пакет собран из dirty checkout (package.json отмечает это). В рабочую систему
новый пакет не установлен, на GitHub не опубликован. Native migration на основном
пользовательском сеансе и сторонние приложения не входят в эти результаты.
