# Plain paste: фиксированная комбинация и непроверенная доступность recorder

2026-10-15. Продолжение [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md) и
[UI_FRAMEWORK_RESEARCH](UI_FRAMEWORK_RESEARCH.md).
Target main arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Доказательства: [hotkey-findings.json](../research/evidence/hotkey-findings.json).
Это статические наблюдения; UI/native действия в этом проходе не выполнялись.

## Что действительно делает настройка plain paste

В main `0x10004a588` callback изменения option подключён к общему SettingsPane
через `0x10004b158 → 0x10004ce18`. Ветка option index 1 в `0x10004ce18`:

- Сохраняет входной Bool в store+`0xd0`; initializer `0x100023dd4` связывает
  его с `tech.caramba.switcher.paste-no-format`.
- При true получает key из `0x1001b507c → 0x100422540`, создаёт пару key/modifier
  через `0x1001c415c` и передаёт её с tag 0 в `0x1001b6fd8` для named shortcut.
- При false передаёт 0/0/tag 1 в тот же setter-путь.

ASM `0x10004cf10–0x10004cf24` показывает загрузку qword key и modifier
`0x120000`; байты `0x100422540` равны `09 00 00 00 00 00 00 00`.
Это preset **Cmd+Shift+V**, а не пользовательская выбранная комбинация.
`0x1001c415c` возвращает пару и вызывает три внутренних helper; их точная
семантика этим пакетом не раскрыта. Нормализация modifiers остаётся гипотезой.

Evidence: option `ev_ec6edabd6abbe814263c9ff004303458dd44f658e9e267e650e449ae36b721c9`;
ASM `ev_534a148222b3b09c97ab24fa012844e81f8353b72da22c73c2664be387657891`;
key helper `ev_7840ed190148705b56001c490f0e53a23e78fc2d73a09ba73a0737bf6c212922`;
key bytes `ev_7442e9228b011a8c20899106dc8ecc3a0b5d636053118d9adbd783e7c37f7c3f`;
pair `ev_d66ca495b7abf8dab5c275c63bd926f5c0ea9c32835a78ab554bbf98e5078855`;
setter relay `ev_f57699c1beefca0fbcfd114615d09946e54a401bb3c48fe615683057432e0469`,
ASM `ev_250b801dc733a6c461205b3ef6fdc8b7410720a8e1973b636a96a41bf17a68ee`.

## Инициализация имени не открывает recorder

`0x10000a45c` передаёт имя `tech.caramba.switcher.paste-no-format` в
`0x1001bf170` с pair 0/0 и optional tag 1. Возвращённая 33-byte структура
сохраняется в global `0x10060ba20`. Constructor копирует имя/optional default,
условно вызывает default setter лишь если tag != 1 и проверка существующего
значения это допускает; затем вызывает `0x1001bdaa0`. В этом callsite ветка
default setter пропускается. Callback recorder в эти параметры не передаётся.

Evidence constructor `ev_8b35d117bcf26f92e89846b2de56c9dbb9136de0454a0bc3557a18e544de3704`;
его ASM `ev_c68ede2706644be8a3565edaf9cb30e6b5997124c6a38af81ab1b2c61c6777d3`;
a45c ASM `ev_46963dcc506cb1399c9ac3518d76631b29687f9885614218967c87d15806787c`.

## Реализация recorder присутствует, подключение к настройкам неизвестно

Frozen Objective-C metadata содержит настоящий `KeyboardShortcuts.RecorderCocoa`
как subclass NSSearchField, с полями `shortcutName`, `onChange`, event monitor.
`0x1001bf490` создаёт экземпляр через type accessor и initializer `0x1001c3ac0`.
Initializer устанавливает name/onChange, delegate, подсказку record_shortcut,
оформление поля и observers. Это исполняемая реализация библиотеки в main,
а не только локализованная строка.

Однако у `0x1001bf490` Ghidra не находит direct callers; единственный xref —
`0x100632943`, расположенный в `__LINKEDIT`, а не в коде вызывающего UI.
У этого xref входящих references не найдено. Его нельзя считать доказанным
application caller или UI witness. У ObjC init wrapper
`0x1001c37ec` direct callers также нет. Эти границы не исключают indirect,
Swift metadata/witness или runtime dispatch. Они **не доказывают** ни доступность
recorder в текущем окне настроек, ни его полное отсутствие.

SettingsPane callback изменения option получает enum+Bool и в доказанной ветке
устанавливает фиксированную Cmd+Shift+V. Произвольное назначение hotkey,
путь открытия recorder и её UI/runtime readback остаются **unknown**. Рекламный
текст shared framework не заменяет эту недостающую связь.

Evidence make recorder `ev_30314fd0c43ed92449ec942ba7b9c0cc17e4f365cede705c465535905bda958a`;
initializer `ev_d08daaf499f58c06e797c0cb646205eb8f432b2035891f67438ce6539027e99c`;
caller lookup `ev_1b1437fac0995d880fdd89e004279c5629df798cf446c7a5e3038be4acf11fcc`;
xref `ev_542c8dabd0bd6f6fbcf6c4e49cf142e8938fa71f220456e7c7aedb72bd2f95e8`;
xref to slot `ev_942a52f9fb35dda933abefe1394afec6f6bf29414349c779286b6d5cae929d78`.

## Звук после reset: обновляется cached override

Ранее reset writer `0x10004a898` очищал optional override Data и вызывал
`0x1000239bc`. Теперь `0x1000239bc` раскрыт: он читает persisted Data wrapper
store+`0x190`, при присутствующем Data пробует NSSound(initWithData:), затем
заменяет cached sound store+`0x1b0` полученным объектом. При отсутствии Data
записывает nil и освобождает прежнее cached значение.

Поэтому reset сбрасывает и cached override. Удаление исходного sound-файла или
конкретный звук fallback из этого тела не следуют. Фактический fallback/play
consumer store+`0x1b0` и звук на слух требуют отдельного доказательства.

Evidence `ev_8ed2291e99b6b267e37909bb1c6f21f9d4ab47d0f0b0d6908535652ef058f2c9`;
ASM `ev_4c249e803c0a53f159382f8f89719965a638104bdae6433fe7291e86937b913e`.

## Сохранение исследования

Перед началом проверены settings export/snapshot: нужные constructor и sound
тела отсутствовали; snapshot содержал только иной primitive analyze_function.
Один обоснованный main import обслужил 8 новых псевдотел, 5 ASM, 3 callers,
3 xrefs и 1 byte read — 20 новых records. Полный export содержит 138 records.
Export и snapshot сохранены private; session закрыта. Snapshot имеет 1 primitive
и 1 workflow binding, поэтому сохранение evidence не обещает replay новых тел.

Следующий точный адрес — `0x1001b71e4`: enabled-option relay вызывает этот
named-shortcut setter. Он не вошёл в лимит 8 тел. Полная запись/registration и
произвольное UI назначение поэтому не объявлены восстановленными.
