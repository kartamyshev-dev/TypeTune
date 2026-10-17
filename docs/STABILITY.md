# Стабилизация ядра LayoutPilot — 2026-10-17

## Исходный отказ

На установленной 0.1.2, GUI 7d6745f62b2cf5c8fb3b9df6894d42ba1dbf9119e72a886e1eb1ba629d75e4f3,
наблюдалось «Ожидает восстановления / Задержано нажатий: 0» при разрешённых AX,
мониторинге и отправке. Recovery отключал обычную обработку. Footer Secure Input
мог быть историческим. Первоначальный триггер не установлен: failing trace отсутствует.
Ноль pending не доказывает отсутствие неопределённой доставки. Исходная рабочая
копия сохранена в research/private/stability-2026-10-17/baseline-files.tar.gz и baseline.patch.

## Установленный кандидат 0.1.3 (6) и текущий отказ

Сборка **0.1.3 (6)** создана из чистого коммита
`056afed46d0af914a70302f274fa450d8bdd380f` и установлена в `/Applications/LayoutPilot.app`.
GUI SHA-256: `1ce3e00080bc011b438903592cf12099b2a3c4bf7bd09bb5216e196245dea66b`.
Все 35 compiled inputs в build identity сверены с этим коммитом.
При установке проверены подпись и совпадение всех 10 файлов кандидата;
при разборе evidence повторно совпали установленный executable и полный bundle.
Наблюдённый PID — `59875`, запуск 2026-10-17 в 22:29:31.
Release CLI: **720/720**, корпус: **4420/4420**; это release-проверки сборки 6.
[Кандидат и установка](../research/evidence/stability-2026-10-17/candidate-build6.json),
[build identity](../research/evidence/stability-2026-10-17/candidate-build6-build-identity.json),
[release selftest](../research/evidence/stability-2026-10-17/build6-release-selftest.txt),
[release corpus](../research/evidence/stability-2026-10-17/build6-release-corpus.txt).
Во время native-записи `sourceDirty=true`; чистота сборки и привязка её inputs
не означают чистую рабочую копию во время прогона.

Обновлены только прежние записи LayoutPilot в AX и Мониторинге ввода через системный UI.
Приложение перезапущено; AX, listening, posting и активный tap подтверждены,
Secure Input выключен. Обычное auto ON, early OFF и plain-paste OFF сохранены.
Подтверждение разрешений и запуска tap не является полной lifecycle-приёмкой.

**Текущий блокер:** повтор трёх строгих TextEdit-регрессий на сборке 6 — **FAIL**.
Первое слово после фокуса осталось `ghbdtn ` в ABC вместо `привет ` в RussianWin;
каретка совпала (UTF-16 location 7, length 0). Первый ввод начался через **54,339 мс**
после подтверждённого фокуса. Immediate Double Shift и короткий поток совпали
по точным text/source/caret; наблюдённый промежуток до Double Shift — **14,512 мс**.
Все 3 случая завершены, helper exit 0, target/bundle/helper identity и fixture SHA
неизменны, модификаторы нейтральны. Строгий валидатор вернул **exit 1**,
два несовпадения text/source первого случая. Это два успешных ограниченных
сценария при FAIL всего набора.
[Native-наблюдения сборки 6](../research/evidence/stability-2026-10-17/candidate-build6-regressions-01.json),
[строгая проверка](../research/evidence/stability-2026-10-17/candidate-build6-regressions-01.verification.json),
[диагностика](../research/evidence/stability-2026-10-17/candidate-build6-regressions-01-diagnostics.json).

В сборку 6 вошла проверка готовности bootstrap: контекст публикуется только после
совпадения текста и каретки с соответствующим keyDown/keyUp, в прежнем ограниченном
бюджете; устаревшее чтение и несовпадающее отпускание отклоняются.
Production helper проверен в [controller probe 58/58](../research/evidence/stability-2026-10-17/first-word-readiness-controller.json);
хеш KeyboardService совпал с compiled input сборки 6, хеш probe — с исходником.
Platform inputs и результаты снимков подставлены; это изолированная проверка,
без native events или чтения настоящего поля. Native-повтор показал, что доработки
недостаточно. В первом boundary сборки 6 `previous=false`, `sameTarget=false`,
`readOnlyBaseline=false`, exact predicted text/caret не совпали; причина отказа
остаётся предметом исследования.

