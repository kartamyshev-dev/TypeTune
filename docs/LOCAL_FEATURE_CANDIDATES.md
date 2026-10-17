# Кандидаты локальных функций: ресурс, связь с main и неизвестное поведение

Узкая проверка 2026-10-15: сохранённый REA export `origin-evidence-bundle.json`
и зафиксированный bundle Caramba2026.10.07/20261007.1. Новых REA сессий/import,
UI, событий ввода и изменений процессов не было. Ни один кандидат этим
документом не объявляется реализованной или поведенчески проверенной функцией.

Авторский индекс: [local-feature-candidates.json](../research/evidence/local-feature-candidates.json),
ID `LP-LOCAL-CANDIDATES-20261015-01`. Target arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
В индексе — SHA всех файлов с найденными точными литералами, offsets/VA,
сохранённые REA IDs и границы собственного сканирования.

Продолжение: [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md). Новый пакет
получил перечисленные ниже main тела и подтвердил callback writers сброса звука
и цвета заголовка. Приведённая далее матрица — исходный уровень до этого пакета;
её открытые runtime-границы сохраняются. FocusEN оказался repeated model field,
не восстановленным Boolean flag; `0x10025a030` оказался TIS language resolver.

## Разделение уровней доказательства

| Кандидат | Общий UI framework/ресурс | Что найдено в main | Чего ещё недостаточно |
|---|---|---|---|
| Произвольная plain-paste hotkey | Полный текст о любой комбинации, включая ⌘V, найден в бинарнике `CarambaSwitcherUI.framework` и EN/RU локализациях его отдельного resource bundle. Точный текст не найден в main executable | Main содержит именованный ключ `tech.caramba.switcher.paste-no-format`, собственный keyboard-shortcut recorder и реальный paste путь `0x100022cb4` | Не доказано, что recorder доступен именно для этой функции в этой версии, как связывается с ключом, обрабатывает конфликт и сохраняет назначение. Реальный paste путь сам не доказывает произвольный выбор горячей клавиши |
| Удаление собственного звука | `Remove custom sound` — только общий UI framework и его EN/RU ресурсы в пределах exact scan | Main содержит `tech.caramba.switcher.sounds.main-sound-override`. Импортированный initializer `SettingsPaneView` содержит параметры callback `onDropSound`, `onResetCustomSound` | Имена callback не устанавливают ненулевую привязку и фактическое действие. Не прослежены удаление ключа/файла, fallback звука, доступность кнопки и её сохранение |
| Цвет заголовка | Общий framework экспортирует `HeaderColor.name(forLegacyHex)` и `ColoredHeaderView.defaultColor`; initializer содержит `onHeaderColorChange` | Main имеет `_headerColorName`, `caramba.header-color-name`, `tech.caramba.switcher.personalization.header-color`; есть прямые вызовы экспортов framework | Не установлено, какие цвета доступны пользователю, где виден заголовок, как мигрируется legacy hex и сохраняется выбор. Это не доказательство поддержки пользовательской темы целиком |
| Переключение в EN при фокусе | Точный `switch_to_en_on_focus` не найден в проверенных UI framework/resources | Маркер есть только в main executable; он расположен среди сериализуемых Rust model fields/special behaviors. Есть адресное обращение из интервала функции `0x1002d68a0` | Наличие поля модели не устанавливает активное правило, приложение-цель, событие фокуса, значение по умолчанию или пользовательскую настройку. Focus→TIS цепочка не восстановлена |

«Только» в таблице означает точный поиск семи выбранных литералов в67 обычных
не-symlink файлах зафиксированного bundle: UTF8 и UTF16 LE/BE byte patterns.
Это не доказательство отсутствия эквивалентного текста, составных Swift literals,
сжатых/зашифрованных данных, динамического кода или самой возможности.
Архитектура framework по одному literal scan не приписывается отдельному slice.
Извлечённые строки не используются как собственный пользовательский интерфейс.

## Проверенные адресные anchors в arm64 main

Ниже дополнительный **локальный форматный анализ**, не новые REA xrefs:
разобраны LC_SEGMENT_64 и LC_FUNCTION_STARTS, непосредственные ARM64 BL и
конструкции ADRP+ADD. Все найденные пары адресации соседние; данные описывают
адресное обращение, не выполнение ветви в runtime. Интервал function-starts
задаёт адрес будущего запроса функции, а не восстановленную семантику.

