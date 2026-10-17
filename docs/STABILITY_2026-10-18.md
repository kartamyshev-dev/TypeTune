# TypeTune: повторная защита, 2026-10-18

## Наблюдение

Работающий `/Applications/TypeTune.app`, PID 94002, GUI SHA-256
`3fde69fd918f023556c5c39386f9f2077ba24cf0c2e79acfa51a20502d60ef88`.
Три автоматических технических отчёта сохранены в
[recovery-2026-10-18](../research/evidence/recovery-2026-10-18/).
Ревизии 11163 и 11329: Double Shift, исходный контекст совпал полностью,
мутация получила gate; результат uncertain через 60,9 и 71,4 мс.
Selection cleanup не подтверждён; pending/outstanding/uncertainDeliveries = 0.
Это неопределённость операции, а не доказательство потерянной доставки.
Точный шаг прежнего отказа в этих отчётах отсутствует. Связь выявленных
дефектов с каждым пользовательским отказом ещё требует runtime-подтверждения.

## Изменения кандидата 0.1.3 (8)

- AXSelectedText readback теперь ждёт согласованных text/caret в прежнем
  бюджете, как keyboard backend. Повторяется только чтение; запись не повторяется.
- При временном AX-отказе чтение выделения/результата повторяется в оставшемся
  бюджете. Проверки target, полного UTF-16, ревизии и фокуса сохранены.
- До записи текста подтверждённое восстановление исходного выделения означает
  notApplied; неудавшийся/неподтверждённый setter и любые неизвестные результаты
  записи остаются uncertain.
- Диагностика replacement содержит техническое имя последнего этапа.
  Ошибки фонового snapshot во время обязательной проверки текста больше не
  вытесняют первичный отчёт восстановления из ротации.
- NativeProbe сохраняет начальное readback только собственного аутентифицированного
  нового тестового документа. Wrapper сохраняет исходную ошибку и отдельную
  ошибку валидации вместо подмены причины на helper_exit_not_verified.

## Текущая матрица

| Проверка | Источник/бинарник | Результат |
|---|---|---|
| CLI-инварианты | изменённые исходники debug | 720/720, offline |
| EditorGuard, включая позднее подтверждение, смену поля, NFD, отмену и deadline | production helper с подставленными снимками | 17/17 |
| RuntimeRecovery | production controller, platform stubs | 59/59 |
| Native fixture validators | helper parsing, без событий | 4/4 |
| Unicode seed + Double Shift | установленный GUI 3fde69fd918f | FAIL: seed совпал, но исправление заблокировано существующей защитой |
| Unicode / выделение / ручная отмена | установленный build8, GUI 77243f2dbab3, PID 9665 | 3/3 PASS |
| Первое слово, immediate Double Shift, поток 10 мс | тот же build8 | 3/3 PASS |
| Дополнительный поток с интервалом 80 мс | тот же build8 | FAIL: одно hello осталось руддщ; остальные две регрессии PASS |
| Профильный smoke без обучающей автоотмены | тот же build8 | 11/11 PASS |
| Отмена автоисправления с обучением | тот же build8 | NOT_RUN: безопасная очистка тестового правила через UI недоступна |
| Четыре часа | — | DEFERRED_USER |

[EditorGuard](../research/evidence/recovery-2026-10-18/editor-guard.json),
[RuntimeRecovery](../research/evidence/recovery-2026-10-18/runtime-recovery.json),
[selftest](../research/evidence/recovery-2026-10-18/selftest.txt),
[validators](../research/evidence/recovery-2026-10-18/native-fixtures.txt),
[Unicode](../research/evidence/recovery-2026-10-18/unicode-diagnosis-01/verification.json).

Прежний fresh_probe_initial_text_mismatch пока не воспроизведён. Байты старого
seed UTF-8 корректны. Новый запуск точно подтвердил исходные 15 UTF-16 единиц,
включая emoji, до жеста; это не PASS преобразования. Полный Unicode набор,
короткие регрессии и smoke необходимо повторить на кандидате после установки.

