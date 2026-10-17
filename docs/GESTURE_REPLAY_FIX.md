# Отмена старого жеста при перехвате ввода

## Подтверждённый дефект до исправления

На GUI `ba8e8277258feae9c0b6e22dace832f97cdad16fef3a2761c87d568b27193e3e`
из source commit `1b790639b5745a531e341426bb1cb127ddea370b` после ручного
⌘⌥Space последующие Single Shift и Double Shift могли перестать работать.
Наблюдавшиеся результаты не содержат прямой потери или повреждения текста.

[Обычный набор 13 случаев](../research/evidence/accelerated-textedit-smoke.json)
содержит оба пропуска; [проверка](../research/evidence/accelerated-textedit-verification.json)
остаётся FAIL. [Повторный subset2](../research/evidence/accelerated-gesture-tags-native.json)
без перезапуска повторил их. После перезапуска
[subset2 с кадрами модификаторов](../research/evidence/accelerated-gesture-frames-native.json)
прошёл: это контроль зависимости от состояния, а не закрытие старого сбоя.

Целевой префикс из трёх случаев: manual-shortcut → single-shift → selected-manual.
[Контроль без искусственной задержки](../research/evidence/accelerated-shortcut-shift-before.json)
прошёл 3/3. Замена завершилась до отпускания Option, и обычный обработчик
модификаторов получил release. При существующем диагностическом AX selection
delay 80 ms на том же GUI
[воспроизведение до исправления](../research/evidence/accelerated-shortcut-shift-delayed-before.json)
дало manual PASS, два последующих жеста FAIL.

Диагностика приложения, сессия `958D0A0A-05EE-4280-9FDF-12377976F64F`,
зафиксировала в пределах одного boot:

- `49996.793396`: Option down при нажатом Command;
- `49996.822446`: mutation gate granted;
- `49996.939474…49996.941930`: три `replay-forward`, соответствующие
  оставшимся release кадрам; обычного gesture Option up нет;
- последующие Shift down/up: `pendingDeadline=false`, действий нет,
  хотя `singleEnabled=true` и AX-кэш актуален.

Это runtime-воспроизведение согласуется с конкретной source-цепочкой:
`ModifierGesture` сохраняет used Option press; `keyUsed()` не удаляет held
presses; barrier удерживает его release; replay намеренно не вызывает
`handleModifier`. Сохранённый Option делает новые Shift перекрывающимися,
поэтому они отклоняются до следующего reset/поступившего Option release.
Порог времени не является причиной установленного сценария.

## Минимальное изменение

`KeyboardService.cancelGestureStateForInterception()` сбрасывает только модель
жестов и отменяет ожидающий Shift timer. Он вызывается на main при выдаче
mutation gate, перед непустым replay и при начале явного recovery. Ревизии,
источник ввода, FIFO, настройки и guards не меняются. Перехваченные события
по-прежнему доставляются через FIFO и не распознаются заново как жесты.

Старый press после interception больше не может стать отдельным действием.
Отпускание физически удерживаемого модификатора без нового press не создаёт
жест. Новое независимое нажатие после завершения перехвата обрабатывается
обычным recognizer. Пороги Single/Double Shift и maximum hold сохранены.
Дополнительно адаптер проверяет текущие aggregate flags: Shift при удерживаемом
Option и Option при удерживаемом Shift не становятся отдельным жестом, даже
если предыдущий press другого модификатора скрыт барьером.

Opt-in диагностика получила фазу `gesture-interception-reset` без текста,
keycodes, raw flags или иных входных метаданных; при выключенном trace запись
не выполняется.

## Проверка после изменения

Сборка из `7e0ad86b4e3b8caa4b37c13866fb8b0c029ec899`, GUI SHA-256
`38a0d4fd41e5aa96842dcbb097402a6f593423beecb44fe712984a33e37a41a0`.
[Идентичность](../research/evidence/gesture-fix-build-identity.json), компилируемые
исходники и ресурс совпадают с коммитом. Release CLI584/584 и корпус4420/4420;
это offline-проверки отдельно от native.

Тот же prefix3 с AX delay80 и trace ON прошёл 3/3, включая текст, source и caret:
[результат](../research/evidence/gesture-fix-delayed-after.json),
[проверка](../research/evidence/gesture-fix-delayed-after-verification.json).
В [trace](../research/evidence/gesture-fix-delayed-after-trace.json) присутствуют
3 gesture-interception-reset и3 replay-forward. До исправления при тех же
диагностических условиях два последующих жеста пропускались.

После штатного выхода оба диагностических ключа удалены (исходно отсутствовали),
ранний режим остался OFF. Обычный TextEdit smoke прошёл 13/13:
[проверка](../research/evidence/gesture-fix-textedit-verification.json).
Сохранены текст, раскладка, selection; модификаторы нейтральны. Исключение ghbdtn,
созданное тестом auto-undo, удалено через «Снова исправлять»; пользовательские
записи не очищались. Это ограниченная регрессия, не полная приёмка PLAN.

Тест, повторяющий вызов reset на игрушечной модели, не добавлялся: установленный
runtime lifecycle подтверждён before/after. Другие физические сочетания и sleep/
wake этим опытом не проверялись.
