# Почему paste/beforeinput не доказывают вставку

Проверено2026-10-15: установленная Chrome по Info.plist — **155.0.8059.40**.
Ниже прочитан официальный Chromium tag той же версии. Это сопоставление
исходников, не наблюдение внутренней ветви установленного процесса; флаги
сборки и фактические return-ветви не измерялись. GUI, клавиши, исходники
LayoutPilot и настройки этим исследованием не менялись.

## Уточнение по фактическому опыту

Основной агент сообщил о доставленных trusted KeyV/meta+alt+shift и paste
с правильными собственными данными. Последующий опыт обнаружил также
beforeinput:insertFromPaste. Поэтому раннюю гипотезу «остановка обязательно до
beforeinput» нельзя применять к этому последнему случаю. Отсутствие input и
неизменный текст остаются наблюдаемым результатом; конкретная причина неизвестна.

## Подтверждённые исходниками развилки

`ExecutePasteAndMatchStyle` последовательно получает clipboard sequence,
отправляет paste, проверяет CanPaste и selection focus, отправляет beforeinput.
После него возможны возвраты при отменённом событии, исчезнувшем frame,
активном EditContext или смене sequence. Затем `PasteAsPlainTextFromClipboard`
читает plain text, повторно проверяет sequence и отправляет TextEvent.
Следовательно, beforeinput ещё не подтверждает DOM mutation.
[clipboard_commands.cc805–855 и478–491](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/commands/clipboard_commands.cc#L805-L855).

Blink `SystemClipboard.ReadPlainText` в этом пути вызывает синхронный IPC
либо возвращает сохранённый plain text из `ScopedSystemClipboardSnapshot`.
Это не JS Async Clipboard API. Browser-side ReadText использует callback-цепочку
извлечения текста и проверки политики: ожидание межпроцессного результата
возможно, но длительность в нашем процессе не измерена.
[system_clipboard.cc110–123](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/clipboard/system_clipboard.cc#L110-L123),
[clipboard_host_impl.cc325–357](https://github.com/chromium/chromium/blob/155.0.8059.40/content/browser/renderer_host/clipboard_host_impl.cc#L325-L357).

Plain-text TextEvent имеет DOM-тип **textInput**, bubbles и cancelable.
Его отмена — отдельная точка после beforeinput, которую журнал только
paste/beforeinput/input не различает.
[text_event.cc40–44,80–99](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/events/text_event.cc#L80-L99).

Editor обрабатывает paste TextEvent через ReplaceSelectionWithText/Fragment.
Замена пропускается при отсутствующей или неeditable visible selection;
ReplaceSelectionCommand также отвергает невалидную selection.
Сам focused DOM-элемент или AX caret0 не подтверждают все эти внутренние условия.
[editor.cc138–164,262–299](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/editor.cc#L262-L299),
[replace_selection_command.cc1422–1432](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/commands/replace_selection_command.cc#L1422-L1432).

## Ограниченный решающий опыт

Это предложения для отдельной собственной fixture; здесь они не выполнялись.

1. На одном наборе listener сохранять paste → beforeinput → textInput → input,
   включая target-owned, trusted, defaultPrevented и совпадение payload с
   собственным expected. Проверять defaultPrevented также через setTimeout0:
   microtask из раннего listener может не отражать поздний обработчик.
2. В тех же точках сохранять только состояние собственной selection:
   rangeCount, isCollapsed, оба конца внутри rich, connected/editable и offsets;
   отдельно — activeElement и getTargetRanges у beforeinput. Не менять selection
   в обработчике опыта. Сравнивать удачный и неудачный случай с одинаковым reset.
3. При правильном, неотменённом beforeinput и отсутствии textInput проверить
   EditContext и sequence/ожидание clipboard. Один вариант опыта — удерживать
   тот же synthetic clipboard без восстановления3сек вместо800мс, сохранив
   все проверки владения и не повторяя команду. Сопоставить timestamps событий
   с моментом восстановления и changeCount. Это проверка гипотезы, не исправление.
4. Если textInput доставлен и не отменён, а input отсутствует, сузить опыт до
   selection/fragment path и состояния empty rich после reset. Изменять только
   одну переменную; не выдавать повторную paste автоматически — возможен дубль.

Нельзя заключать о гонке clipboard лишь из задержки или из самого факта paste.
Нельзя объявлять проблему исправленной увеличением150/200мс без воспроизведения
и причинного опыта. Native-прогоны текущего кандидата и совместимость Codex
этим source-review не закрываются.

## Уточнение: macOS sequence и наблюдение cache

В exact155 tag `ClipboardMac.GetSequenceNumber`170–179 создаёт новый token при
новом NSPasteboard.changeCount, но не обновляет `last_known_sequence_number_`.
`ClipboardChanged`631–640 сравнивает count с этим отдельным полем и также
создаёт token. Допустимо статическое чередование: внешний count B → первый
GetSequenceNumber даёт token1 → отложенный ClipboardChanged видит B новым для
last_known и даёт token2. Поэтому одинаковый OS count сам по себе не доказывает
одинаковый Chromium token. Нужен активный observer/callback; его выполнение в
неудачном опыте пока не подтверждено.
[clipboard_mac.mm](https://github.com/chromium/chromium/blob/155.0.8059.40/ui/base/clipboard/clipboard_mac.mm#L631-L640).

Наблюдатель этой версии использует `_CFPasteboardCache.setChangeCount:` и
отложенный main-thread PostTask, а не подтверждённый polling interval. Устаревшее
упоминание polling в комментарии другого файла не следует считать реализацией.
[pasteboard_changed_observation.mm55–107](https://github.com/chromium/chromium/blob/155.0.8059.40/base/mac/pasteboard_changed_observation.mm#L55-L107).

Основной агент уже проверил предварительную выдержку clipboard750мс:
ошибка повторилась. Следовательно, простая задержка до клавиш не стала
подтверждённым исправлением, а описанный interleaving остаётся гипотезой.
Следующий изолирующий контроль — один synthetic clipboard write на весь
ограниченный блок A/B, без промежуточных restore/rewrite; сравнивать прямую
native command и перехваченную команду на одинаковом поле, затем восстановить
clipboard при сохранённом владении. Не менять product deadline.

## beforeinput.dataTransfer=false не всегда означает потерю clipboard

`DispatchBeforeInputDataTransfer` при !IsRichlyEditable(target) создаёт событие
с обычным **data**, а не dataTransfer. Это законная ветвь даже при наличии
корректного plain payload. Нужны отдельные hasDataTransfer/dataEqualsExpected,
target и editability наблюдения в синхронном обработчике.
[editing_utilities.cc1654–1679](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/editing_utilities.cc#L1654-L1679).

В clipboard-backed DataObjectItem строка читается отложенно; после чтения
сравнивается sequence. При несовпадении возвращается пустая строка. Поэтому
наличие text/plain в types также не доказывает успешный getData. Проверять
нужно hasDataTransfer, typesHasPlain, getDataIsEmpty и payloadMatch раздельно.
[data_object_item.cc183–203](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/clipboard/data_object_item.cc#L183-L203).

Обычный CmdV тоже использует ScopedSystemClipboardSnapshot (Paste550+), как и
PasteAndMatchStyle805+. Разница — выбор plain-only либо rich/all-MIME пути,
а не доказанное отсутствие snapshot у одной команды. Сравнение этих двух
команд полезно, но не само по себе устанавливает неисправность LayoutPilot.

## Источник CGEvent: ограниченная проверка exact155.0.8059.40

Повторное чтение официального exact-tag2026-10-15 не обнаружило проверки
private/HID/sourceStateID/PostToPid в просмотренном пути Mac keyboard → Blink
→ paste/clipboard. Это ограниченный отрицательный результат по перечисленным
файлам, а не поиск по всему Chromium или доказательство поведения закрытого
AppKit/WindowServer.

- [WebKeyboardEventBuilder269–342](https://github.com/chromium/chromium/blob/155.0.8059.40/components/input/web_input_event_builders_mac.mm#L269-L342)
  переносит NSEvent type/modifiers/keycode/characters/timestamp; source-state
  в этой структуре не переносится.
- [NativeWebKeyboardEvent107–110](https://github.com/chromium/chromium/blob/155.0.8059.40/components/input/native_web_keyboard_event_mac.mm#L107-L110)
  использует этот builder и сохраняет исходный NSEvent.
- [Mac performKeyEquivalent1348–1398](https://github.com/chromium/chromium/blob/155.0.8059.40/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm#L1348-L1398)
  проверяет key window/first responder, redispatch и системные сочетания.
  [keyEvent1460–1644](https://github.com/chromium/chromium/blob/155.0.8059.40/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm#L1460-L1644)
  фильтрует отдельные flagsChanged и unmatched keyUp, обрабатывает IME и команды.
  В просмотренных ветках нет условия private против HID.
- [pasteAndMatchStyle2942–2943](https://github.com/chromium/chromium/blob/155.0.8059.40/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm#L2942-L2943)
  отправляет host-команду. В
  [ExecutePasteAndMatchStyle881–936](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/commands/clipboard_commands.cc#L881-L936)
  последующие проверки используют editor command source, selection, отмену,
  EditContext и clipboard sequence; CGEvent source-state не участвует.

По [Apple CGEventSourceStateID](https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid)
private/HID выбирают таблицу состояния клавиш/модификаторов. Это не гарантия
одинаковой доставки AppKit. По
[CGEventSourceGetSourceStateID](https://developer.apple.com/documentation/coregraphics/cgeventsource/sourcestateid)
созданная private-таблица получает собственный уникальный ID; константа создания
private=-1 не означает, что фактический ID каждой private-таблицы останется-1.

Источник и способ отправки — разные оси: private/HID нужно сравнивать при
одинаковом post-route; postToPid/HID-post — отдельным контролем. Доставленный
trusted KeyV и paste не доказывают ветвь источника внутри AppKit.

### Новый независимый HID-контроль

[paste-hid-independent-rich.json](../research/evidence/paste-hid-independent-rich.json)
зафиксировал неудачу первого CmdOptionShiftV: поле осталось AX«\\n», восемь
событий отправлены, target guards прошли, начальные/конечные modifiers нейтральны,
clipboard остался собственным и все исходные representations восстановлены.
По сообщению основного агента переключатели были остановлены; сам JSON не
содержит process-inventory и handlerIdentityProven=false. Поэтому evidence
опровергает утверждение «переход на HID сам по себе уже исправил опыт», но
не доказывает конкретную внутреннюю причину Chrome и не заменяет сравнение GUI.

### Plain-only против multi-type: что действительно различает опыт

В exact-tag
[DataObject.CreateFromClipboard62–103](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/clipboard/data_object.cc#L62-L103)
режим kPlainTextOnly явно пропускает все MIME, кроме text/plain.
[ClipboardMac.ReadText324–332](https://github.com/chromium/chromium/blob/155.0.8059.40/ui/base/clipboard/clipboard_mac.mm#L324-L332)
читает NSPasteboardTypeString. Отдельный
[ReadHTML364–380](https://github.com/chromium/chromium/blob/155.0.8059.40/ui/base/clipboard/clipboard_mac.mm#L364-L380)
выбирает HTML/RTF/string по приоритету, но это не прямое доказательство выбора
RTF для PasteAndMatchStyle. У plain-only и multi-type остаются одинаковые
[sequence checks120–136,526–539,931–935](https://github.com/chromium/chromium/blob/155.0.8059.40/third_party/blink/renderer/core/editing/commands/clipboard_commands.cc#L120-L136).

Для последующего отдельного helper-изменения достаточно параметра
`--clipboard-format plain|multi`, где multi сохраняет текущее поведение,
а plain создаёт один NSPasteboardItem с тем же setString(.string), без RTF/HTML.
Не использовать NSString.writeObjects как замену: это добавляет другую ось
автоматического объявления representations. После write проверять только
собственные заданные типы/байты в RAM и стабильность changeCount, не раскрывая
исходный clipboard. Все guards/restore/таймауты остаются прежними.

Минимальная матрица — два формата × два режима жизненного цикла: fresh write
перед каждым независимым trial и один write на bounded repeat-block. Сохранить
одинаковые source, post-route, прямую native-команду, поле/выделение и паузы;
переключатели остановлены. Начальное содержимое каждого опыта — один и тот же
известный synthetic payload с полным выделением, чтобы не смешивать format с
empty-paragraph sentinel. После команды проверять текст И схлопнутый insertion
caret: одинаковый текст сам по себе не доказывает вставку. Чередовать порядок
форматов AB/BA; не выполнять автоматический повтор после failed paste.

Интерпретация ограничена: если оба формата ломаются только после fresh write,
это усиливает зависимость от lifecycle, но не доказывает sequence race. Если
multi ломается и на стабильном clipboard, а plain нет при одинаковом lifecycle,
это показывает зависимость от набора representations; само по себе это не
доказывает ошибочный выбор RTF/HTML. Для sequence-причины требуется наблюдение
внутреннего token/return-ветви Chrome; неизменный OS changeCount недостаточен.
DOM-listener следует отдельно записывать наличие dataTransfer, список ТОЛЬКО
synthetic MIME, совпадение plain payload, data, defaultPrevented, selection и
textInput/input. Этот план в данном source-review не исполнялся; helper/GUI
не изменялись.
