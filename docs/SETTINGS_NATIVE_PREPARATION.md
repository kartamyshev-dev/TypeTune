# Подготовка F19/F08 и отдельная process-boundary проверка F13

GUI не запускался/не останавливался, CUA/AX/HID не использовались. Звук не
воспроизводился. Это подготовка следующего native опыта, не его приёмка.
Store, SettingsView, KeyboardService и общий реестр функций этим заданием
не изменялись.

## Готовые синтетические материалы

- `.build/settings-fixtures/LP-F19-drop.png`
- `.build/settings-fixtures/LP-F19-drop.tiff`
- `.build/settings-fixtures/LP-F08-soft.wav`

Изображения — собственный blue/green checkerboard128×64 с одинаковыми пикселями.
WAV — monoPCM16,22050Hz,440Hz,0.22с, ограниченная амплитуда800/32767 с плавными
краями. Это специально слабый тестовый сигнал, не обещание слышимости.
Оригинальные материалы Caramba не использованы.

Digest/параметры:
[settings-fixtures-preparation.json](../research/evidence/settings-fixtures-preparation.json).
Системный ImageIO декодировал оба формата с ожидаемыми размерами, NSSound создал
WAV и подтвердил duration без play:
[decoder check3/3](../research/evidence/settings-fixtures-decoder-check.json).

## Read-only own-app проверяющий helper

`Tools/SettingsArtifactsReadback.swift` скомпилирован directswiftc с уже готовым
Core, без SwiftPM/GUI rebuild. Ни один режим живого приложения пока не запускался.
Его можно пересобрать `scripts/settings_artifacts_readback.sh`.

Исполняемый `.build/settings-artifacts-readback` принимает ровно один positional
mode: `header-png`, `header-tiff`, `header-reset`, `sound`, `sound-reset`,
`statistics` или `validate-fixtures`.

Режимы живого приложения требуют ровно один процесс bundleID`dev.layoutpilot.mac`
по точному пути текущего workspace `dist/LayoutPilot.app/Contents/MacOS/LayoutPilot`.
Helper не активирует окна и не меняет настройки. Для изображения/звука проверяет
owned UUID copy только в HeaderImages/Sounds, точный размер и совпадение с
собственной fixture вRAM. Пути/байты/хеш пользовательской копии не выводятся.
Читает только необходимые собственные preference keys и counts-only stats;
не обращается к оригиналу или clipboard. `statistics` выводит только6counts.
Встроенные поля nativeDropVerified/audibilityVerified всегда false.

Readback подтверждает сохранённые значения, **не** видимое отображение картинки,
маршрут drag/drop, фактическое воспроизведение или слышимость. Raw preference
read также не доказывает, что текущий UI уже обновился; требуется separateUIobserve.

## Конкретный следующий UI/native опыт основного агента

1. Снять исходное собственное состояние шапки/звука и counts; зафиксировать
   GUIbinary SHA, не переносить старый803c UI PASS на новую сборку.
2. На собственной странице настроек перетащить PNG-файл в шапку. Наблюдать
   обновление изображения в UI, затем выполнить `header-png` readback.
3. Повторить с TIFF-файлом и `header-tiff`; проверить restart/reset отдельно
   с UI-наблюдением и `header-reset`. Исходные fixture files должны остаться
   неизменными по собственному manifest.
4. **Граница TIFF-only:** drag TIFF-файла из Finder часто предоставляет NSURL.
   Это проверяет fileURL branch, даже если расширение.tiff. Для доказательства
   отдельной `loadDataRepresentation(public.tiff)` ветви нужен отдельный
   собственный drag source с TIFF-only NSItemProvider без NSURL; он здесь
   не создавался/не запускался. Не отмечать эту ветвь по одному TIFF file drop.
5. Выбрать WAV через существующий picker, наблюдать «Собственный звук» и
   `sound` readback. Снять numeric sound count. В собственном разрешённом
   тестовом документе выполнить одно проверенное исправление с sound on:
   после него count+1 подтверждает только NSSound.play()==true. Слышимость
   требует независимого наблюдения; helper её не проверяет.
