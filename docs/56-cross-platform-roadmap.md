# 56 — перенос текущего TypeTune на Windows и macOS

Обновлено: 2026-09-17. Это план, не описание работающих портов.
Отправная точка — Linux preview этапов 53–55: один compatibility runtime,
общий Rust engine/bridge, Python controller/GTK GUI, evdev/uinput и GNOME bridge.
Исторические IBus-исследования не являются обязательной частью переноса.

## 1. Какой продукт переносим

Цель — одинаковое пользовательское поведение в поддерживаемых приложениях:

- Double Shift исправляет последнее слово RU↔EN и меняет язык дальнейшего ввода.
- Повторный Double Shift переключает то же слово и раскладку обратно.
- Автокоррекция на пробеле использует частотные и пользовательские словари,
  включая реализованные ограничения двух- и трёхбуквенных слов.
- GUI и индикатор позволяют запустить/остановить, поставить на паузу, управлять
  автоматикой и автозапуском. Настройки применяются через один controller.
- Пользовательские слова, исключения слов и приложений сохраняются.
- После трёх возвратов автозамены предлагается исключение; после трёх отдельных
  ручных исправлений — слово для автоматики. Пробел допускается до или после
  жеста; повторное переключение отзывает вклад текущего вхождения. Добавление
  требует подтверждения; счётчики предложений остаются только в памяти сеанса.
- Графическая установка, обновление/удаление с сохранением пользовательских данных.

Сниппеты, anti-chatter, выделенный текст, другие языковые пары, мобильные ОС и
Linux desktops кроме GNOME не являются условием паритета с нынешним preview.
Физический фильтр клавиш не включаем в обязательный путь текстовой коррекции.

## 2. Что реально общее, а что предстоит выделить

| Слой | Что есть в Linux | Решение для портов |
|---|---|---|
| Правила RU/EN и словари | `typetune-engine`, frequency data, user dictionary | Сохранить общий Rust-код и corpus; без независимых matcher-ов |
| ABI | `typetune-bridge`: configure/infer и контракты планов | Проверить `.dll`/`.dylib`, Unicode, ownership, ошибки; версия протокола до независимого выпуска |
| История и Double Shift | `integrations/compat/history.py`, `integrations/app/gesture.py` | Выделить платформонезависимый автомат; evdev-коды не переносить как универсальные |
| Feedback | `integrations/app/correction_feedback.py` | Сохранить семантику через единые fixtures; выделить доменную часть без Gio/GTK |
| Настройки/controller | Python JSON + Unix locks, Gio/D-Bus, XDG | Отделить схему, migration/generation от Unix storage/IPC; Windows не поддерживает текущий fcntl путь |
| Интерфейс | GTK4/PyGObject + Linux tray | Перенести сценарии и controller-контракт; конкретный toolkit выбрать после packaging spike |
| Capture/output/focus/layout | evdev/uinput + GNOME extension | Написать отдельные Windows/macOS adapters и guards |
| Установка/автозапуск | `.deb`, polkit, udev, XDG | Native installer/login integration; input group и GNOME extension не переносить |

Не объявляем Python frontend переносимым только потому, что Python доступен на ОС.
Решение об общем GUI (GTK или иной toolkit) принимается в CP-1 по работающему
окну, tray/menu bar, установке и разрешениям на обеих целевых системах.
Rust остаётся владельцем правил; UI toolkit не должен содержать копию корректора.

## 3. Контракт адаптера

В callback только нормализовать событие и передать его в ограниченную очередь;
обычный ввод продолжает поступать приложению. Никаких синхронных GUI/IPC/дисковых
операций или ожидания движка в keyboard callback.

Событие несёт native keycode namespace, Down/Up/Repeat, timestamp, modifiers,
origin и device identity, если API её предоставляет. Недоступная identity —
Unknown; нельзя выдумывать device ID для гарантии Double Shift с одной клавиатуры.
Layout/application/focus epoch и состояние разрешений проверяются до удаления
и перед вставкой. Собственные события маркируются и не становятся новым вводом.

