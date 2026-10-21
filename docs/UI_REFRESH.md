# Обновление интерфейса TypeTune

База: `main` `2f31167`; работа только в `ui-refresh`, без слияния и выпуска.
macOS 14+, Swift language mode v5. Новый дизайн до выбора пользователя не реализуется.

## Исходный интерфейс

Утилита строки меню с одним окном настроек 740×690 фиксированного размера.
Сверху цветная шапка с клавиатурой, названием, подзаголовком и капсулой состояния.
Шапка принимает изображение перетаскиванием. Ниже вертикально добавляются предупреждения,
затем четыре вкладки: «Основное», «Исключения», «Сниппеты», «Проверка».
Основное — grouped Form, остальные вкладки содержат списки/прокрутку. Нижняя строка:
сообщение службы, последнее событие, версия и кнопка выхода.
Сниппеты: поиск, список с переключателями и действиями, модальный редактор.
Меню строки меню: состояние, автоисправления, настройки, выход; флаг текущей раскладки.

## Контракт элементов управления и привязок

Чекбоксы ниже — приёмка после редизайна; исходный аудит кода не отмечает их выполненными.
`settings.*` означает `store.settings.*`; `form.*` — локальный `SettingsForm`.

### Окно, шапка, баннеры и нижняя строка

- [ ] Четыре раздела и выбранный раздел (`form.tab`, 0…3).
- [ ] Заголовок/подзаголовок; цвет (`@AppStorage headerColor`), светлая надпись (`headerLightText`).
- [ ] Изображение (`store.headerImage/headerImagePath`), drop fileURL/TIFF → `acceptHeaderImage` → `importHeaderImage`; индикатор `form.headerDropTargeted`.
- [ ] Статус: `serviceStatus.title`, `running`, `recoveryRequired`.
- [ ] Нет AX/мониторинга: `trusted/listening`, «Разрешить доступ» → `keyboard.requestPermission()`.
- [ ] Ошибка чтения: `settingsStorageAvailable`; объяснение сохранности данных; разделы заблокированы.
- [ ] Secure Input: `secure`, владелец `secureInputOwner`, объяснение паузы.
- [ ] Число буферизованных событий (`bufferedEvents`).
- [ ] Неподтверждённый результат (`recoveryRequired/textReviewRequired/uncertainInput`), запрет повторной отправки.
- [ ] «Текст проверен — продолжить» → `confirmTextReviewed()`, disabled при `outstandingInput > 0`.
- [ ] Сохранённые нажатия (`pendingInput`), инструкция возврата в исходное поле и ⌘⌥R.
- [ ] «Отбросить сохранённые нажатия…» → `discardPendingInput()`.
- [ ] Ожидаемая доставка (`outstandingInput`), даже без `recoveryRequired`.
- [ ] Нижняя строка: `serviceStatus.message`, `lastStatus`, версия Bundle и экспериментальный статус.
- [ ] «Выйти» → `NSApp.terminate`, обработка незавершённого ввода в AppDelegate сохраняется.

### Основное

- [ ] Пауза → `settings.paused`.
- [ ] Автоматическая раскладка → `settings.automatic`.
- [ ] Все приложения → `store.universalInput`, обе условные подсказки.
- [ ] Раннее исправление → `store.earlyCorrection`, предупреждение при ON.
- [ ] Опечатки → `settings.typos`.
- [ ] Ё → `settings.yo`.
- [ ] Словарь macOS → `store.useSystemDictionary`.
- [ ] Звук → `settings.sound`.
- [ ] Выбрать звук → `chooseSound()`, стандартный → `customSoundPath = ""`, условная кнопка/подпись.
- [ ] ABC/Русская → `InputSources.select(.english/.russian)`, затем `keyboard.refresh()`.
- [ ] Single Shift → `settings.singleShift`.
- [ ] Подсказки Double Shift / ⌘⌥Space / ⌘⌥Z.
- [ ] Single Option → `settings.optionCorrection`.
- [ ] Два Shift → `settings.shiftChordPause`.
- [ ] ⌘⇧V → `settings.plainPaste`, экспериментальный статус.
- [ ] Автозапуск → `SMAppService.mainApp.register/unregister`, readback `launchAtLogin`, ошибки и requiresApproval в `lastStatus`.
- [ ] Тема → `@AppStorage theme`: system/light/dark; `preferredColorScheme`.
- [ ] Палитра → `headerColor`: blue/green/violet/orange/neutral, прежние ключи и значения.
- [ ] Контраст → `headerLightText`.
- [ ] Выбрать изображение → `chooseHeaderImage()`, убрать → `resetHeaderImage()`; условные состояния отсутствия/ошибки/наличия.