Дополнительный опыт с ABC, заранее выбранной через UI, остановлен:
**0/3 завершённых случаев**, helper exit 2, причина в checkpoint —
`target_not_frontmost`; строгий валидатор exit 1. Приложение записало
`mutation-result verified=true` и `apply-commit` для первого слова, но итоговый
text/source/caret этого случая не получен. Внутренняя запись мутации **не является
native PASS**. Target PID и хеши bundle/helper/fixture совпали с обычным опытом.
Исходная RussianWin восстановлена через UI, что зафиксировано в отчёте опыта.
[Остановленный опыт](../research/evidence/stability-2026-10-17/candidate-build6-preselected-abc-regressions-01.json),
[его строгая проверка и условия](../research/evidence/stability-2026-10-17/candidate-build6-preselected-abc-regressions-01.verification.json),
[диагностика](../research/evidence/stability-2026-10-17/candidate-build6-preselected-abc-regressions-01-diagnostics.json).
Оба новых диагностических файла проверены с режимом 0600.

Следующий шаг в работе — явное преобразование keycode по текущей TIS-раскладке.
[Опыт без отправки событий](../research/evidence/stability-2026-10-17/current-layout-translation-experiment.json)
разделяет raw Unicode / NSEvent.characters и преобразование модификаторами при
стабильной раскладке; он не воспроизводит живую гонку после смены источника и
не доказывает окончательную причину. Доработка ещё не входит в установленный бинарник.
Исходники переводят физическую клавишу через данные точной текущей TIS-раскладки
во всех трёх местах: прогноз непрерывного ввода, readiness и replay projection.
Неизвестный источник или недоступные данные не заменяются прежним Unicode события.
[Production decoder probe](../research/evidence/stability-2026-10-17/input-source-translation-probe.json)
прошёл 70/70 без отправки клавиш, смены раскладки и AX-чтений;
[controller](../research/evidence/stability-2026-10-17/current-layout-controller.json) — 58/58.
Первый controller repeat упал из-за реального таймера в тестовой fixture;
[исходный сбой сохранён](../research/evidence/stability-2026-10-17/current-layout-controller-initial-crash.json).
Время изолированного теста задано явно; production-бюджет 60 мс не менялся.
Сборка 7 не собрана. Полная native-приёмка не пройдена; широкий smoke,
четыре часа и рабочий день — NOT_RUN. В обоих коротких опытах нет сегментов простоя.

Native bundle hash `ce3b8d0e…` использует `paths-files-modes-symlinks-v1`,
а `1690f468…` в build identity — файловый manifest. Разные форматы хеширования
не означают расхождение файлов. Строгий verifier дополнительно сверяет SHA-256
ровно тех байтов fixture, которые разобраны для проверки; подмена процедуры
при тех же ID/expected отклоняется.
[Проверки fixture binding](../research/evidence/stability-2026-10-17/harness-fixture-binding-checks.json).

### Предыдущая сборка 0.1.3 (5) — исторический checkpoint

Сборка 5 из `4e029473230c594cabe30302c889d53e6195a40e`, GUI
`6a3b4af8c062e774ae2f137e6d84173d977c522690649859ac01164a19f48bad`, PID `56846`,
дала FAIL первого слова; ввод после фокуса — 65,92 мс, Double Shift — 14,61 мс.
Double Shift и поток совпали, весь набор не принят. Bootstrap после keyUp и
его [controller probe 50/50](../research/evidence/stability-2026-10-17/first-word-bootstrap-controller.json)
не устранили отказ; в первом boundary `previous=true` и `sameTarget=true`,
но exact predicted text/caret не совпали.
[Кандидат сборки 5](../research/evidence/stability-2026-10-17/candidate-build5.json),
[build identity](../research/evidence/stability-2026-10-17/candidate-build5-build-identity.json),
[результат сборки 5](../research/evidence/stability-2026-10-17/candidate-build5-regressions-01.verification.json).
Перед заменой сборка 5 сохранена в
`research/private/stability-2026-10-17/replaced-installed-0.1.3-build5.app`;
совпали все 10 файлов, прежний процесс завершён. Этот checkpoint не даёт PASS сборке 6.