| Объект | VA литерала / импортный thunk | Обращение в main | Интервал LC_FUNCTION_STARTS для следующего запроса |
|---|---|---|---|
| paste shortcut key | `0x1004bcfa0` | ADRP/ADD `0x10000a468/0x10000a46c` и `0x100024024/0x100024028` | `0x10000a45c`, `0x100023dd4` |
| custom sound override key | `0x1004be0b0` | `0x100024214/0x100024218` | `0x100023dd4` |
| color-name key | `0x1004be060` | `0x10002417c/0x100024180` | `0x100023dd4` |
| legacy personalization header-color key | `0x1004bf140` | `0x10004d8f8/0x10004d8fc` | `0x10004d510` |
| `SettingsPaneView.init` | `0x1003ef208` | direct BL `0x10004a734` | `0x10004a588` |
| `HeaderColor.name(forLegacyHex)` | `0x1003ef1cc` | direct BL `0x10004d9b4` | `0x10004d510` |
| `ColoredHeaderView.defaultColor` | `0x1003ef214` | direct BL `0x10004d6d8` | `0x10004d510` |
| `switch_to_en_on_focus` model field | `0x100430d3c` | `0x1002d7d74/0x1002d7d78` | `0x1002d68a0` |

Названия импортов сопоставлены с прежним REA inventory:
`ev_066eefbfea61311f20d4b59a89de4a566c8645cf62f9a3e4c6a6604063ebe89d`.
Общие recorder классы перечислены в том же search record. Отдельный paste API
inventory: `ev_989c78f27762a0dc0de2ab249d579145231a51660db4092835029b2586afdf2f`.
Наличие общих recorder классов не доказывает их подключение к конкретной функции.

## Что уже подтверждается сохранёнными телами

Plain-paste операция `0x100022cb4`:
`ev_6a01a7b57c19fe099f11b87374ca21b2260cd82f3f0ce1760574d5589b8d6189`.
Она временно меняет представление clipboard и выдаёт сочетание; продолжение
восстановления описано в [PHASE3_STATIC](PHASE3_STATIC.md). В этом теле нет
восстановленной логики выбора произвольной пользовательской hotkey.

`0x1002db840`, Evidence
`ev_79bce0abad7ec1b544bdfc1ae38c7f293127b97e6a8ef49545c4de4e9e8ab8d5`,
копирует model special-behavior данные из глобального состояния под mutex.
Это поддерживает наличие данных конфигурации движка; не устанавливает
применение `switch_to_en_on_focus` при конкретной смене окна.

В исходном origin export до продолжения не было полного тела caller-интервалов `0x10000a45c`,
`0x100023dd4`, `0x10004a588`, `0x10004d510`, `0x1002d68a0`.
Их действия нельзя было реконструировать только по списку литералов или импортов.
Новые тела и текущие выводы находятся в LOCAL_SETTINGS_RESEARCH.

## Приоритетные недостающие запросы

1. **`0x10004a588`** — восстановить фактические callback arguments
   `SettingsPaneView.init`: reset sound, header-color change, paste recorder
   binding. Проверить, не передаются ли пустые callbacks/скрытые options.
2. **`0x100023dd4`** и **`0x10000a45c`** — определить создание именованного
   shortcut, его default/recorder/storage и звук override. Затем перейти
   к конкретным callbacks записи/сброса, не назначать их по имени alone.
3. **`0x10004d510`** — восстановить builder состояния header color,
   использование обоих ключей и legacy mapping; отделить миграцию от UI action.
4. **`0x1002d68a0`** — установить десериализацию/тип focus-флага, затем
   следовать его consumers. Отдельный `0x10025a030` — существующий callsite
   в dispatch для поиска special behavior, его тело также не восстановлено.
   Для вывода о focus нужен именно caller `focus/window change → flag → TIS`,
   а не только десериализатор и общий retype.

При исходном составлении документа запросы только перечислялись; затем
они выполнены в пакете LOCAL_SETTINGS_RESEARCH. Сессия вновь закрыта,
snapshot cache разрежён. Перед следующим проходом проверить повторное
использование базы/сохранённых Evidence, не создавать дубликаты import.

После статического связывания каждому кандидату нужен отдельный синтетический
UI/native опыт с возвратом настроек. До этого наличие framework resource
не расширяет проверенный реестр локальных функций этой версии.
