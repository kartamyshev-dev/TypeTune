# Заголовок настроек и границы исследования recorder

2026-10-15. Продолжение [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md).
Индекс доказательств и SHA-256: [ui-framework-findings.json](../research/evidence/ui-framework-findings.json).
Это статическое исследование поставленного framework зафиксированной версии
2026.10.07 / 20261007.1. Этот исследователь не выполнял UI/native действия.

## Идентичность и объём

Universal framework SHA-256:
`31e915394d99184e19aaa1a454d289762404ff57610ba28de1498c1233231d9a`.
Частная arm64 slice SHA-256:
`aeb68b283c8a65a7469870adb1853b385a5ec2162f89d71d5bb2208efdca332a`.
Проверено точное побайтовое равенство slice arm64-члену FAT-файла.
Адреса framework начинаются от VM base 0; адреса main с `0x100…` относятся
к другому target, хеш которого указан в предыдущем отчёте.

Использованы полный symbol inventory, load commands и Objective-C metadata
зафиксированного файла. Затем один отдельный import framework в REA 6.5.0 /
Ghidra 12.1.4: 15 псевдотел и 8 ASM records. Первоначальный бюджет 8–12 тел
расширен координатором до 15 ради drop → writer → removal. Export содержит
23 уникальных Evidence ID; export и snapshot сохранены private, session закрыта.
Snapshot содержит 0 primitive / 0 workflow cache: сохранение evidence не означает
возможности продолжить новые Ghidra запросы без import. Сырой код и palette
оригинала в публичный отчёт не включены.

## Действия заголовка: цикл и сброс

При отсутствии пользовательского изображения **левый щелчок по свободному фону
заголовка** выбирает следующий из 25 preset цветов и вызывает `onColorChange`.
Swift entry `0x2fc18` состоит из перехода к `0x3120c`; для реальной логики отдельно
получен ASM `0x3120c`. Число 25 видно в циклическом индексе, это не предположение
по количеству ресурсных строк.

**Правый щелчок без изображения** присваивает `caramba-orange`, обновляет фон и
вызывает тот же callback. Меню или color picker в этой ветке нет. **С изображением**
правая кнопка открывает меню с действием `removeHeaderImage`.

Main `0x10004a588` передаёт callback, который через `0x10004b168 → 0x10004d3a0`
сохраняет имя цвета в `caramba.header-color-name`. Таким образом, правый щелчок
может впервые записать default в настройки. Нельзя утверждать, что именно это
объясняет историческое изменение preference в текущем UI-эксперименте.

Evidence: mouseDown
`ev_e09757184292ed65d713d9931d8639e5ecedc1457f44478c0ca0c74cc0bc83a8`;
entry ASM `ev_b228a9f10116e50b1f2a68f808855f19204e0da36f3d1cc86ea8de0b0dc4a2ad`;
cycle ASM `ev_b826705eeb77bb2645662e9130eff50da01f89fd3024a48e9db6860dd084bbbb`;
rightMouseDown `ev_7f8b7b2153111f80367988e7c1947d309638e5ad85285dffbada0eb3e52fe631`;
его ASM `ev_ef141e8612e74487b9dfb6e1478d5ac73fd2dee77288aa37721ecf44fe41e8aa`.
Main callback Evidence указан в предыдущем отчёте.

## Щелчок по надписи/логотипу

`titleViewClicked:` (`0x2fad8`) вызывает `0x2f8a0`: текущий белый tint становится
чёрным, иной — белым. Результат сохраняется Bool в `headerTitleWhite`, затем
обновляется рисунок заголовка; при изображении дополнительно обновляется его
оформление. Это отдельное действие title button, а не открытие выбора цвета.

Evidence: `ev_59563f0135e579a2435efed524b3f949c21937566ba753cce134049bff729b59`,
`ev_ab59f92b12c40dbab1b25a230ffb65ab0f37508fb0d97fe0f05ed03da6742fb2`,
ASM `ev_28f2d1ddb1927d3b4a68d39fb29dfeefb7af14107f13a25dbf731a43107dfe9c`.
Ключ `headerTitleWhite` также привязан к строке `0x42700`.

## Собственное изображение — путь подключён в этой версии

