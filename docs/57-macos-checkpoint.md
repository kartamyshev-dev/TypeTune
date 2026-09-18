# 57 — macOS local preview

## Индикация паузы в строке меню — 2026-09-18

Baseline `d4db2fd` + незакоммиченные изменения; macOS 27.0 (26A428),
Apple Silicon, Aqua, SwiftUI/AppKit, TypeTune 0.1.0 (57).
Пользователь сообщил об отсутствии визуальной реакции на «Пауза / продолжить».
В исходниках подтверждены статические title/toolTip и отсутствие подписки меню;
в установленной прежней сборке кнопка настроек перевела runtime в «На паузе».

Меню теперь подписано на `running` и `status` единого Controller: действие
«Пауза» ↔ «Продолжить», индикатор `TT` ↔ `TT ⏸`. Подсказка и accessibility label
показывают текущий статус, при явной паузе — «На паузе». Включённое состояние
не подменяет сообщения о разрешениях или недоступном контексте словом «Работает».
Переключение из настроек обновляет те же элементы. Обработка ввода не менялась.

- MAC-TRAY-SIM-01: тест настоящих NSButton/NSMenuItem с Combine publishers —
  initial, pause, запоздалый runtime status на паузе, resume и новый status PASS.
- `bash scripts/test-macos.sh`: 37 Rust + 13 Python + 13 Swift = 63 теста PASS.
- MAC-TRAY-PKG-01: release build, codesign verify и установка PASS; SHA-256
  установленного executable совпал со сборкой:
  `7b6797336c4d988a09e53e9a0bebb72a3f2f2afd52889d9052d88fcb7bb64f54`.
- MAC-TRAY-UI-01: после перезапуска установлена единственная работающая копия
  из `~/Applications`; настройки generation 5 сохранены; через настройки
  получены «На паузе»/«Запустить», затем «Работает · US · режим совместимости»/
  «Пауза». Приложение оставлено включённым.

Ограничения: SystemUIServer недоступен через CUA (timeout), поэтому внешний вид
строки меню и непосредственный клик её пункта после установки не проверены live.
Подписка и свойства AppKit элементов проверены автоматическим тестом. Физический
ввод, Double Shift и новые CI/release в этой задаче не проверялись. Публикации нет.

Дата: 2026-09-18. Исходная ревизия: `5d0cae9`, изменения этого этапа пока
незакоммичены. Стенд: Apple Silicon arm64, macOS 27.0 build 26A428,
Command Line Tools Swift 6.4, Rust 1.89.0, пользовательская Aqua-сессия.
Это локальная реализация и частичная приёмка, **не подтверждённая готовность
общесистемной коррекции**.

## Реализовано

- SwiftUI/AppKit приложение со строкой меню, русскими настройками, паузой,
  словарями, исключениями по bundle ID и предложениями. Один процесс/controller,
  per-user instance lock. Закрытие окна не завершает приложение.
  Исключение приложения отключает автоматику, сохраняя ручной Double Shift,
  как в Linux preview.
- Rust bridge protocol 2: `protocol`, `key_event`, `reset_context`, `edit_result`,
  `suggestions`, `dismiss_suggestion`; прежние Linux-операции сохранены. JSON ABI
  с прежними пределами 131072/32768 байт, однопоточное владение handle.
- Общий Rust-автомат истории/Double Shift/feedback. Native keycodes остаются
  в платформенном адаптере. Общие gesture/feedback fixtures выполняются Rust
  и прежними Python-автоматами; Linux runtime пока использует Python-обвязку.
- Пассивный CGEvent session tap, отдельный run loop, очередь 256 событий,
  SPSC ring с атомарными индексами без mutex в callback. Потеря/переполнение очереди
  отбрасывает весь batch и инвалидирует историю. Down/Up/Repeat, стороны Shift,
  source time и origin сохраняются; device identity остаётся Unknown.
- Собственные события помечаются `eventSourceUserData`; события другого процесса
  считаются Unknown и сбрасывают историю. Физическая идентификация по source PID
  требует native acceptance и не является защитой от подделки другим ПО.
- Единственный исполнитель Backspace/Unicode, парные Down/Up, ожидание отпускания
  физических клавиш, guards перед каждым действием, ABC/RussianWin с readback.
  Text Input Source API вызывается на главной очереди: macOS 27 действительно
  завершила первый прототип при вызове с worker; исправление проверено запуском.