### Исключения

- [ ] Поле слова `form.word`, Return/«Добавить» → `addWord`: trim, lowercase, без дубликатов; disabled пустого.
- [ ] Список `excludedWords`, «Убрать» удаляет только выбранное слово.
- [ ] Bundle ID `form.bundleID`; добавить → `addApp`, выбор приложения → `chooseApp`; disabled пустого.
- [ ] Список `excludedApps`, «Убрать» удаляет выбранный ID.
- [ ] Подсказка приоритета полного запрета/паузы над автоматикой.
- [ ] `form.autoBundleID`, «Добавить правило» → `addAutoApp`, выбор → `chooseAutoApp`; trim/проверка пробелов, новое правило OFF.
- [ ] Для каждого `settings.appAutomatic[id]` — Picker false/true и удаление только выбранного правила.
- [ ] Подсказка защищённых полей и неподдерживаемых редакторов.

### Сниппеты

- [ ] Общий переключатель → `store.snippetsEnabled`.
- [ ] «Импорт…» → NSOpenPanel JSON → `importSnippets`, disabled при недоступном хранилище.
- [ ] «Экспорт…» → NSSavePanel JSON → `exportSnippets`, disabled пустой библиотеки.
- [ ] «Добавить» → новый Snippet/editor; disabled при недоступном хранилище.
- [ ] Поиск `query`: по сокращению/тексту без учёта регистра.
- [ ] Список `filtered`: enabled → `setSnippet`, сокращение, summary текста, тип триггера.
- [ ] «Изменить» → редактор выбранного; «Удалить» → alert с сокращением, отменой и destructive `deleteSnippet`.
- [ ] Подсказки срабатывания/другой раскладки/⌘⌥Z, недоступного файла, universal OFF, хранения без шифрования.
- [ ] Выученные слова `settings.learnedWords`; «Снова исправлять» удаляет только выбранное исключение.

### Редактор сниппета

- [ ] Новый/существующий заголовок; локальный `draft`, отмена не сохраняет.
- [ ] Сокращение → `draft.abbreviation`, автоматический defaultTrigger до ручного выбора.
- [ ] Триггер → `draft.trigger`, фиксирует `triggerChosen`.
- [ ] Текст → `draft.text` (TextEditor).
- [ ] Кнопки {{дата}}, {{время}}, {{буфер}}, {{курсор}} дописывают переменную; подсказка форматов/экранирования.
- [ ] Другая раскладка → `draft.otherLayout`; регистр → `draft.matchCase`; включён → `draft.enabled`.
- [ ] Приложения → `draft.applications.mode` all/only/except.
- [ ] При only/except: список ID, удаление одного, поле `bundleID`, добавить с trim/без дубликатов, выбрать .app через NSOpenPanel.
- [ ] Предпросмотр `SnippetTemplate.render` с датой/временем, условным буфером, маркером каретки.
- [ ] Все сообщения `SnippetIssue`, предупреждение immediate для буквенного/цифрового сокращения.
- [ ] «Отмена»/Esc → dismiss; «Сохранить»/Return → `saveSnippet`, dismiss только без ошибок; disabled при issues.

### Проверка

