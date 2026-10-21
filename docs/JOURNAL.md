# Журнал TypeTune

## Опубликован v0.1.7 — 2026-10-20

Тег `v0.1.7` → `874fd29`. CI на коммите ([39400920268](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39400920268))
и выпуск ([39401298799](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39401298799)) прошли: selftest 1707/1707,
пробник, `package.sh` из чистого тега, подпись, CLI и приложение из архива без `.build`. Файлы релиза скачаны:
SHA-256 архива `a0a4b5ba…54237` совпал с опубликованным, версия 0.1.7 (13) и коммит верны. Native-ввод на
релизном архиве не проверялся; пользователь проверил сборку `99c015a`.
[Evidence](../research/evidence/release-0.1.7/publication.json).

## Выпуск v0.1.7 — 2026-10-20

Пользователь проверил сборку `99c015a` («нормально работает», user manual) и поручил выпуск. Версия
0.1.7 (13); выпуск собирает и публикует CI по тегу `v0.1.7`. Результат публикации — следующей записью.

## Короткие слова сразу — 2026-10-19

Пользователь: в Caramba «в» исправляется сразу, это удобнее (DECISIONS п. 35). `Engine.decide` исправляет
слова из 1–2 букв на своей границе. Первая версия дала 169 (RU) и 110 (EN) ложных исправлений на ~0,8 млн
слов, из них почти все — заглавные аббревиатуры и `T.`; после исключения аббревиатур и токенов со знаком:
RU 52, EN 55; полнота коротких слов RU 93,1%, EN 95,3%; слов от трёх букв без изменений. Linux offline:
selftest 1707/1707, корпуса. На Mac не проверено.
[Evidence](../research/evidence/short-words-immediate-2026-10-19/natural-text-after.json).

## Первое слово в любом поле, кроме паролей — 2026-10-19

Пользователь напомнил решение «работать во всех полях, где возможно, кроме паролей» (DECISIONS
п. 34). Снято собственное ограничение пп. 26/30: в нечитаемом поле первое слово после клика, короткие
слова в начале буфера и сниппеты правятся вслепую. В шестом отчёте это 8 из 20 пропусков. Читаемое
поле по-прежнему сверяется с границей слова. Linux offline и CI; на Mac не проверено.

## Шестой отчёт «то работает, то нет»: первое слово и защищённый ввод — 2026-10-19

Отчёт сборки `1c57afd` (user manual, сессия `C5680AA4…`, 2 ч 7 мин, 0 ошибок). Короткие слова и
сниппет сработали. Из 20 слов, которым нужно было исправление, 8 пропущены: каждое — первое после
паузы от 4 с до 3 мин (новое сообщение после клика или перехода) в поле, которое не отдаёт каретку
(`anchored=false`, правка вслепую запрещена, DECISIONS п. 26). В 17 наблюдениях поле — `AXTextArea`
с текстом, но без `AXSelectedTextRange`. Защищённый ввод включался 4 раза, дольше всего 26 и 10 мин —
TypeTune всё это время стоял. Изменено (не проверено на Mac): поле с текстом без каретки сверяется
по тексту (`valueWithoutCaret`) — может только разрешить правку, если текст кончается набранным
словом после границы, но не запрещает разрешённую вслепую; показывается приложение, включившее
защищённый ввод (`secure-input-owner`, IORegistry); в `universal-boundary` без решения пишутся
признаки слова без текста (`lettersOnly`, `short`, `knownAsTyped`, `convertedKnown`).

## Отчёт пользователя «то работает, то нет»; короткие слова — 2026-10-19

Отчёт v0.1.6 (user manual, сессия `7E84616C…`, 1000 записей, 0 ошибок): 232 пробела после слова;
24 раза нужно было исправление — 20 слов после известной границы исправлены и подтверждены, 4 первых
слова после клика в нечитаемом поле пропущены (DECISIONS п. 26, 30). Остальные 208 — словарь решил
не исправлять; какие слова, отчёт не показывает. Замер на естественном тексте: короткие слова не
исправлялись никогда. Добавлено исправление коротких слов по контексту: полнота коротких слов RU
0 → 55,7%, EN 0 → 76,3%, ложные исправления без изменений. Linux offline; приложение — в CI.
[Evidence](../research/evidence/short-words-2026-10-19/verification.json).

## Опубликован v0.1.6 — 2026-10-19

Тег `v0.1.6` → `1f7b2c2`. Выпуск собран и опубликован CI на macOS
([39177649862](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39177649862)): версия и описание
совпали с тегом, selftest 1648/1648, пробник, `package.sh` из чистого тега, подпись, CLI из архива,
приложение из архива работает 8 с без `.build`. Файлы релиза скачаны с GitHub: SHA-256 архива
`18796897…b88a8` совпал с опубликованным, в архиве 102 файла, коммит и версия 0.1.6 (12) верны.
Native-ввод на релизном bundle не проверялся.
[Evidence](../research/evidence/release-0.1.6/publication.json).

## Сниппеты в main, выпуск v0.1.6 через CI — 2026-10-19

По решению пользователя (DECISIONS п. 33): ожидание стирания сокращения в Chrome — 600 мс вместо 80
(`8bcc9fa`, CI [39177133686](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39177133686),
native не проверялось); версия 0.1.6 (12); `main` перемотан на `snippets`; выпуск собирает и публикует
`.github/workflows/release.yml` по тегу `v0.1.6`. Результат публикации — следующей записью.

## 2026-10-19 — повтор выбранной S8 завершён, исходные данные возвращены

`agent native, user-authorized` / TextEdit NativeProbe; установленный TypeTune
92a0ba845c75ba767bc19cbb65c697a6bd9df008, GUI2d4edbde… не менялся. После официального
обновления/перезапуска Chrome155.0.8059.85 обычный диагностический paste9/9,
с clipboardchange-наблюдателем3/3. Польза AX warmup4/4 не подтверждена контролем;
новую продуктовую правку не делали. Upstream fix ещё отсутствует: постоянное устранение
гонки не доказано. Native повтор: Chrome16/16, Safari11/11, Notes11/11, Telegram11/11,
TextEdit26/26 —75/75. [Итог](../research/evidence/snippets-s8-chrome-2026-10-19/verification.json),
[матрица](../research/evidence/snippets-s8-chrome-2026-10-19/matrix.json).

Safari Secure Input: ожидаемый guard,0 событий; typed-password E2E не выполнен.
Clipboard: текст/изображение и все представления возвращены; image `{{буфер}}`
оставлен сокращением. Stream10 requested10мс, не утверждение о реальной частоте.
Итоговый trace858 записей,0faults, ready/очереди0. После восстановления отдельный
отчёт новой сессии ready/очереди0; он не заменяет trace матрицы.

Исходного snippets.json не было; отсутствие восстановлено, в UI только3 исходных
правила. При восстановлении CmdQ закрыл окно, но не процесс; проверка UI обнаружила9
правил. После явной кнопки «Выйти» отсутствие процесса проверено по фактическому пути,
исходный файл повторно загружен, UI подтвердил3, затем исходное отсутствие возвращено.
ABC и все типы clipboard равны checkpoint; настройки равны кроме statistics.v1
(статистику не откатывали). Chrome AXEnhancedUserInterface=true возвращён/проверен;
Caramba выключена, TypeTune работает. В Maccy удалена одна видимая собственная подпись;
второй ID из диагностического запроса был NULL, а не второй элемент истории.
48 orphan-представлений остались в базе;450 прочих content rows неизменны по хешу.
Прямых изменений базы не было. [Состояние](../research/evidence/snippets-s8-chrome-2026-10-19/state-after.json).

Сообщений не отправляли; непреднамеренный Google-поиск тестового пути описан ниже.
Slack/VS Code/Word/Terminal вне разрешения; U8/весь S8/4часа не закрыты. В main не сливали.

## 2026-10-19 — Chrome S8: причина в идентификаторе clipboard Chromium

Отклонение при подготовке после запуска TypeTune: быстрый CUA-ввод адреса потерял
префикс `fi` у `file:///…/fixture.html`; Return открыл Google-поиск с локальным
тестовым путём. Это непреднамеренный поисковый запрос, не отправка сообщения;
локальный путь содержал имя домашнего каталога. Дальше адрес задан через AXSetValue,
точное значение проверено перед Return. Чужие черновики не использовались.

Пользователь повторно разрешил исследование/исправление Chrome и повтор S8 в
TextEdit, Заметках, Safari, Chrome и Telegram без отправки. Исходное отсутствие
snippets.json зафиксировано приватно; после диагностического импорта тестовая
библиотека сохранена, файл снова отсутствует. Продуктовый код не менялся.