- AX-контекст с ограничением ожидания 50 ms; известные secure fields и Secure Input
  отключают обработку. Ожидаемый суффикс/каретка проверяются, когда доступны.
  Результат различается как verified/submitted/rejected/indeterminate; нет retry.
  Clipboard не используется. Неопределённый результат остаётся видимым в статусе.
- Настройки version/generation, атомарное сохранение с ограниченным доступом,
  ACK конфигурации из Rust, opt-in `SMAppService.mainApp` и состояние разрешений.
- Автономный ad-hoc signed `.app` с Rust dylib через `@rpath`, установка
  в `~/Applications`, `--doctor` без текста/clipboard. Подпись не notarized.
- CI: общий workflow вызывает macOS build/test/package на hosted `xcode-27`
  (ARM64/macOS 27); Linux job сохранён. Релиз ожидает обе платформы.

## Принятые решения

Первый порт — macOS, перед Windows. Общее ядро Rust + нативная оболочка Swift;
Python/GTK не нужны установленному приложению. Использованы собственные реализации
по контрактам проекта; Espanso служит архитектурным reference из документа 15,
его исходники не копировались.

Режим совместимости выключен до явного включения. Автоматика по умолчанию включена
внутри выбранного режима; автозапуск выключен. Поддерживаемая пара этого этапа:
ABC ↔ Русская — ПК. Другие input sources/IME не активируют коррекцию. Unknown
selection/sensitivity/composition не превращаются в подтверждённую безопасность.
Без AX-текста результат остаётся inferred/submitted. API замены не атомарный.

## Выполненные проверки

| ID | Проверка | Результат |
|---|---|---|
| MAC-SIM-01 | `cargo test --locked -p typetune-engine -p typetune-bridge` | 37 тестов, PASS |
| MAC-SIM-02 | Общие fixtures + Python gesture/feedback | 13 тестов, PASS |
| MAC-SIM-03 | Swift Testing: editor, настройки, observer | 12 тестов, PASS |
| MAC-PKG-01 | Release build, dylib relocation, ad-hoc codesign verify | PASS |
| MAC-PKG-02 | Установка и запуск `~/Applications/TypeTune.app` | PASS, окно настроек открыто |
| MAC-UI-01 | Вкладки словарей/приложений; добавление и удаление `github` | PASS, поколения 0→1→2 |
| MAC-PERM-01 | Отсутствующие разрешения в `--doctor` | listen/post/AX = false; native gate не пройден |

Swift-тесты создают CGEvent только в памяти, не отправляют их в чужие приложения.
Контролируемый editor проверяет текст/каретку/баланс клавиш, отказ до правки,
прерывание после одного удаления, Unicode и различие submitted/verified.
Общие fixtures покрывают обе стороны Shift, overlap, таймауты, обратное время,
три отмены, пробел до/после жеста, retoggle и потерю контекста.

В установленном Command Line Tools нет XCTest. Скрипт тестирования использует
Swift Testing с явными путями framework. Для локальной сборки выбран native
SwiftPM backend: default swiftbuild упирался в dsymutil sandbox. `@State` задан
через alias property-wrapper, поскольку SDK 27 выбирает новый macro, которого
нет в комплекте CLT. Эти ограничения не требуют установки полного Xcode.

Strict Clippy обнаружил две **существовавшие** `nonminimal_bool` в engine
(`automatic.rs`, `lib.rs`). Проверка bridge с подавлением только этого lint
прошла. Исходные файлы engine не изменены. Полный Linux compatibility suite на
macOS не прошёл загрузку: нет PyGObject `gi` и Linux `.so`; 5 pure-history tests
из него прошли. Это не заменяет Linux CI/native acceptance.

## Оставшиеся gates

- Пользователь должен выдать установленному приложению Input Monitoring и
  Accessibility. Без них PAR-01–PAR-10 в TextEdit/Safari/VS Code не выполнялись.
- Native физический ввод, раскладка следующего слова, AX readback, rapid typing,
  secure fields, revoke, sleep/wake, lock/unlock и balance после ошибок — pending.