Один executor выполняет удаление, вставку и запрос раскладки с readback.
До первой правки отказ сохраняет текст. Частичная/неопределённая вставка сбрасывает
историю, не запускает слепой retry. Потеря фокуса, lock, sleep, compose/IME,
ошибки output, overflow очереди и потеря наблюдения инвалидируют историю.
Unknown text/selection/password не считается подтверждённой безопасностью.

Compatibility-профиль может работать по истории клавиш с явно показанными
ограничениями, как Linux. Accessibility/text API — необязательное усиление
контекста, не условие запуска каждой поддерживаемой программы.

## 4. Этапы и критерии завершения

Порядок: **CP-1 → Windows W-1…W-4 → macOS M-1…M-4 → CP-2**.
Это предлагаемый порядок разработки, не обещание сроков. macOS spike разрешений
можно выполнить раньше при доступе к Mac; полного порта без native стенда не принимать.

### CP-1 — общие границы и сборки

- [ ] Зафиксировать fixtures Linux этапа 55 как parity suite: текст, каретка,
  раскладка следующего ввода, баланс клавиш, feedback, настройки и ошибки.
- [ ] Выделить историю/gesture/feedback и контроллерные операции из Linux-зависимостей.
  Сначала сохранять поведение на Linux; перенос в Rust делать по контрактным тестам.
- [ ] Ввести storage/IPC abstraction: atomic save, generation conflict, apply ACK,
  per-user access. Слова/clipboard не попадают в обычные логи.
- [ ] Добавить CI common crates на Linux, Windows, macOS и ABI smoke.
  Полный Linux workspace не считать подходящим списком зависимостей для портов.
- [ ] Сделать GUI/tray/package spike и записать ADR выбора toolkit и схемы IPC.

**Gate:** parity suite не регрессирует на Linux; core/ABI собирается и тестируется
на трёх ОС. Это ещё не общесистемная коррекция на Windows/macOS.

### Windows

Первый кандидат стенда — Windows 11 x64, обычная пользовательская сессия.
Версию/build и минимальную ОС зафиксировать по результатам W-1; ARM64 — отдельный gate.

- [ ] **W-1 capture/context:** сравнить Raw Input и WH_KEYBOARD_LL на native spike;
  выбрать один canonical observer без двойного счёта. Проверить Down/Up/Repeat,
  левый/правый Shift, injected origin, foreground window/application и текущую
  раскладку целевого потока. Hook живёт на отдельном message-loop потоке.
- [ ] **W-2 manual executor:** SendInput для Backspace/Unicode либо проверенной
  последовательности клавиш; запрос языка целевого окна с readback, восстановление
  modifiers. Double Shift и обратное переключение, неудачи до/после удаления.
- [ ] **W-3 parity:** автоматическая коррекция, слова/исключения, оба вида feedback,
  GUI/tray/controller, per-user persistence, pause/stop и opt-in startup.
- [ ] **W-4 delivery:** выбрать installer после spike, подписать выпуск, проверить
  чистую установку, обновление и удаление с сохранением настроек, logout/reboot.
  В релиз прикреплять installer только после native acceptance.

Ограничения для проверки: повышенные права приложения, UAC/secure desktop,
IME/dead keys, layout per window, несколько клавиатур, held modifiers, удалённая
сессия и консольные поля. Запускать весь TypeTune администратором по умолчанию не планируем.
SendInput ограничен уровнем целостности (UIPI); успешная отправка событий не
доказывает изменение документа. Hook может отключиться при долгом callback:
нужны неблокирующий транспорт и проверка восстановления. Основание:
[Microsoft: LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc),
[Microsoft: SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).

### macOS

Первый кандидат — Apple Silicon и зафиксированная в spike версия macOS.
Intel, минимальная версия ОС и universal binary требуют отдельной проверки.