`agent native, user-authorized`, диагностическая изоляция, **не S8 PASS**:
TypeTune92a0ba8 остановлен, поле заранее пустое. Сбой воспроизводится без удаления
сокращения. Страница получает trusted CmdV/paste с30 символами; paste и beforeinput
не отменены, input отсутствует, поле визуально и через AX пустое. Системный
changeCount204 одинаков от записи до итогового чтения. Это соответствует дефекту
Chromium568453825: ClipboardChanged повторно создаёт token после GetSequenceNumber,
и Blink отменяет вставку из-за ложной смены буфера. Upstream исправление
[fc5529f5](https://chromium.googlesource.com/chromium/src/+/fc5529f522a28df6ff5d5f7e572debc71d6f18e4).
Внутренние token работающего Chrome не читались; вывод основан на native-последовательности
и исходниках точной версии. [Evidence](../research/evidence/snippets-s8-chrome-2026-10-19/root-cause.json).

Официальный updater Chrome обновил155.0.8059.82→155.0.8059.85, перезапуск проверен UI;
обе версии исходников без исправления. Настройки канала/разрешений не менялись.
Диагностическое чтение AXEnabled команды Paste после записи, затем100мс и единственный
CmdV дало4/4 на исходном fixture; контроль после обновления выполнен в следующем этапе, см. запись выше.
Временные страницы trace закрыты, запись трассы не запускалась, debug-pages не включались.
AXEnhancedUserInterface временно сброшен при отдельном опыте, CUA после него возобновлён;
финальная сверка подтвердила true, см. запись выше. Два первых файла service-off ошибочно названы:
TypeTune там был запущен; остановленность подтверждена только service-off3/4 и следующих
изоляционных опытах. Первые PASS прежних кандидатов не переносятся.


## 2026-10-19 — S8 остановлен после двух неудачных кандидатов Chrome

На `92a0ba8`, GUI `2d4edbde…`, CI39166705738 Linux/macOS success, CLI1648/1648,
контроллер102/102. Chrome без DOM-наблюдателя:1 PASS, затем пустая multiline-вставка
и `mutation-uncertain`; `snippet-deletion matches=true,current=true`. Второй кандидат
Chrome не принят. Дальнейший ввод остановлен по MAC_AGENT_GUIDE §2.7 (две неудачные попытки).
[Итог](../research/evidence/snippets-s8-2026-10-18/verification.json),
[trace](../research/evidence/snippets-s8-2026-10-18/deletion/chrome-fault-report.json),
[восстановление](../research/evidence/snippets-s8-2026-10-18/deletion/state-after.json).

Ничего не отправлено, затронуты только свои fixtures/черновики. Исходного snippets.json
не было: восстановлено отсутствие файла; исходные3 правила загружены в память, тестовых
сниппетов там нет. ABC, clipboard checkpoint и все настройки кроме статистики возвращены.
Maccy не содержит тестовую подпись/nonce. Итоговый readback ready, pending/outstanding/
uncertainDeliveries0. Из очереди после сохранения trace удалён только остаток тестового
кадра. Установленный кандидат оставлен по §9.5, но Chrome multiline **не принят**.
Остальные S8-клетки на этом бинарнике NOT_RUN: прежние PASS не перенесены. Полный перечень
по версиям — SNIPPETS_PLAN; S8/U8/полная готовность не закрыты, main не менялся.


## 2026-10-19 — S8: полный кадр ⌘V недостаточен; кандидат с подтверждением удаления

`5984232`, GUI `43fca30f…`: Chrome multiline повтор1 PASS, повтор2 — пустое поле и защита.
Кандидат с полным Command-кадром не принят. Две read-only трассы clipboard показали
точный payload до возврата исходного буфера, посторонней записи не наблюдалось.
Системный журнал показывает вызов Chrome Command-V в обеих попытках. Session tap
не видит PID-targeted события — пустую трассу нельзя считать недоставкой. На fixture
с DOM-журналом7/7 совпадений; наблюдатель меняет тайминг, исходный fixture этим не принят.
[Разбор](../research/evidence/snippets-s8-2026-10-18/frame/delivery-investigation.json).

Второй кандидат Chrome: разделены удаление и вставка. Только для читаемого Chrome
ожидается точное UTF-16 содержимое перед кареткой после удаления, максимум80мс;
перед единственной вставкой снова проверяются revision/source/PID/trust/Secure Input
и свежесть доказательства. Отказ после уже выполненного удаления — uncertain,
в том числе отказ разрешения на вставку; автоматического повторного paste нет.
CLI1648/1648, контроллер102/102 без событий. Native этого кандидата NOT_RUN.


## 2026-10-18 — S8: повтор после Telegram и отказ вставки Chrome

На `4af15f7`, GUI `04476538…`: TextEdit24 завершённых случая, включая поток10/10
(requested10мс), отмену, восстановление текстового и графического clipboard и отказ
`{{буфер}}` с картинкой. Maccy не содержит текста тестовой подписи. Notes10 наблюдений.
Telegram multiline targeted PASS с U+2028; отдельная отмена остановлена драйвером
на ожидании отпускания модификаторов, не PASS. После безопасного завершения
тестового кадра модификаторы нейтральны; guard не ослаблен.

Повтор Chrome:5 наблюдений, затем multiline FAIL — сокращение удалено, поле пустое,
`mutation-uncertain`. Ничего не отправлено, только собственный fixture. Safari/Telegram
полностью на этом GUI ещё не повторены. Trace сохранён. Пользователь отдельно разрешил
исправить Chrome и повторить. [Проверка](../research/evidence/snippets-s8-2026-10-18/verification.json).

Кандидат исправления: полный кадр Command down → V down/up → Command up вместо
только V с флагом Command, по образцу `pastePlainNative`. Контроллер102/102, без событий.
Причинность исторического пустого paste этим не доказана; native кандидата NOT_RUN.
Все данные восстановлены перед исправлением: исходное отсутствие snippets.json,
исходные3 правила в памяти, ABC, clipboard равен checkpoint после первых групп;
настройки равны кроме тестовой статистики, ready/очереди0.


## 2026-10-18 — S8: Telegram, представление перевода строки

Ветка `snippets`, исходный код `4cf6030`, CI GUI `e862b158…`. Вид проверки:
`agent native, user-authorized`, TextEdit — `native TextEdit, NativeProbe`.
Пользователь разрешил ввод в TextEdit, Заметки, Safari, Chrome и Telegram только в пустые
поля/черновики без отправки; отдельно разрешил обновление прежних разрешений TypeTune
через системный UI и исправление Telegram с повтором S8.

На исходном GUI TextEdit: регистр, граница слова, yf, поток80мс, подпись, дата/курсор,
отмена. Notes/Chrome/Safari: по10 случаев (один — отрицательное наблюдение `;flh`).
Telegram: первые5 случаев совпали с oracle; многострочная вставка остановлена защитой.
AX вернул U+2028 вместо LF, текст строк сохранён, Return не отправлялся.
[Исходная проверка](../research/evidence/snippets-s8-2026-10-18/initial-verification.json),
[trace](../research/evidence/snippets-s8-2026-10-18/telegram-fault-report.json).

Исправление ожидает U+2028 только для AX-представления сниппетов Telegram, включая
проверку перед отменой. Другие приложения и точный текст сохраняют прежние условия.
Регрессия red:3 отказа/1643; green:1643/1643. Native исправления ещё NOT_RUN.
`snippets.json` до запуска отсутствовал; состояние отсутствия сохранено. Статистика
увеличена тестами, остальные настройки совпали. Полная S8 не закрыта.


## Сниппеты: этапы S5–S7 (вставка, срабатывание, вкладка) — 2026-10-18

Ветка `snippets`, коммит `ebd4e9e`. Linux offline: `ci_core.sh` exit 0, selftest 1635/1635. CI на macOS
[39162932150](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39162932150): сборка без
предупреждений, `runtime_recovery_probe.sh` passed, в нём 8 проверок хранения на настоящем Store,
приложение запускается без `.build`. Первый запуск CI упал: сборка пробника по списку файлов не
включала `SnippetEditor.swift`. Native S8 не выполнялась.
[Evidence](../research/evidence/snippets-s5-s7-2026-10-18/verification.json).

## Универсальный режим в main — 2026-10-18

По решению пользователя (DECISIONS п. 32) `main` перемотан на `universal-input` после проверки
агентом на Mac и выпуска v0.1.5. Код не менялся; CI на этом коммите — в STATUS. U8 остаётся
частичной: пропущенные приложения и сценарии перечислены в п. 32.

## 2026-10-18 — опубликован предварительный релиз0.1.5(11)

Пользователь явно поручил push GitHub и новый релиз. Версия/build в build.sh0.1.5/11,
package archive0.1.5; README download обновлён. Тегv0.1.5 → a6e6213a4729,
из universal-input без merge main. Полная готовность не заявляется, prerelease=true.

Release build/signature выполнены; финальная упаковка из чистого a6e6213 использовала
candidate-build с проверкой source/resource/CLI/bundle identity (после первой сборки
изменился только README). GUI8f554257. CLI1439/1439, корпуса4420/4420+22000/22000,
controller93/93, guard23/23, audit4/4, fixtures8/8. CI39161125663 Linux/macOS success
на точном исходном SHA, GUI CI запускался без .build. Native релизного bundle NOT_RUN.
Установленный ab020042 и разрешения не менялись; второй переключатель локально не запускался.

Финальный ZIP9e06df8b53b9c5d984e82392fecfd263d4fceb5120f96af5fbe9238c1aeb1482,
19 050 627байт. Ditto-unpack:93 файла manifest, версия0.1.5(11), подпись и CLI PASS.
GitHub release опубликован, remote annotated tag peeled commit сверён; ZIP и SHA256
скачаны обратно, оба побайтно равны локальным. Картинки/пропущенные приложения/4часа
не запускались. [Публикация](../research/evidence/release-0.1.5/publication.json),
[полный выпуск](RELEASE_0.1.5.md).

## 2026-10-18 — S14: native inline suffix Chrome/Safari и меню PWA

Пользователь: «Продолжай проверки встроенного автодополнения и командного меню PWA,
исправляй до стабильной работы. Картинки и пропущенные приложения не трогай,
четырёхчасовой прогон пока не запускай». Разрешение на ввод всей матрицы сохраняется.
Вид проверки agent native, user-authorized, без Enter/clipboard в native probes.
GUI ab020042 / production6e07197 неизменен; рабочая база95f7ca6.

Chrome inline5/5: настоящий выделенный suffix адреса, сверка полного completion и range
до Space, после точный собственный127space/caret/source/flag. Затем auto5/5.
Safari inline5/5: браузер выбирал host либо полный собственный fixture URL; после Space
предлагал новое целиком выделенное поисковое продолжение. Введённый127space сохранён,
новый suffix весь выделен; затем auto5/5. Ни URL, ни поиск не отправлялись в native;
CUA Return использовался только для открытия собственного localhost fixture в новой вкладке.

PWA AionUi, текущий home composer: slash/open/open-space по5=15 PASS, отдельные slash и
open+SingleShift PASS; меню действительно открывалось и содержало open-candidate (CUA),
команда не исполнялась. Очистка собственного текста, затем dot1, auto5/5 и stream4words PASS.
Другие окна/команды и все виды autocomplete этим не приняты.

Всего48 native attempts,44 приняты. Четыре exploratory/harness attempts сохранены отдельно:
два исходных discovery не ожидали browser completion; Safari затем предложил full URL вместо
host (остановка до Space); после исправления предиката предложил новый suffix после Space.
Это ошибки оракула, не потеря пользовательского текста. Не скрыты и не отмечены PASS.
Test helper: slash44/dot47, inlineSpace только в fixture-адресной строке, максимум2 точных
известных completion, строгие text/range проверки перед Space; финальный typed-prefix
и полностью выделенный browser suffix. Native cleanup отказывает при selection;
Safari после каждого из5 случаев очищен CUA только после собственного prefix readback.
Return/Tab, field/PID/window/focus/perms/SecureInput guards не ослаблены.
Offline:3 unittest methods,14 reject subcases,9focus policy,8selected-suffix policy; evidence77.

Settings семантически равны началу S14, sourceRussianWin; один TypeTune PID32477,
Caramba не запускалась. PWA draft пуст/меню закрыто, ready,pending/outstanding/uncertain0.
В retained trace новее прошлого checkpoint19587 нет faults/snapshot-failed/rejections;
старый legacyOFF fault сохранён в ring, это не полная сессия. Статистика тестов не откатывалась.
Image helper/пропущенные приложения/4часа не запускались. Main не менялся.
[Итог](../research/evidence/mac-agent-s14-2026-10-18/verification.json).

## 2026-10-18 — P1: холодный Chrome подтверждён пользователем

В ответ на протокол после обычного перезапуска Chrome без CUA, ABC, ghbdtnspace
в пустом поиске google.com и новой вкладки по5 раз без Enter пользователь сообщил:
«работает стабильно». Вид проверки **user manual PASS**, отдельно от agent-native warm5/5.
Агент не наблюдал ввод, повторно не сверял identity после пользовательского теста и не
проводил отдельный clean-profile тест. P1 закрыт в пределах этого протокола; остальные
ограничения U8, inline suffix/PWA/password E2E и пропуски пользователя сохраняются.
[Подтверждение](../research/evidence/mac-agent-p9-2026-10-18/chrome-cold-user-manual.json).

## 2026-10-18 — P9: Google warm5/5, отдельные окна и итоговый checkpoint

GUI ab020042 / код6e07197 неизменен. Google search S1 warm5/5; S2/S3/S4/S6/S7/S8/S9 PASS.
В первом S7 после S6 не было удалено собственное исключение vbh: точный «привет vbh привет мир »
сохранён, ready; ошибка порядка тестов, не принято. Удалён только vbh, свой текст сверён/очищен;
повтор S7 PASS. Google/newtab S14: открытый popup виден CUA, собственный точный запрос,
без Enter и без сохранения скриншотов. Выбранный inline suffix отдельно не проверен.
S10 отдельные google/newtab/address/textarea/contenteditable: по3 возврата из Notes,0событий,
фактические флаг/tooltip=TIS. AX-пробники отдельных Chrome-полей записаны без текста.

Ограничение PWA S14: slash отклонён helper до событий; сценарий остаётся NOT_RUN.
Matrix:107 PASS,15 SKIP_USER,48 SKIP,6 NOT_RUN (из них5 явно NOT_APPLICABLE scaffold).
Не переносить эти числа на полную приёмку/U8. Cold Chrome без CUA не принят.

Test-only: parent wait NativeProbe180→300с для полного stream, production deadlines не менялись.
Matrix helper повторяет только readonly отсутствие одного focus-атрибута при другой закреплённой
identity; оба отсутствуют/объекты изменились → отказ; ни одного события до двух положительных
проверок. 9 policy checks и8 reject workloads PASS. В успешном Notes retry счётчик0:
ожидание на реальном transient в этом повторе не наблюдалось. Evidence77 tamper checks PASS.

Итоговый trace1000 содержит1snapshot-deadlineExceeded uptime18373.800 при temporary universalOFF,
до off-mode TextEdit start18382.026; не заявляется fault-free. Предыдущий universal-only trace
отдельно0faults/0snapshot-failed; итог ready,pending/outstanding/uncertain0.
Settings.v1 семантически равен исходному, sourceRussianWin, autocorrectOFF возвращены,
yf сохранён; статистика не откатывалась. Своё тестовое обучение удалено.
Image helper не запускался; четыре часа не запускались. Main не менялся.
[Итог и ограничения](../research/evidence/mac-agent-p9-2026-10-18/verification.json).

## 2026-10-18 — P9: текстовые группы и отдельные флаги TextEdit

GUI ab020042 / 6e07197, никаких следующих изменений production-кода.
Chrome input/textarea/contenteditable, Telegram, Notes, AionUi: доступные текстовые
S1–S4/S6–S9 и правило yf проверены; точный состав — новая matrix.json, не декартово
обобщение на ещё не проверенные поля. Telegram S7 дополнительно10/10 PASS.
Chrome S7:10 завершённых PASS, одна дополнительная попытка остановлена frontmost_changed
после полного правильно исправленного текста; точный собственный readback сохранён и очищен.
Причина краткой смены frontmost не установлена, попытка не засчитана. Никакой ⌘⌥R не было.

TextEdit: smoke13/13, review12/12, stream80 12/12 (192 слова,176.27с) PASS.
Последние1000 записей сразу после потока:0faults/0rejections, ready,
pending/outstanding/uncertain0; это не полный trace всей сессии.
Отдельные matrix-кейсы S1/S2/S3/S4/S6/S7/S8/S9/S11 выполнены с чтением настоящего флага.
Перед запуском original source выбран равным ожидаемому итоговому; NativeProbe выбирает
начальный source теста, а его восстановление после кейса не меняет конечный source.
Поэтому отдельный readonly StatusFlagRead (0 событий) действительно сверяет итог кейса.
S6 beforeGesture подтвердил « мир »/RussianWin до ⌘⌥Z; после — « vbh »/ABC.
Выучен только vbh, удалён через UI; исходные настройки сравнивались семантически.
S11 первое ожидание sourceABC было ошибкой теста: public fixture требует RussianWin;
текст «на » был правильным. Повтор с корректным итоговым source и флагом PASS.

S8 — отдельный новый UUID.txt с собственным abcdef, точный document/PID/field fence
NativeProbe, verified caret2 и реальные Left/Right сброса, затем ghbdtnspace:
«abghbdtn cdef», caret9, sourceABC и флаг PASS. Без clipboard и Return.

S13 TextEdit: первый запуск в другом новом документе не принят — настройка автозамены
переносилась только в тот документ, где была включена. В том же собственном UUID-документе
после включения checked=true, native «123 ghtdtn »→«123 привет », caret11/RussianWin PASS;
после теста тот же документ всё ещё checked=true, затем через меню возвращено исходное off,
readback равен baseline. Notes S13 также PASS, его autocorrect восстановлен.
S5 SKIP_USER, image helper больше не запускался. Четырёхчасовой прогон не запускался.
[Матрица и файлы](../research/evidence/mac-agent-p9-2026-10-18/matrix.json).


## 2026-10-18 — P9, новая сборка ab020042: первые повторные проверки

Код 6e07197, полная установленная identity в mac-agent-p9-2026-10-18/installed.json.
Исправлена асимметрия runKeystrokes: прежний цикл80мс повторял несовпавший readable prefix,
но не transient unreadable. Теперь оба состояния повторяются до прежнего порога;
selection/secure останавливаются сразу. Критерии правки, proof50мс и blind-anchor не менялись.
Предпосылка доказана на старом GUI: Safari focused AX cannotComplete54мс, затем диагностика
видела поле; newtab4/5 с таким же безопасным пропуском. Точная причина newtab unreadable
не доказана отдельно, переносить Safari AXError на него нельзя.

Controller93/93, CLI1439/1439, corpora4420/4420+22000/22000, audit4/4; ci_core локально
не проходит только XCTest отсутствующий в CLT. Release build/signature/selftest PASS.
CI39151757178 Linux/macOS success. Обе только прежние записи разрешений TypeTune
обновлены через System Settings UI; новый PID32477, один переключатель, Caramba не запускалась.

Новый GUI: newtab warm S1 5/5 PASS; Safari input S1 5/5 + S2/S3/S4 PASS.
Cold Chrome и Google с активными подсказками отдельно не приняты. TextEdit smoke13/13 PASS,
plainPaste временно включался, возвращён off, ghbdtn unlearned; settings семантически равны
исходным, yf сохранён. Review/stream ещё выполняются. Старые PASS не перенесены.
[Evidence](../research/evidence/mac-agent-p9-2026-10-18/matrix.json).


## 2026-10-18 — продолжение без картинки; Chrome contenteditable и новая вкладка

Пользователь: «Проверку картинки пропускаем, продолжай остальное». S5 SKIP_USER
во всей матрице; private image helper больше не запускать, разработка его pixel/parent
механизма исключена из текущего продолжения. Это не PASS картинки.
GUI по-прежнему 80652518, код 3244c81; scripts/matrix_input_probe.sh пересобран после
исправления shared ClipboardLease, 0 событий при сборке.

Chrome локальный contenteditable: S1/S2/S3/S4/S6/S7/S8/S9/S11 PASS, bound evidence
chrome-rich-*-current.json. Свой текст сверялся и очищался CUA только после точного
совпадения; S8 сохранил оба фрагмента abcdef. S6 vbh удалён через «Снова исправлять»,
settings семантически равны исходным (bound/rich-undo-settings-restored.json).
Никаких пользовательских полей/сообщений не менялось, Return 0.

Новая вкладка warm S1: 4/5 PASS, пятый исходный ghbdtn сохранён без потери текста.
Trace rev6127: decision=true, observe unreadable, anchored=false, fieldMatches=false;
TypeTune законно пропустил первое слово. Это LIMIT, не 5/5 и не закрытие P1.
Очередь пуста, manual-snapshot ready, faults последнего случая нет.
Собственное ghbdtn проверено CUA и очищено; отчёт newtab-five-diagnostics.json.
Холодный Chrome и Google с активными подсказками не приняты. CI 39150766561 success.


## 2026-10-18 — восстановление clipboard при modal исправлено; image helper упал

Пользователь: «Буфер не важен, исправляй и продолжай». Исправление Tools/ClipboardLease:
если generation ещё принадлежит lease, восстановление не зависит от поля документа.
Принятие exact nonce после чужой generation по-прежнему требует pinned context и сравнения
всех представлений. ClipboardLeaseProbe: modalRestore/newerOwnerPreserved/исходный clipboard
PASS, 0 событий; NativeProbe fixture tests 8/8.
[Проверка](../research/evidence/mac-agent-p8-2026-10-18/clipboard-modal-fix.json).

Три предварительные попытки нового RTFD не дошли до ввода: directory mode 0600,
затем несовпадение URL без trailing slash; выставлены 0700 и isDirectory:true.
В готовом RTFD преобразование и настоящая вставка картинки выполнены, но необязательный
разбор AXRTFForRange дал пустую NSAttributedString. Чтение attachment at 0 вызвало
Objective-C exception/SIGABRT, Swift catch/defer не выполнились. Исходный clipboard
не подтверждён восстановленным. Собственный документ по CUA: привет[вложенное изображение].
TypeTune жив, модификаторы нейтральны, source RussianWin. Native остановлен по §2.7;
пиксели и S5 PASS не заявлены. [Технические факты](../research/evidence/mac-agent-p8-2026-10-18/image-helper-crash.json).
Рекомендуемая следующая правка — убрать ненужный разбор RTF, исходный clipboard держать
в supervising parent, дочерний emitter не должен его перезаписывать. Ждём ответа пользователя.


## 2026-10-18 — остановка: буфер обмена при буквальной вставке картинки

Частный ImagePasteMain helper, GUI без изменений. Выделение мышью + Double Shift
в новом RTF подтвердило «привет», clipboard syntheticUnchanged. Настоящее CmdV открыло
системный sheet TextEdit «Конвертировать RTF в RTFD». verifiedField остановил работу,
а ClipboardLease.restore с referenceContext отказался восстанавливать при sheet.
Процесс завершился, прежний RAM snapshot недоступен; восстановление пользовательского
clipboard не подтверждено, возможна утрата. Это ошибка test harness, не P8 продукта.
Нельзя считать S5 PASS. Sheet отменён через CUA, точный readback собственного документа —
«привет», вставка отменена. Исходное содержимое clipboard не читалось/не логировалось.
[Инцидент](../research/evidence/mac-agent-p8-2026-10-18/clipboard-incident.json).
После sheet остались собственные V/Command нажатые. Узкий recovery в точном новом RTF
отправил только V-up и Command-up (2 события), текст/каретка неизменны, modifiersNeutral=true.
Исходная RussianWin восстановлена. [Readback](../research/evidence/mac-agent-p8-2026-10-18/image-owned-command-released.json).
Дальнейшие тесты остановлены, вопрос пользователю по MAC_AGENT_GUIDE §2.7.
До ответа никаких повторов; исправление должно обеспечить restore при модальных
окнах, затем использовать новый RTFD, не RTF.

Перед инцидентом Chrome textarea S1/S2/S3/S4/S7/S8/S9/S11 PASS;
S5 только byte-subgate, literal paste не завершён. CI 39150068825 Linux/macOS успешен.


## 2026-10-18 — смешанные потоки в четырёх приложениях, GUI 80652518

Agent native, user-authorized; приложение без изменений, код `3244c81`.
По 4 пары «привет hello» при физическом интервале 80 мс: Chrome input, Telegram,
Заметки и установленное Chrome-приложение AionUi — 4/4 PASS, 32 слова.
Точные текст/каретка/source и настоящий флаг, очистка только собственного fixture,
исходная раскладка восстановлена, модификаторы отпущены, Return 0.
Первый запуск Notes безопасно остановлен `focus_unavailable` после 8 событий:
UI подтвердил ровно собственное `ghb`, оно очищено, повтор PASS. Это не PASS первой попытки.

[Вердикт и привязки](../research/evidence/mac-agent-p8-2026-10-18/mixed-stream-verification.json).
Диагностический ring: 1000 записей, включая предыдущие тесты; 12 route/event rejections,
во всех единственная отрицательная проверка — leaseFresh. Fault 0, итог ready,
pending/outstanding/uncertain 0. Случаи не доказывают отсутствие задержек: безопасный
повтор после новой полной проверки справляется с наблюдавшимися истечениями.
Источник системной задержки по-прежнему не установлен.

Дополнительная серия TextEdit review дважды дала 11/12: только первый punct-period-ru
оставался исходным. Trace — decision=false, без попытки замены/блокировки. NativeProbe
создавал новый документ программно в уже активном TextEdit, не отправляя событие сброса
буфера; обычный пользовательский CmdN/клик такой сброс создаёт. В пробнике перед первым
обычным случаем в пустом документе добавлена настоящая Left с проверкой пустоты/каретки0.
Специальные firstWordAfterFocus и непустой initialText не меняются. GUI не изменён.
После исправления пробника review 12/12 PASS: [вердикт](../research/evidence/mac-agent-p8-2026-10-18/current-review-reset-verdict.json).
Предыдущая остановленная попытка review не засчитана: агент открыл вкладку TypeTune
параллельно native-запуску, нарушив фокус. Повтор выполняется без UI-действий.

Полный TextEdit smoke 13/13 PASS, включая plain paste и auto-undo; [вердикт](../research/evidence/mac-agent-p8-2026-10-18/current-smoke-full-verdict.json).
Временный plainPaste выключен, выучен только ghbdtn и удалён через UI; настройки семантически
равны исходным, yf сохранён ([проверка](../research/evidence/mac-agent-p8-2026-10-18/current-smoke-settings-restored.json)).

Режим universal off: TextEdit «привет », Notes «ghbdtn » — PASS; обе проверки
привязаны к прежнему GUI, настройка через UI возвращена в on, все settings семантически
равны исходным ([вердикт](../research/evidence/mac-agent-p8-2026-10-18/universal-off-verdict.json)).
Первый Notes-запуск остановлен focus_unavailable, собственная g подтверждена и очищена;
повтор PASS. В Google warm поиск две остановки пробника: 0 событий при выбранной подсказке,
после Escape — 8 событий и field_or_window_changed. UI подтвердил точное ghb, очищено,
Return 0. Chrome передаёт AX-фокус выбранному тексту подсказки, поэтому строгий пробник
прекращает ввод. Это не native-PASS Google и не доказанная порча текста продуктом.

Terminal/vim и Codex SKIP по прямому ответу пользователя; ограничения инструмента не обходились.
Матрица дополнена подтверждёнными Notes/PWA/focus-клетками; S5 всё ещё лишь byte-subgate,
буквальная вставка картинки не засчитана. Полная приёмка и cold Chrome остаются открыты.


## 2026-10-18 — Chrome-приложение, переходы и автозамена macOS

GUI 806525181a5b (код 3244c81), agent native, user-authorized. В установленном
AionUi (Chrome app shim 8059.82) прошли S1–S4, S6–S9, S11 и byte gate S5;
ввод только в пустой черновик, Return=0, собственный текст очищен. Отмена подтвердила
исправление до жеста; выученное vbh удалено, настройки семантически равны исходным.
Окно shim не отдаёт AXTitle: fixture явно ожидает null, объект окна по-прежнему
закреплён и сверяется перед каждым событием. Это изменение пробника, не ослабление PID,
поля/окна, permissions, Secure Input или запрета отправки.

Три круга Chrome → Safari → Telegram → Notes → AionUi → TextEdit: 18/18 focus-only
проверок, 0 клавиатурных событий; флаг и source ID настоящего status item совпали с TIS.
TextEdit использовал отдельный новый пустой документ с проверкой точного AXDocument.
[Evidence](../research/evidence/mac-agent-p8-2026-10-18/bound/).

Notes S2/S5(byte gate)/S6/S8/S9 PASS. Для S13 исходная автозамена macOS была выключена
(AX mark отсутствует); временно включена через меню, положительная отметка ✓ проверена.
Native `123 ghtdtn ` дал точные `123 привет `, каретку/source/флаг; префикс цел,
собственный текст очищен. Исходная отметка меню восстановлена с точным readback.
[Состояния](../research/evidence/mac-agent-p8-2026-10-18/bound/notes-spelling-restored.json).
Это не закрывает холодный старт P1: CUA при работе с Chromium включает AX-доступность.


## 2026-10-18 — подготовка S8 в Заметках

Пробник остановился до ввода ghbdtn: немедленное AX-чтение после четырёх Left ещё
не подтвердило каретку 2. Отдельный readonly-пробник затем показал точные 6 символов
abcdef и диапазон {2,0}; GUI подтвердил собственный fixture. Он очищен без изменения
чужих данных. Добавлено ограниченное ожидание только положительного полного readback
(до 300 мс, прежние per-event guards). Повтор Notes S8 PASS: текст/каретка/source/флаг
совпали, оба фрагмента слова целы, модификаторы нейтральны, собственный fixture очищен.
[Evidence](../research/evidence/mac-agent-p8-2026-10-18/bound/notes-s8-settled.json).
Матрица теперь связывает новые результаты с SHA приложения, helper, исходников,
fixture и идентичностью процессов до/после; GUI по-прежнему 806525181a5b.


## 2026-10-18 — отмена, середина слова и состояние модификаторов пробника

GUI остаётся `806525181a5b` (код `3244c81`). Chrome: подтверждённое исправление
перед ⌘⌥Z, точные восстановленные текст/каретка/source/флаг, обучение vbh и удаление
только этого исключения; семантическое равенство настроек и yf→на подтверждены.
S8 сохранил оба фрагмента собственного abcdef; S9 совпал с настоящим флагом;
один focus-only переход S10 не отправлял событий. Telegram S5 (clipboard byte gate),
S8/S9/S11 PASS. [Разбор пробника](../research/evidence/mac-agent-p8-2026-10-18/harness-undo-recovery.json).

Первый пробник отмены остановился на foreign_modifier при отпускании Option:
системная очередь ещё не подтвердила его отпускание. Отмена в TypeTune уже сработала,
но пробник не завершил Command-up. Отдельным строго закреплённым пробником отпущен
только его Command: одно событие, текст/каретка неизменны, модификаторы нейтральны.
Теперь собственный модификатор учитывается до подтверждения обеими системными
очередями (ограниченное ожидание с прежними проверками). Повтор S6 PASS.
Это дефект тестового инструмента, не новый дефект TypeTune. Публичные синтетические
шаблоны — Tools/fixtures/matrix/scenarios.json; private поля/названия аккаунтов не публикуются.


## 2026-10-18 — расширение текущей матрицы на GUI 806525181a5b

Agent native, user-authorized; код приложения `3244c81` не менялся. Safari input
S1/S3/S4/S7 и адресная строка S1/S3/S4 PASS. Telegram: S1/S3/S4/S7 и ещё 10 S7
PASS в пустом черновике «Избранного», Return не отправлялся, собственный текст очищен.
Chrome input ещё 10 S7 PASS. Заметки: S1/S3/S4/S11 PASS в новой заметке;
S7 — LIMIT: первое ghbdtn осталось, остальные слова правильные, текст/каретка целы.
Trace rev3860: unreadable, anchored=false, fieldMatches=false — ожидаемый безопасный
пропуск (DECISIONS 26/30), не replay-сбой. UI ready, 0 pending/outstanding/uncertain;
0 faults в сохранённом окне trace. [Матрица](../research/evidence/mac-agent-p8-2026-10-18/matrix.json).

Пробник читает Notes через ограниченный AXStringForRange при отсутствии AXValue;
идентичность поля/окна и все per-event защиты сохранены. Флаг и source ID берутся
из настоящего status item TypeTune. Chrome Single Shift: текст/каретка/source/флаг PASS.
Выделение слова мышью + Double Shift: текст/каретка/source/флаг PASS, тестовая картинка
осталась побайтно той же во всех представлениях clipboard; исходный пользовательский
clipboard восстановлен с readback. Буквальная вставка картинки после этого ещё NOT_RUN.
Общий ClipboardLease вынесен из NativeProbe без изменения защит, обе сборки используют
его; launcher NativeProbe переведён на @main. Offline guard-fixtures 5/5 и native-fixtures
8/8, NativeProbe runtime launch 1/1. Это изменения тестового инструмента, не GUI.

Computer Use запретил доступ к Terminal и Codex (`for safety reasons`); событий туда
не отправляли, обхода не было. Пользователь явно выбрал пропуск Terminal/vim и Codex.
Ранее он также разрешил пропуск отсутствующих Slack, VS Code и Word.


## 2026-10-18 — P8: восстановление очереди и повторная проверка доставки

Пользователь поручил разобрать сохранённый stream-сбой и разрешил продолжение после §2.7.
Очередь восстановлена в исходном synthetic TextEdit-документе без перезапуска/очистки;
текст и каретка до/после совпали, UI «Работает» ([evidence](../research/evidence/mac-agent-p8-2026-10-18/recovery.json)).
Trace старого GUI показывает suspension уже в первой строке, после rev405; последующие
строки были набраны в recoveryPending. Точная причина задержки main callback не доказана.

Код `7c84860`: при единственном отказе leaseFresh=false заново проверяется вся цель,
не более двух повторов. Старое доказательство не используется, срок lease 50 мс не увеличен.
Добавлена длительность просроченной проверки без текста/клавиш. Controller 87/87
([evidence](../research/evidence/mac-agent-p8-2026-10-18/controller.json)), CLI 1439/1439,
корпуса 4420/4420 и 22000/22000 offline. Локальный ci_core остановлен на отсутствии XCTest
в CLT; это не PASS XCTest. Сборка/подпись успешны; GUI `a8b91960280f`, оба прежних
разрешения TypeTune обновлены через системный UI. Первичная native-строка 80 мс PASS.
Первая полная серия на `7c84860` FAIL: с шестой строки нет исправлений. Trace:
replay-event-rejected leaseFresh=false, 1 событие; остальные проверки true. Очередь
восстановлена: текст/каретка совпали. Это уточнило второй участок истечения допуска.
Код `3244c81` повторяет полную проверку также для события, уже подавленного tap до
доставки в приложение; общий бюджет двух повторов сбрасывается только после доставки
или начала новой replay-сессии. Controller 88/88. GUI `806525181a5b`.
Полная native-серия нового GUI: 12/12, 192 слова, точные текст/каретка/source
([вердикт](../research/evidence/mac-agent-p8-2026-10-18/second-full-verdict.json)).
Последние 1000 записей trace: 0 faults, 0 route/event rejected, pending/outstanding/uncertain=0,
UI ready. Ранние записи могли вытесниться; это не полный trace всей серии.
Короткая TextEdit-серия: 11/11, без plain paste и undo-learning.
CI `39143449199` Linux/macOS success на `3244c81`.
Второй полный поток: 12/12, суммарно 24/24 строки и 384 слова с точными текстом/кареткой/source.
Chrome input S1/S3/S4/S7 PASS на том же GUI.
Прежние PASS не перенесены.
Slack, VS Code, Word пропущены по явному ответу пользователя: не установлены.


## Mac agent: подготовка P1 — 2026-10-18

Проверяемый код `adb0283dfe764beeec515f0f183db9e2bdd751c8`, ветка `universal-input`.
Пользователь в этой сессии явно разрешил ввод в Chrome, Safari, Telegram, Slack, VS Code,
Заметки, Word, Codex и Terminal: только пустые поля/черновики по матрице, ничего не отправлять.
Дополнительно разрешил самостоятельно обновлять разрешения. Обе записи TypeTune обновлены
через системный UI, остальные записи не изменялись. Исходный bundle и defaults сохранены
в `research/private/mac-agent-2026-10-18/`.

Release arm64 собран, подпись проверена, установлен GUI SHA-256
`62368559e2dc60853bfe92e24ff6e70190f497222e11f774339063f5bf64bb5f`.
Debug/release CLI: 1439/1439 offline; корпуса v2 4420/4420 и v3 22000/22000;
четыре regression-набора прошли. `ci_core.sh` завершился ошибкой из-за отсутствия XCTest
в CLT; это не полный PASS. Runtime recovery hooks: `passed=true`, без реальных полей;
audit gates 4/4; AXFocusProbe собран. Native P1 пока NOT_RUN.
Evidence: `research/evidence/mac-agent-2026-10-18/`.


Хронологический журнал проверок и решений, новые записи сверху. До 2026-10-17 он вёлся
в docs/STATUS.md и перенесён сюда дословно; текущее состояние — в [STATUS](STATUS.md).
Каждая запись относится к своей версии кода и виду проверки; PASS между записями
не переносится.

## Четвёртый отчёт; агент на Mac снова используется — 2026-10-18

Отчёт сборки `07d55dc` (user manual, сессия `2D3DFDEB…`). Строка поиска Google в Chrome: Double Shift
сработал трижды (`universal-result confirmed`, поле нечитаемо, правка вслепую по п. 30);
автоисправление первого слова после клика пропущено (`anchored=false`). `unreadable-field`:
`focusedField=false` — Chrome не отдаёт поле в фокусе; `web-accessibility`: `unsupported`.
Пользователь вернул агента на Mac (DECISIONS п. 31): инструкция [MAC_AGENT_GUIDE](MAC_AGENT_GUIDE.md),
AX-пробник `scripts/ax_focus_probe.sh` (компилируется в CI
[39137057145](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39137057145)).

## Третий отчёт: Chrome отклоняет AXManualAccessibility — 2026-10-18

Отчёт сборки `9ea6fd7` (user manual, сессия `84ED2F92…`). `web-accessibility` при переходе в
Chrome: `unsupported`. Поле в фокусе находится (`focusedField=true`), но текста и каретки не
отдаёт; слово первое после клика → `unreadable`, `anchored=false`, правка пропущена. Изменено
(DECISIONS п. 30): Double Shift / ⌘⌥Space правят набранное слово без требования границы.
Добавлена запись `unreadable-field`: роль поля и какие текстовые атрибуты оно отдаёт, без текста.
На Mac не проверено.

## Второй отчёт: строка поиска Google в Chrome не читается — 2026-10-18

Отчёт сборки `81b0a28` (user manual, сессия `4838E533…`, 43 записи). Для строки поиска Google:
`universal-boundary` — слово в буфере, решение есть, `anchored=false` (первое слово после клика);
`universal-observe` — `unreadable`; правка вслепую запрещена (DECISIONS п. 26). Фоновое чтение
прежнего механизма тоже нашло поле без текста и каретки и получило `cannotComplete`. Вывод: Chrome
не отдаёт текст веб-поля. Изменено (гипотеза, не проверено на Mac): в универсальном режиме TypeTune
один раз на процесс просит `AXManualAccessibility = true` — при переходе в приложение и при первом
нечитаемом поле; в последнем случае ждёт 150 мс и читает поле снова. Оригинал так не делает
(CARAMBA_REPLACEMENT); это собственное решение. Результат пишется как `web-accessibility`.

## Разбор отчёта пользователя: «защита» после правки в Chrome — 2026-10-18

Отчёт сборки `959cb9f` (user manual, сессия `A9D0814D…`, 385 записей, без текста). Защита
включалась дважды по одной схеме: поле читалось, сверка перед правкой совпала, нажатия ушли,
но за 150 мс поле не показало результат → `mutation-uncertain` и блокировка до подтверждения.
Одно чтение AX в Chrome у пользователя — 30–54 мс; 150 мс хватает на 2–3 чтения. Вывод:
вероятно ложная тревога из-за задержки AX Chrome, порча текста не наблюдалась.
Ещё 139 `snapshot-failed deadlineExceeded` — фоновые снимки прежнего механизма (60 мс) по таймеру
контекста; они занимают ту же очередь AX, что и подтверждение. Double Shift много раз
пропускался: поле нечитаемо и слово первое после клика (`readable=false`, `anchored=false`).
Изменено: подтверждение ждёт до 600 мс; если поле всё ещё показывает ровно прежний текст —
правка не подтверждена, но без блокировки (без отмены, буфер сброшен); блокировка только когда
поле показывает ни прежний, ни новый текст; автодополнение после вставленного текста не мешает
подтверждению; таймер контекста в универсальном режиме не читает поле. На Mac не проверено.

## Тестовая сборка у пользователя: правило работает, строка поиска Google — нет — 2026-10-18

Сборка `959cb9f` (user manual): `пшерги,` → «github,» сработало. Строка поиска Google в Chrome
по-прежнему не меняет раскладку ни автоматически, ни Double Shift; причина без отчёта не
установлена. Добавлена диагностика без текста: `universal-boundary` (токен в буфере, граница,
цель, решение, `anchored`) и `universal-observe` (поле читается, не читается, выделение, пароль).
Найдено чтением кода и исправлено: читаемое поле с выделением (встроенное автодополнение)
считалось нечитаемым и могло правиться вслепую, хотя первый Backspace удалил бы выделение, а не
букву. Теперь это расхождение, правка пропускается. На Mac не проверено.

## Сообщения пользователя: правила и строка поиска Google — 2026-10-18

Сборка у пользователя не указана; по поведению — v0.1.4 (user observation, без отчёта).
1. Правила `yf` → «на», `пшерги` → «github», `дщпштшь` → «loginom» не срабатывают. Ядро выполняет
   правила для слов в другой раскладке: fixtures `corpus/user-rule-regressions.jsonl` 6/6, CI
   [39133863400](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39133863400). Третий источник
   на скриншоте содержит «ш» вместо «щ» («loginom» в русской раскладке — `дщпштщь`) и не совпадёт
   с набранным. Правила молча отключаются выключателем «Автоматически исправлять раскладку RU/EN»,
   паузой и правилом приложения на вкладке «Исключения». Причина для двух других правил в
   приложении не установлена.
2. Строка поиска Google в Chrome: ни автоисправления, ни Double Shift. Прежний механизм намеренно
   не трогает поля с ролью `AXComboBox` (selftest «combo boxes remain blocked»), а строка поиска
   Google — комбобокс. Универсальный режим роль поля не проверяет; шаг 7а чек-листа.

## Ресурсы приложения на чужом Mac — 2026-10-18

Первая тестовая сборка CI показала, что словарь ищется через `Bundle.module` SwiftPM: в корне
приложения и по абсолютному пути `.build` сборочной машины, а `build.sh` кладёт бандл в
`Contents/Resources`. CI-проверка, которая прячет `.build` и запускает приложение, упала с
`Trace/BPT trap` ([39131862546](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39131862546)).
После `CoreResources` (Resources приложения, затем каталог исполняемого файла, затем
`Bundle.module`) приложение работает 8 с без `.build`, selftest 1439/1439
([39132089811](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39132089811)).
Опубликованная v0.1.4 (`package.sh` кладёт бандл так же), по всей видимости, падает при запуске
на любом Mac, кроме того, где собрана; на другом Mac не проверялась. Это вывод из кода и CI,
не наблюдение на Mac пользователя. Тестовая сборка для чек-листа: артефакт
`TypeTune-test-ec87be80…`.

## Проверка на Mac без агента; веб-приложение Chrome — 2026-10-18

По решению пользователя агент на Mac больше не используется (DECISIONS п. 29). CI на macOS
выкладывает тестовую сборку, пользователь проверяет её по [MAC_MANUAL_CHECK](MAC_MANUAL_CHECK.md).

Сообщение пользователя (v0.1.4, user observation): в веб-приложении, установленном из Chrome,
TypeTune не работает, а флаг в строке меню не совпадает с раскладкой. Разбор кода, не native:
прежний механизм разрешает только точные `com.google.Chrome`, TextEdit и Codex, а веб-приложение
Chrome на macOS работает как отдельное приложение-обёртка со своим идентификатором (по устройству
Chrome — `com.google.Chrome.app.<id>`, на Mac не подтверждено). Универсальный режим разрешает
любое приложение. Флаг обновлялся только по уведомлению о смене раскладки и при смене состояния
службы; теперь он сверяет раскладку при смене активного приложения и раз в 0,5 с (гипотеза:
macOS переключает раскладку окна без уведомления). Если флаг всё равно не совпадёт, значит, TIS
сообщает не ту раскладку; это покажет шаг 9 чек-листа.

## Универсальный режим: воспроизведение во всех приложениях — 2026-10-18

Воспроизведение задержанного ввода и смена раскладки после него проверяли прежний список
приложений (`allowedFrontmost`), поэтому в Telegram, Slack, VS Code и других приложениях быстрый
набор во время правки останавливал воспроизведение. Для целей универсального режима теперь
проверяется `universalAllowed()`, для закреплённых AX-полей — прежний список. Найдено чтением кода,
не native-наблюдением. Автоматической проверки нет: пробник не может подменить фронтальное
приложение. Подтверждение — сборка в CI и пункт 5 чек-листа U8. CI на `02c30ed`: Linux и macOS прошли,
сборка без предупреждений, `runtime_recovery_probe.sh` passed, selftest 1431/1431 —
[39130618583](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39130618583).

## Слияние v0.1.4 в универсальный режим — 2026-10-18

`main` с v0.1.4 влит в `universal-input` (`f6736e1`), затем в `snippets` (`fa6c1e2`). CI на macOS 15
arm64 прошёл на обоих коммитах: сборка всех продуктов без предупреждений, `runtime_recovery_probe.sh`
passed, selftest 1431/1431 и 1623/1623, XCTest 14/14 — запуски
[39130142851](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39130142851) и
[39130142574](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39130142574).
Native-проверка универсального режима (U8) не выполнялась; проверки v0.1.4 на Mac относятся
к прежнему механизму.
## Сниппеты: этап S4 (план правки) — 2026-10-18

Ветка `snippets`. Linux offline, Swift 6.0.3: `scripts/ci_core.sh` exit 0, selftest 1604/1604
(38 новых проверок), XCTest 14/14. Проверки нашли ошибку: без `{{курсор}}` каретка уходила
назад через пробел; теперь у шаблона «нет курсора» отличается от «курсор в конце». Намеренная
поломка порога вставки, отмены с курсором и привязки буфера после вставки ловится. Приложение
(macOS) после изменения `TypedWordBuffer` не собиралось: `switch` по причинам сброса в GUI нет.
[Evidence](../research/evidence/snippets-s4-2026-10-18/verification.json).

## Сниппеты: этап S3 (распознавание) — 2026-10-18

Ветка `snippets`. Linux offline, Swift 6.0.3: `scripts/ci_core.sh` exit 0, selftest 1566/1566
(44 новые проверки), XCTest 14/14. Проверки нашли две ошибки порядка разбора пунктуации:
`спс!?` получал суффикс `!,`, а `спсб` срабатывал через двойную смену раскладки; исправлено.
Намеренная поломка левой границы, выключателя другой раскладки и порядка по длине ловится.
Граница — только пробел (DECISIONS п. 28 уточнён). Приложение распознавание пока не использует.
[Evidence](../research/evidence/snippets-s3-2026-10-18/verification.json).

## Сниппеты: этап S2 (шаблон) — 2026-10-18

Ветка `snippets`. Linux offline, Swift 6.0.3: `scripts/ci_core.sh` exit 0, selftest 1522/1522
(60 новых проверок шаблона), XCTest 14/14. Проверки нашли ошибку: комбинируемый знак после
`}}` или `{{` склеивался со скобкой, и разбор или экранирование их не видели; теперь оба работают
по Unicode-скалярам. Намеренная поломка курсора, регистра и пустого буфера обмена ловится.
Движок и приложение шаблоны пока не используют.
[Evidence](../research/evidence/snippets-s2-2026-10-18/verification.json).

## Сниппеты: этап S1 (модель и хранение) — 2026-10-18

Ветка `snippets`. Linux offline, Swift 6.0.3: `scripts/ci_core.sh` exit 0, selftest 1462/1462
(50 новых проверок библиотеки сниппетов), XCTest 14/14. Проверки ловят намеренную поломку
триггера по умолчанию, проверки версии и совпадения в другой раскладке. Движок и приложение
сниппеты пока не используют; GUI не собирался, native не проверялся.
[Evidence](../research/evidence/snippets-s1-2026-10-18/verification.json).

## Первый прогон CI — 2026-10-17

Запуск [39085643742](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39085643742) на `9c44f31`:
оба задания зелёные. macOS 15 arm64, Apple Swift 6.1.2: собраны все продукты, включая приложение,
предупреждений нет — это первая компиляция GUI-изменений этапов 1–7. На macOS selftest 1317/1317,
XCTest 14/14, `runtime_recovery_probe.sh` passed (настоящий KeyboardService, тестовые хуки, без event
tap и без native-ввода). [Evidence](../research/evidence/stage8-ci-2026-10-17/ci-run-39085643742.json).
Native-проверки на Mac остаются открытыми (чек-лист в STATUS).

## Исправления по ревью: этап 9 (README и документация) — 2026-10-17

STATUS переписан в текущее состояние на один экран; прежний журнал дословно перенесён сюда
(48/48 разделов, ни одна строка не потеряна). В PLAN и FEATURES по 6 разделов дословно
повторяли STATUS — заменены ссылкой на журнал. README: поддерживаемые приложения, первый
запуск ненотаризованного релиза, отличие v0.1.3 от `main`, пауза, одиночный Shift по
умолчанию, словарь и аббревиатуры, раскладка «Русская – ПК». Три битые ссылки на `.log`
заменены пометками; 348 ссылок проверены. AGENTS.md указывает на журнал.
[Evidence](../research/evidence/stage9-docs-2026-10-17/verification.json).
Продолжение: чек-лист на Mac в STATUS.

## Исправления по ревью: этап 8 (CI) — 2026-10-17

`.github/workflows/ci.yml`: задание Linux (контейнер `swift:6.0.3-noble`) и задание macOS
(`macos-15`). Общие офлайн-проверки собраны в `scripts/ci_core.sh`: CLI, selftest, корпуса v2/v3,
fixtures, XCTest, audit gates и воспроизводимость отчётов корпуса. Задание Linux воспроизведено
локально в том же контейнере на чистом клоне без Git-идентичности — exit 0. Задание macOS
собирает все продукты (в том числе приложение) и запускает `runtime_recovery_probe.sh` —
**NOT_RUN** до push. [Evidence](../research/evidence/stage8-ci-2026-10-17/verification.json).
Продолжение: этап 9 — README и документация.

## Исправления по ревью: этап 7 (MutationSession) — 2026-10-17

Вид проверки: **Linux offline только для Core**; перенесённый KeyboardService **не компилировался**.
Машина состояний барьера ввода (шлюз мутации, очередь перехваченных событий, цель
восстановления, токены доставки replay) вынесена в `MutationSession<Target, Event>` в Core
и покрыта 46 проверками. KeyboardService переведён на её переходы в коммитах 7b–7g; поля
сессии закрыты на запись, прямых записей в GUI не осталось (проверено поиском).
Единственное изменение поведения: сброс задержанных нажатий после модального окна заново
проверяет, что он применим. Selftest 1317/1317, v2 4420/4420, v3 22000/22000, XCTest 14/14.
[Evidence](../research/evidence/stage7-mutation-session-2026-10-17/verification.json).
На Mac обязательно: сборка GUI, `scripts/runtime_recovery_probe.sh`, native-сценарии replay
и восстановления. Продолжение: этап 8 — CI.

## Исправления по ревью: этап 6 (словарь) — 2026-10-17

Вид проверки: **Linux offline** + независимая оценка на естественном тексте через CLI.
Словарь: 30 022 EN и 30 057 RU слов. Отбор по частотам FrequencyWords, допустимость
по SCOWL и Hunspell ru_RU, защита неоднозначных пар, правило доминирования частоты.
Лицензия словаря CC BY-SA 4.0; атрибуция в README, LEXICON-NOTICE.txt и docs/LEXICON.md.
Полнота на тексте в чужой раскладке: EN 7,2% → **91,8%**, RU 4,6% → **68,7%**.
Ложные конвертации на правильном тексте: 0 → 4,7 (EN) и 8,6 (RU) на 100 тыс. токенов.
Это в основном трёхбуквенные латинские аббревиатуры и имена; пользователь решил оставить
поведение как есть (DECISIONS п. 25).
Движок: `it.` больше не становится «шею», `IDs` не меняет регистр. Selftest 1271/1271,
корпус v2 4420/4420, новый v3 22000/22000 (holdout зафиксирован до прогона), XCTest 14/14,
gates 4/4, fixtures 21/21 + 13/13. Загрузка словаря ~0,1 с; в приложении — фоновый прогрев
(не компилировался). [Evidence](../research/evidence/stage6-lexicon-2026-10-17/verification.json),
[подробности](LEXICON.md). Продолжение: этап 7 — MutationSession в Core.

## Исправления по ревью: этап 5 (таблица из раскладок macOS) — 2026-10-17

Вид проверки: **Linux offline только для Core**. Таблица преобразования теперь строится
из установленных раскладок: InputSources прогоняет UCKeyTranslate по клавишам 0…50
(без Shift и с Shift) для той пары EN/RU, которую выбрал бы select(); Core
(`Layout.Mapping.decoded`) пропускает одинаковые и повторные выходы и принимает таблицу,
только если в ней есть все латинские и кириллические буквы, иначе остаётся авторская PC.
Таблица проходит через Engine, раннее исправление, системный словарь и предпросмотр.
Selftest 1266/1266, корпус 4420/4420, XCTest 14/14, gates 4/4, review 21/21.
[Evidence](../research/evidence/stage5-layout-mapping-2026-10-17/verification.json).
Код InputSources/KeyboardService/SystemVocabulary/SettingsView не компилировался.
На Mac проверить: ABC + «Русская – ПК» даёт ту же таблицу; Apple «Русская» — «ё» и знаки
по реальным клавишам. Продолжение: этап 6 — расширение словаря.

## Исправления по ревью: этап 4 (события мыши, буфер) — 2026-10-17

Вид проверки: **Linux offline только для Core**; изменения KeyboardService не компилировались.
Вне барьера прокрутка и перетаскивание больше не сбрасывают контекст и не вызывают AX-чтение
(барьер по-прежнему их задерживает); удалена недостижимая строка обработки mouseDown.
При 512 задержанных событиях отменяются AX-записи и пишется fault `replay-buffer-limit`;
во время воспроизведения доставка приостанавливается до явного восстановления, ввод не теряется.
Сигнал предела — `InputReplayQueue.reachedPendingLimit`. Selftest 1254/1254, корпус 4420/4420,
XCTest 14/14, gates 4/4. [Evidence](../research/evidence/stage4-events-2026-10-17/verification.json).
На Mac проверить: прокрутку во время набора, выделение перетаскиванием + Double Shift,
быстрый ввод во время replay. Продолжение: этап 5 — таблица раскладки из UCKeyTranslate.

## Исправления по ревью: этап 3 (полная пауза) — 2026-10-17

Вид проверки: **Linux offline**. Новое `Settings.paused` (меню «Автоисправления»,
жест обоих Shift, индикатор Ⅱ, переключатель в настройках) и выключенные
автоисправления программы останавливают все автоматические изменения; ручное
преобразование работает. Прежний контракт «пауза программы сохраняет опечатки
и ё» отменён решением пользователя — DECISIONS п. 22. Сохранённое `automatic=false`
не мигрирует и означает только «раскладка выключена».
Selftest 1250/1250 (матрица паузы 388 проверок), корпус v2 4420/4420, XCTest 14/14,
gates 4/4, review-regressions 21/21.
[Evidence](../research/evidence/stage3-pause-2026-10-17/verification.json).
Меню, индикатор, жест, настройки и SystemVocabulary не компилировались (NOT_RUN на Mac).
Продолжение: этап 4 — события мыши, мёртвый код, предел буфера.

## Исправления по ревью: этап 2 (двойные заглавные) — 2026-10-17

Вид проверки: **Linux offline**. Трёхбуквенные формы с двумя заглавными меняются,
только если исправленное слово известно в одной из раскладок: `IDs`, `PCs`, `GHz`
остаются, `МИр` → `Мир`, `VBh` → `Мир`. Для четырёх и более букв правило прежнее.
Предикат вынесен в `Engine.isDoubleCapitalTypo` и используется статистикой.
Selftest 862/862, корпус v2 4420/4420, XCTest 14/14, gates 4/4, review-regressions 21/21.
Ограничение до этапа 6: `THe` больше не исправляется — слова the нет в словаре.
[Evidence](../research/evidence/stage2-doublecaps-2026-10-17/verification.json).
Изменение статистики в KeyboardService не компилировалось (NOT_RUN на Mac).
Продолжение: этап 3 — полная пауза.

## Исправления по ревью: этап 1 (пунктуация) — 2026-10-17

Вид проверки: **Linux offline**. Таблица раскладки стала данными `Layout.Mapping`
и получила верхний ряд PC (`@#$^&|` ↔ `"№;:?/`). Завершающие клавиши другой раскладки
преобразуются со словом: `ghbdtn/` → `привет.`, `руддщю` → `hello.`; отмена учит слово
без знака (`Decision.learnAs`). Решение и смена `руддщ,` → `hello?` — DECISIONS п. 21.
Selftest 840/840, корпус v2 4420/4420 без изменений, XCTest 14/14, gates 4/4;
review-regressions 15/21 — остались только 6 случаев этапа 2.
[Evidence](../research/evidence/stage1-punctuation-2026-10-17/verification.json).
Изменения KeyboardService и SystemVocabulary не компилировались (NOT_RUN на Mac).
Продолжение: этап 2 — двойные заглавные.

## Исправления по ревью: этап 0 (Linux) — 2026-10-17

Начато выполнение [плана исправлений по ревью](PLAN.md#исправления-по-ревью-2026-10-17).
Вид проверки: **Linux offline** (Ubuntu 24.04, Swift 6.0.3, подпись toolchain проверена) —
ядро, CLI и XCTest. Это не macOS, не GUI и не native-результат.
Package.swift объявляет GUI-таргет только на macOS; в GestureChecks явно указан тип литерала
(на Linux проверка типов не укладывалась в лимит), значения те же.
Сборка CLI, selftest 720/720, корпус 4420/4420, XCTest 14/14 (впервые выполнен), audit gates 4/4.
Новые fixtures corpus/review-regressions.jsonl: 12 дефектов ревью падают до исправления,
9 контрольных проходят. [Evidence](../research/evidence/stage0-linux-2026-10-17/verification.json).
GUI-таргет не собирался (NOT_RUN на Mac). Хеши исходников изменились, поэтому build9
к этому дереву не применим.
Продолжение: этап 1 — физическая пунктуация и таблица раскладки.

## Выпуск v0.1.3 — 2026-10-18

Опубликован [предварительный релиз](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.3),
тег `v0.1.3` → `c62b398ce78c`. В архиве сохранён проверенный build9 `920564da6286`
без пересборки. Подпись, все 75 файлов манифеста, selftest распакованного CLI
и побайтовое совпадение скачанных с GitHub assets проверены.
[Evidence выпуска](../research/evidence/release-v0.1.3/verification.json).
Незавершённые локальные build7 evidence сохранены вне выпуска.
Четырёхчасовой прогон не запускался; полная приёмка остаётся открытой.

## Поток 80 мс и автоотмена — завершено 2026-10-18

Установлен build9, GUI `920564da6286`, исходники `4099b12`, PID 12741.
Убрано дублирующее AX-чтение на keyUp, прежний бюджет 60 мс сохранён.
Поток 80 мс: **12/12, 192/192 слова**, точные text/caret/source.
Автоотмена и последующее действие обученного исключения: **2/2**.
Пользователь удалил только тестовое ghbdtn через UI; исходные settings совпали.
После удаления исправление возобновилось; короткие регрессии **3/3**.
Controller 62/62, release CLI 720/720, корпус 4420/4420.
[Актуальная матрица и evidence](STREAM_2026-10-18.md).
Четырёхчасовой прогон не запускался. Полная стабильность/PLAN не приняты.

## Повторная защита и Unicode — 2026-10-18

Продолжение: [актуальный разбор и проверки](STABILITY_2026-10-18.md).
В сохранённых отчётах установленной TypeTune `3fde69fd918f` найдены два
`mutation-uncertain` после Double Shift. Причина внутри replacement раньше
не записывалась; точный отказавший шаг этих операций неизвестен.
Исправлены преждевременная проверка AX-readback и классификация подтверждённого
восстановления выделения до записи. Добавлена диагностика шага отказа.
Кандидат 0.1.3 (8), GUI `77243f2dbab3`, установлен и запущен (PID 9665).
Unicode 3/3, строгие регрессии 10 мс 3/3, профильный smoke 11/11 прошли.
Дополнительный поток 80 мс выявил один пропуск hello → руддщ; автоотмена
с обучением не проверена из-за недоступности очистки тестового правила через UI.
Настройки сохранены. Стабильность ещё не принята. Четырёхчасовой прогон
явно отложен пользователем; не запускать без нового окна времени.

## Анимация README — 2026-10-18

Обе статичные иллюстрации в README заменены выбранным вариантом «В потоке
текста»: assets/readme/typetune-demo.gif. Две сцены отдельно показывают
пробел и последовательные нажатия одной клавиши Shift со счётчиком.
Проверены декодирование GIF, цикл 12 секунд, локальная ссылка и diff.
Это иллюстрация, не запись приложения; код и установленная сборка не менялись.
Продолжение: прежние открытые условия приёмки приложения ниже.

## Иконка Z / Я — 2026-10-18

Добавлены assets/AppIcon.png и AppIcon.icns; scripts/build.sh включает иконку
в bundle и указывает CFBundleIconFile. Обложка README заменена выбранным
вариантом Z / Я. Release arm64-сборка завершена, подпись и совпадение ресурса
проверены; CLI selftest 720/720. [Evidence](../research/evidence/typetune-icon-2026-10-18/verification.json),
[сборка](../research/evidence/typetune-icon-2026-10-18/build.txt),
[selftest](../research/evidence/typetune-icon-2026-10-18/selftest.txt).
Иконка просмотрена в размере 128 px. Native UI не проверялся, установленное
приложение не заменялось. Продолжение: при установке проверить системное
отображение иконки и прежние открытые условия приёмки.

## README — 2026-10-18

README оформлен как визуальная страница продукта: две авторские сгенерированные
иллюстрации в assets/readme, краткое описание, карточки возможностей,
горячие клавиши и установка. Текст на иллюстрациях просмотрен; локальные ссылки
и diff проверены. История разработки и отчёты в README не включены.
Код приложения не менялся; runtime/UI-проверки не повторялись.
Продолжение: открытые условия приёмки ниже.

## Начальная публикация TypeTune — 2026-10-18

Репозиторий https://github.com/kartamyshev-dev/TypeTune начинается с одного
корневого коммита текущего приложения. Старый проект, его ветки, теги,
релизы, задачи, pull request и сборки исключены из новой публикации.
Исходники приложения сохранены; приватные материалы и незавершённые
локальные stability-build7 evidence в поставку не включены.
Текущие проверки и ограничения приведены ниже и не получают новый PASS
от изменения истории Git. Продолжение: визуальная проверка подзаголовка,
затем открытые runtime/UI условия приёмки.

## Подзаголовок TypeTune — 2026-10-17

В исходниках заголовок «Русская и английская раскладки» заменён на выбранный
пользователем «Чтобы мысли не спотыкались о клавиши». GUI debug-сборка прошла,
diff-check без ошибок. [Evidence](../research/evidence/typetune-tagline.json),
[сборка](../research/evidence/typetune-tagline-build.txt).
Установлен `/Applications/TypeTune.app`, GUI `3fde69fd918f`; 10/10 файлов
совпали, подпись и backup проверены, настройки сохранены. Оба прежних разрешения
обновлены через системный UI, выполнен системный перезапуск.
[Установка](../research/evidence/typetune-tagline-installation.json),
[release-сборка](../research/evidence/typetune-tagline-release-build.txt).
CUA по-прежнему связывает путь с ID удалённого TypeTune; чтение нового окна
и native-ввод NOT_RUN. Продолжение: визуально проверить размещение подзаголовка.

## Переименование в TypeTune — 2026-10-17

Пользовательское имя заменено в заголовке настроек, окне, меню, подсказке,
сообщениях запуска и имени диагностического отчёта; CFBundleName/DisplayName — TypeTune.
Три поясняющих блока про поддерживаемые приложения, Chrome и терминалы удалены
из настроек. Собственный PID исключён из поиска конфликтующих переключателей.
Технические target/module, bundle ID dev.layoutpilot.mac и хранилища LayoutPilot
сохранены ради совместимости настроек, блокировки, ресурсов и terminal socket.

Установлено `/Applications/TypeTune.app`, GUI `318c3d710823`, 10/10 файлов
совпали, подпись и backup проверены. Старые TypeTune и LayoutPilot убраны из
/Applications, их копии сохранены в research/private/typetune-rename-install.
Настройки текущего проекта сохранены; данные прежнего отдельного TypeTune не удалялись.
Путь существующей интеграции в .zshrc обновлён с резервной копией файла.
Оба разрешения обновлены через системный UI, приложение перезапущено, PID82622
указывает на новый путь. [Evidence](../research/evidence/typetune-rename-installation.json).
Release CLI720/720, изолированная проверка конфликтов5/5, diff-check прошёл.
CUA всё ещё связывает новый путь с ID удалённого TypeTune; чтение нового окна
заблокировано, UI/native-ввод и автозапуск после нового входа NOT_RUN.
Продолжение: проверить новое окно и автозапуск после обновления индекса CUA;
не переносить native PASS предыдущей версии.

## Стабильная пауза и выравнивание флага — 2026-10-17

Индикатор Ⅱ зависит только от глобального automatic=OFF, а не от готовности поля.
Приоритет ошибки ! сохранён. Флаг 20 pt опущен на 2 pt через baselineOffset.
Установлен GUI `22547ba38f73`, подпись и совпадение 10/10 файлов проверены;
настройки и резервная копия сохранены. После обновления прежних разрешений
и restart UI показывает «Работает». [Установка](../research/evidence/menu-pause-installation.json).
[Изолированная проверка 16/16 сочетаний](../research/evidence/menu-pause-check.txt),
[окончательная сборка](../research/evidence/menu-pause-alignment-release-build.txt).
Визуальное выравнивание и native-ввод NOT_RUN. Продолжение: оценить новый вид
флага в реальной строке меню; прежние результаты приёмки не переносятся.

## Крупные флаги — 2026-10-17

Флаги увеличены до 20 pt, суффиксы паузы/ошибки оставлены системного размера.
Установлен GUI `e1d6899aca5a`, release-сборка и подпись проверены, 10/10 файлов
совпали с кандидатом; настройки и проверенная резервная копия сохранены.
После обновления прежних разрешений через системный UI и restart — «Работает».
[Evidence](../research/evidence/menu-large-flag-installation.json).
Визуальная проверка строки меню и native-ввод NOT_RUN; прежние PASS не переносятся.
Продолжение: оценить визуальный размер в строке меню.

## Флаг раскладки в строке меню — 2026-10-17

В исходниках LP заменён на 🇷🇺 для русской и 🇺🇸 для ABC/US; прочие источники
показывают 🌐. Обновление — по системному уведомлению смены источника ввода;
суффиксы паузы/ошибки сохранены. GUI скомпилирован, diff-check пройден.
[Evidence и хеш исходника](../research/evidence/menu-layout-flag-2026-10-17.json).
Установлен `/Applications/LayoutPilot.app`, GUI `3a0411ef8d1c`; 10/10 файлов
совпали, подпись и резервная копия проверены, настройки сохранены. Release CLI720/720.
Оба прежних разрешения обновлены через системный UI, после restart — «Работает»,
обработчик подключён. RussianWin восстановлена. [Установка](../research/evidence/menu-flag-installation.json).
Отдельная визуальная проверка флагов в строке меню и native-ввод NOT_RUN;
старые результаты приёмки на эту сборку не переносятся.

## Стабилизация ядра 0.1.3 (6) — первое слово остаётся FAIL

Установлена сборка 6: commit `056afed`, GUI `1ce3e000…`, наблюдённый PID `59875`.
Строгий набор TextEdit — **FAIL первого слова**; Double Shift и поток совпали.
Дополнительный опыт с заранее выбранной ABC остановлен, 0 завершённых случаев.
[Текущая матрица, evidence и продолжение](STABILITY.md): readiness probe 58/58
вошёл в сборку 6, следующий TIS-fix в работе; сборка 7 не собрана.
Широкий smoke, четыре часа и рабочий день — NOT_RUN. Checkpoints ниже исторические.


## Установлена0.1.2: адресная строка Chrome — 2026-10-17

Добавлены auto после пробела и Double Shift для обычных поисковых слов в omnibox.
URL/email/пути/цифры/спецсимволы защищают всю строку; ранний режим и plain-paste
interception здесь запрещены. [Поведение, ограничения и evidence](CHROME_OMNIBOX.md).
Установленный GUI7d6745f6, PID25237; candidate/installed совпадают, подпись проверена,
UI «Работает». Прежняя0.1.1 сохранена и backup проверен. Настройки сохранены.
Release CLI672/672, corpus4420/4420, guard12, gates3, identity17, integrity15, PTY6/6.
Omnibox12 native-наблюдений совпали; IP case остановился на подготовке до клавиш,
не PASS. Webpage single auto/manual и TextEdit auto дали ожидаемый результат.
Это не strict native-suite/длительная приёмка; другие локализации кромеRU/EN
не проверены. Новый ZIP не создавался, рабочая копия не стала чистым коммитом.


Обновлено 2026-10-16. Полный аналог не завершён и не принят.
Прототип экспериментальный. Текущий этап — оставшиеся локальные функции и стабильность.
По указанию пользователя от2026-10-15 проверку настоящего Codex composer
выполняет пользователь самостоятельно. Агент её больше не проводит; это
не считается PASS и не останавливает остальную работу.

## ChatGPT восстановлен после перезапуска — 2026-10-17

Пользователь подтвердил «готово сейчас работает» после физического ghbdtn,
Double Shift и пробела в своём composer. Перед этим перезапущен тот же GUIefd117a0
с временным test.traceInput. Безтекстовый trace содержит2 accepted explicit-context,
3 verified apply-result и3 apply-commit. Это внутренняя телеметрия и пользовательское
подтверждение, не самостоятельная native-приёмка агентом и не точный диагноз
предыдущего сбоя: failing trace до перезапуска отсутствует.
[Trace](../research/evidence/diagnosis-2026-10-17/chatgpt-user-trace.json),
[окончательное состояние](../research/evidence/diagnosis-2026-10-17/final-state.json).

Диагностика полностью выключена: test.traceInput удалён (до опыта ключ отсутствовал),
приложение штатно перезапущено, UI «Работает / Готово». Обычное auto ON, ранний режим
OFF из-за отдельного воспроизведённого дефекта. Подпись/бинарник/разрешения не менялись.
В Chrome пользовательское ghbdtn наблюдалось в адресной строке — она намеренно
не обрабатывается; собственная textarea auto/Double Shift дала ожидаемый результат.
Собственная тестовая вкладка закрыта, HTTP fixture server остановлен.

Точное продолжение при повторении: получить ограниченный failing trace до перезапуска,
сравнить наличие snapshot/explicit-context и события tap. Не выдавать эффект перезапуска
за доказанную причину и не считать ранний defect единственным объяснением прежнего
сообщения. Доступ инструмента CUA к ChatGPT запрещён; не обходить ограничение.

## Chrome и ChatGPT: ранний режим — 2026-10-17

На установленном GUIefd117a0 сбой Chrome воспроизведён в собственной локальной
textarea: helper type-wrong при earlyCorrection=ON дал `приdtn  ` вместо `привет  `.
После выключения только раннего режима через UI тот же сценарий дал `привет  `;
выделенное слово + Double Shift + два пробела также оставило `привет  `.
[Сравнение](../research/evidence/diagnosis-2026-10-17/chromium-early-comparison.json),
[новая runtime-fixture](../Tools/fixtures/chromium/early-regression.json).
Это AX-наблюдения результата, не проверенный exit дочернего helper/strict suite.

Непосредственная причина воспроизведённого дефекта — экспериментальная замена
незавершённого слова в Chromium; точная ветка гонки suffix/replay/source ещё не
трассировалась. Ранний режим оставлен OFF, обычное automatic ON. Код, подпись,
разрешения, словарь и пользовательские исключения не менялись; пересборки нет.
Это обход дефекта конфигурацией, не исправление самого экспериментального режима.
До отдельного исправления/проверки не включать ранний режим для обычной работы.

Установленное `/Applications/ChatGPT.app` имеет bundle ID `com.openai.codex`,
который уже разрешён и использует keyboardEvents backend, как Chrome.
Отсутствие allowlist для ChatGPT не подтвердилось. По указанию пользователя
composer проверяет он сам; native ввод агента туда не выполнялся.
Пользовательский повтор в привычных Chrome/ChatGPT полях не помог. Основная жалоба
не устранена; ранний дефект — отдельная проблема. В Chrome наблюдался ghbdtn в
адресной строке, которую политика намеренно запрещает. Доступ CUA к com.openai.codex
отклонён инструментом по safety reasons; не обходить отказ другим UI-драйвером.
Исторический этап: для ChatGPT была запущена временная безтекстовая диагностика test.traceInput=ON;
исходное значение отсутствовало. Новый diagnostic session A550CC8C…, пользователь
сам вводит ghbdtn/Double Shift/Space. После опыта удалить только test.traceInput и
штатно перезапустить тот же установленный бинарник; не оставлять trace включённым.
Постоянный общий отказ исключён только в проверенном TextEdit-сценарии;
остальные пропуски быстрого потока и F07 остаются открытыми.

## Диагностика сообщения «перестало работать» — 2026-10-17

Установленный GUIefd117a0 совпадает с installation evidence, PID17088. UI «Работает»,
AX/Мониторинг ввода/отправка разрешены, события приходят, других переключателей нет.
Auto/early включены, app exclusions пусты; trace/delay отсутствуют. На этой версии
в новых TextEdit-документах два ограниченных наблюдения совпали: ghbdtn+Space→привет+Space,
seeded ghbdtn+Double Shift→привет, включая каретку и RussianWin. Исходная ABC восстановлена
helper, оба тестовых документа закрыты. Код и настройки не менялись.
[Evidence](../research/evidence/diagnosis-2026-10-17/diagnosis.json).

Общий отказ не воспроизведён. Сообщение «Контекст ещё не подтверждён» указывает на
отказ cached snapshot при ручной операции, но не доказывает причину сообщения пользователя.
Пользователь уточнил: оба механизма не работают во всех приложениях. Следующее —
сопоставить настоящий ввод с синтетическим: открыт пустой тестовый документ CF39ADC4…,
helper отправил0 клавиш; baseline счётчика101. Пользователь физически набрал ghbdtn+Space
и подтвердил «привет »; AX readback совпал, счётчик143, исправления5522→5523, RussianWin.
[Физическая проверка](../research/evidence/diagnosis-2026-10-17/physical-input.json).
Постоянный общий отказ не воспроизведён. Запрошен конкретный неудачный host/слово/жест.
Нельзя считать синтетические два успеха доказательством приёма физической клавиатуры. Terminal native пока не разрешён отдельно; Codex composer проверяет пользователь.
Это два runtime-наблюдения, не strict suite/полная native-приёмка. OpenViking transient
fetch failed восстановился: health и повторный find успешны.

## Установка0.1.1 — 2026-10-17

LayoutPilot установлен в `/Applications/LayoutPilot.app` и запущен оттуда.
Release CLI626/626, PTY6/6; подпись и побайтовое совпадение файлов candidate/installed
проверены. [Evidence](../research/evidence/install-2026-10-17/installation.json).
Предыдущий dist сохранён в private/install-2026-10-17/previous-080bd487.zip.
В пользовательский .zshrc добавлен отдельный блок LayoutPilot, прежние байты
сохранены в private; интеграция применяется в новых вкладках Ghostty/Terminal.
Настройки приложения не менялись. Версия собрана из рабочей копии, без release ZIP.

UI показывает0.1.1 и приостановку из-за Универсального доступа. Обновление прежней
записи TCC потребовало Touch ID; пользователь подтвердил. Дальнейшее UI-обновление
заблокировано ошибкой `Sky Computer Use native pipe startup failed` (три попытки,
включая reset сессии). Работа обработки после подтверждения не проверена.
После подтверждения: удалить прежнюю запись, добавить `/Applications/LayoutPilot.app`,
обновить только его запись Мониторинга ввода и перезапустить. Затем проверить UI.
Native terminal/Chrome/TextEdit на этой сборке NOT_RUN; прошлые PASS не переносятся.

## Терминалы — работа продолжается

Подготовлена отдельная интеграция локального zsh для Ghostty и Terminal.
Обычная AX-замена в терминалах остаётся запрещённой. CLI626/626 и PTY6/6;
native-проверка не выполнена; установка0.1.1 завершена, см. выше.
[Механизм, ограничения и точка продолжения](TERMINAL_INTEGRATION.md).

## Исходники после повторного аудита — 2026-10-16

Исправлены все три замечания: точное UTF-16 сравнение снимков вместо канонического
String equality; привязка CLI/его внешнего словаря к build identity; общая
пунктуационная политика в Replay. CLI/GUI скомпилированы, CLI617/617,
editor guard12/12, Python gates3 + identity17/integrity15, corpus4420/4420.
[Разбор, evidence и точное продолжение](AUDIT_ROUND2_FIXES.md).

Рабочий dist080bd487 ниже не заменялся; это новые исходники без новой native-приёмки.
Следующее: окончательная сборка и её собственные Chrome/TextEdit/Unicode проверки,
после них быстрый поток и F07. Старые native PASS не переносятся.

## Текущий рабочий app — восстановление Chrome, 2026-10-16

GUI `080bd487db570e070b8a52ada9a5e3f1df403e7c98b4417557d73491a463cd1d`,
рабочая копия от `ae319d6d2e9c`. Исправлены однострочные web-поля Chrome;
отсутствие Мониторинга ввода отдельно приостанавливает обработку и объясняется
в UI. После обновления обеих записей TCC app запущен из `dist/LayoutPilot.app`.
CLI608/608, Store34/34, lock4/4, Python gates2 + identity17/integrity15,
авторский corpus4420/4420. Chrome10/10 ограниченных runtime-наблюдений;
TextEdit13/13 совпадений текста/source/caret. Это не strict-suite/длинная сессия.
[Разбор и точное продолжение](BROWSER_INPUT_FIX.md),
[identity/readback](../research/evidence/browser-single-line-2026-10-16/verification.json).

Настройки восстановлены, тестовое ghbdtn удалено из обучения, RussianWin
восстановлена, модификаторы нейтральны, trace/delay отсутствуют, early OFF.
Другие переключатели остановлены. Новый ZIP не создавался.
Следующее: быстрый поток и Chrome rich F07, затем новая длительная проверка
этой сборки. Реальный Codex оставлен пользователю; полная готовность PLAN открыта.

## Исправления пяти замечаний аудита — исходный checkpoint, 2026-10-16

Повреждённые настройки сохраняются без перезаписи, обработка и редактирование
блокируются. Второй экземпляр отклоняется до Store/event tap. Общая политика
пунктуации теперь учитывает исключение полного токена; слово для отмены/обучения
остаётся без завершающей пунктуации. Native-валидатор требует успешного процесса,
identity и подтверждённого отпускания модификаторов. Упаковка проверяет полный
набор исходников/ресурсов, а не только старый список хешей.

Проверено на рабочей копии от `ae319d6d2e9c`: сборка CLI/GUI, CLI594/594,
Store34/34, межпроцессная блокировка4/4, два Python-теста проверочных скриптов
с положительными и отрицательными сценариями, прежние identity17 и integrity15;
авторский корпус4420/4420. Корпус и словарь не изменены.
[Разбор пяти исправлений](AUDIT_FIXES.md),
[команды и результаты](../research/evidence/audit-fixes-2026-10-16-checks.json),
[хеши проверенных исходников](../research/evidence/audit-fixes-2026-10-16-sources.json).

В этом checkpoint выполнялись только offline/изолированные проверки и компиляция;
это не native-приёмка. Позднее рабочий dist обновлён, см. текущий статус выше.
XCTest в CLT отсутствует; его PASS не заявляется. Старые результаты ниже
относятся только к указанным в них исходникам и бинарникам.

Непокрытый остаток аудита: отдельная UI-проверка повреждённых настроек и отказа
запуска рядом с прежней версией; изолированные проверки Store/lock выполнены.
F07, пропуски быстрого потока и остальные условия PLAN остаются открытыми.

## Проверенная сборка38a0d4fd — native до исправлений аудита

Source `7e0ad86b4e3b8caa4b37c13866fb8b0c029ec899`; компилируемые файлы совпадают
с коммитом: [identity](../research/evidence/gesture-fix-build-identity.json).
Release CLI584/584, авторский корпус4420/4420. Native: диагностический prefix3
при delay80 прошёл3/3; после удаления trace/delay и restart обычный TextEdit13/13,
Chrome plain/rich wrong/correct/stream20/manual→Space8/8. Удаления слов после
пробела в этих ограниченных сценариях нет. Настоящий Codex проверяет пользователь.
[Описание исправления](GESTURE_REPLAY_FIX.md),
[TextEdit](../research/evidence/gesture-fix-textedit-verification.json),
[Chrome plain](../research/evidence/gesture-fix-chrome-plain.json),
[Chrome rich](../research/evidence/gesture-fix-chrome-rich.json).

Дополнительный F07 paste rich на этой сборке FAIL: текст не вставился,
исходное содержимое сохранилось; handler identity не доказан. Clipboard полностью
восстановлен, модификаторы нейтральны. Старый intermittent F07 остаётся открытым;
не выдавать8/8 основных Chrome-сценариев за F07 PASS.
[Evidence](../research/evidence/gesture-fix-paste-rich.json).

Длинная сессия завершена:1968.28сек (32мин48сек),1000 отдельных случаев плюс100
длинных последовательностей. Строгая проверка identity/integrity/telemetry PASS;
980samples, max gap2.121сек. [Итог](../research/evidence/native-session-gesture-fix-38a0d4fd/summary.json),
[проверка](../research/evidence/native-session-gesture-fix-38a0d4fd/verification.json).
В corpus1000/1000 expected:520 исправлений,480 сохранений, false corrections0,
misses0; контроль300/300. [Качество](../research/evidence/gesture-fix-native-quality.json).
Это авторский корпус, не независимая языковая оценка и не новое сравнение Caramba.

Быстрый поток: integrity100/100, но полностью исправлены59/100 последовательностей;
51 из1600 слов остались неисправленными. Это открытый недостаток качества, не PASS
всех исправлений. [Отдельные метрики](../research/evidence/gesture-fix-stream-quality.json),
fixture corpus/native-fast-stream-v1.json. Медиана CPU3%, peak13.4%; peakRSS86496KiB.

Архив dist/LayoutPilot-0.1.0-a840f0415c12-arm64.zip создан из неизменной проверенной
сборки.60 файлов manifest, подпись, extracted CLI584/584 и идентичность bundle
проверены. Извлечённый app перенесён в тот же разрешённый путь dist/LayoutPilot.app,
запущен; новый PID85874. После запуска ghbdtn→привет с пробелом прошёл в TextEdit
и Chrome rich. [Архив](../research/evidence/gesture-fix-archive-verification.json),
[итоговое состояние](../research/evidence/gesture-fix-final-state.json).

40 повторов четырёх исторических train-пропусков завершены40/40. LayoutPilot
оставлен работать, original остановлен, исходная RussianWin восстановлена,
модификаторы нейтральны; trace/delay отсутствуют, early OFF. Настройки совпадают
с состоянием перед longrun. [Полный отчёт](VERIFICATION_2026-10-16.md).

Точное продолжение: исследовать пропуски corpus/native-fast-stream-v1.json и
нестабильный F07 на отдельных синтетических полях. Не выдавать текущую проверку
за полный parity, тест настоящего Codex или приёмку всех приложений. При новом
изменении GUI потребуется новая сборка и соответствующая повторная проверка.

## Исправление жизненного цикла жестов — сборка перед native

На GUI ba8e8277 обычный TextEdit smoke завершился, но Single Shift и выделенное
ручное исправление пропустились. Управляемый prefix3 при AX delay80 повторил
сбой: release Option ушёл в FIFO, распознаватель продолжал считать Option
нажатым. Исправление сбрасывает только жесты/Shift timer при перехвате, replay
и recovery; текущие flags защищают от сочетания с реально удерживаемым другим
модификатором. [Описание и before evidence](GESTURE_REPLAY_FIX.md).

Новый исходный код: CLI584/584 и15 offline harness checks PASS; native после
исправления ещё не запускался. Оба переключателя остановлены. Следующее:
собрать из чистого коммита, обновить только AX-запись LayoutPilot, тот же prefix3
с delay80, затем обычные TextEdit/Chrome и длинный прогон на неизменной сборке.
Тестовые trace/delay временно сохранены для строгого before/after; ранний режим OFF.

На ba8e ранний экспериментальный режим: обычный набор9 имеет пропуск первого
минимального ghb; delayed suffix6/6 и anchor2/2 прошли, в trace подтверждены
verified rollback/catch-up. Это разные условия, общий PASS раннему режиму не дан.
[Первый набор](../research/evidence/accelerated-early-native.json),
[delayed suffix](../research/evidence/accelerated-early-delayed-verification.json).

## Ускоренный пакет 16 октября — перед новой GUI-сборкой

Последняя проверка нового ядра:584/584 CLI-инвариантов; авторский корпус4420/4420,
контрольные JSONL не менялись. Evidence accelerated-final-cli-selftest.txt и
accelerated-final-corpus.txt. Store22/22 на коде с новым ранним флагом; новая
граница процессов4/4 — replay-stats-process-probe.json. Новый GUI пока не принят.

Реализованы percategory statistics, bounded catch-up projection; fresh identity-only
AX proof перед каждым FIFO event, отдельная recovery projection только ACK-prefix;
экспериментальный opt-in partial classifier и verified inverse rollback/catch-up
при поступившем suffix. Эти изменения требуют новых native-проверок вместе;
старые PASS944f не переносятся. [PARTIAL_LAYOUT_DETECTOR](PARTIAL_LAYOUT_DETECTOR.md),
[REPLAY_PROJECTION](REPLAY_PROJECTION.md). Остаточные AX→delivery TOCTOU и best-effort
catch-up cancellation остаются открытыми, не объявляются абсолютной защитой.

REA/Ghidra восстановили F01 partial/complete lookup markers, lowercase/original
passes, overlapping byte-pattern collection и scalar minimum; веса/словарь
не переносились. F14 initializer callbacks оказались статистикой. Отдельные12
native Backspace-опытов не воспроизвели автоматическую отмену/обучение, User Rules
остались0 строк. Это bounded negative, не доказательство отсутствия обучения.
[Исследование F01](F01_TIMING_FOLLOWUP.md), [F14](F14_FOLLOWUP.md).

Новая согласованная backup redb (closed writers, byte stable) и SQLite (backup API,
integrity_check) проверена: accelerated-quiescent-backup.json. После F14 original
штатно остановлен, redb побайтно восстановлен, исходная раскладка подтверждена;
функциональные настройки не менялись. accelerated-f14-verification.json.
Сейчас оба переключателя остановлены перед сборкой; финалом нужно включить LayoutPilot.

Safari: только read-only профили2 полей PASS. Пользователь отказал в native вводе;
не запускать его и не переносить Chrome PASS. Собственная вкладка/сервер закрыты.
Native drop F19 заблокирован возможностями CUA cross-window drag; sound decoding
не является audibility. [OTHER_HOSTS_PREPARATION](OTHER_HOSTS_PREPARATION.md),
[SETTINGS_NATIVE_PREPARATION](SETTINGS_NATIVE_PREPARATION.md).

Длинный harness теперь привязывает bundle/resources/helper/PID-start и отклоняет
невалидные/неполные результаты с exit1;14 tamper/session checks PASS, native0.
Точное продолжение: собрать один GUI из записанного коммита; обновить только его
AX-запись; обычный TextEdit/Chrome + early opt-in и delayed suffix, восстановить
настройки. Затем решать финальную1000/30мин/p95 приёмку. Полный parity не достигнут.

## Последний проверенный checkpoint944f9cce

GUI SHA-256 `944f9ccec18becc8fb72e2ca991582443aa7231ee21ff0399f5cd04e76707455`.
[Идентичность сборки](../research/evidence/replay-stats-build-identity.json).
На этой сборке: CLI451/451, авторский корпус4420/4420; изолированный Store22/22;
TextEdit smoke13/13; Chrome plain/rich — wrong/correct/stream20/manual→Space,
всего8/8 в обычном режиме. Это ограниченные проверки, не полная приёмка.
[Chrome plain](../research/evidence/replay-stats-chrome-plain.json),
[Chrome rich](../research/evidence/replay-stats-chrome-rich.json),
[TextEdit](../research/evidence/replay-stats-textedit-verification.json).

Реализованы отдельные категории статистики с восстановленными default-весами;
UI проверен отдельно: [evidence](../research/evidence/replay-stats-ui-verification.json).
Добавлена ограниченная проекция доставленных replay-событий с проверкой точного
текста/каретки; её ограничения перечислены в [REPLAY_PROJECTION](REPLAY_PROJECTION.md).
Новые успешные Chrome-прогоны не закрывают прежние пропуски или F07.

В конце этого прохода включён только LayoutPilot944f9cce, original остановлен.
`test.traceInput` отсутствует, синтетическое learned-исключение ghbdtn удалено.
[Настройки и миграция](../research/evidence/replay-stats-migration-readback.json).
Новый ZIP не создавался. Исторические состояния ниже не описывают текущий запуск.

**Точное продолжение и сокращение повторной работы:**
1. Один свежий guarded F07-опыт в каждом собственном Chrome-поле; не повторять
   неудачную вставку вслепую. Проверить сохранение новой статистики после restart.
2. Продолжить восстановление F01/F14 и адаптеры других hosts. Для новых native
   targets сначала подготовить конкретные ограниченные helpers; существующее
   разрешение NativeProbe относится только к TextEdit.
3. Группировать изменения, сначала проверять ядро без GUI-пересборок; затем
   проверять итоговую сборку. Длинные1000/30мин/p95 — после функциональных изменений.
4. Полный parity, replay при смене поля, F07 и финальная приёмка остаются открытыми.
   Настоящий Codex composer агент не проверяет.

## Checkpoint94aa34c2 (ночь15→16октября)

GUI SHA-256 `94aa34c27022489f534b67c765b7abdb99b7aaf701865d1b03a4279ab2fe065d`.
Точный bundle и compiled sources:
[whole-token-final-identity](../research/evidence/whole-token-final-identity.json).
Не объявляется полной приёмкой.

- Release CLI352/352, авторский corpus4420/4420. Контрольный JSONL не менялся.
- TextEdit:16 F17,5 punctuation/file/code,3 seeded LF/TAB/emoji/NFD+undo,
  smoke13 и узкийShift2 прошли. Evidence `whole-token-{caps,punctuation,smoke,shift}-verification.json`
  и `whole-token-selections/verification.json`.
- REA/Ghidra восстановили F17 model veto и stages case→layout→spelling.
  Самостоятельная реализация больше не требует положительного словаря для
  doublecaps; veto facebook/iphone/MHz — собственное приближение.
- Выделение теперь снимается после ручного преобразования, caret в конце.
  Original защищённые clipboard-опыты подтвердили LF/TAB/emoji/NFD и caret.
  Старые неправильные ожидания/FAIL сохранены. [SELECTION_RESEARCH](SELECTION_RESEARCH.md).
- Native доказал отдельный GUI-риск: до whole-token fix `ABc.txt`/`ABc;def`
  менялись ещё на точке/semicolon, хотя CLI guard проходил. Теперь auto ждёт
  whitespace и проверяет целый token;5/5 новых native PASS. Это намеренное
  отличие по моменту срабатывания от ранней модели Caramba.
- Chrome normal plain: wrong/correct PASS; stream20 дважды оставил второе слово
  `ghbdtn`, сохранив все символы/каретку. `whole-token-chrome-plain.json`,
  ранее `f17-selection-chrome-plain.json`. Trace-on standalone stream20 прошёл;
  он не отменяет FAIL. Queued replay bypass анализа — source-derived гипотеза,
  точная runtime-причина ещё не доказана.
- Chrome manual plain/rich: actual ghbdtn→selected6→DoubleShift→привет caret6→
  дваSpace→привет caret8 прошли, modifiers neutral, без clipboard/Return.
  `whole-token-manual-chrome-{plain,rich}-ack.json`; это trace-on проверки.
  Первая попытка до ACK остановилась на AX precondition; FAIL сохранён.
- F07 source/private/HID и plain/multi/normal/incognito контроли дали как FAIL,
  так и PASS без изменения production path. Причина не установлена; слепого retry нет.
  [NATIVE_PASTE_INVESTIGATION](NATIVE_PASTE_INVESTIGATION.md).
- F01: ранний gate/модельные categories/iterator раскрыты; native ghb→при доSpace.
  Самостоятельный early classifier ещё не реализован. [F01_TIMING_FOLLOWUP](F01_TIMING_FOLLOWUP.md).
- F14: manual upsert→context.save и visible-filter/exact-membership восстановлены;
  automatic learning не восстановлено. [F14_FOLLOWUP](F14_FOLLOWUP.md).
- F13:8 events→5 countercategories, increments и default-веса времени раскрыты;
  текущая реализация ещё использует собственную общую оценку2сек.
  [STATS_RESEARCH](STATS_RESEARCH.md).

Сейчас включён только LayoutPilot94aa34c2. Original остановлен, bundle70entries
неизменен (`whole-token-original-integrity.txt`); его настройки этого прохода
не менялись. Тестовый learned ghbdtn убран через UI. `test.traceInput` временно ON
для Chrome stream; журнал только boolean/timing. Перед передачей удалить ключ
и перезапустить app. Новый ZIP не создавался.

**Точное продолжение:**
1. Bounded selection ACK и manual→Space в обоих Chrome fields проверены;
   повторить обычный режим после отключения trace, не касаясь Codex.
2. Зафиксировать trace stream, различить skipped replay boundary и capture lag;
   catch-up projection сначала проверить отдельно, не ослаблять AX/FIFO guards.
3. Добавить percategory статистику по восстановленным local defaults, затем
   F01 самостоятельный classifier/остальные hosts и полную конечную приёмку.
4. После native завершения восстановить trace/settings/source и сохранить новый
   проверенный checkpoint. Реальный Codex ввод выполняет пользователь.

## Предыдущий проверенный checkpoint6a93cdc9

Рабочий GUI `6a93cdc9bbf1aff55c5fcab3c525d9b62a13f6aa16b7601da167f445c52eed5e`,
bundle SHA `fd91372a5a3904a4754df2d3531eaf3f03745327496dabdca307fb996bad27e1`.
[Идентичность исходников/resources](../research/evidence/short-caps-build-identity.json),
[ограниченная проверка](../research/evidence/short-caps-limited-verification.json).

- Найдено и исправлено отдельное расхождение оригинала: `ПРи → При`.
  Причина — отсутствующее общеупотребительное слово в собственном словаре.
  Original4/4; до изменения prototype3/4, после изменения4/4. CLI313/313,
  авторский corpus4420/4420; контрольный JSONL не менялся. [CORPUS](CORPUS.md).
- Новый TextEdit smoke13/13 и узкий Shift2/2 прошли; на предыдущем5d6a
  два gesture-сценария пропустили действие. Их причины не установлены, результаты
  сохранены. Повторный PASS не объявляется исправлением этих пропусков.
- Chrome6/6 word cases: correct/wrong/20words в обоих полях, дополнительный
  Space не удаляет слова. Выполнены в обычном режиме после удаления test.traceInput.
- Chrome: один write synthetic clipboard на блок, plain20/20 + rich20/20,
  точный курсор/LF/TAB/clipboard; следующий Space в обоих полях тоже PASS.
  Но первый самостоятельный plain block пропустил вставку. F07 открыт.
  Независимые стандартные команды Chrome и опыт без LayoutPilot также дали
  пропуск. Callback/token race Chromium — source-supported гипотеза,
  не доказанная runtime-причина. [Расследование](NATIVE_PASTE_INVESTIGATION.md).

В конце этого исторического checkpoint LayoutPilot был включён, original и другие известные switchers остановлены.
Тестовый trace-key удалён, own ghbdtn-исключение убрано через UI, global auto,
Single Shift/plain paste ON; sound/Option/chord/systemDictionary OFF;
временных Chrome app rules нет; header blue/light/noimage, custom sound очищен.
[Восстановление](../research/evidence/short-caps-settings-restored.json).
Native wrapper теперь привязывает evidence ко всему bundle, а не только executable.

REA: новый закрытый main-пакет восстановил фиксированную CmdShiftV option и
cached sound reset; arbitrary recorder UI всё ещё unknown:
[HOTKEY_RESEARCH](HOTKEY_RESEARCH.md). Framework-пакет установил цвет/контраст/
fileURL/TIFF image persistence/remove; собственные F18/F19 добавлены в реестр.
Store25/25 и native picker/restart/reset на803c проверены; это не переносится
на6a93. Native drop и audibility не приняты. Оригинальный bundle70 entries
неизменен; проверка paste-stage-original-integrity.txt. Новый ZIP не создавался.

**Точное продолжение:**
1. Cached-only F17 пакет закрыт: [DOUBLE_CAPS_RESEARCH](DOUBLE_CAPS_RESEARCH.md);
   missing model gate2dfeb4 — следующий узкий REA запрос.
2. Для F07 отделить свежий clipboard/внутренний Chrome sequence от nativeкоманды:
   воспроизводимый один-write контроль уже имеет40 PASS, первый свежий FAIL
   оставлен открытым; не добавлять слепой повтор вставки.
3. Добавить opt-in boolean/timing stages gesture→enqueue→TIS, воспроизвести
   исторические2 gesture-пропуска; без доказательства не менять пороги/guards.
4. Продолжить F01/F05/F14 и адаптеры других приложений. Затем новый1000/30мин/p95
   на одном конечном bundle. Реальный Codex composer и вся приёмка PLAN открыты.

## Исторический checkpoint803c1fab: оформление проверено, вставка расследуется

Dist GUI `803c1fabd98114a552701b07d6d4f13e5c7d7b8db9d136826002f1cd2b84520f`.
Добавлены собственные цвет/контраст и изображение заголовка, импортер fileURL/TIFF,
хранилище своих копий. UI: color/contrast/image import/restart/reset прошли;
исходные synthetic PNG/WAV не изменены. Выбор/рестарт/сброс собственного звука
проверены отдельно, слышимость не заявляется. Evidence: header-pilot-ui-verification,
sound-pilot-ui-verification. Настоящий Store прошёл25/25 runtime-инвариантов,
phase3-header-image-store-probe.json; это не native drag/drop-приёмка UI.

ВАЖНО: новый803c НЕ наследует native PASS425e44e3. Повтор CmdShiftV в rich
дважды не вставил текст; поле осталось пустым, clipboard восстановлен, все6
frames и neutral modifiers прошли. Evidence header-phase-paste-rich.json и
header-phase-paste-rich-diagnostic.json. Наблюдаемый отказ безопасен для текста,
но функциональная проверка НЕ пройдена. GUI сообщает пропуск/прерывание.
Причина ещё не установлена: диагностика пока показывает только один успешный
AXFocused read86.8мс, не доказывает timeout или отказ posting access.

Временно включён собственный `test.traceInput` (до этого absent), GUI перезапущен.
Он пишет только время/boolean, без текста. Готовится более точная диагностика
gate/native-paste stages; после окончательной проверки удалить только этот ключ
и перезапустить app. Сейчас запущен только LayoutPilot803c, оригинал остановлен.
Source содержит ещё не собранную строку Lab «Отправка клавиш»; новый stage logging
готовится агентом. Следующее действие: закончить instrumentation, собрать,
обновить только запись LayoutPilot AX через UI, увидеть точный отказ, исправить
его с сохранением guards/deadline; затем все native retests и clean checkpoint.

Оригинал: через REA framework восстановлены25-cycle/resetOrange/titlecontrast,
TIFF/fileURL image persistence/remove; [UI_FRAMEWORK_RESEARCH](UI_FRAMEWORK_RESEARCH.md).
UI cycleOrange→Red/resetOrange иwhite→black проверены, исходный вид возвращён.
Default color иheaderTitleWhite теперь явно сохранены; byte-identical prefs не
заявляются. HeaderImage оригинала не менялся. Двойные заглавные original4/4:
header-phase-original-double-caps-verification.json. Полное покрытие не завершено.
Параллельный REA main-проход1bf170/239bc ещё исследует recorder/звук.

## Предыдущая проверенная сборка425e44e3

### Проверки425e44e3

GUI SHA-256 `425e44e3be9a2832aac60fd91bc950e7e88be3c4309a1b9650393b3b26e3facc`.
Release CLI309/309 и авторский корпус4420/4420 отдельно прошли.
[Build identity](../research/evidence/phase3-handshake-build-identity.json) содержит
хеш каждого исходного файла; после native они повторно совпали.

На этом же GUI выполнены15/15 ограниченных Chrome native cases:
plain/rich — CmdShiftV LF/TAB, точный курсор, сохранение всех items/types/data
clipboard, следующий Space; correct/wrong/20words в обоих полях; timeout2.3с
без вставки; app off/on, global off поверх app on, ё при global off.
Rich formatting indicator absent; отдельный обычный CmdV control — present.
UI приложения подтвердил обе вставки и сообщение отмены по тайм-ауту; recovery
не потребовался. [Native verification](../research/evidence/phase3-handshake-native-verification.json).
Global off и Chrome app on сохранились после restart; затем global on возвращён,
только временное правило Chrome удалено. Другие известные switchers отсутствуют.

Новый обработчик Chromium ждёт фактически полученные V-up, Cmd-release,
Shift-release и neutral flagsChanged вместе с текущим глобальным neutral.
До этого нет mutationGate/синтетической команды; тайм-аут2с, новый ввод,
фокус/разрешения/clipboard отменяют ожидание, после него полный AX recheck.
Предыдущие1b92f4c5/800d263f остановки plain не скрыты: external_modifier_pressed;
прямая причина чужого modifier не доказана. Один global-neutral poll оказался
недостаточным для стабильного native опыта; explicit release handshake прошёл.
Baseline без switchers: все6 frames/neutral, CmdShiftV не вставляет; false oracle
в baseline — ожидаемое наблюдение, не PASS вставки. Пользователь восстановил
Cmd/Shift/Option, нейтральность подтверждена read-only до нового прогона.

TextEdit smoke13/13 на новом синтетическом документе прошёл на том же425e44e3:
text/source/cursor/clipboard/undo precondition и neutral modifiers проверены
phase3-handshake-textedit-verification.json. Source/helper identity неизменна.
Созданное undo-исключение ghbdtn удалено через UI, остальные настройки сохранены.
Новый settings-проход REA закрыт:11pseudo+6ASM, export118; callbacks reset/header
и конкретная native CmdV команда установлены, focusEN — только repeated schema
field. [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md). Следующее действие:
проверить доступ к цвету заголовка оригинала через UI и закрыть F18.
Настоящий composer Codex, остальные редакторы,1000/30мин/p95 для этого бинарника
и полное покрытие PLAN ещё не приняты. Новый ZIP не создавался.

## Третий проход исследования и app policy


Исследованы ресурсы и новые тела функций REA на закреплённой arm64-копии.
Результаты: [STORAGE_RESEARCH](STORAGE_RESEARCH.md), [PHASE3_STATIC](PHASE3_STATIC.md),
[UNDO_RESEARCH](UNDO_RESEARCH.md), [INPUT_ORIGIN_RESEARCH](INPUT_ORIGIN_RESEARCH.md).
Установлены exact String Set для исключений и путь временной замены clipboard
в оригинале; семантика обучения и полный алгоритм пока не установлены.

Через UI оригинала добавлены и удалены только синтетические `lpfixture` и правило
Chrome. SQLite readback подтвердил additions=0/disabled=0/visible=1 для слова,
enabled=0/1 для приложения; после удаления обеих тестовых записей нет.
Перед опытами сохранён новый согласованный SQLite backup; установленный bundle
не менялся. Global auto оригинала возвращён во включённое состояние.
Evidence: phase3-backup-check.json, phase3-original-word-{add,removed}.json,
phase3-app-rule-{off,on}.json, phase3-original-restored.json.

В LayoutPilot реализованы отдельные off/on правила автопереключения по bundle ID
и совместимое чтение прежних Settings JSON. На промежуточном GUI SHA-256
`f3c47452372d4eeab3ace9c317337c2e3919ff43ab50b19262e7ddc4ef7fea90`
проверены app off, app on, приоритет global off и работа ё при global off,
а также UI/readback сохранения global off/app on после перезапуска.
Затем возвращён global on и удалено только временное правило Chrome.
Evidence: phase3-pilot-{app-off,app-on,global-off-app-on,yo-while-global-off}.json.
Это не перенос native PASS на последующую сборку.

Контроль происхождения ввода: без переключателей private/HID дают `ghbdtn `;
с единственной Caramba и одинаковыми настройками оба дают `привет `.
Раннее различие источников не воспроизведено. Оригинал после контроля остановлен.
Evidence: phase3-origin-baseline-{private,hid}.json и
phase3-origin-original-{private,hid}-control.json. Подробности в INPUT_ORIGIN_RESEARCH.

Вставка без форматирования: прежний CmdShiftV fallback Chrome не сработал,
что сохранено как неуспешный опыт. Нативная Chrome CmdAltShiftV вставила
многострочный текст с TAB и сохранила все типы/data clipboard; это пока проверка
команды браузера, не нового адаптера LayoutPilot. Новый адаптер написан, но ещё
не собран в dist и не принят native. Исходники CLI260/260 и GUI compile отдельно.
Следующее действие: завершить узкое подтверждение пустого contenteditable,
собрать новый GUI, обновить только его AX-запись через UI, проверить production
CmdShiftV в обоих полях и повторить коррекцию/второй Space на том же бинарнике.

### Новый кандидат вставки: частичный результат и найденная гонка

GUI `1b92f4c5c8d45ffb1eaaa79ee8a1d2535a3b48d7a54c20a9f34566ee28e484a6`
собран и AX обновлён через UI. Release CLI272/272; корпус4420 отдельно.
Rich: CmdShiftV вставил LF/TAB, курсор20/0, UI подтвердил вставку, DOM-fixture
показал отсутствие форматирования. Контроль обычного CmdV показал наличие
жирного красного оформления. Исходный clipboard все items/types/data сохранён
и восстановлен только при неизменном собственном поколении. Следующий Space,
wrong/correct и20слов rich прошли. Подробности phase3-paste-candidate-verification.json.

Plain-попытка НЕ прошла: helper external_modifier_pressed. Предполагается наложение
исходного HID CmdShiftV и внутреннего CmdAltShiftV; прямой trace обеих
последовательностей пока отсутствует, поэтому причина не считается доказанной; следующие plain-проверки
также остановились active_modifiers. Эти отказы не скрыты и не являются PASS.
Пользователь отпустил клавиши, GUI остановлен. Исправляется ожидание исходного
отпускания перед native-paste; guards не ослабляются. После изменения требуется
новая сборка, AX refresh и повтор обоих полей на одном бинарнике.

## Предыдущий checkpoint: исправление Chromium

Новая сборка app SHA-256 `e1c52501a439acf1fe71c594275d95903a7f8c56f2016a49fbbd8567c61c0dec`.
На отдельной странице Chrome воспроизведён no-op AXSelectedText с оставленным
выделением и удалением слова следующим Space. Новый Unicode-event адаптер
рабочего AccessibilityEditor проверен: исправление, точный курсор, no-op и
следующий пробел без потери слова. Chrome и Codex снова включены в policy;
реальная native-приёмка composer Codex ещё не выполнена. Переписка не затронута.

Проверено с запущенным GUI, e1c52501: contenteditable и textarea Chrome —
`ghbdtn` + Space → `привет `; `hello` + Space → `hello `; следующий Space
не удаляет слова, курсор после двух пробелов, выделение0. Дополнительно в каждом
поле сохранены все20 слов непрерывного ввода и последний дополнительный пробел.
Итого6/6 ограниченных native-сценариев. Другие известные переключатели отсутствуют.
Разрешение текущего app обновлено через системный UI после Touch ID пользователя.
LayoutPilot показывает «Работает» и по явному запросу оставлен включённым.

Evidence: chromium-gui-verification.json, chromium-gui-{plain,rich}-*.json.
App не пересобирался после этих проверок. CLI222/222, guard7/7, corpus4420/4420
относятся к этому же GUI-коду; это отдельные offline-проверки.
Точное продолжение общей задачи: отдельная native-приёмка реального composer
Codex, TextEdit-регрессия нового бинарника и оставшиеся критерии PLAN.
Chrome-проверка не заменяет приёмку Codex или длительную устойчивость.
Подробности: CODEX_TEXT_LOSS.md, CARAMBA_REPLACEMENT.md.

## Историческое ограничение CODEX-001: потеря слова после пробела

Пользователь сообщил: в поле текущего разговора Codex слово выделяется и
удаляется после Space; конкретное слово неизвестно, «все слова» — предположение.
Самостоятельного воспроизведения нет. При первом осмотре LayoutPilot уже не
работал; остановку процесса агентом не заявляем.

Защитное изменение: обработка клавиш, AX-снимки и замена теперь разрешаются
только для com.apple.TextEdit. Codex/ChatGPT/браузеры/неизвестные приложения
отклоняются до выделения и подавления горячих клавиш. Снятие пользовательского
исключения не расширяет этот список. Добавлены положительные проверки TextArea,
идентичности окна и фактического выбранного текста перед записью. AX settable
не считается самостоятельным доказательством совместимости редактора.

Текущий dist/LayoutPilot.app с защитой, SHA-256:
`86ff47a1e80bbb9ab5e8ebd3ce5e4ff66af92a72e440c72abf721a953ed62af7`.
CLI debug/release212/212, corpus4420/4420, production-entry probe6/6: неподдержанные
hosts отклонены до current-check/AX. Это проверка защитного входа, не live-тест
Codex и не native TextEdit-приёмка нового бинарника. Старые native PASS ниже
на эту сборку не переносятся. App собран и подписан ad-hoc, оставлен выключенным;
при завершающем осмотре другие известные переключатели тоже не работают.

Архив3be783b не содержит защиты: не использовать его для продолжения тестирования
в Codex. Новый архив пока не создан. Подробности: [CODEX_TEXT_LOSS](CODEX_TEXT_LOSS.md),
research/evidence/codex-loss-containment.json. Поддержка замены в Codex остаётся
незавершённой; требуется отдельный проверенный адаптер и синтетический сценарий
без вмешательства в эту переписку. Текущая авторизация NativeProbe — только TextEdit.

## Исторический checkpoint до CODEX-001

Исполняемый GUI ac35b53, SHA-256:
`b911718f071b06d166c09a2648fa67cc21fe6c7d84651ae1ef1b6c8a88773957`.
Последующие коммиты меняют помощник, fixtures и документацию, не GUI.

- Исправлены преждевременный AX capture до появления введённого суффикса,
  потеря транзакции отмены при replay keyUp и восстановление точного источника
  после отпусканий. Неизвестные modifier frames не считаются отпусканием.
- Helper моделирует нажатие/отпускание физических модификаторов и фиксирует
  нейтральное конечное состояние. Перед каждым событием все прежние проверки
  цели/разрешений/Secure Input сохранены; общий300мс срок не ослаблен.
- CLI204/204 и авторский корпус4420/4420: modifier-frame-selftest/corpus.txt.
  Корпус не независимая языковая оценка; XCTest не заявляется.
- На этом GUI: native smoke13/13, четыре train-пропуска40/40, controls6/6,
  один Unicode/emoji/NFD-case. Текст, источник, курсор и специальные условия
  clipboard/undo проверены по fixtures; modifier cleanup подтверждён.
- Плотный RU/EN-поток остановлен после6 завершённых фраз; все6 исправлены.
  Диагностический повтор с измерением AX остановлен после2; профилированный —
  после4. AXCannotComplete около150мс, не мгновенный отказ. Это НЕ12/12/30мин.
- Без переключателей12/12 и с пассивным LayoutPilot12/12 завершены, AX timeout
  отсутствует. Поток опечаток без смены языка завершён12 случаев,191/192
  исправлены, один пропуск сохранён в corpus/native-typo-observed-misses.json.
- Sample TextEdit показывает синхронный XPC в обработке смены источника;
  LayoutPilot — selectSource/selectVerified. Это свидетельство пути ожидания,
  не доказательство конкретного взаимоблокирования. Все raw profiles private.
- Диагностика GUI opt-in, ограничена1000 записей времени/булевых признаков,
  без текста/keycodes/имён документов. Обычный trace off: файлы/mtime неизменны.
- Проверены сохранение и повторное открытие отдельного Ghidra project новым
  процессом без import/analysis: target/function digest и marker совпали.
  REA session save остаётся unsupported; metadata backups Ghidra изменились,
  основные DB-файлы идентичны. Полнота анализа не заявляется.
- Установленный оригинал:70 entries без изменений.

Доказательства: [INPUT_TIMING](INPUT_TIMING.md), [GHIDRA_PROJECT](GHIDRA_PROJECT.md),
research/evidence/modifier-frame-*.json, ax-duration-*.json, ax-profile-*.json.
Остановленные опыты сохранены; успешные короткие проверки не заменяют длительную
или межприложенную приёмку. Старый архив3173cfd сохранён без перезаписи.

**Результат длительного запуска:** paced80-barrier остановлен через252,73сек,
129/1000 завершены и совпали с ожиданиями; курсор129/129 соответствует UTF16.
Следующий случай остановлен AXCannotComplete.126 telemetry samples,30мин НЕ
выполнены. Startup barrier решил только ожидание начального фокуса; устойчивость
не доказана даже при interval80. Эталон и другие версии helper отдельно.

**Новая экспериментальная поставка:**
`dist/LayoutPilot-0.1.0-3be783b6fe0f-arm64.zip`, исходный чистый коммит
`3be783b6fe0f0445d87ce007c7995a67bb1bbf76`.
SHA-256: `726bdba04ab6def1927aae5925bc1754a1652a73a42e002d38e99305c4c7d3f5`.
Проверены32 файла MANIFEST, arm64/deep strict ad-hoc, CLI204/204,
запуск именно распакованного приложения и preview ghbdtn→привет.
Весь app bundle побайтно равен b911718f, поэтому ограничения его native-проверок
сохраняются без подмены кандидата. Старый3173cfd архив побайтно сохранён.
Нотариализация/публичный релиз не выполнялись. [DELIVERY](DELIVERY.md).

**Восстановлено после проверок:** LayoutPilot/Caramba/TypeTune остановлены,
Lang Switcher снова единственный переключатель, PID58019 проверен по точному
пути. RussianWin, neutral modifiers, Secure Input false. Настройки прототипа
исходные, тестовые исключения/rules/learnedWords пусты, trace/delay keys отсутствуют.
Оригинал70 entries без изменений. Тестовые документы не закрывались вместе с
личными окнами. Счётчик прототипа содержит тестовую активность.
Доказательства: delivery-3be783b6fe0f-verification.json, restoration-after-3be783b.json.
Документы внутри архива относятся к исходному коммиту до проверки извлечения;
этот итоговый readback добавлен следующим docs-коммитом.

**Точное продолжение:** изучить задержки синхронного XPC в обработке TIS у
TextEdit. Не увеличивать timeout и не убирать gates ради формального PASS.
Нужна проверенная стратегия работы с системной задержкой; затем новый полный
native1000/30мин на одном бинарнике. До этого завершённая короткая приёмка
ограничена13/40/6/Unicode/12 фразами, прототип experimental.
Независимый корпус, строгий оригинал с единым helper, correction-only p95,
Safari/Electron/терминал, смена фокуса во время replay, Secure Input/сон/реальный
вход также остаются открытыми.

## Историческая проверенная поставка

Результаты далее относятся к старому коду ae3f565 и поставке3173cfd. Они не
переносятся на текущие изменения. Восстановление Caramba ниже — прошлый этап;
актуальное состояние процесса указано в checkpoint выше.

## Реализовано

Самостоятельный Swift/AppKit/SwiftUI arm64 .app: RU/EN, ручное преобразование
слова/выделения, независимые авто/опечатки/ё, Shift/Double Shift/Option/оба Shift,
отмена и обучение исключения после отмены, plain paste, правила/исключения,
меню/настройки, звук, регистрация автозапуска. Ограниченный собственный словарь
и необязательный NSSpellChecker (по умолчанию off). Покрытие: FEATURES/SPECIFICATION.

Предыдущий проверенный исполняемый код: ae3f565b39a319825b7cdae8dbebc4746940f0a5.
Native executable SHA-256:
102ad5b5e8326662751a31947a51183481a38e366b1c475db67967433e139791.
Результаты следующего раздела относятся к этому историческому бинарнику.
Для текущих изменений старые native PASS не переносятся; новый digest фиксируется
в native-load-after-route-cache/summary.json и дальнейшем checkpoint.

## Выполненные проверки

- CLI selftest140/140, CLI8/8; synthetic-v2 train3094/3094, holdout1326/1326.
  Корпус в основном создан из того же словаря: не независимая языковая оценка.
  XCTest отсутствует в CLT; XCTest PASS не заявляется.
- Исторический кандидат ae3f565: native smoke13/13, ручная отмена с промежуточной заменой,
  Unicode/emoji/NFD, controls6, исключение TextEdit, буквальное правило и приоритет
  исключения слова. Clipboard/выделение/источник проверены в соответствующих cases.
- R01 (перестановка букв в прежней сборке) исправлен FIFO/ACK и частным CGEventSource.
  Повтор кандидата delay80: 20/20 сохранность, 17/20 полные исправления. Старые
  ошибки сохранены. Диагностический ключ удалён перед штатными проверками.
- Native1000: прототип516/520 ожидаемых исправлений, 480/480 ожидаемых сохранений;
  оригинал518/520 и283/480. Всего203 различия классифицированы; четыре пропуска
  прототипа остаются открытыми, corpus/native-observed-misses.json. COMPARISON
  объясняет собственные ожидания и различавшиеся версии помощника оригинала.
  Условное совпадение holdout не закрывает общий критерий языкового качества.
- Сессия2170,29сек (36мин10сек): 1000 сравнительных случаев +167 длинных фраз.
  167/167 без нарушения oracle сохранности; только104/167 полностью исправлены.
  1080 снимков ps, максимальный разрыв2,071сек, тот же PID жив после окончания.
  CPU median29,1%, peak52,3%; peakRSS115056KiB. CPU требует оптимизации.
  Это синтетический ввод с короткими служебными паузами, не физический ввод человека.
- NSSpellChecker отдельно: native6/6, включая новые слова/опечатку и URL/цифры;
  standalone13/13 +9/9 guard checks. Этот режим не включён в основной benchmark.
- AX отозван между операциями: ввод сохранён без коррекции; разрешение возвращено,
  коррекция работает без перезапуска. Отзыв во время AX-операции не проверен.
- Автозапуск: регистрация on→off и readback UI; реальный вход не проверен.
  Оформление «Светлое» сохранилось после перезапуска; возвращено «Как в системе».
- Установленный оригинал: повторная проверка70 entries — без изменений bundle.
  REA6.5.0/Ghidra12.1.4/JDK21; snapshot replay проверен. Подробнее RESEARCH и FOLLOWUP.

## Историческое состояние после поставки3173cfd

LayoutPilot завершён. Системный словарь, Option, Shift-chord и звук выключены;
авто/опечатки/ё, Single Shift и plain paste включены. Тестовые правила, исключения,
обученные слова и диагностический ключ удалены. Автозапуск off, тема system.
Helper status: событий0, RussianWin, Secure Input false, Shift/Ctrl/Option/Command
не удерживаются. Caramba восстановлена после проверки архива.

Поставка: dist/LayoutPilot-0.1.0-arm64.zip, исходный коммит
3173cfdb2c8d53b94050a5419544285e67d72af4. SHA-256 архива:
e67f2ae3bb0ca600a600810d8794f29ecb451b1e883fbd6da04fb04e3aca7d76.
Извлечены и сверены27 файлов MANIFEST, arm64, deep strict ad-hoc подпись,
CLI140/140 и открытие именно извлечённого .app. Встроенный preview ghbdtn→привет
проверил загрузку ресурса. Бинарник равен native-кандидату байт в байт.
Нотариализация/публикация не выполнялись. Полное evidence:
research/evidence/delivery-verification.json; инструкция — DELIVERY.md.
Документы внутри архива относятся к исходному коммиту до проверки извлечения;
данный итоговый статус и внешний verification добавлены последующим docs-коммитом.

Оригинал Caramba запущен снова; прототипы завершены. UI option/chord/off,
plainPaste/on совпадают с исходными; RussianWin подтверждена status-only helper,
активные Shift/Ctrl/Option/Command отсутствуют. Повторно проверены70 файлов bundle.
Счётчик прототипа содержит синтетические тестовые исправления; личная БД оригинала
не откатывалась. Тестовые документы сохраняются в игнорируемой research/private.

Точное продолжение: получить ответ о расширении helper на Safari/Cursor/Terminal;
проверить фокус/replay и отзыв разрешения во время операции до объявления широкой
совместимости. Отдельно воспроизвести четыре train-пропуска с трассой решений,
оптимизировать CPU, подготовить независимый корпус и измерение correction-only p95.
Для static extractor0x1002e0030 в RESEARCH_FOLLOWUP записаны два недостающих REA
запроса; тело в текущем snapshot отсутствует. После изменений кода не переносить
на него результаты ae3f565: новые native-проверки и идентичность обязательны.

## Открытые ограничения

Полный набор локальных функций/первоначальная настройка оригинала, извлечение
признаков, веса модели, конфликтующие правила и семантика обучения не восстановлены.
Собственная замена не выдаётся за восстановленный исходный алгоритм.
NSSpellChecker зависит от локальных словарей и может задержать главный поток.

Не выполнены: независимый языковой корпус, строгий повтор оригинала на едином
помощнике, correction-only live p95, Safari/Electron/терминал, Secure Input,
отзыв во время замены, сон/пробуждение и реальный автозапуск после входа.
Расширение помощника за пределы TextEdit ожидает ответа пользователя.
Слишком быстрый ввод/неподтверждённый AX-контекст безопасно пропускают коррекцию.
Смена поля/приложения во время доставки replay-пакета не проверена; глобальные
CGEvents не имеют атомарной привязки к AX-полю. Мягкий timeout/overflow и RAM-only
recovery описаны в DECISIONS. Совместимость за пределами macOS27.0.1/arm64 не заявлена.

REA6.5 provider удаляет временную Ghidra базу. Отдельный .gpr save/reopen
проверен новым workflow: GHIDRA_PROJECT; REA snapshot — другой результат. SQLite backup согласован,
согласованность live-копии redb не доказана. Личные данные — research/private,
они не включаются в Git/поставку. Статистика оригинала от опытов не откатывалась
слепым восстановлением личной базы; его настройки не менялись.

## Исследование проекта на текущем Mac — 2026-10-18

Исходники `bcaf82a297be2abc03f71cf4dc13f56129c00ba3`, рабочее дерево до проверки чистое.
macOS 27.0.1 (26A434), arm64, Swift 6.4. Локальная debug-сборка CLI: exit 0;
selftest: 1317/1317, 0 failures. Два предупреждения линковщика об отсутствующих
путях CommandLineTools сохранены в [evidence](../research/evidence/mac-study-2026-10-18/verification.json).
GUI, XCTest, корпус и native-ввод в этом проходе не проверялись. Установка,
разрешения, настройки и активные переключатели не изменялись.
Продолжение: release-сборка и selftest, затем чек-лист Mac из STATUS; этапы 4, 5, 7
остаются открытыми. Четырёхчасовой прогон остаётся отложенным.

## Локальная release/native-проверка bcaf82a — 2026-10-18

Собран и установлен arm64-кандидат, GUI SHA-256
`bff09d98ebab7e97f1172c0e623a6e870ae8046af2aa0196115364ab0b532668`.
Selftest 1317/1317, корпуса 4420/4420 и 22000/22000; controller 62/62,
audit 4/4. XCTest заблокирован отсутствием модуля в CLT.
Native: smoke 4/4, pointer/typo 3/3, пауза, отмена/обучение, первое слово,
поток 80 мс 10/10 с точным текстом/кареткой/раскладкой. Пробник расширен
ограниченными scroll/drag-сценариями; его decoder tests 6/6.
Первый потоковый прогон отклонён из-за изменения исходника помощника во время
прогона; PASS относится только к `native-stream80-final.json`.
PC-таблица 70/71: Shift+key50 даёт Ë и в UCKeyTranslate, и в TextEdit.
Диагностическая задержка 150 мс + ввод 10 мс: качество FAIL, удержаны 10 событий;
UI отмены и подтверждения сброса проверен. Настройки/статистика восстановлены
точно, диагностический ключ удалён, переключатели остановлены.
[Подробный отчёт](MAC_ACCEPTANCE_2026-10-18.md),
[машиночитаемый результат](../research/evidence/mac-acceptance-2026-10-18/verification.json).
Полная приёмка и положительное native-восстановление не заявляются.

## Удержание, ⌘⌥R и Apple «Русская» — 2026-10-18

Кандидат bcaf82a, GUI bff09d98ebab (полный SHA в отчёте), продуктовый код не менялся.
Apple «Русская» 8/8 native TextEdit: обе стороны, ё/Ё, отличия grave/tilde;
текст/каретка/source/identity проверены. NativeProbe расширен явными Russian/recover,
fixtures decoder 7/7. Восемь коротких recovery-попыток не удерживали очередь.
Длинный ввод с задержкой AX 150 мс воспроизвёл 10 pending: verified через 196,24 мс,
повторное чтение с общим deadline 200 мс не подтвердило контекст. При возврате точного
префикса и каретки ⌘⌥R начала replay, но завершилась replay-suspended до forward;
повтор тоже не доставил ввод. Положительное восстановление FAIL, причина конкретного
routing/identity guard требует дальнейшей диагностики.

Оставшиеся 14 синтетических событий очищены через UI. Настройки/статистика восстановлены
точно, исходные раскладки и скрытое меню ввода возвращены, модификаторы нейтральны,
все переключатели остановлены. Четырёхчасовой прогон не запускался.
[Полный отчёт, evidence и точка продолжения](MAC_RECOVERY_2026-10-18.md).


## Исправление удержания и положительное ⌘⌥R — 2026-10-18

Локальная изменённая копия поверх bcaf82a, установленный GUI
`0f6d2a79a8690e5f183c9808ef2400d14752b0a2724a7c1279d32b80a13c4738`.
Убрано повторное чтение после verified; операция/обратная замена и завершение
привязаны к исходной раскладке; временный AX-отказ identity повторяется в ограниченном
бюджете, проверки адресата и безопасности сохранены. Добавлена диагностика отказов.

Native TextEdit: удержанная очередь доставлена по ⌘⌥R (pending 4 → 0),
длинный поток с AX-задержкой 150 мс прошёл. Обычный поток 80 мс — 10/10,
Apple «Русская» — 8/8, review smoke — 7/7. Обычный поток 10 мс остаётся FAIL качества:
текст 7/10, текст/каретка/source вместе 1/10. Controller 64/64, CLI 1317/1317,
корпус v2 4420/4420, fixture tests 8/8 — отдельные offline/hooks проверки.

Исходный replay-suspended bff09d98 не удалось приписать конкретному guard;
ограниченный положительный тест не доказывает отсутствие всех гонок macOS.
Настройки/статистика восстановлены точно, ABC+PC и текущая PC возвращены,
меню ввода скрыто, все переключатели остановлены. Четыре часа не запускались.
[Подробный отчёт и evidence](MAC_RECOVERY_FIX_2026-10-18.md).

## Быстрый ввод 10 мс и конечная раскладка — 2026-10-18

Исправлен непрерывный поток: завершённые слова сохраняются до свежей полной
AX-сверки после паузы 150 мс; обычный разделитель учитывает начатое до снимка слово.
Конечная раскладка учитывает последнее известное неизменённое слово. Контекст нового
окна обновляется при простое; неудачные чтения и отменённый readback очищают старое
состояние. Собственная смена раскладки отложена до завершения pinned-source проверки,
что сохраняет одиночную отмену с обучением. Защитные условия и бюджеты не ослаблены.

Кандидат `f1d7539f9d4531767706567979a25a51535dc4d7a0012ec55279940f709efbfe`
установлен и сверен с dist и текущими исходниками; подпись проверена. Изменённая
рабочая копия поверх `bcaf82a`, без коммита и публикации.

На этом бинарнике: native TextEdit requested interval 10 мс **20/20** в двух новых
документах; mixed **6/6**; smoke 80 мс **7/7**. Проверены текст, каретка и source.
Одиночное исправление + ⌘⌥Z **1/1**, с обязательным исправленным состоянием до жеста
и обучением только `ghbdtn`. Тестовое исключение удалено через UI; настройки сверены.
Offline CLI **1336/1336**, corpus **4420/4420**, controller hooks **65/65**,
защитные отказы **17/17**, audit gates **4/4**, native fixtures **8/8**.

Исходные настройки и статистика восстановлены с точным plist readback, RussianWin
и нейтральные модификаторы подтверждены, все переключатели остановлены.
[Отчёт и промежуточные неудачи](MAC_FAST_FIX_2026-10-18.md),
[сверка](../research/evidence/mac-fast-fix-2026-10-18/validation.json),
[восстановление](../research/evidence/mac-fast-fix-2026-10-18/restoration.json).
10 мс — пауза harness плюс защитные проверки, не измеренный интервал доставки.
Четырёхчасовой прогон не запускался. Native ⌘⌥R и Apple «Русская» предыдущей сборки
не перенесены на эту; Chrome, терминалы, XCTest и полная приёмка остаются отдельно.

## Итоговая сборка: восстановление, Apple Russian, Chrome, терминалы — 2026-10-18

На неизменённом GUI `f1d7539f` выполнены последующие короткие проверки.
⌘⌥R PASS: удержаны четыре события, семь replay-подтверждений с отпусканиями жеста,
queueEmpty и drained; точные текст/каретка/source. NativeProbe получил только
170 мс паузы внутри уже ограниченной interruptRecover-fixture; guards сохранены,
pure fixture tests 8/8. Приложение не пересобиралось.

Apple «Русская»: 7/8 + 6/8, всего 13/16. Авто RU/EN и физические ё/Ё прошли;
три ручных действия не получили anchor после AX-тайм-аутов. Chrome: семь коротких
случаев PASS по тексту/каретке, поток contenteditable из 20 слов остался без
исправления при exactPrediction=false. Эти дефекты не закрыты.

Native Terminal и Ghostty запрещены инструментом Computer Use; обход не выполнялся.
zsh/vared PTY с mock-сервером 6/6, dispatch helper с mock-политикой 36/36 — отдельные
результаты, не native. Настройки/статистика точно восстановлены; RussianWin,
исходный набор раскладок, скрытое меню и нейтральные модификаторы подтверждены.
Переключатели остановлены, тестовая вкладка закрыта, локальный сервер остановлен.
Четырёхчасовой прогон не запускался. [Отчёт и evidence](MAC_HOSTS_2026-10-18.md).

## Ручное преобразование Apple и поток Chrome — 2026-10-18

Установлен кандидат `6f1d9cc51ab5bdf62efafb510948aba3c9d93234dfafd737de2759a94b396703`.
Сохранено предложение ручного контекста после временного AX-отказа с обязательной
свежей полной сверкой; первая вставка после паузы читается фактически до прогноза.
Apple 16/16, Chrome rich-stream 2/2, TextEdit 10 мс 10/10 + mixed 6/6, ⌘⌥R PASS.
Chrome single: один неподтверждённый insertion-readback и зависимый пропуск;
ручной повтор и четыре auto-повтора PASS. Отказ сохранён отдельной fixture.
Терминалы повторно заблокированы инструментом. Настройки и состояние восстановлены.
Четырёхчасовой прогон не запускался. [Отчёт](MAC_MANUAL_CHROME_FIX_2026-10-18.md).

## Диагностика подтверждения каретки — 2026-10-18, ожидает Touch ID

Добавлены только технические признаки insertion-observation и replacement-preflight,
без текста или ослабления guards. Изолированный production-helper четырежды
завершился notApplied до записи (выявлен deadlineExceeded в preflight);
это не воспроизведение исходного insertion-readback отказа. Изменения helper отменены.
Установлен диагностический GUI `28247d26`; предыдущий `6f1d9cc5` сохранён private.
Обновление прежнего разрешения ожидает системного Touch ID. Native-проверка
диагностического GUI не запускалась; исправление причины пока не выполнено.
Продолжить после подтверждения: завершить refresh AX/Input Monitoring, получить
диагностический failing trace в локальном single-поле, затем исправить и проверить.
Четырёхчасовой прогон не запускался.


## Подтверждение каретки Chrome — 2026-10-18

Диагностический 28247d26 воспроизвёл отказ на single-auto №23: AX отдавал исходный
текст с уже новой кареткой; старое ожидание немедленно завершалось uncertain.
Кандидат bdecb08f разрешает только ограниченное повторное чтение этого состояния
для Chrome. Точный конечный текст/каретка, цель и остальные guard сохранены;
бюджет не увеличен. Новые тесты RED2 → PASS23/23; release CLI1336, corpus4420,
controller70, audit/fixtures12 прошли отдельно.
На итоговом установленном бинарнике Chrome48/48: single-auto40 и соседние8.
Редкое состояние в финальных40 не встретилось; новая ветвь проверена offline.
Настройки/статистика восстановлены точным readback, Русская — ПК, модификаторы
нейтральны, переключатели остановлены. Четыре часа NOT_RUN, публикации не было.
[Отчёт и evidence](MAC_CHROME_CARET_FIX_2026-10-18.md).


## Подготовка v0.1.4 — 2026-10-18

Обновлены метаданные 0.1.4 (10), README и имя архива. Релизная сборка c722c3d7
прошла CLI1336, corpus4420, guard23, controller70, audit4 и fixtures8.
Native PASS кандидата bdecb08f не перенесён на новый bundle. Четыре часа NOT_RUN.
[Отчёт](RELEASE_0.1.4.md).

### Публикация v0.1.4

Код отправлен в main, тег установлен на `39ee28e88270` после зелёного CI Linux/macOS.
ZIP и SHA-256 опубликованы как prerelease; скачанные assets совпали побайтово.
Установленный на Mac кандидат bdecb08f не заменялся. Четыре часа NOT_RUN.
[Evidence](../research/evidence/release-0.1.4/publication.json).

### Остановка Mac agent по §2.7 — 2026-10-18

При подготовке P1 Computer Use typeText получил полный тестовый URL Google,
после Return AX показал `l.cm`. Причина не установлена; это не доказательство
дефекта TypeTune. Дальнейший ввод остановлен; созданная вкладка закрыта,
приватный отчёт сохранён до перезапуска. P1 и прочая матрица NOT_RUN.
Точка продолжения — STATUS; восстановление — evidence/mac-agent-2026-10-18.

### Продолжение и калибровка ввода — 2026-10-18

Пользователь разрешил продолжить до стабильности всей матрицы. При всех
остановленных переключателях CUA typeText снова потерял символы тестового URL.
Вставка URL сохранила строку полностью. Отдельные CUA pressKey дали точное
`ghbdtn ` в Google, но диагностический счётчик TypeTune остался 0. Такой ввод
не квалифицирован для native-проверки системного event tap, FAIL продукту не ставится.
Запрошено явное расширение разрешения NativeProbe за пределы TextEdit с сохранением
всех защит. Результаты: evidence/mac-agent-2026-10-18/input-calibration.json.
AXEnhancedUserInterface у Chrome уже был true после CUA; пробник временно сбросил
его в false, текстовое поле осталось читаемым. Это не чистый cold-start P1.

### Разрешение защищённого ввода всей матрицы — 2026-10-18

На прямой вопрос о расширении NativeProbe за пределы TextEdit пользователь ответил:
«Да, разрешаю для всей матрицы». Сохранены проверки PID, конкретных поля и окна,
фокуса, разрешений и Secure Input перед каждым событием; ввод только в новые
тестовые поля/черновики, без отправки. Разрешение текущей сессии имеет приоритет
над прежним ограничением AGENTS.md. MatrixInputProbe требует начальное пустое
поле с кареткой 0, ограниченный набор клавиш и не умеет отправлять Return.

### Google: ограниченная системная серия — 2026-10-18

Текущий GUI `62368559e2dc` на коде `adb0283`: S1 5/5 в уже читаемом поле
(google-s1-08, google-s1-repeat02…05); S7 10/10, 40 слов, точные текст/каретка/source,
с проверенной очисткой только собственного текста (google-s7-01…10). Интервал
между клавишами включает проверки AX, это не строгая нагрузка 80 мс.
Исходная P1 не закрыта: Computer Use включает расширенный AX-режим Chrome.
В отдельном чистом профиле Chrome `AXEnhancedUserInterface=false`, focused-field
отсутствовал и AXManualAccessibility был unsupported; включение enhanced само
по себе не дало focused-field. Без подтверждённого начального фокуса этот опыт
не доказывает причину P1. Изолированный процесс завершён; основной браузер сохранён.

### Пауза по блокировке Mac — 2026-10-18

Computer Use вернул: Mac locked, automatic unlock unavailable. Ввод остановлен.
Ожидается ручное разблокирование; STATUS и verification/matrix обновлены.
Стабильность всей матрицы не заявлялась; P1 после чистого запуска остаётся открытой.
Настройки/статистика и исходная раскладка будут восстановлены после окончания тестов;
исходные снимки сохранены. Сейчас TypeTune запущен и временная вкладка Google открыта.
Производственный код не менялся. Добавлены MatrixInputProbe и отвергающие
до отправки событий self-checks; финальная версия helper требует ровно один процесс
целевого bundle ID. Native-наблюдения выше получены до последнего ужесточения
проверки числа процессов, на том же неизменённом GUI приложения.

### Продолжение после разблокирования и P3 — 2026-10-18

Пользователь разблокировал Mac и разрешил продолжать всю матрицу. CI `555422d`
успешен. Для прежнего GUI `62368559e2dc`: поиск новой вкладки S1 5/5
(newtab-s1-02…06); input и textarea — S1/S3/S4/S7/S11 совпали; textarea S8
сохранил `abcdef` по обе стороны вставки (каретка 9, длина 13). S8 использует
клавиатурную навигацию в середину слова, мышиный вариант остаётся NOT_RUN.
Rich: S1 текст/каретка совпали, но cleanup остановлен на пустом `<br>` (AX длина 1,
каретка 0); S3/S4 прошли. S7 оставил первое слово `ghbdtn`: trace `decision=false`,
до AX-сверки. CUA-сброс поля не попадает в event tap и оставлял предыдущий токен.
MatrixInputProbe дополнен настоящим Left в подтверждённом пустом поле и проверкой
его неизменности; это подготовка теста, не изменение механизма исправления.

P3: в приватном отчёте серии Google 6 snapshot-deadlineExceeded, 26 подтверждённых
universal-result, mutation-uncertain отсутствует; после следующих тестов 7 таймаутов.
Причина: captureAfterEvent запрашивает legacy-контекст при universalInput=true и
plainPaste=false. Новая проверка controller сначала red, затем green 83/83.
Лишние снимки отключены, при plainPaste=true снимки остаются только для разрешённого
прежнего адаптера. Текстовая сверка universal не изменялась. Native на новой сборке
ещё NOT_RUN. Полное восстановление исходного состояния отложено до конца серии.

Slack, VS Code и Word не найдены системным поиском; вопрос пользователю ожидает
ответа. Их строки матрицы не принимаются без проверки реальных приложений.

### P3: установленный кандидат и ограниченная приёмка — 2026-10-18

Код `d145971243299354edcd86f7d08d01c8ab74e4d0`, GUI SHA-256
`34439d48f36b7d675352a83e51101fb260e91032ede3d80f51806240b7c7bf07`.
Оба разрешения обновлены через системный UI, подпись проверена. CI 39141018700
успешен. Новая серия Chrome: input S1/S3/S4/S7/S11, rich S7 — точные текст,
каретка, source. Отчёт: 6 confirmed, 0 snapshot-failed, 0 faults при plainPaste=false.
TextEdit smoke 13/13 с временным plainPaste=true; затем plainPaste возвращён
и только `ghbdtn` удалён через «Снова исправлять». Семантическое равенство настроек
исходному снимку доказано. Review-набор 12/12. Поток 80 мс ещё выполняется.
Эти результаты принадлежат новому бинарнику; вся матрица и cold-start P1 не приняты.
Evidence: `research/evidence/mac-agent-p3-2026-10-18/`.

### P8: поток 80 мс и истёкшая replay lease — остановка по §2.7

На GUI 34439d48 поток native-stream-80ms-v1 не прошёл: завершённые строки
содержат неисправленные ghbdtn, при совпадающих длине/каретке/source. При обнаружении
серия остановлена SIGTERM только helper native-probe, checkpoint сохранён отдельно;
обёртка закономерно не получила финальный JSON. Данные завершённых строк не выдаются
за полный прогон. После этого UI TypeTune показал recoveryPending и 1 сохранённое
нажатие. Trace: replay-route-rejected с identity/focus/source/permissions=true и
leaseFresh=false. Почему истекли 50 мс и связь остановки helper с итоговым состоянием
ещё не установлены. Дальнейший ввод остановлен по MAC_AGENT_GUIDE §2.7; приложение
не перезапускалось, очередь не очищалась, тестовый документ сохранён.
Evidence: mac-agent-p3-2026-10-18/stream-stopped-analysis.json и stream-diagnostics.json.
Вся матрица остаётся открытой; восстановление исходного состояния ещё требуется.


## UI refresh: безопасная offline-отрисовка — 2026-10-21

Ветка `ui-refresh` создана от обновлённой `main` `2f31167`, рабочая копия до начала чистая.
Изменение: DEBUG `--render-settings` до блокировки/делегата, изолированный suite
`dev.layoutpilot.ui-render`, Store с временными сниппетами, KeyboardService(false),
NSHostingView → bitmapImageRepForCachingDisplay/cacheDisplay → PNG. DEBUG начальная вкладка.
Контракт всех элементов и source-доказательство отсутствия event tap/AX:
[UI_REFRESH](UI_REFRESH.md). Продуктовый дизайн, ядро, KeyboardService и AccessibilityEditor
не менялись. Системные разрешения/установка/синтетический ввод не выполнялись.

Вид проверки: **offline-отрисовка**, общий результат **PARTIAL**.
50 PNG: 4 вкладки × 2 темы × 6 состояний + 2 редактора. Реальные Toggle/Picker/List
видны; репрезентативные снимки просмотрены моделью. cacheDisplay неверно захватывает
сегментированные вкладки; у части снимков содержимое выходит за рамку 740×690.
Фон/NSAppearance и titled-window не устранили артефакт вкладок. Это ограничение захвата,
не доказанный native-дефект. Полная визуальная приёмка не заявлена.
Снимки приватные: `research/private/ui-2026-10-21/before/`, в Git только их хеши.

GUI/CLI debug build на SDK26.5 успешны (у default SDK27 отсутствует SwiftUIMacros).
CLI **1707/1707**, corpus **4420/4420**, shell syntax/invalid label checks успешны.
Настройки пользователя семантически равны исходным, раскладка не менялась;
изолированный suite очищен и удалён. Installed TypeTune не заменён и не перезапущен.
[Evidence](../research/evidence/ui-refresh-2026-10-21/verification.json).
Коммит этой записи определяется через `git log -- docs/UI_REFRESH.md`.
Выбор дизайна ещё не получен; native/user manual NOT_RUN. Следующий шаг — замечания
пользователя по «до», затем 2–3 концепции и явный выбор перед реализацией.


## UI refresh: три концепции боковой панели — 2026-10-21

Пользователь: «Не нравится большая яркая шапка и перегруженность. Хочу спокойный нативный
вид macOS с боковой панелью и компактными формами. Покажи 2–3 концепции, все функции сохрани».
Это направление и разрешение на прототипы; выбор конкретного варианта ещё не сделан.

Подготовлены DEBUG А «Системные настройки» (6 разделов), Б «Компактная панель»
(8 разделов, флажки, звук/автозапуск отдельно), В «Сначала главное»
(4 раздела, пауза в заголовке, DisclosureGroup дополнительных настроек).
Все используют прежние Store bindings/ключи; исключения, сниппеты/редактор и лаборатория
переиспользованы. [Карта функций и границы](UI_REFRESH.md).
Product-формы, меню, Store и input/core-код не менялись. Установка/разрешения/ввод не запускались.
Изображение, цвет, светлая надпись и drop предусмотрены в компактном образце оформления.

Вид проверки: **offline-отрисовка**, результат **READY_FOR_SELECTION**, не native PASS.
Скрипт создал50 прежних и66 новых PNG. Exact-name/dimensions/hash assert прошёл;
репрезентативные main light/dark, оформление, сниппеты, Secure Input и recovery
просмотрены моделью. У Б устранено вертикальное центрирование компактного Form;
явный secondary для символов исправил их контраст на тёмном snapshot;
minHeight0/clipping основного содержимого сохранили заголовок и safety-card при recovery.
Полная визуальная приёмка всех состояний/прокрутки не заявляется.

GUI/CLI debug build SDK26.5 успешны, CLI1707/1707 и корпус4420/4420.
Исходные разделы SettingsView побайтово совпали с99333f2, защищённые файлы не изменены.
Пользовательские defaults семантически равны исходным, раскладка совпала; suite очищен.
[Evidence с SHA бинарника и исходников](../research/evidence/ui-concepts-2026-10-21/verification.json).
PNG: `research/private/ui-2026-10-21/concepts/`, в Git не включены.
Коммит определяется через `git log -- Sources/LayoutPilot/SettingsConcept.swift`.
Native/VoiceOver/клавиатура/resize/drop/user manual NOT_RUN; baseline TabView остаётся PARTIAL.
Продолжение: показать А/Б/В, дождаться выбора, записать выбор и реализовать выбранный дизайн
маленькими коммитами. Слияние, установка и выпуск не выполнялись.

## UI refresh: выбран вариант А — 2026-10-21

Пользователь: «Берём вариант А. Реализуй его в ui-refresh, сохрани все функции и настройки».
Выбран именно А «Системные настройки»: шесть разделов, sidebar, grouped Form,
спокойная шапка и компактный статус. Б/В больше не рассматриваются для реализации.
Сохраняются полный контракт UI_REFRESH, прежние ключи @AppStorage/Store, input/core-логика.
Работа в ui-refresh без слияния/публикации; native/user manual принимаются отдельно.

### Каркас выбранного А

Продвинут в product UI каркас А: sidebar из шести разделов, изменяемое окно1000×740
с минимумом920×640, компактный статус/выход и постоянный отчёт. DEBUG Б/В удалены.
Store/ядро не меняются. На этом промежуточном шаге «Основное» ещё содержит прежний полный
Form; следующий коммит разделит его без дублирования. Результат проверок — в
`research/private/ui-2026-10-21/implementation/`, по SHA каждого коммита, до финального свода.

### Разделы «Основное» и «Клавиши»

Из «Основного» убраны дубли клавиш и оформления; оставлены исправления, звук и автозапуск,
как в выбранном А. Длинное объяснение доступно через DisclosureGroup, предупреждение раннего
режима остаётся видимым. Контролы вынесены в единственные общие блоки с прежними bindings,
повторная исходная форма удалена. «Клавиши» содержит все жесты/выбор раскладки/plain paste.
Каркас83cecba прошёл GUI/CLI/selftest1707/corpus4420/74PNG; это только offline.

### Раздел «Исключения»

Три прежних набора (слова/полный запрет приложений/правила auto) переведены в grouped Form
с List, выбором строки, общей кнопкой «−» и пустыми состояниями. Добавление по «+»/Return,
выбор приложения и семантика нормализации/приоритета сохранены. Подписи VoiceOver заданы
для списков и кнопок. Перед изменением рядов «Убрать» проверены ссылки Tools/scripts/docs:
активные MAC-инструкции на эти подписи не ссылаются. Проверка UI-действий ещё NOT_RUN.

### Раздел «Сниппеты»

Список со стабильным выбором, общей панелью «+ / изменить / −», поиском, пустым состоянием
и счётчиком; прежние import/export/toggle/delete-confirmation сохранены. Переключатель каждого
сниппета получил VoiceOver-подпись. Learned words — отдельный List с выбором и прежней
командой «Снова исправлять». MAC_MANUAL_CHECK обновлён на реальные пути «Сниппеты»/«+»;
историческое evidence не переписывалось. Действия Store и форматы файлов не менялись.

### Раздел «Оформление»

Восстановлены заголовок/подзаголовок в компактном образце, реальный статус,
индикация drop и VoiceOver-подпись области. Сохранены темы system/light/dark,
пять цветов, headerLightText, выбор/сброс/перетаскивание fileURL/TIFF и обработка ошибок.
Ключи theme/headerColor/headerLightText и методы Store не менялись.

### Раздел «Проверка»

Preview, подключения, статистика и диагностика сгруппированы в Form. Все категории/веса,
исторические показатели/ошибки, счётчики, privacy-текст и refresh/retry/report сохранены.
MAC_MANUAL_CHECK дополнен UI1–UI11 для ручной приёмки выбранного А и исправлен устаревший
запрет агента п.29 на ссылку на действующий п.31. Новый PASS этим документом не заявляется.

### Баннеры безопасности

Карточка сохраняет отдельные признаки: storage/permissions/secure с владельцем,
review/uncertain/pending/outstanding/buffered. Буферизованные нажатия снова видны независимо
от recoveryRequired (важно при обычной текущей операции); добавлены source-fixtures
buffering/outstanding/review-outstanding. Review-кнопка остаётся disabled при outstanding,
discard вызывает прежнюю подтверждаемую команду, отчёт вне заблокированной формы.
Основные действия выделены системной кнопкой, тексты и смысл защит сохранены.

### Редактор сниппета

Модальный редактор переведён на прокручиваемый grouped Form: сокращение/триггер, текст и
переменные, флаги, приложения, preview/валидация. Save/Cancel постоянно доступны вне формы,
Esc/Return и проверки/автовыбор триггера прежние. Фильтр приложений теперь menu Picker
с теми же all/only/except; List и кнопка «−» удаляют только выбранный ID.
Добавлены DEBUG-снимки invalid/app-filter, пустых/длинных списков, недоступного snippets.json
и минимального окна. Исправлен fixture review-outstanding: статус uncertain, как в службе,
а не демонстрационный ready. Это исправление фикстуры, не input-логики.

### Видимость ошибок редактора

Просмотр invalid-снимка ba82671 выявил, что причина disabled Save была ниже прокрутки.
Первая ошибка и предупреждение immediate-word перенесены в постоянную нижнюю панель;
полный список ошибок остался в Preview. Условия валидации/сохранения не менялись.
Предыдущий проход ba82671: GUI/CLI/selftest1707/corpus4420/162PNG, только offline.

### Меню и стандартные команды окна

В status menu сохранены статус/автоисправления/настройки/выход и прежний guard
недоступных настроек; добавлена read-only строка текущей раскладки, обновляемая вместе с флагом.
Приложению задано стандартное меню для ⌘,/⌘Q, операций текста, ⌘W/⌘M через responder chain.
Новых глобальных перехватов нет; KeyboardService и pending-input termination gate неизменны.
Renderer дополнительно утверждает, что окно остаётся за экраном. Native-клавиатурная
приёмка меню/редактора остаётся пользовательской; source/compile не заменяют её.

### Коррекция offscreen-окна renderer

В d9d0e0e GUI/CLI/selftest/corpus прошли, но новый precondition координат остановил renderer:
AppKit перемещал обычное titled NSWindow обратно на экран. Прежние снимки не доказывают
невидимость окна; это ограничение прежнего source-доказательства. Синтетические события,
event tap и AX в renderer по-прежнему не запускались.
Исправление только DEBUG: отдельное NSWindow без constrain-to-screen и без возможности
стать key/main; явная установка offscreen-origin. Проверка координат сохранена, не ослаблена.
Итоговые результаты относятся только к следующей сборке с этой проверкой.

## UI refresh А: итог и установка — 2026-10-21

Исходники `01b42fc01602c555714675318cbcd51ab8d196b4`: шесть разделов, компактные
формы, native-списки, редактор и постоянные предупреждения. Store/Core/input-код
сохранены. GUI/CLI debug, CLI1707/1707, corpus4420/4420,162 offline PNG прошли.
Строгая offscreen-проверка renderer сначала упала на `d9d0e0e`; AppKit возвращал
окно на экран. В `01b42fc` исправлено ограничение DEBUG-окна, проверка сохранена.
Release собран один раз после финальных исходников, release CLI1707/1707.

Установлен GUI SHA-256 `163f9db1375843275089b78d63241eafe215c941c994f3ce10c8779c7133c3f5`.
Подпись и полный файловый manifest совпали; предыдущий bundle
`0109fb16c565b7c545a889c282c79018310ab28265f7e4f2bf4ce8ef310394ba`
сохранён в private evidence. Конфигурация семантически равна исходной, snippets.json
не изменён. Живые счётчики corrected+4/automatic+2/manual+2 сохранены, агент ввода
не посылал; причинность этих событий не устанавливалась. RussianWin восстановлена
через TIS с readback. Временная DEBUG defaults suite очищена.

Пользователь: «записи обновил можешь запустить приложение». Приложение запущено
обычным способом, наблюдался один переключатель PID55343. Окно настроек снято
без кликов: боковая панель и статус «Работает» видимы. Это native-наблюдение окна,
не проверка действий/исправлений/VoiceOver. UI1–UI11 user manual NOT_RUN.
[Итоговые evidence](../research/evidence/ui-implementation-2026-10-21/verification.json).
В main не слито, выпуск не опубликован, длительный прогон не запускался.

## Клики по значку строки меню — 2026-10-21

По прямому запросу пользователя в ui-refresh обычный клик открывает окно настроек,
правый — контекстное меню. Убрано дублирование «Настройки…» в контекстном меню;
статус/раскладка, пауза, выход и защита незавершённого ввода сохранены.
GUI debug build (SDK26.5), source-контракт и diff whitespace прошли.
Native-проверка кликов NOT_RUN; старые результаты на этот код не переносятся.

Код `40ae789` собран debug/release. Release CLI1707/1707. Установлен GUI
`5bcbfddc736d9e2a77a2be42a337020dd9792350a5fc926c8506edf9207ad682`;
подпись и полный manifest совпали. Прежний bundle сохранён в private evidence,
snippets.json неизменён. Приложение штатно завершено и оставлено остановленным
до обновления разрешений по §3 MAC_AGENT_GUIDE. Native clicks NOT_RUN.
[Evidence](../research/evidence/ui-status-click-2026-10-21/verification.json).

Пользователь сообщил: «Разрешения обновил, запускай приложение». TypeTune запущен
через open, наблюдался один переключатель PID59516. Кликов и ввода не выполнялось;
native-проверка нового поведения значка остаётся NOT_RUN.

## Удаление оформления — 2026-10-21

Запрос: «вкладка оформление и все что с ней связано теперь не нужно».
Удалены раздел, palette/theme AppStorage, образец/drop, поля и image-import код Store.
Старые пользовательские файлы и defaults оставлены нетронутыми. Все остальные
разделы, настройки и native-input исходники сохранены. Source guard обновлён
с явным исключением только снятых функций и новым hash Store; исходный baseline
не переписан. GUI debug build и source guard прошли; renderer проверяется отдельно.