- Login/logout/reboot и сохранение TCC после обновления — pending; ad-hoc rebuild
  может потребовать повторной выдачи разрешений.
- Чистая установка/обновление/удаление в отдельном профиле и полноценная проверка
  второго процесса — pending. Проверено только создание/запуск локальной `.app`.
- Windows/Intel/старые macOS, публичная подпись и notarization не входят в этап.

Команды сборки и использования: [macOS README](../integrations/macos/README.md).
Следующая точка продолжения: проверить финальную установленную сборку после
выдачи разрешений, фиксируя app versions, source commit/dirty и каждый PAR case.

## Продолжение — проверка разрешений

После сообщения пользователя о выдаче разрешений проверены CLI и GUI.
`--doctor` из sandbox вернул false/false/false, а вне sandbox — true/true/true.
Однако установленный GUI после перезапуска продолжил сообщать о недостающем
доступе. Поэтому результат CLI **не является доказательством TCC-доступа GUI**:
контекст запуска и responsible process отличаются.

Системный журнал TCC для `dev.kartamyshev.TypeTune` подтвердил
`Failed to match existing code requirement` для `kTCCServiceAccessibility`:
сохранённое разрешение относится к прежнему cdhash, текущая ad-hoc сборка имеет
другой cdhash. Нужна повторная выдача Accessibility именно установленной копии
`~/Applications/TypeTune.app` (удалить старую запись и добавить текущую).
Разрешения автоматически не менялись. Режим совместимости включён пользователю
для приёмки (generation 5), но observer не запускается без разрешений. Native
text acceptance всё ещё pending. До повторной выдачи приложение не пересобирать.

После повторной выдачи Accessibility пользователь сообщил о завершении действий.
Проверка непосредственно GUI текущей установленной сборки: сообщение о нехватке
разрешений исчезло; вне окна TypeTune показано «Работает · RU · режим совместимости».
Это подтверждает прохождение permission gate и запуск/recover CGEvent tap в GUI,
но ещё не подтверждает замену текста. Сборка не менялась.

Запрошен физический PAR-01/02: ABC, `ghbdtn` без пробела, Double Shift → `привет`,
повторный Double Shift → `ghbdtn`. Программный ввод CUA не используется как
эквивалент физических клавиш: события с ненулевым source PID очищают историю.
CUA-доступ к окну TextEdit дважды вернул ScreenCaptureKit -3811; это ограничение
инструмента UI, а не доказательство ошибки TypeTune. Результат физического кейса
пока ожидается.

## Исправление пропусков Double Shift — 2026-09-18

Пользователь подтвердил работу замены, но сообщил о периодических пропусках
Double Shift. Воспроизведён дефект очереди: `NSLock.try()` в callback отбрасывал
события при одновременном чтении revision. Тест на 20 000 событий без переполнения
потерял 1 222 события до исправления. Это результат стресс-теста, не оценка частоты
ошибок при обычном наборе.

Очередь заменена на bounded SPSC ring (256 элементов), индексы и revision — атомарные.
Чтение revision больше не конкурирует с записью. Переполнение по-прежнему сбрасывает
историю. Тот же regression test прошёл без потерь; дополнительный тест проверил
порядок timestamp/revision 10 000 событий при параллельном producer/consumer и
многократном обороте кольца. События CGEvent создавались только в памяти.

На baseline `5d0cae9` + незакоммиченные изменения, macOS 27.0 (26A428), прошли
35 Rust + 13 Python + 10 Swift = 58 тестов. Release app собрана, ad-hoc подпись
проверена; установленный executable совпал с собранным по SHA-256
`c7d988dcb98ca0a0020e32231b04d6d32ce19fa7afbd8255125905b317faaf69`.
Физический Double Shift после обновления и полная native-приёмка остаются pending.
GUI после обновления запустился, настройки generation 5 сохранились. GUI сообщает
«Нужны разрешения: мониторинг ввода и универсальный доступ». Системные разрешения
не менялись; пользователю требуется повторно разрешить установленную сборку.


## Исправление частичной истории слова — 2026-09-18

