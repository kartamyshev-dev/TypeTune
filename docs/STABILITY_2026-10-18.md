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
| Короткая native-приёмка кандидата 8 | кандидат ещё не установлен | NOT_RUN |
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

## Точка продолжения

Сохранность сегодняшнего пользовательского текста запрошена отдельно: старое
подтверждение не распространяется на новые неопределённые операции. Текущая
защита не сбрасывалась. CUA пока неверно разрешает путь TypeTune в старый
bundle ID dev.kartamyshev.TypeTune; фактический ID установленного приложения
по-прежнему dev.layoutpilot.mac. Не запускать вторую копию для обхода.
После подтверждения — штатный выход, backup, установка точного кандидата,
обновление прежних разрешений, проверка одного процесса, короткие native-наборы.
Старые build7 результаты относятся к другому GUI и не переносятся на кандидат.

Пользователю предложен штатный выход через меню после проверки текста: CUA
не смог связаться с текущим процессом даже после обновления регистрации bundle.
Ожидается сообщение «закрыл»; установка до этого не выполнялась.