- [ ] **M-1 permissions/capture:** prototype CGEvent tap, preflight/request доступа
  к наблюдению и отправке событий, Accessibility при использовании AX API.
  GUI показывает отказ/отзыв разрешений. Проверить Secure Input, отключение tap,
  sleep/wake и lock/unlock; не собирать историю при потере наблюдения.
- [ ] **M-2 manual executor:** CGEvent output, собственный origin, клавиши/Unicode,
  источник ввода через системные API с readback. Проверить flagsChanged для Shift,
  две стороны Shift, held modifiers, Command shortcuts, compose/dead keys.
- [ ] **M-3 parity:** тот же corpus, автоматика, dictionaries/feedback, app exclusions
  по стабильной идентичности приложения, GUI/menu bar, сохранение и apply ACK.
- [ ] **M-4 delivery:** подписанный `.app`, notarization и выбранный формат доставки;
  opt-in login item, миграция настроек/permissions при обновлении, удаление.
  Проверять установленное подписанное приложение, а не только dev binary.

CGEvent tap и ServiceManagement — кандидаты native API, не подтверждённая
реализация TypeTune. Точные возможности выдачи/отзыва разрешений и смены источника
устанавливаются в M-1/M-2 на выбранной ОС. Официальные точки входа:
[Apple: CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[Apple: CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()),
[Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

### CP-2 — выпуск портов

- [ ] Добавить платформенные build/test/package jobs; secrets подписи доступны
  только доверенным release jobs, не pull request из fork.
- [ ] Отдельные assets и SHA256SUMS для каждой прошедшей acceptance платформы.
  Tag не объявляет неподтверждённую ОС поддержанной; Linux `.deb` остаётся отдельным asset.
- [ ] До публикации скачать assets и проверить hash/version/source_commit.
- [ ] Разделить unit/simulated, native dev и packaged acceptance в release notes.
  Отсутствие native runner/машины означает pending gate, а не успешную проверку.

## 5. Минимальная acceptance-матрица

На каждой ОС фиксировать commit, OS/build, architecture, app/version, session,
permissions, backend и case IDs. Сначала контролируемый редактор, потом native apps.

| Cases | Проверка | Где |
|---|---|---|
| PAR-01/02 | Double Shift и обратный жест; следующее слово в нужном языке | Простой редактор + браузер |
| PAR-03/04 | Автокоррекция, 2/3 буквы; known words/URL/code не меняются | Общий corpus + native поле |
| PAR-05 | Три отмены → предложение исключения; Add/Dismiss | GUI + редактор |
| PAR-06 | «пшерги» → Space → Double Shift и обратный порядок; один счёт; отзыв | GUI + native поле |
| PAR-07/08 | Исключения слов/приложений, pause/stop; apply generation | Браузер, редактор, IDE |
| PAR-09 | Focus/selection, modifiers, clipboard paste, IME/dead keys | Negative matrix |
| PAR-10 | Output failure, observer loss, lock, sleep/wake; без слепого retry | Fault/native stand |
| PAR-11 | Install/upgrade/remove, настройки, startup после login/reboot | Чистая машина/VM + signed build |

Первичный app-набор Windows: Notepad, Edge/Chrome, VS Code; macOS: TextEdit,
Safari/Chrome, VS Code. Версии записываются при тестировании. Терминалы,
password/Secure Input, elevated apps, игры и удалённые сеансы тестировать отдельно;
наличие API не означает гарантированную поддержку этих классов.

## 6. Что делать следующим

Начать **CP-1**: оформить canonical parity fixtures и выделить Linux-независимый
controller/storage/gesture/feedback contract, затем включить core/ABI CI для трёх ОС.
До W-1 и M-1 нужны реальные Windows/macOS стенды. На текущей Linux-машине можно
подготовить контракты и сборочную матрицу, но нельзя принять native-порты.