Пользователь сообщил: в текстовом редакторе `frr` после Double Shift стало `frк`.
Конкретное приложение/его версия не установлены. Обнаружен дефект проверки:
`hasSuffix(before)` разрешал заменять `r` внутри полного `frr`. Воспроизведён
Rust-тест с историей `r` и текущим словом редактора `frr`: до исправления план
содержал `before=r`, а должен был содержать `before=frr`, remove=3, replacement=акк.
Это воспроизведение механизма, не native trace исходного пользовательского сбоя.

В нормализованное событие добавлено необязательное поле `editor_word`. macOS
передаёт его при отпускании Shift только из доступного AX snapshot того же
контекста и при совпадении revision. При распознанном ручном жесте Rust использует
целое слово, сбрасывая устаревший feedback при несовпадении истории. Пустой известный
контекст/выделение/неподдерживаемый token не допускают fallback к истории.
Старые Linux-запросы без поля совместимы. Автоматическая коррекция это поле
не использует. Перед отправкой событий исполнитель повторно проверяет точное
слово и обе границы, а не только suffix; UTF-16 selection переводится в String range.

37 Rust + 13 Python + 12 Swift = 62 теста PASS, release build и codesign verification
PASS, baseline 5d0cae9 + dirty, macOS 27.0 (26A428). Проверены восстановление полного
слова и обратный жест, отказ для некорректного известного контекста, границы слова,
выделение, UTF-16 и прежние corpus/feedback сценарии. Это simulated результаты.
Без AX value/selection остаётся compatibility history; восстановление целого слова
там не гарантируется. Источник первоначальной потери истории и native acceptance
обновления остаются открытыми; эта правка не объявляет все ошибки ввода исправленными.
Установленная сборка совпала с build по SHA-256 executable
`cbbb3c6ebd030edbfd35540cf479f81b100bd40bf1818d06e4508c55bfda17a9`.
GUI запустился с сохранённой generation 5, но вновь сообщает о необходимых
разрешениях после смены ad-hoc подписи. Проверка физического ввода ожидает
повторного разрешения пользователем; разрешения автоматически не менялись.


## GitHub Actions — автоматическая сборка

Пользователь сообщил «вроде работает» после последнего исправления; это не
полная native-приёмка. По запросу добавлена hosted CI-сборка без личного Mac.
`ci.yml` запускается на push веток, PR, тегах `v*` и вручную, вызывает reusable
`macos.yml`; сам macOS workflow также доступен вручную. Runner — `xcode-27`,
Rust закреплён на проверенном 1.89.0. Проверяются arm64 и macOS 27, версии Xcode
и Swift записываются в журнал. Swift Testing ищется как в полном Xcode, так и CLT.

Артефакт `macos-preview` (14 дней): `TypeTune-macos-arm64.zip` и
`MACOS-SHA256SUMS`. После распаковки проверяется подпись. Публикация prerelease по
существующему формату `vMAJOR.MINOR.PATCH-previewN-REVISION` ожидает и Linux, и macOS,
добавляет оба пакета и проверяет скачанные контрольные суммы. Реальный ввод и TCC
в CI не проверяются. Локальная установленная копия не обновлялась этим изменением.

Локально: 62 теста PASS, release build PASS, ZIP extraction/codesign PASS,
YAML/встроенные shell scripts и `cargo fmt --all -- --check` PASS.
Hosted runner: [официальный образ](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md),
public preview; его обновления могут требовать адаптации. Первый remote run pending.

CI-изменения сохранены локально: `9430975`; актуальный main `8580836` включён merge
`76fa770`, Linux release notes сохранены. Отправка в публичный origin была отклонена
автоматической проверкой разрешений: нужен явный допуск публикации новых исходников
macOS вместе с workflow. Push не выполнен, remote CI и публикация artifacts не
проверены. Ветка: `codex/macos-hosted-ci`; до согласия пользователя не отправлять.


### Hosted macOS подтверждён — 2026-09-18

