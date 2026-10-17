# Локальные настройки: привязки main и конкретный путь plain paste

2026-10-15. Узкий REA проход продолжил [LOCAL_FEATURE_CANDIDATES](LOCAL_FEATURE_CANDIDATES.md).
Target arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Индекс: [local-settings-research.json](../research/evidence/local-settings-research.json).
Это наблюдения кода поставленного оригинала; UI/native действия не выполнялись.

REA6.5.0 / Ghidra12.1.4, skill42. Проверены прежние export/snapshot и отсутствие
нужных тел в cache. Один обоснованный readonly import обслужил весь пакет:
11 новых псевдотел и6 ASM records, общий export118 records. Расширение с10 до11
тел согласовано координатором ради настоящего reset writer. Export и snapshot
сохранены private; session закрыта, `open=false`, повторных imports нет.

## Сброс собственного звука — main callback действительно подключён

`0x10004a588` передаёт в `SettingsPaneView.init` ненулевой callback сброса.
Его путь `0x10004b160 → 0x10004a898`: это уже больше, чем текст общего UI framework.
Initializer `0x100023dd4` связывает settings-store поле`0x190` с Data-wrapper
и ключом `tech.caramba.switcher.sounds.main-sound-override`.

Reset writer `0x10004a898` передаёт этому wrapper пустое/nil-кодированное
optional Data значение через setter и затем вызывает `0x1000239bc`.
ASM подтверждает запись по store+`0x190` и оба вызова. Семантика последнего
callee пока не восстановлена. Удаление файла звука, фактический fallback,
звук на слух и readback после перезапуска **не проверены**.

Evidence: settings caller
`ev_9366214b18d17718302648c3f2272b7773a32d6797211d0569123829a6c89712`;
его ASM `ev_f80f837dfceb641a53759ad036a4bc8cd22c4e5a55307754050423cb886acd16`;
wrapper `ev_034b5bcf8f5468d6905e21b16d41056db134c10a696b8b52cf7a4e8bdadab53b`;
writer `ev_31c89858e50a664e59a6c8e77fa56f80d3ce170db5e1d8d8c6eb1d94a68b0bc5`;
writer ASM `ev_1f3afaf2c6215ed19be0170362a04352aa09d0b6798c219988d7f8749ab9e197`.

Отдельный sound-drop callback `0x10004d19c` проверяет state feature4 и
NSItemProvider с URL-объектом, затем запускает асинхронную загрузку. Это
статическая связь импорта собственного звука; вся цепочка загрузки/сохранения
по этому пакету не восстановлена. Evidence:
`ev_4c2a85517ee68711dc65f83edcbd173c88b4749086ac9b08fee399eb131a9805`.

## Цвет заголовка — подтверждены setter, builder и legacy fallback

Main settings callback идёт через thunk`0x10004b168` в `0x10004d3a0`.
Он передаёт входную строку в persisted wrapper store+`0x150` и обновляет
Published state view model. По initializer`0x100023dd4` это поле связано
с ключом `caramba.header-color-name`.

Builder`0x10004d510` сначала берёт сохранённое имя цвета. Если оно отсутствует,
читает legacy `tech.caramba.switcher.personalization.header-color` как Int и
вызывает `HeaderColor.name(forLegacyHex)`. При отсутствии пригодного результата
использует `ColoredHeaderView.defaultColor`, затем публикует состояние.
Это статически восстановленный local settings путь. Набор цветов picker,
нажатие в UI, визуальный результат и сохранение после restart не приняты.
Поддержка произвольной темы из этого не следует.

Evidence: header callback
`ev_ee50288560065df2f3dd5980eb4027b247859f6030b5a44007f640ecc79cde21`;
ASM `ev_a34775c63fcffa9defa9839ec87e46dd1e9c8f40b97692e90fc451cdb8ed7c0d`;
builder `ev_7d582fc95526c35381759537eb5cfc95c40b8954acdf8870138da875f625ae10`;
initializer `ev_6c510fdf02f056be77e6970e712f04a92bfab297a602d3613314d6dba8b60238`.

## Plain paste: именованная hotkey и точный native Cmd+V — разные вопросы