6. Sound off + одно проверенное исправление: sound count не увеличивается.
   Выбор/сброс без исправления также не должен менять sound count. Для default
   sound после сброса — отдельный успешный старт; custom path empty проверяет
   `sound-reset`. Ошибочный файл не должен считаться начатым звуком.
7. Восстановить исходные собственные настройки и раскладку; не трогать нашу
   переписку и не запускать второй переключатель. Все неисполненные native/audio
   шаги остаются NOT_RUN.

## Новая проверка настоящего Store между процессами

`Tools/StatisticsProcessProbe.swift` + `scripts/statistics_process_probe.sh`
используют actualStore и unique named UserDefaults suite. Parent не создаёт Store:
четыре разных childprocess последовательно seed → restart/read → increment →
restart/read. Seed31historical, затем проверенные категории, первый total33,
второй35; неизвестная история остаётся31, estimated19→34с. Settings bytes
сравниваются с собственным sorted synthetic input. После завершения suite удалён.

[Cross-process evidence4/4](../research/evidence/replay-stats-process-probe.json)
подтвердил разные PID, счётчики/историю/итог/оценку и сохранение own settings на
границе завершения процессов; [compile log](../research/evidence/replay-stats-process-probe-build.log).
Это новая проверка process boundary, не повтор предыдущих22in-processchecks.
Она не запускает приложение, звук, AX, clipboard или клавиши и не доказывает
runtime интеграцию GUIс native events.

## Предложенная точная замена F13 в FEATURES

Общий FEATURES этим заданием не редактировался. Устаревшая строка28 всё ещё
сообщает «оценка2сек/исправление; реализация ещё не обновлена». Предложение:

| F13 | Статистика | REA cached + persistent ARM64: event→counter, default weights, JSON override | раздельные counts, оценки10/10/3/7/2/1с; миграция старого итога без выдуманной категории | CLI451/451 и actualStore22/22 + process-boundary4/4; GUI debug build PASS; native/UI статистика и звук не проверены, runtime overrides оригинала неизвестны; STATS_RESEARCH |

После новых изменений core или actualStore исполненные результаты должны
сопоставляться с их идентичностями; другой GUI/native PASS не подразумевается.

## CUA feasibility: native drop остаётся NOT_RUN

НаGUI SHA`944f9ccec18becc8fb72e2ca991582443aa7231ee21ff0399f5cd04e76707455`
через documentedCUA
открыто состояние собственного окна: «Однотонный фон», цвет «Синий», светлая
надпись включена, звук выключен. Finder переведён строго в собственную
`.build/settings-fixtures`, обеLP-F19fixtures видны. Интерфейс приложения и
пользовательские файлы не менялись.

Concrete blocker: exposedAPI содержит лишь `Target.drag(from,to)` на bound
App/Window. API глобальной drag-сессии/mouseDown→move→mouseUp, cross-app target
и проверенной общей геометрии двух окон не предоставлены. Finder закрывает
экран своим окном, LayoutPilot — другаяboundwindow. Без предположений о
глобальных координатах нельзя безопасно выразить Finder→header drag. Ни одной
попытки drag/handler invocation не делалось; обход через CGEvent запрещён
границами этого опыта. Отрицательный вывод относится к доступному механизму
проверки, не к работоспособности onDrop приложения.

[settings-drop-cua-blocker.json](../research/evidence/settings-drop-cua-blocker.json)
и readback до/после подтвердили прежнее пустое изображение, неизменные counts,
fixture digests и GUIbinary. Разрешения/clipboard не менялись, GUI не
останавливался. Restart/reset после drop не проводились, поскольку drop не
состоялся и исходная настройка не менялась. Finder оставлен в собственной
тестовой папке; эксклюзивный CUA-доступ возвращён основному агенту.