### Предыдущая сборка 0.1.3 (4) — исторический checkpoint

Сборка 4 из `72ad44f451c8c11b46436fec376973410402e372`, GUI
`a46c7c6a69410118fca48b66e36abc37cc05068efef48f99f8c01000179a1391`, PID `53149`,
дала тот же FAIL первого слова; первый ввод после фокуса — 92,58 мс.
Immediate Double Shift и поток в том опыте совпали, но набор не был принят.
[Кандидат сборки 4](../research/evidence/stability-2026-10-17/candidate.json),
[установка сборки 4](../research/evidence/stability-2026-10-17/installed-candidate.json),
[результат сборки 4](../research/evidence/stability-2026-10-17/candidate-20261017-regressions-01.verification.json).
`sourceCommit: 6abb300…` в том опыте обозначает HEAD записи, а build commit — `72ad44f`.
Перед заменой сборка 4 сохранена в
`research/private/stability-2026-10-17/replaced-installed-0.1.3-build4.app`.
Её процесс завершён; этот checkpoint не описывает текущий PID и не даёт PASS текущей сборке.

## Контракт кандидата 0.1.3

- Пустая завершённая (.verified/.notApplied до записи) операция возобновляет работу
  без старого поля. .uncertain и неподтверждённая доставка требуют проверки текста;
  подтверждение не отправляет клавиши и не отбрасывает pending.
- Pending/outstanding/uncertainDeliveries учитываются отдельно. Реальная очередь
  сохраняет exact target/text/caret/source gates; поздние токены подавляются.
- Текущий health вычисляется отдельно от последнего события, учитывает permissions,
  Secure Input, исключения, поддержку host/layout и активность tap. Попытки восстановления
  ограничены enable→recreate, только вне мутации/доставки/неопределённости.
- AX capture возвращает типизированную причину, разделяет общий срок между IPC,
  повторяет временные отказы только при актуальном контексте и в оставшемся бюджете.
  Общий срок мутации — существующие 200 мс; стадия не получает больше 150 мс
  и оставшегося срока. Проверяемая очистка временного выделения/модификаторов
  имеет отдельный ограниченный бюджет.
  Таймаут API не является гарантией жёсткого wall-time срока macOS.
- Диагностика локальная и автоматическая: последние 1000 технических событий,
  максимум 3 managed stability-*.json, 0700/0600. Нет текста, самих нажатий, документов,
  clipboard или сети. Экспорт удерживает снимок на время окна сохранения,
  файловая запись выполняется вне главного потока. Старые UUID-отчёты не удаляются; экспорт работает без restart.
- Первый профиль: обычное auto и Double Shift; early и перехват plain-paste OFF
  с сохранением прежних пользовательских значений в частной резервной копии.
  Новые настройки создаются с plain-paste OFF; явно сохранённое значение
  декодируется без изменений. Профиль применён после установки и подтверждён в UI.
  Словарь, облако, поддерживаемые приложения и пользовательские коллекции не расширяются.

## Проверки и критерии