`0x10000a45c` создаёт именованный shortcut `tech.caramba.switcher.paste-no-format`
через `0x1001bf170`, сохраняет структуру в глобальном состоянии.
Evidence `ev_4ea5e7200eb94d6cd6fba66d711b41b90e337477297c170f902d987c0942ac62`.
Полный constructor, default и его связь с редактируемым recorder ещё не
восстановлены. Поэтому возможность **произвольного назначения** комбинации
не считается завершённой только по общему UI тексту и наличию ключа.

Зато native выдача команды paste восстановлена точно:

1. `0x100022cb4` передаёт enum`0x15` и массив модификаторов через
   relay`0x100077ecc → 0x100076104 → 0x100076108`.
2. `0x100076108` создаёт одну keyboard-command запись. По frozen таблице
   `0x10041781e[0x15]` получается virtual keycode9, то есть **V**.
3. Static modifier array`0x10058fe10` имеет count1 и index1; запись
   `0x1004178f8[1]` равна`0x100000`, **Command**.
4. `0x100076734` создаёт CGEventSource с constructor state1, HIDSystemState,
   down и up для keycode9, устанавливает Command flags и вызывает CGEventPost
   с location0, HID. В paste callsite параметр отправки up включён.

Таким образом, это конкретный **Cmd+V через HID с source constructor1**,
статически наблюдаемый в оригинальном исполняемом коде. Значение enum`0x15`
само по себе нельзя было назвать virtual keycode21: его обязательно переводит
таблица. Выбранные скалярные константы сверены форматным чтением frozen Mach-O
и локальными SDK enum; бинарные таблицы целиком в public не перенесены.

Evidence native path: clipboard ASM
`ev_0b1a4b89962ec12f98177432522ede85a2adf361873a2d4c071e0d1c263bce5d`;
constructor pseudo `ev_6904cc698e13354182cc3ebbf7e3f1cc923dac45b74bc5fc9f6a71339917e42f`,
ASM `ev_d097d90d8d28327c856cacfc41fad42a7995aaa5cd4169b25c143040110602de`;
emitter ASM `ev_e60b7ef624501ebbc7a968d8bf73491e850bc5fa0b48e2480710e401b18c0b6e`.
Его прежний pseudo находится под
`ev_c1683e1bcc9a10b5bcebdacfc16212bff387c2d3e4117277d8381563a04f34b8`.

**Отдельные свойства сохранности:** чтение/временная замена clipboard,
запрошенный sleep1с и восстановление type→data описаны в
[PHASE3_STATIC](PHASE3_STATIC.md). Точная выдача Cmd+V не доказывает сохранение
нового clipboard изменения, фокуса, нескольких pasteboard items или текста
во всех редакторах. Этот worker native clipboard опыт не выполнял.

## FocusEN: поле модели, а не установленный Boolean toggle

Полное тело `0x1002d68a0` подтверждает, что маркер `switch_to_en_on_focus`
участвует в десериализаторе. Соответствующая ветвь поля2 принимает wiretype2,
вызывает `0x1002d4bf0` и добавляет записи размером`0x18` в vector.
Это похоже на repeated delimited/string list. Называть поле Boolean flag
или пользовательской настройкой преждевременно. Тип значения, конкретные
consumer и цепочка смены фокуса→TIS остаются неизвестными. Evidence:
`ev_734199f05f45a9750c2e948596578f59d613d77a439bce9c7a4560cd3ec7da20`.
У этого большого тела есть предупреждение Ghidra о нестабильной type propagation;
полного ASM corroboration ветви в данном пакете нет.

Также исправлена прежняя гипотеза: `0x10025a030` **не** matcher специальных
правил приложений. По полученному телу она сравнивает language IDs TIS источников
и выбирает удержанный альтернативный источник. Evidence:
`ev_b9a191b73902b5cd924684cd4302344929e552801f3daaf8a27f9bc9ba45cca2`.
Использовать её как доказательство focusEN нельзя.

## Следующее действие

До новой статической сессии проверить сохранённые тела/базу; cache snapshot
по-прежнему разрежён (1 primitive/1 workflow). Приоритет: constructor`0x1001bf170`
и фактическая привязка editable recorder; callee`0x1000239bc` после reset;
подтверждение типа`0x1002d4bf0` и consumers focusEN vector. Далее отдельные
синтетические UI/native проверки настроек, с возвратом исходного состояния.
Пункты PLAN о полном покрытии этим документом не закрываются.
