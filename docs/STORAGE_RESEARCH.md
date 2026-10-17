# Настройки, исключения и пользовательские правила Caramba

Проверка 2026-10-15 относится к зафиксированным ресурсам версии 2026.10.07
(20261007.1). Приложения не запускались, UI и настройки пользователя не менялись.
Строки личной базы не выбирались. Исследование не закрывает полное покрытие.

Авторский индекс: [storage-resource-findings.json](../research/evidence/storage-resource-findings.json),
ID `LP-STORAGE-20261015-01`. Это локальная проверка форматов, не новый REA Evidence.
Предыдущий REA разбор keyed archive имеет ID
`ev_8ed31ebf42477ac0055078501fb15f1f96ac3730a8b1466271ccc94b582e36b3`.
Все выводы ниже разделяют декларацию в ресурсе и поведение программы.

## Проверенные факты

1. `Caramba.momd/VersionInfo.plist` выбирает `Caramba.8` текущей моделью.
   Все восемь поставленных `.mom` прочитаны через `plistlib` как данные
   NSKeyedArchiver; классы не создавались и код оригинала не выполнялся.
   Текущая модель SHA-256
   `309116244e07a0e8df5b7d7b05a3e2061a4fb2e284b6ff83c7a47a24384e6f78`.
2. У текущей `AppException` есть optional-поля `enabled` Boolean,
   `bundleID` String, `path` String. У `AutoswitchException`: `pattern` String,
   `additions` Int16 (default0), `visible` Boolean (defaultfalse),
   `disabled` Boolean. `pattern` проверяется моделью на длину >1 и <100
   (предыдущий REA разбор). Архивные номера объектов атрибутов и digest каждой
   версии сохранены в новом индексе.
3. Уже существующий SQLite backup открыт `mode=ro&immutable=1` без чтения строк
   и без применения WAL. Схема `ZAPPEXCEPTION` и `ZAUTOSWITCHEXCEPTION`
   согласуется с текущими атрибутами модели. Идентичности DB/WAL/SHM сохранены.
   Это проверка схемы backup, а не его транзакционной согласованности или данных.
4. Старые модели содержат `sourceLanguage`/`targetLanguage`, позднее
   `createdAt` и `visibleToUser`; текущая модель этих полей не содержит.
   Историческая `Caramba.2` также содержит `AppStats` с `asw`, `msw`,
   `startedAt`. Исторические схемы не доказывают работу этих функций сейчас.
5. В текущей модели исключений **нет поля строки замены**. Поэтому собственные
   правила LayoutPilot `source → replacement` нельзя считать восстановленной
   семантикой User Rules Caramba. Другое хранилище замены теоретически возможно;
   его отсутствие во всём приложении не доказано.

## Локальные возможности, требующие расширения реестра

| Область | Наблюдение и точный anchor | Текущее отличие LayoutPilot | Что установить до реализации parity |
|---|---|---|---|
| F07: назначаемая plain-paste комбинация | UI framework EN key `Paste without formatting — on any hotkey, even ⌘V itself`; в arm64 найден `tech.caramba.switcher.paste-no-format` | Комбинация фиксирована ⌘⇧V | Через UI проверить назначение, конфликт/сброс, передачу сочетания при off, сохранение после restart; затем реализовать собственный recorder |
| F09: режим по приложению | `en.lproj/Exceptions.strings` key `Wp8-nN-1kz.title`; локализация main содержит `appex.autoswitching-on/off`; модель `AppException.enabled` | Исключение bundle ID блокирует всю обработку | Установить, означает ли off только авто, доступны ли manual/typo/ё; установить приоритет общего auto-off и per-app on, роль path и rename приложения |
| F10: неприкосновенное сочетание | `Exceptions.strings` key `S2x-DJ-lQj.title`; `AutoswitchException.pattern` | Исключение прототипа — точное слово без учёта регистра | Не считать substring доказанным: проверить точное слово, префикс, середину, суффикс, регистр, RU/EN, пунктуацию; уточнить длину и валидацию |
| F10/F14: User Rules и обучение | main EN keys `Add to User Rules`, `Would you like to add this word to your user rules?`; атрибуты `additions`, `visible`, `disabled` | Автоотмена сразу добавляет lowercased слово в learnedWords; буквальные замены — отдельная собственная функция | Проследить store методы, операции add/remove/disable; проверить, когда появляется предложение, нужен ли повтор, влияет ли отмена сразу; не угадывать смысл additions |
| F10: управление списком | main EN key `Delete all rules?`, текст необратимости | Прототип удаляет записи по одной | Установить, какие записи удаляются целиком и можно ли отключить без удаления; затем реализовать проверенный локальный scope |
| F13: раздельные счётчики | arm64 literals `counters.autoswitch`, `doubleshift`, `singleshift`, `yofikator`, `cupertino`, `sounds` с общим prefix `tech.caramba.switcher.` | Один счётчик коррекций и собственная оценка2с | Проверить назначение каждой категории, persist/reset и формулу времени; literal не доказывает доступность статистики категории в UI |
| F08/F16: звук и оформление | UI framework key `Remove custom sound`; arm64 `sounds.main-sound-override`, `personalization.header-color` | Свой звуковой файл поддержан, тема system/light/dark | Проверить выбор/удаление/недоступный файл, слышимость; не считать тему эквивалентом настройки header-color |

Полные пути ресурсов и SHA-256 каждого файла находятся в `resources` индекса.
Все указанные ключи проверены на наличие форматным парсером UTF16 XML plist.
Имя ключа и перевод не всегда совпадают: main key `Send to developers`
переведён как удаление всех правил. Одной локализацией нельзя установить
действие кнопки: нужен обработчик и проверка UI.

## Следующий статический проход

На arm64 SHA-256
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`
есть маркеры `AppExceptionsStore.swift`, `AutoswitchExceptionsStore.swift`,
`fetchAppExceptions`, `updateAppException`, `fetchAutoswitchExceptions`,
`removeAutoswitchExceptions`, `addAutoswitchException`, `removeAppException`
и `patternSet`. Их **файловые byte offsets**, не адреса процедур, сохранены в
`followup_symbol_markers`. Эти offsets подходят для дальнейшего перехода к
xref в существующей Ghidra базе; новый import ради них не требуется.

Порядок вопросов: `pattern → поиск совпадения`;
`additions/visible/disabled → условие выборки/изменение при отмене`;
`AppException.enabled → effective feature flags`;
`paste-no-format → чтение назначенного сочетания → событие вставки`;
`counters → инкремент → время UI`. Статические находки далее должны получать
адрес процедуры и REA Evidence ID, затем синтетическое подтверждение поведения.

## Проверка результата и ограничения

Проверены восемь моделей, три локализованных plist (97/73/13 записей),
16 preference literals и девять групп follow-up маркеров. Все отобранные
anchors присутствуют; JSON разбирается, digest исходных артефактов сохранён.
Извлечённые правила/словари, сырые plist и декомпиляция в публичные файлы
не включены. Live данные пользователя не открывались.

Положительные, отрицательные и граничные проверки поведения в таблице пока
**не выполнены**. Ни per-app force-on, ни substring, ни обучение по счётчику,
ни скрытые правила не объявляются установленной семантикой. Общие пункты
PLAN о полном исследовании/реализации остаются открытыми.