| Функция / сценарий | Приложение | Код / бинарник | Вид проверки | Результат |
|---|---|---|---|---|
| Наблюдённое зависание | Установленный LayoutPilot | 0.1.2, GUI `7d6745f6…` | UI, процесс, SHA | [FAIL: recovery при 0 pending](../research/evidence/stability-2026-10-17/installed-before.json) |
| Recovery, AX budget/retry, настройки | Release CLI | 0.1.3 (6), build identity `056afed` | CLI selftest | 720/720, [PASS](../research/evidence/stability-2026-10-17/build6-release-selftest.txt) |
| Завершение, timeout, review, готовность bootstrap | Production KeyboardService | Хеш `6a8f9223…` соответствует сборке 6; platform inputs и snapshots подставлены | Изолированный controller probe | 58/58, [PASS](../research/evidence/stability-2026-10-17/first-word-readiness-controller.json); native first-word остаётся FAIL |
| Безтекстовый журнал и экспорт | InputDiagnostics | Хеш компонента в evidence | Изолированный IO probe | 30/30, [PASS](../research/evidence/stability-2026-10-17/diagnostics-final.txt) |
| Пауза перед edit/manual/undo | TerminalBridge | Хеш компонента в evidence | Production dispatch helper; без socket/AX | 36/36, [PASS](../research/evidence/stability-2026-10-17/terminal-dispatch-final.txt) |
| Распознавание | Release CLI | 0.1.3 (6); корпус не менялся | Offline train / holdout | 3094/3094 + 1326/1326, [PASS](../research/evidence/stability-2026-10-17/build6-release-corpus.txt) |
| Защиты редактора, настройки, zsh | Guard / Store / PTY | Точные hashes в evidence | Изолированные probes | 12/12, 34/34, 6/6, [PASS](../research/evidence/stability-2026-10-17/implementation-checks.json) |
| Identity / quality / duration / idle / modifier gates | Native harness | Хеши предыдущего checkpoint; не новый GUI PASS | Offline / mocked orchestration | 77 + 26 + 11 + 4 + 3, [PASS](../research/evidence/stability-2026-10-17/harness-final-checks.json) |
| Привязка fixture и сохранение предыдущих gates | Native harness | Хеши после усиления verifier в `4e02947` | Offline / mocked orchestration | 4 + 1 + 77 + 11, [PASS](../research/evidence/stability-2026-10-17/harness-fixture-binding-checks.json) |
| Первое слово после фокуса | TextEdit | 0.1.3 (6), GUI `1ce3e000…`; PID `59875` | Короткая guarded native-регрессия, строгий валидатор | [FAIL: text и source; suite exit 1](../research/evidence/stability-2026-10-17/candidate-build6-regressions-01.verification.json) |
| Immediate Double Shift и короткий поток | TextEdit | 0.1.3 (6), тот же PID | Два ограниченных native-наблюдения, text/source/caret | [2/2 совпали; весь suite FAIL](../research/evidence/stability-2026-10-17/candidate-build6-regressions-01.json) |
| Первое слово при заранее выбранной ABC | TextEdit | 0.1.3 (6), тот же PID | Дополнительный контролируемый native-опыт | [STOP: target_not_frontmost, 0/3, suite exit 1](../research/evidence/stability-2026-10-17/candidate-build6-preselected-abc-regressions-01.verification.json); внутренняя verified mutation не PASS |
| Остальной auto smoke, undo, selection, emoji/NFD | TextEdit | 0.1.3 (6) | Native, только новые собственные документы | NOT_RUN |
| Auto / Double Shift и защищённые строки | Chrome single / textarea / rich / omnibox | 0.1.3 (6) | Собственные локальные поля | NOT_RUN |
| Auto / Double Shift | Ghostty / Terminal | 0.1.3 (6) | Реальное окно, отдельно от PTY | NOT_RUN |
| Auto / Double Shift | ChatGPT / Codex | 0.1.3 (6) | Пользовательская физическая проверка | NOT_RUN |
| Обновление разрешений и запуск tap | macOS | 0.1.3 (6); PID `59875` | Native UI после перезапуска | [Разрешения и tap подтверждены](../research/evidence/stability-2026-10-17/candidate-build6.json); это не полный lifecycle |
| Sleep / Secure Input / отзыв TCC / event tap lifecycle | macOS | 0.1.3 (6) | Native переходы во время работы | NOT_RUN |
| Не менее 4 часов ввода / простоя | TextEdit | Кандидат 0.1.3 (6) | Guarded native session и telemetry | NOT_RUN |
| Один рабочий день | Поддерживаемые приложения | Кандидат 0.1.3 (6) | Наблюдение пользователя | NOT_RUN |

Сохранность текста и полнота коррекции — отдельные gates. Для immutable
regression fixtures требуются точные text/source/caret, ноль потерь/дубликатов
и записей в чужое поле, ноль пустых бессрочных recovery. NativeProbe разрешён
только для новых собственных TextEdit-документов. Composer проверяет пользователь.
Реальный terminal/native и прочие границы не подменяются PTY/offline.

