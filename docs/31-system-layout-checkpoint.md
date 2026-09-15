# Системное управление раскладкой GNOME — 2026-09-16

## Результат

Первый реализованный срез [общесистемного направления](30-systemwide-product-direction.md):
GNOME-мост умеет запросить реальную раскладку US/RU, а клиент — подтвердить её чтением.
Это управление вводом сессии, не локальная замена символов в собственном TextView.
HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.

Добавлены RequestSource в расширении и `integrations/gnome/switch_source.py`.
Команды требуют установленного и включённого обновлённого расширения:

```sh
python3 integrations/gnome/switch_source.py ru
python3 integrations/gnome/switch_source.py us
```

В основной сессии расширение этим этапом не устанавливалось; переключения выполнены
только в disposable compositor. Собран новый архив в `target/gnome/`.

## Контракт

RequestSource принимает JSON до 1024 символов с instance/generation/window/target.
Допустимы только настроенные xkb us/ru. До вызова source.activate(true) проверяется
свежий snapshot в потоке Shell: та же instance/generation/window, обычная user session,
ненулевое окно, без shield/lock/overview/external keymap, текущий источник xkb us/ru.
Неизвестный target, лишние поля, устаревший запрос и отсутствующий источник отвергаются.
Совпадение текущего источника — unchanged без повторной активации.

Активация использует штатный InputSource.activate, включая настройки per-window
самого GNOME; список источников команда не переписывает. API сверено с установленным
GNOME Shell 50.1 (`ui/status/keyboard.js` из libshell-18.so). Реализация не скопирована.
Поддержка других версий GNOME не заявлена.

Возвращаемый requested означает запрос, не доставленный приложению текст. Исключение
после начала активации — indeterminate без retry. CLI закрепляет unique D-Bus owner,
читает новое состояние с bounded calls, сверяет instance/window/restrictions и
разность generation/source_generation (смена контекста во время readback отменяет
подтверждение). observed означает наблюдаемую целевую раскладку, не успешную замену.
При timeout/ошибке после отправки — indeterminate. До чтения моста — unavailable.

Команда не читает текст, не меняет его, не вызывает clipboard и не захватывает ввод.
Это отдельная операция от будущей коррекции слова. Отсутствие password/IME field
context этим API не исправлено; text capabilities не повышаются.

## Проверки

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1, GJS 1.88.0,
GTK 4.22.4. Backend: отдельный native Wayland GNOME, временные config/data/runtime,
private session bus. Рабочая клавиатура и пользовательские приложения не затрагивались.

[Вывод совмещённого native-стенда](evidence/31-system-layout-native.txt).

- SWITCH-JS: deterministic проверки схемы, target, generation/window/instance,
  lock/shield/overview/external/non-user/IBus; старые BRIDGE-JS cases проходят.
- SWITCH-01: CLI RU → US; readback; один evdev keycode 30 после переключений
  приходит в реальный GTK-клиент как `ф`, затем `a`; полный fixture buffer проверен.
- SWITCH-02: отсутствующий настроенный источник и stale focus/generation отклонены;
  запрос текущего источника возвращает unchanged.
- SWITCH-03: активный screen shield запрещает смену источника.
- SWITCH-04: после disable/re-enable запрос предыдущей instance отклонён.
- GNOME-01…07, TEXT-01…08, MANUAL-01…02, LOCAL-01…04, EDITOR-01…03 проходят
  в одном запуске. Это прежние проверки с прежними границами, не новая матрица
  глобальной коррекции во всех приложениях.
- Проверены Python syntax, упаковка расширения, локальные ссылки и diff.
  Rust не изменён, Rust workspace tests повторно не запускались.

Первый keyboard fixture имел начальный текст, который GTK выделял при фокусе;
вместо предположения о положении каретки fixture теперь начинает с пустого поля.
Restart case в совмещённом запуске сначала попадал в context rejection после
закрытия всех окон; стенд теперь создаёт сфокусированное окно для изоляции проверки
старой instance. Рабочие guards не ослаблялись.

Повторение:

```sh
gjs -m integrations/gnome/tests/state_test.js
python3 integrations/gnome/tests/native_stand.py --text-stand --editor-stand
```

## Ограничения и продолжение

Этот этап — системная смена раскладки с подтверждённым последующим вводом.
Общесистемное исправление уже набранного слова и глобальная горячая клавиша
ещё не реализованы. Проверено одно GTK-поле в Wayland; ввод в Firefox, Qt,
Electron, терминалах, XWayland и per-window restore ещё требует отдельных cases.
Внутренний RemoteDesktop API использован только как тестовая клавиатура; это
не проверка portal permissions и не выбранный продуктовый input backend.

Следующий срез общего плана — выбор глобального observation/text path: IBus
против наблюдения клавиатуры + session bridge, с проверкой охвата неизменённых
приложений. Существующий physical helper и новый source control являются
составляющими решения, а не законченной Caramba-подобной функцией.

Продолжение: [системное наблюдение через IBus](32-ibus-observation-checkpoint.md).