## Собранный кандидат

0.1.3 (8), исходный коммит `b43ef15980e00da207c1179452176d16aa89dbd6`,
GUI SHA-256 `77243f2dbab348bd49258f64932c1def167d3c3446702dac659cd8ec0c8d3589`.
Все compiled inputs совпали с коммитом, arm64 build и строгая проверка подписи
прошли. Release selftest 720/720, корпус 4420/4420. Это не native-приёмка.
[Identity](../research/evidence/recovery-2026-10-18/candidate-build8-identity.json),
[build](../research/evidence/recovery-2026-10-18/build8.txt),
[release selftest](../research/evidence/recovery-2026-10-18/release-selftest.txt),
[release corpus](../research/evidence/recovery-2026-10-18/release-corpus.txt).

## Установка и короткие native-проверки

Пользователь подтвердил сохранность сегодняшнего текста и штатно закрыл прежний
процесс. Установлен ровно собранный build8; все 11 файлов совпали, подпись проверена.
Предыдущая сборка сохранена в research/private/recovery-2026-10-18/previous-TypeTune.app.
Прежние записи AX и Input Monitoring обновлены через системный UI, обе включены.
Запуск выполнен через Finder по точному установленному пути; PID 9665,
других переключателей не запускали. [Установка](../research/evidence/recovery-2026-10-18/installation-build8.json).

[Unicode 3/3](../research/evidence/recovery-2026-10-18/build8-unicode-01/verification.json),
[регрессии 10 мс 3/3](../research/evidence/recovery-2026-10-18/build8-regressions-fast-01.verification.json),
[дополнительный 80 мс FAIL](../research/evidence/recovery-2026-10-18/build8-regressions-01.verification.json),
[smoke 11/11](../research/evidence/recovery-2026-10-18/build8-smoke-01.verification.json).
Наборы привязаны к точному PID, bundle и helper; завершение помощников и отпускание
модификаторов проверены. Пробы восстановили исходную RussianWin. Настройки после
проверок семантически идентичны сохранённым, learnedWords пуст:
[readback](../research/evidence/recovery-2026-10-18/build8-settings-verified.json).

Первое слово при 80 мс началось через 56,2 мс после подтверждения фокуса,
Double Shift через 15,7 мс после последнего ввода. Дополнительный поток сохранил
длину/каретку, но один hello остался руддщ. Этот FAIL не аннулируется успешным
повтором при 10 мс: качество потока остаётся открытым.

В [сохранённой диагностике новой сессии](../research/evidence/recovery-2026-10-18/build8-final-diagnostics.json)
нет mutation-result uncertain; отчёт представляет момент фонового snapshot timeout,
а не полную трассу всего smoke. Успешный smoke после этого подтверждает, что
работа продолжилась. Полное отсутствие будущих отказов из этого не следует.

CUA по-прежнему связывает путь TypeTune со старым ID dev.kartamyshev.TypeTune.
Поэтому auto-undo, создающий learned word, исключён до возможности безопасно
удалить только тестовое правило через UI. Ручная отмена проверена Unicode-набором;
это другой сценарий. [Точный scope smoke](../research/evidence/recovery-2026-10-18/build8-smoke-scope.json).

## Точка продолжения

Build8 установлен и оставлен работающим. Не пересобирать его перед длительным
прогоном без новой привязки evidence. Разобрать отдельный пропуск потока 80 мс;
проверить auto-undo после восстановления управления UI. ChatGPT/Codex проверяет
пользователь. Chrome, терминалы, сон/Secure Input/отзыв разрешений и сравнительный
p95 не получают нового PASS из TextEdit-проверок.
Четырёхчасовой прогон не запускался: ждать явно назначенного пользователем окна.
Стабильность ядра и весь PLAN ещё не приняты.