Это не вывод из рекламной строки. Main создаёт shared SettingsPane;
его типизированная композиция body включает ColoredHeaderView. `makeNSView`
`0x2e768` устанавливает переданный callback и вызывает setup `0x2e80c`.
Setup безусловно регистрирует drag types FileURL и TIFF. Objective-C metadata
ColoredHeader (`class ro 0x607a8`, methods `0x41420`) содержит dragging handlers.

1. `performDragOperation` `0x2fc78` пробует TIFF data → NSImage; если не получилось,
   FileURL string → URL → NSImage(contentsOf:). Успешный путь вызывает `0x2f540`
   и возвращает true; неподходящий ввод возвращает false.
2. `0x2f540` создаёт/подключает image subview, задаёт изображение и, если доступно
   TIFFRepresentation, сохраняет Data через NSUserDefaults в `headerImageData`.
3. Setup `0x2e80c` читает тот же Data key и, если NSImage создаётся, применяет его
   через `0x2f540`. Путь восстановления сохранённого изображения существует.
4. ObjC action `removeHeaderImage` `0x306e8 → 0x305d0` удаляет image subview,
   обнуляет поле, удаляет `headerImageData` и `headerTitleWhite`, убирает тень title.

Ключ `headerImageData` восстановлен из непосредственных Swift small-string
слов в ASM: writer `0x2f680–0x2f6b4`, reader `0x2ebc0–0x2ebf0`, removal
`0x30620–0x30650`. Это важно: псевдокод bridgeToObjectiveC не показывает аргумент
строки достаточно ясно. Setup не вызывает `onColorChange` в проверенном теле;
гипотеза обязательной lazy записи default при открытии окна им не подтверждается.

Evidence: make `ev_f51ba43c062cd8735b2a0b5f37f711a36b570fe8d7d260faeaa52fbae68bc0d9`;
setup `ev_38ccc01ea3feed27d3534d1dedcee9af761f8ca9fce7e56b954a669a9e058eeb`;
setup ASM `ev_46e5c27df0f92f1a3524c149acd9708816e083eea8aa7a61d4cce4bb1ad14257`;
drop `ev_c35b8120b5b997ff3cbef9114d27672b877b275c4f855c0af69fbacf859b4f0b`;
drop ASM `ev_7a5f06c68a4ffdfb1424b7345760d329195d5e289a2eceaf99e0af09f3be52b1`;
writer `ev_8fd451c7ce3d639e3f962bd46f790627e2870479e7eb71f31d861cd5f8e01f92`;
writer ASM `ev_78216a6950d3d162ebec78010e4b6da952039ccab9a2898401729473a83d76f8`;
remove `ev_a70d13288ddddb3913dc1af41cad52b16d0471c807683bedcb55322f2e149f2d`;
remove ASM `ev_45b921384f87e1afd46aa2a78f892adb8d61b949c0df93373cc03ba3cb08bf37`.

**Остаётся native проверка:** drop синтетической картинки, прочтение нужного
preference, восстановление после перезапуска, неподходящий файл и удаление с
возвратом исходных настроек. Статический путь не является UI/native PASS.

## Произвольная hotkey: граница знания

Полный symbol inventory этого framework не содержит Recorder или
CarambaKeyboardShortcuts-specific символов; load commands не содержат зависимости
CarambaKeyboardShortcuts. Есть стандартные SwiftUI keyboardShortcut для кнопок.
Это ограниченное отрицательное наблюдение: анонимные тела, статическая линковка
и UI в main этим не исключены.

`SettingsSheet.rawValue` `0x361c0` даёт три случая: license, about, exceptions.
Shortcut sheet в этом enum не обнаружен. Body `0x386e8 → 0x388d4 → 0x38b04`
исследован частично; полная структура настроек из него не восстановлена.
Evidence IDs этих четырёх тел есть в индексе. Рекламный текст «любая hotkey»
в shared ресурсах не становится подтверждённой editable функцией main.

Следующий узкий шаг: main constructor `0x1001bf170`, его связь с настоящим
KeyboardShortcuts.RecorderCocoa и сохранением именованного shortcut; при нужде
следующий framework helper `0x39308`. Новый import ради всего SettingsPane без
этой связи пока не оправдан. Произвольное назначение сочетания остаётся unknown.