После явного разрешения пользователя ветка `codex/macos-hosted-ci` опубликована,
создан [PR #1](https://github.com/kartamyshev-dev/TypeTune/pull/1).
[Run 35347690287](https://github.com/kartamyshev-dev/TypeTune/actions/runs/35347690287)
собрал commit `a905ae8d43e6e617c4c85d663512596bd32933e5` на macOS 27.0
(26A5406e), Xcode 27.0, Swift 6.4, Rust 1.89.0. macOS job PASS: 37 Rust,
13 Python, 12 Swift тестов, release build, ZIP и codesign после распаковки.
[Артефакт macos-preview](https://github.com/kartamyshev-dev/TypeTune/actions/runs/35347690287/artifacts/10547258892)
скачан обратно; SHA-256 сверена, подпись распакованной `.app` проверена,
TypeTuneSourceCommit совпал с commit run. Установленная пользовательская копия не
заменялась. Публикация prerelease по тегу настроена, но новый тег не создавался
и release-upload ещё не проверялся. Native-приёмка клавиатуры остаётся отдельной.
Полный run завершился success: Linux build/tests/package lifecycle PASS,
macOS PASS; release ожидаемо skipped, поскольку это push ветки, а не тега.


## Общий выпуск preview57-1

По поручению пользователя подготовлен тег `v0.1.0-preview57-1` на актуальном main.
Это общий prerelease, не объявление полной native-готовности. CI должен собрать
Linux `.deb` и macOS `.zip`, проверить обе платформы, опубликовать файлы и SHA-256
в одном GitHub Release. Системные разрешения и ad-hoc/notarization ограничения
macOS сохранены в release notes. Создание тега и проверка публикации выполняются
отдельно; этот checkpoint фиксирует намерение до запуска release workflow.

Общий prerelease [v0.1.0-preview57-1](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.0-preview57-1)
опубликован 2026-09-18 из commit `7913b7f9dcb478d3c701dcb275f5d4f56d3ea9a3`.
[Release run 35353451385](https://github.com/kartamyshev-dev/TypeTune/actions/runs/35353451385)
завершился success: Linux build/tests/package lifecycle, macOS build/tests/package
и release job. Публичные assets `.deb`, `.zip`, SHA256SUMS и MACOS-SHA256SUMS
скачаны повторно; обе суммы совпали. Подпись распакованной TypeTune.app проверена,
TypeTuneSourceCommit совпал с тегом. Это подтверждает публикацию и упаковку,
а не полную native-приёмку ввода. Пользовательская установленная копия не изменялась.


## Единственная установленная копия — 2026-09-18

По запросу пользователя оставлена обновлённая `~/Applications/TypeTune.app`.
Прежняя релизная `/Applications/TypeTune.app` и сборочная `dist/TypeTune.app`
сохранены в `dist/archived-apps/previous-release-20260918.zip` и
`dist/archived-apps/build-copy-20260918.zip`, затем удалены и сняты с регистрации
LaunchServices. До удаления проверены ZIP CRC и побайтовое совпадение всех файлов.
LaunchServices и Spotlight после очистки возвращают только `~/Applications/TypeTune.app`;
подпись оставленной копии проверена. Настройки и системные разрешения не менялись.
В этой операции сборочный скрипт не менялся: будущая сборка снова создаст
`dist/TypeTune.app`; после локальной установки сборочный bundle следует архивировать
и снимать с регистрации, чтобы не оставлять вторую запускаемую копию.


## Выпуск preview57-2 — опубликован

Пользователь подтвердил, что исправление паузы работает, и поручил публикацию
на GitHub и новую сборку. Выпуск `v0.1.0-preview57-2` содержит StatusMenu,
regression test и инструкции обновления без дублирования установленных копий.
Локальные 63 теста и сборка прошли ранее; исходники после проверок не менялись.
Remote CI, публикация и проверка скачанных assets фиксируются после завершения.


Выпуск [v0.1.0-preview57-2](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.0-preview57-2)
опубликован из `9cd07e06517bb7a76e9f2db02632789f22d67a1c`.
[Run 35385523712](https://github.com/kartamyshev-dev/TypeTune/actions/runs/35385523712)
завершился success: Linux tests/GTK/package lifecycle, macOS tests/build/package,
release upload и повторное скачивание. macOS runner: 27.0 (26A5406e), Xcode 27.0,
Swift 6.4; 37 Rust + 13 Python + 13 Swift = 63 теста PASS.
После публикации ZIP и DEB скачаны локально: обе SHA-256 совпали с release sums;
подпись распакованной `.app` проверена, SourceCommit совпал с тегом, SourceDirty=false.
Временная распакованная проверочная копия удалена; пользовательское приложение не
заменялось. Физический ввод в hosted CI не проверяется.
