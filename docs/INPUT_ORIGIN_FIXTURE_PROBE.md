# Проверка происхождения собственных событий

Новый ограниченный `Tools/InputOriginFixtureProbe.swift` сравнивает генерацию
одинаковых g,h,b,d,t,n,Space с `CGEventSource.privateState` (-1) и
`hidSystemState` (1). Он не запускает/останавливает переключатели, не меняет их
настройки, не подключается к REA и не управляет их окнами.

Собрать без native-запуска:

```sh
scripts/input_origin_fixture_probe.sh --compile-only
```

Оператор заранее выбирает один переключатель и фокусирует отдельное поле Chrome
на точной странице `http://127.0.0.1:18763/?fixture=LP-CODEX-001`:

```sh
scripts/input_origin_fixture_probe.sh --source private
scripts/input_origin_fixture_probe.sh --source hid
```

Допускаются только `LP-CODEX-001 plain/rich` с пустым или известным синтетическим
содержимым: ghbdtn/привет/hello с одним/двумя конечными пробелами либо20 повторений
«привет ». Известное содержимое выбирается; первый g заменяет его. Пустой rich AX
`\n` рассматривается как placeholder. Чужой текст не очищается. Перед каждым
из14 событий проверяются точный PID/поле/окно/URL, AX trust, posting access,
Secure Input и нейтральность flags/keyState всех модификаторов. Новый фокус
прерывает опыт; автоматических повторов и Return нет. Clipboard не используется.
Перед вводом выбирается именно ABC с readback; после опыта восстанавливается
точный исходный TIS source и проверяется его ID.

Два пассивных `.listenOnly` tap с `.headInsertEventTap` стоят на cghid и
cgSession. Оба должны создаться и оставаться включёнными, иначе опыт прекращается
без fallback. Callback сначала проверяет `eventSourceUnixProcessID == ownPID`
и точный собственный userData tag. Только затем читает keycode/sourceStateID;
Unicode не читает вообще. Другой ввод не записывается и не подсчитывается.
Лимит64 собственных trace rows; ожидается не более28 (14×2). В trace только
location, type, keyCode, sourceStateID и event timestamp собственных событий.

Отчёт содержит известный synthetic before/afterFirstSpace, курсор, source IDs,
created-event metadata, trace counts и guards. Неожиданный текст скрывается.
`probeCompleted=true` означает завершение ограниченного опыта и восстановление
состояния, **не успешную коррекцию**. `ownDeliveryObservedAtBothTaps` отдельно
показывает, были ли собственные события фактически замечены на обоих уровнях.
Различие результатов private/hid является наблюдением доставки/поведения в
условиях опыта; само по себе оно не доказывает, какой фильтр есть в Caramba.
Сопоставление текста и ожидаемой коррекции выполняет основной агент отдельно.

При добавлении оба helper прошли только компиляцию Swift5; native-запуск этим
автором не выполнялся. Полнота покрытия Caramba не заявляется.
