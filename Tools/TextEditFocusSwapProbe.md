# TextEdit focus-swap candidate

Отдельный helper; NativeProbe и его guards не изменены. Сборка без SwiftPM:

```text
sh scripts/build_focus_swap_probe.sh
```

Режим по умолчанию и `--preflight` только читают разрешения, Secure Input,
neutral keyboard/source readiness; не создают файлов, не открывают/активируют
приложения и не отправляют событий. `preflightReady` отличается от `success`
сбора сведений. На подготовительном этапе executable не запускался.

Явный будущий запуск `.build/focus-swap-probe --run`:

- Требует ранее выданных AX/PostEvent, ABC/US, нейтральной клавиатуры и ровно
  одного LayoutPilot с executable в project `dist/LayoutPilot.app`; настройки,
  PID этого процесса и hash bundle фиксирует внешний record harness.
- Создаёт только два новых пустых UUID файла A/B в `research/private/probes`
  с mode0600; открывает их именно в TextEdit. До чтения текста доказывает
  exact file URL, app PID, window и AXTextArea. Разные window/field обязательны.
- До первого события репетирует focusB→focusA через собственный AXWindow Raise
  и AXFocused field; ACK каждого focus ограничен1s. Если две независимые цели
  или выбранный API фокуса не подтверждаются, завершается с0 событиями.
- В A вводит физические `ghbdtn ab` без Return —9 пар, cap18 кадров
  (<=40), по5ms между кадрами. Перед каждым кадром повторяет pinned identity A/B,
  focusedA, Secure Input/permissions, neutral modifiers/all key states кроме
  единственного своего Down. A допускает только префиксы известных RU/EN
  синтетических вариантов; B должен оставаться пустым/caret0.
- После сбалансированного suffix `ab` и neutral state делает единственную
  попытку focusB. С этого момента нет HID, управляющих/cleanup событий,
  input-source writes, clipboard или text setters; только bounded readonly
  наблюдение1.5s и полные тексты/ranges обеих принадлежащих helper целей.
- Утечка текста в B даёт failure/exit2. На отказе identity не отправляет
  cleanup в чужое окно; `ownedKeyReleasePending` сообщает о незавершённом кадре.
  Новые документы не закрываются и раскладка не восстанавливается helper после
  swap, поскольку фаза после swap исключительно readonly; завершение/восстановление
  выполняет координатор отдельно в безопасной точке.

Снаружи можно заранее настроить существующую диагностическую задержку LayoutPilot
30..150ms. Helper её не читает и не меняет. AX проверки и планирование могут
сдвинуть момент swap: один лишь `noLeakToBObserved` не доказывает пересечение с
активной mutation/replay. Всегда `raceProven=false`, `fullAcceptance=false`;
для отрицательной приёмки необходима независимая target trace с доказанным overlap.
Счётчик pending/recovery не читается из defaults: он RAM-only и не является
публичным интерфейсом; отчёт содержит null и явное ограничение. Перед публикацией
PASS нужно сопоставить сохранённые target diagnostics/доступный собственный UI
отдельным разрешённым наблюдением; отсутствие текста в B не доказывает отсутствие
потери или корректное восстановление задержанного ввода в A.

Safari native scope пользователь отклонил; этот helper не обращается к Safari,
Cursor, Terminal, Codex или существующим пользовательским документам.
