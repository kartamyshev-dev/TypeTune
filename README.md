# TypeTune

Помощник ввода для исправления ошибочной RU/EN раскладки на Linux.
Текущая версия — **экспериментальный preview для GNOME 50 / Wayland**.

## Что работает

- **Двойной Shift** исправляет последнее слово и меняет язык дальнейшего ввода.
- Повторный двойной Shift в режиме совместимости переключает то же слово обратно:
  `ghbdtn → привет → ghbdtn → привет`.
- **Автокоррекция на пробеле** использует небольшой встроенный словарь: 150 RU / 149 EN слов.
- Пауза, включение/выключение автоматики, диагностика и остановка через один controller.

| Режим | Механизм | Проверки и ограничения |
|---|---|---|
| Максимальная совместимость (`compat-on`) | Пассивный evdev + виртуальная клавиатура uinput, без exclusive grab, IBus и списка разрешённых приложений | Стендовые Wayland/XWayland text/caret cases; пользователь подтвердил работу в браузере после исправления задержки. Текст, выделение, пароль и composition не подтверждаются |
| IBus (`browser` / `start`) | Замена через общий Rust engine и IBus, контекст GNOME; дополнительная проверка AT-SPI для других приложений | Приняты ограниченные профили Chrome и GNOME Text Editor; поля без нужных API отклоняются |

Режимы не работают одновременно. Отправка клавиш не гарантирует одинаковое поведение
во всех программах: терминалы, игры и нестандартные поля могут обрабатывать их иначе.
Windows/macOS и другие Linux desktop-среды ещё не приняты.

## Установка и запуск

Нужны Rust/Cargo, системные зависимости workspace и Python GI. Требования
и диагностика перечислены в [инструкции](docs/35-user-test.md).

```sh
./scripts/typetune-test install
# После установки/обновления расширения: выйти из GNOME и войти снова.
./scripts/typetune-test compat-on
```

В обычной US-раскладке наберите `ghbdtn` в пустом поле и дважды коротко нажмите
один и тот же Shift. Ожидается `привет` и русский ввод. После завершения замены
повторите жест для обратного переключения. Для автоматики используйте пробел.

Режим совместимости включается явно и требует доступа к `/dev/input` и `/dev/uinput`.
Установщик не выдаёт эти права автоматически. Перед паролями и важными терминальными
командами приостанавливайте коррекцию: этот режим не распознаёт все чувствительные поля.

```sh
./scripts/typetune-test pause
./scripts/typetune-test resume
./scripts/typetune-test auto-off
./scripts/typetune-test auto-on
./scripts/typetune-test status
./scripts/typetune-test compat-off
# Остановить любой активный режим:
./scripts/typetune-test stop
```

Для отдельной проверки IBus: `./scripts/typetune-test browser`.
Эта команда выключает compatibility и открывает локальную страницу в отдельном Chrome.
Автозапуск compatibility не добавлен; настройка автоматики действует до завершения runtime.

## Проверки

```sh
cargo test --workspace --all-targets --locked --offline
/usr/bin/python3 -m unittest discover -s integrations/compat -p 'test_*.py'
/usr/bin/python3 -m unittest discover -s integrations/ibus -p 'test_*.py'
```

На текущем Linux checkout: **115 Rust-тестов и 35 Python-тестов прошли**.
Результаты native-стендов и их точные границы — в [протоколе проверок](docs/17-validation-record.md).
Offline-команды требуют уже установленных системных библиотек и Cargo dependencies.

## Документация

- [Установка, управление и пользовательская проверка](docs/35-user-test.md)
- [Общий evdev/uinput backend и архитектурный ориентир Espanso](docs/37-universal-input-investigation.md)
- [Исправление задержки физического ввода](docs/38-compat-input-latency.md)
- [Повторный Double Shift](docs/39-repeat-double-shift.md)
- [Архитектура](docs/13-target-architecture.md), [спецификация](docs/16-product-spec.md), [план](docs/14-development-plan.md)
- [Обзор](docs/00-overview.md), [проверки](docs/17-validation-record.md), [оставшаяся работа](docs/18-linux-completion-plan.md)

Аудиты [Linux](docs/11-linux-audit.md) и [функций](docs/12-feature-audit.md) описывают
исторический baseline `8cc19d0`. Наличие старых GUI/tray, packaging, snippets или
anti-chatter модулей само по себе не означает готовность этих функций в preview.
Код Espanso не копировался; TypeTune сохраняет лицензию MIT.