- [ ] `form.sample`, преобразование → `Layout.convert(... InputSources.mapping)` в `form.preview`.
- [ ] Автоправило → `keyboard.decide`, «Без изменения» при nil.
- [ ] Выделяемый результат/пустое состояние, предупреждение о пределах preview.
- [ ] Раскладка, AX, мониторинг, отправка, tap, последний отказ → соответствующие поля Store.
- [ ] Итог исправлений `corrected`, категории `statistics`: automatic/typo/yo/manual/singleShift, количество и оценка времени.
- [ ] Общая экономия, пояснение весов, звук, исторический итог, ошибка хранения статистики.
- [ ] Пропуски `skipped`, события `keyEvents`, пояснение приватности отчётов.
- [ ] «Обновить состояние» → `refresh`; «Повторить подключение» → `retryConnection`; «Сохранить отчёт…» → `saveDiagnosticReport`.

### Строка меню и доступность

- [ ] Статус `serviceStatus.title`, разделители.
- [ ] «Автоисправления» инвертирует `settings.paused`, флажок и disabled при недоступных настройках.
- [ ] «Настройки…»/⌘, → `showSettings`, повторное открытие существующего окна.
- [ ] «Выйти из TypeTune»/⌘Q → terminate с прежним recovery gate.
- [ ] Флаг/источник InputSources, суффиксы !/Ⅱ, tooltip со статусом и владельцем Secure Input.
- [ ] Понятные VoiceOver-подписи, Tab, ⌘W, Esc в sheets, контраст обеих тем — отдельная native/user manual проверка.

## Безопасность offline-отрисовки

DEBUG-вход в main выполняется до SingleInstance и создания AppDelegate. NSApplication
имеет policy prohibited; delegate/status item не создаются. Store получает отдельный suite,
очищаемый до и после запуска, и временный путь сниппетов. @AppStorage получает тот же suite.
Начальная вкладка доступна только через DEBUG initializer. Никакие кнопки не нажимаются.
KeyboardService(false): инициализация возвращается до наблюдателей/таймеров/refresh;
`vocabulary`/`terminalBridge` lazy, в stored initializers AX нет. CGEventSource создаёт источник,
но не event tap и не посылает событий. deinit → stop сразу возвращается при observesSystem=false.
SettingsView/SnippetEditorSheet не имеют onAppear/task, запускающих службу или AX.
Системная раскладка/разрешения, приложение в /Applications и пользовательский suite не меняются.

Матрица: 4 вкладки × 2 темы × 6 состояний (ready, AX denied, listening denied,
Secure Input с владельцем, review+saved input, settings unavailable) + 2 редактора = 50 PNG.
PNG приватные, в Git не включаются. Скрипт: `scripts/render_settings.sh before`.
Это снимки содержимого, не native-проверка действий, VoiceOver или полной прокрутки.

## Продолжение

После снимков «до» пользователь уточняет шапку/цвета/плотность/вкладки/размер/шрифты/тексты.
Затем 2–3 offline-прототипа и выбор. До выбора не менять продуктовый дизайн.

## Результат первого прохода — 2026-10-21

50 PNG созданы, заголовки/формы/списки/редактор доступны для предварительного обсуждения.
При визуальном просмотре обнаружены ограничения cacheDisplay: сегментированные вкладки
частично чёрные/белые без подписей, есть выход содержимого за фиксированную рамку.
Общий статус отрисовки PARTIAL; эти снимки не подтверждают фактический вид установленного UI.
Фон окна добавлен только в renderer, NSAppearance задан окну/hosting/drawing context.
Изменение window style на titled и принудительное display не устранили артефакт вкладок.
Не подменять настоящие вкладки нарисованными копиями ради красивого снимка.
Полная визуальная приёмка требует устранить ограничение renderer или отдельно сравнить
снимок настоящего окна в разрешённом пользователем этапе установки.
SDK по умолчанию на этом Mac: 27.0 с отсутствующим SwiftUIMacros; скрипт выбирает
установленный 26.5, если SDKROOT не задан. Ключи/логика пользователя не менялись.
[Проверки и хеши](../research/evidence/ui-refresh-2026-10-21/verification.json).
