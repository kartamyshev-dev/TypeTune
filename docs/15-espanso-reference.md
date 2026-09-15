# 15 — Espanso: что применить в TypeTune

Дата исследования: **2026-09-10**. Статус: архитектурное исследование; код TypeTune и Espanso в рамках этого документа не изменялся и не запускался.

## 1. Вывод

Espanso подходит как образец разделения платформенного ввода, распознавания текста, выполнения замен и контекста приложения. Он **не является готовым образцом антидребезга**: его Linux evdev detector читает устройства, не захватывая их эксклюзивно, а замена компенсирует уже введенный триггер Backspace-событиями. Обработку физического ввода TypeTune и текстовые действия нужно проектировать как разные подсистемы. Основание: [открытие evdev-устройства](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/evdev/device.rs#L59-L85), [компенсация триггера](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/process/middleware/action.rs#L118-L132).

Главный переносимый принцип: ядро формирует семантическое действие, а адаптер платформы определяет, допустимо ли оно и как его выполнить. Подробные целевые контракты TypeTune описаны в [целевой архитектуре](13-target-architecture.md), последовательность реализации — в [плане разработки](14-development-plan.md).

## 2. Зафиксированная версия и границы проверки

Изучен репозиторий [espanso/espanso](https://github.com/espanso/espanso), ветка `dev`, commit **`a6bfad5985ea2e16d43d906aed0282b63bdb2bd2`**. В его [Cargo.toml](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/Cargo.toml#L1-L26) указана версия `2.4.1`; это идентификатор исследованных исходников, а не утверждение о версии установленного или последнего стабильного релиза.

Проверено:

- исходники `espanso-detect`, `espanso-inject`, `espanso-info`, `espanso-engine` и сборка этих компонентов в worker;
- конкретные алгоритмы чтения событий, преобразования раскладки, выбора способа вставки, подавления повторного распознавания и сброса текстового состояния;
- содержание 164 полученных файлов сверено с SHA blob-объектов дерева указанного commit; номера строк в ссылках взяты из этих файлов;
- официальная документация Espanso по Linux прочитана как отдельный источник, доступный на дату исследования.

Не проверены live-поведение Espanso в приложениях, гарантии доставки событий compositor-ом, корректность всех upstream workaround-ов и полный набор ошибок upstream. Наличие реализации в исходниках не означает ее приемку для TypeTune.

## 3. Разделение компонентов

| Область Espanso | Что фактически выделено | Решение для TypeTune |
|---|---|---|
| `espanso-detect` | `Source`: инициализация и получение событий; отдельные реализации для ОС | `InputObserver` отдельно от эксклюзивного физического фильтра |
| `espanso-engine` | Получение событий → обработка → отправка эффектов | Чистое ядро решений; никаких ioctl, GUI, shell-команд и ожиданий в обработчике физического ввода |
| `espanso-inject` | Отдельные операции строки, последовательности клавиш и комбинации | Различать вставку текста, нажатие сочетания и передачу исходного key-event |
| `espanso-info` | Контекст приложения с необязательными полями | Достоверность и доступность контекста являются частью контракта |
| Worker adapters | Связывают настройки, detector, injector, clipboard и renderer | Сборка приложения находится вне portable core |

Источники: [Source](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/lib.rs#L41-L96), [Engine](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/lib.rs#L34-L77), [Injector](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/lib.rs#L41-L65), [AppInfo](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-info/src/lib.rs#L37-L46), [сборка worker](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/mod.rs#L93-L195).

Espanso также разделяет события ввода и запросы побочных действий; у событий есть связь с исходным `source_id`. Это полезная основа для причинности и отмены устаревших действий. Для TypeTune следует добавить собственные поколения контекста, раскладки и конфигурации, идентичность устройства и транзакции: одного счетчика событий недостаточно для надежной замены текста в меняющемся окне. Источники: [события и source_id](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/event/mod.rs#L26-L48), [типы эффектов](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/event/effect.rs#L20-L63).

## 4. Платформы: наблюдение и вставка — разные возможности

| Платформа | Наблюдение в исследованной версии | Вставка | Что это означает для TypeTune |
|---|---|---|---|
| Linux X11 | XRecord, события клавиатуры/мыши; XKB/Xlib для интерпретации | X11 backend с libxdo и fallback через xdotool; отдельный clipboard backend | Хороший первый адаптер текстовых функций. Наблюдение не дает контракт эксклюзивного антидребезга |
| Linux Wayland | Чтение `/dev/input/event*`, собственное XKB-состояние | uinput с обратной картой символ → клавиша/модификаторы; clipboard | Доступ к физическим клавишам не дает автоматически контекст native Wayland-приложения или его текущую раскладку |
| Windows | Raw Input в служебном окне, преобразование `ToUnicodeEx` с раскладкой foreground thread | `SendInput`, в том числе Unicode-события | Можно изучать для текстового адаптера. Эту наблюдающую реализацию нельзя объявлять готовым подавлением дребезга |
| macOS | Глобальный монитор `NSEvent`, отдельно modifier events и hotkeys | CoreGraphics Unicode/key events | Нужен свой native adapter и управление разрешениями. Наблюдающий монитор Espanso не является блокирующим фильтром |

Источники: [X11 capture](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/x11/native.cpp#L89-L166), [X11 injection fallback](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/x11/mod.rs#L29-L101), [evdev reading](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/evdev/device.rs#L100-L194), [Windows capture](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/win32/native.cpp#L95-L190), [Windows Unicode injection](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/win32/native.cpp#L42-L58), [macOS capture](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/mac/native.mm#L61-L141), [macOS injection](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/mac/native.mm#L30-L94).

У Espanso Wayland выбран Cargo feature и связан с отдельной сборкой. Для TypeTune из этого следует необходимость изоляции зависимостей платформ, но не обязательность повторять схему отдельных Linux-бинарников: способ упаковки нужно выбрать после проверки backend-ов. Нельзя незаметно подключать X11 через XWayland и на основании этого объявлять поддержку всей Wayland-сессии. Источник feature: [Cargo.toml](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/Cargo.toml#L19-L26).

## 5. Текстовый буфер имеет границы достоверности

Matcher Espanso хранит ограниченную историю состояний, возвращается назад по Backspace и сбрасывает состояние при навигационных клавишах или клике мыши. Модификаторы обрабатываются отдельно с платформенными правилами. Это полезнее модели «копить все keycode до пробела»: положение курсора и назначение нажатия могут измениться независимо от пробела. Источник: [matcher state/history/invalidation](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/process/middleware/matcher.rs#L98-L250).

Для TypeTune требуется более явный контракт:

1. История представляет предполагаемый недавно введенный текст, а не содержимое редактора.
2. Смена focus, окна, раскладки, неизвестная composition, вставка из clipboard, перемещение курсора и потеря событий делают историю непригодной для автоматического удаления.
3. Физическая клавиша, keysym, Unicode scalar, grapheme cluster и подтвержденный текст приложения — разные сущности.
4. Коррекция раскладки должна использовать подтвержденный или явно ограниченный layout context. Язык распознанного слова не доказывает текущую системную раскладку.
5. При недостаточной достоверности действие отменяется или предлагается пользователю через доступный UI. Удалять предполагаемое число символов вслепую нельзя.

Это требования TypeTune, выведенные из его задачи; они не заявляются как уже реализованные гарантии Espanso.

## 6. Раскладка и модификаторы

EVDEVInjector Espanso строит обратные таблицы по XKB keymap и комбинациям модификаторов. Перед вставкой строки сначала проверяет наличие всех отображений символов, затем исполняет события и освобождает временные модификаторы. В нем есть ожидание отпускания уже удерживаемой клавиши. Переносимый принцип — сначала подготовить исполнимый план, затем выполнять его с явным состоянием клавиш. Источник: [карты и подготовка/исполнение строки](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/evdev/mod.rs#L151-L317).

Ограничения reference:

- Карта keymap — не универсальный способ ввести любой Unicode. В `Auto` Espanso выбирает clipboard для длинных строк и для non-ASCII текста в Linux. Это аргумент против жесткого ASCII-инжектора TypeTune. Источник: [выбор способа вставки](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/dispatch/executor/text_inject.rs#L66-L115).
- RMLVO для detector/injector получается из явной настройки либо обнаруженной раскладки; при неудаче выводится предупреждение. Сам факт создания XKB state не доказывает совпадения с состоянием рабочего стола. Источник: [keyboard_layout_util](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/keyboard_layout_util.rs#L23-L75).
- Wayland `get_active_layout` в этом commit имеет специальную ветку GNOME; в остальных случаях возвращает `None`. Обнаружение контекста окна и обнаружение раскладки имеют разные уровни поддержки. Источник: [layout provider](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/layout/mod.rs#L32-L57).
- Linux watcher периодически проверяет раскладку и сигнализирует о ее изменении. Перезапуск worker по такому изменению не следует переносить в захватывающий клавиатуру TypeTune без отдельного протокола безопасного переключения. Источник: [layout watcher](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/daemon/keyboard_layout_watcher.rs#L25-L66).

Для TypeTune нужны отдельные тесты: Shift с другой клавиатуры, AltGr, CapsLock/NumLock, изменение group, удержание клавиши во время вставки, невозможный для текущей карты символ, dead keys и composition. Нельзя считать поддержку этих случаев подтвержденной только наличием xkbcommon в зависимостях.

## 7. Исполнение замены не должно задерживать физический ввод

Detector Espanso работает на отдельном потоке: обновляет состояние клавиш и модификаторов и назначает монотонный ID до передачи события engine. Поэтому ожидание в engine не останавливает сам detector. Источник: [detect thread и stores](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/funnel/mod.rs#L45-L108).

При этом Espanso действительно использует блокирующие ожидания. Middleware ждет освобождения конфликтующих модификаторов, но после timeout продолжает обработку события; это не гарантия безопасной отмены. Для TypeTune такое поведение нужно заменить собственной политикой: timeout до начала удаления отменяет замену, а ошибка после начала исполнения переводит результат в частично выполненный. Источник: [delay_modifiers](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/process/middleware/delay_modifiers.rs#L27-L70).

Целевая последовательность TypeTune:

1. Получить кандидат замены из достоверной истории текста.
2. Выполнить вычисления и динамический renderer вне forwarding loop, с timeout и лимитом результата.
3. Подготовить весь способ вставки; проверить возможность удаления, layout/context generation и разрешения.
4. Получить право на исполнение одной замены и повторно проверить отсутствие пользовательского вмешательства.
5. Удалить подтвержденный фрагмент и вставить подготовленный результат.
6. Завершить собственные нажатия, обновить историю, сохранить результат операции без исходного введенного текста в журнале.

Операция «удаление + вставка» обычно не атомарна для внешнего редактора. Повторять всю операцию после неизвестного/частичного результата нельзя: это может удалить уже другой текст.

## 8. Clipboard и подсчет удаляемого текста

Clipboard adapter Espanso имеет настройку paste shortcut, задержки перед вставкой и восстановлением, а также RAII guard. Однако guard хранит только `Option<String>` через `get_text` и возвращает текст через `set_text`; из этого нельзя заключить сохранение всех MIME-форматов или защиту от новой пользовательской записи в clipboard. Источник: [clipboard adapter и restore guard](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/dispatch/executor/clipboard_injector.rs#L65-L218).

Требования TypeTune: изолированный clipboard adapter, выбор подходящего shortcut по достоверному контексту, сохранение поддерживаемых форматов, проверка владения/изменения clipboard перед восстановлением, отмена при смене focus. Фиксированная пауза снижает вероятность гонки, но не подтверждает, что целевое приложение приняло текст.

В Espanso компенсация триггера использует `chars().count()`. Для TypeTune число Unicode scalar values нельзя объявлять универсальным числом Backspace: combining marks, emoji и редакторы имеют различную семантику удаления. MVP должен явно ограничить допустимую область автоматической замены, а расширение Unicode support проходить через отдельную матрицу приложений. Источник: [подсчет удаления и undo](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/process/middleware/action.rs#L118-L148).

## 9. Собственные события и устаревшая очередь

В Espanso нет одного универсального механизма распознавания собственных событий:

| Область | Фактический прием | Что требуется TypeTune |
|---|---|---|
| macOS | Вставленные события помечаются специальной координатой; detector проверяет ее | Отдельный контракт происхождения событий и проверка выбранного native marker. Координатный workaround не копировать без обоснования |
| Windows | Фильтрация Raw Input без известного HID source, учитывающая настройку и текущую expansion | Проверить программные клавиатуры, accessibility tools и собственный ввод; неизвестный источник не означает автоматически собственное событие |
| EVDEV | Список устройств открывается при инициализации detector; injector создается позже | При hotplug и restart явно исключать свое виртуальное устройство по контролируемой идентичности. Порядок запуска не является достаточной защитой |
| Engine | `source_id` и discard middleware исключают устаревшие диапазоны событий | Отменять устаревшие текстовые решения; физические key-release обязаны сохранять корректность состояния |

Источники: [macOS marker capture](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/mac/native.mm#L61-L69), [macOS marker injection](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-inject/src/mac/native.mm#L26-L28), [Windows event filtering](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/win32/mod.rs#L192-L207), [порядок запуска detector/injector](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/mod.rs#L132-L193), [discard middleware](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-engine/src/process/middleware/discard.rs#L27-L77).

## 10. Wayland context и реальные ограничения

Официальная [инструкция Espanso для Wayland](https://espanso.org/docs/install/linux/#install-on-wayland) на дату исследования называет поддержку экспериментальной и перечисляет ограничения: настройка non-US layout, зависимость app-specific поведения от окружения, особенности clipboard и необходимость перезапуска после подключения клавиатуры. Это полезный список сценариев проверки, но не описание всех возможностей текущей ветки `dev`.

В исследованном commit `AppInfoProvider` уже включает KDE через `kdotool`, ряд compositor-ов через `wlrctl`, Niri через его CLI и fallback с пустыми полями. GNOME не имеет отдельного AppInfoProvider в этой таблице выбора. Поэтому утверждения «Espanso вообще не умеет app context на Wayland» и «Espanso полностью решил app context на Wayland» одинаково неверны. Источники: [выбор Wayland provider](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-info/src/lib.rs#L70-L127), [реализации и пустой fallback](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-info/src/wayland/mod.rs#L20-L209).

Для TypeTune поддержка должна публиковаться по возможностям конкретной сессии: наблюдение, подавление физического ввода, чтение layout, focus context, insertion, secure-field signal. `Unknown` — отдельное состояние, а не пустое имя разрешенного приложения. Невыполненная проверка capability должна отключать зависимую функцию, а не весь безопасный базовый ввод.

На macOS Espanso отдельно следит за Secure Input и передает изменения в engine; аналогичного watcher в Linux/Windows в этом модуле нет. Нельзя переносить эту платформенную возможность как якобы универсальное распознавание password fields. Источник: [Secure Input watcher](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/secure_input.rs#L23-L48).

## 11. Привилегии: заимствовать принцип, определить свою границу

Espanso реализует Linux capability flow: проверка `CAP_DAC_OVERRIDE` в permitted set, включение effective capability и последующая очистка effective/permitted. В worker вызов включения расположен до инициализации detector, а очистки — после создания обработчиков. Это изученный порядок вызовов; аудит всех потоков и фактических привилегий процесса на Linux здесь не проводился. Источники: [capabilities helper](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/capabilities/linux.rs#L23-L42), [worker initialization](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/mod.rs#L132-L193), [вызов очистки](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/src/cli/worker/engine/mod.rs#L278-L285).

Это не reference реализации отдельного привилегированного input broker. Для TypeTune граница между доступом к физическим устройствам и пользовательскими действиями должна быть самостоятельным архитектурным решением. В компоненте, который удерживает клавиатуру, не должно быть renderer-а сниппетов, shell-команд, сетевых операций, GTK или произвольной записи файлов. Hotplug, отзыв прав, завершение пользовательской сессии, остановка и авария должны иметь формальные сценарии восстановления ввода. Разрешения процесса и владение открытыми дескрипторами необходимо проверять наблюдением на Linux, а не только чтением установочного скрипта.

## 12. Лицензия и способ использования reference

TypeTune сейчас указывает MIT в корневых `LICENSE` и `Cargo.toml`. Espanso содержит [GPL version 3](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/LICENSE#L1-L16), его [package metadata](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso/Cargo.toml#L1-L8) указывает `GPL-3.0`, а заголовки рассмотренных файлов предусматривают version 3 or later. В отдельных файлах есть собственные уведомления о происхождении, например [evdev/native.cpp](https://github.com/espanso/espanso/blob/a6bfad5985ea2e16d43d906aed0282b63bdb2bd2/espanso-detect/src/evdev/native.cpp#L1-L27) содержит уведомление кода примера libxkbcommon.

В этом исследовании upstream-код в TypeTune не переносился. Практический подход: сохранять ссылки на изученные решения, формулировать собственные контракты и тесты, реализовывать их по документации платформ. Если позднее планируется копирование файла/фрагмента или подключение Espanso как зависимости, сначала отдельно определить происхождение, применимые условия и последствия для выбранной модели распространения. Этот документ фиксирует факты из лицензий и не делает юридического заключения о конкретном способе интеграции.

## 13. Что принять и что не считать решенным

**Принять в архитектуру TypeTune:**

- Раздельные адаптеры наблюдения, injection и контекста.
- Семантические действия вместо передачи синтетических key-events между всеми стадиями.
- Независимость физического ввода от выполнения замен.
- Ограниченную историю текста и явную ее инвалидацию.
- Предварительную проверку полного плана вставки, поддержку clipboard как самостоятельного backend-а.
- Отдельный учет клавиш/модификаторов, происхождения событий и последовательности действий.
- Публикацию возможностей по реально проверенной платформе и сессии.

**Не считать полученным от Espanso:**

- Anti-chatter state machine и сохранение Press/Release/Repeat при exclusive grab.
- Защиту от потери клавиатуры при зависании, panic, disconnect или ошибке uinput.
- Универсальный Wayland focus/layout/secure-field provider.
- Гарантированную атомарную замену в любом приложении, произвольный Unicode deletion или полное восстановление clipboard.
- Доказательство, что фиксированные задержки, startup order и эвристика неизвестного HID source подходят TypeTune.
- Основание объявлять все три платформы поддерживаемыми до независимых live-проверок.

Приемка перенесенного принципа должна проверять пользовательский результат и отказ: физический ввод продолжает работать, лишние символы не удаляются, исходное слово сохраняется при невозможности подготовки замены, зависшая команда не удерживает клавиатуру, смена контекста отменяет устаревшее действие, собственный ввод не запускает повторную замену.

## Обновление 2026-09-16

Повторное исследование dev `76a61b87f037e0ce7e84db5891f9968a8fa4059e`,
проверка альтернативы GNOME и решение о системном keyboard backend:
[37 — общий ввод без IBus](37-universal-input-investigation.md).