Harness принимает точный `--app /Applications/LayoutPilot.app`, не ослабляя identity.
Короткие регрессии и команды строгой проверки записаны в
[harness-final-checks.json](../research/evidence/stability-2026-10-17/harness-final-checks.json).
Четырёхчасовой запуск: `python3 scripts/run_native_session.py --run-id candidate-20261017-4h-01
--app /Applications/LayoutPilot.app --duration-minutes 240` (одной строкой).
Ошибка прекращает прогон; короткий/неполный прогон не получает PASS. Проверки
с подставным временем не являются четырьмя часами runtime.

## Границы доказательств

- CLI selftest — отдельно исполненные инварианты; это не XCTest.
- RuntimeRecoveryProbe использует production controller/queue и исполняет finishMutation,
  timeout и confirmation. Разрешения и tap подставлены; AX, реальные поля, клавиши,
  observers и sleep/wake в этом probe не исполняются.
- SnapshotChecks исполняет production retry helper с подставными часами/чтением
  (cannotComplete → success, отмена, истечение срока и постоянный отказ),
  а также проверяет совокупный бюджет; всего 23 сценария. EditorGuard проверяет
  отказы до обращения к реальному полю. Реальный временный AX-отказ и восстановление
  требуют отдельного native-сценария.
- Четырёхчасовой runner проверяет TextEdit с чередованием потока и простоя.
  Он не подменяет смену приложений, сон, Secure Input, TCC и рабочий день.
- Подавление поздних replay-токенов действует в живом активном обработчике.
  Подтверждение текста не доказывает опустошение очереди macOS; сценарий
  timeout → подтверждение → остановка обработчика → позднее событие остаётся
  отдельной границей native-приёмки. Потеря текста в нём не воспроизведена.
- Терминальная политика повторно проверяется перед отправкой в bridge queue.
  Уже переданную IPC-команду текущий протокол не отзывает; пауза между последней
  проверкой и исполнением zsh остаётся границей, отдельно от проверенного
  запрета dispatch после уже наступившей паузы.
- Исторические 51 пропуск из 1600 слов остаются задачей качества потока.
  Сохранность текста не закрывает пропущенные исправления.

## Продолжение

1. Исходники зафиксированы, чистый release-кандидат собран, проверки и evidence сохранены.
2. Резервные копии установленной 0.1.2 и настроек созданы и проверены.
3. Проверка текста пользователем подтверждена; старый recovery снят без replay, старый процесс завершён.
4. Сборка 6 установлена и идентична; обновление разрешений и перезапуск завершены,
   разрешения/tap подтверждены. Наблюдённый PID 59875. Второй переключатель не запускать.
5. Продолжить исправление первого слова: readiness bootstrap в сборке 6 недостаточен,
   её строгий повтор остаётся FAIL. Явное преобразование по текущей TIS-раскладке в работе;
   сборка 7 не собрана. После новой окончательной сборки заново выполнить три регрессии.
   Затем выполнить профильный smoke 12 и selection/Unicode; native пока не запускать.
   После auto-undo убрать через UI только вновь добавленное тестовое learned word ghbdtn,
   сверившись с сохранённым словарём; подготовка описана в [provenance](../research/evidence/stability-2026-10-17/candidate013-profile-smoke-v1-provenance.json).
6. Только после устранения регрессии переходить к четырём часам и пользовательскому
   рабочему дню; оба этапа пока NOT_RUN. Пользователь 2026-10-17 сообщил, что работает
   на Mac и отдельно укажет окно четырёхчасовой проверки; до этого её не запускать.
7. Early Chromium и F07 остаются отдельными этапами; полный PLAN/parity/p95 открыт.

## Резервная копия перед кандидатом — исторический checkpoint

Установленная 0.1.2 сохранена в `research/private/stability-2026-10-17/previous-0.1.2.app`.
При создании копии побайтовые SHA-256 всех 10 файлов совпали с тогдашней
`/Applications/LayoutPilot.app` версии 0.1.2.
Пользовательские настройки экспортированы в частный `preferences-before-candidate.plist`
с режимом 0600. На момент этого checkpoint настройки ещё не менялись, PID 25237
продолжал работать. Позднее этот процесс штатно завершён, кандидат 0.1.3 установлен
и профиль применён; PID сборки 4 был 53149. Затем её заменили сборкой 5 и
текущей сборкой 6, описанной выше. Резервные копии сохранены.
