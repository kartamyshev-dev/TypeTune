# Состояние TypeTune

Обновлено 2026-10-18. Здесь только текущее состояние. История проверок —
[журнал](JOURNAL.md), план и приёмка — [PLAN](PLAN.md), функции — [FEATURES](FEATURES.md),
исправления по ревью — [REVIEW_FIX_PLAN](REVIEW_FIX_PLAN.md), решения — [DECISIONS](DECISIONS.md).

## Ветки

- `main` = `universal-input` (перемотка 2026-10-18, DECISIONS п. 32): универсальный режим в `main`,
  U8 частичная — пропуски перечислены в п. 32. Дальнейшая работа универсального режима — в `main`.
- `snippets`: сниппеты S5–S7 (GUI) — следующий этап, [SNIPPETS_PLAN](SNIPPETS_PLAN.md).

## Mac agent — текущая точка продолжения

Ветка `universal-input`, код приложения `6e07197`, установлен GUI SHA-256
`ab020042b1f89b42bcf3cca79fedbf10a3a5dd7e6b5710ec9e11fb60f7eec129`, PID32477.
Подпись и неизменность бинарника проверены. Только прежние разрешения TypeTune обновлены UI.
[Итог](../research/evidence/mac-agent-p9-2026-10-18/verification.json),
[матрица](../research/evidence/mac-agent-p9-2026-10-18/matrix.json).

- P8: просроченная proof повторяется с новой полной проверкой, общий предел2 повтора
  на событие; срок50мс/FIFO/все защиты сохранены. P9: transient AX unreadable повторяется
  в прежнем бюджете80мс; selection/secure не повторяются. Причина системных задержек
  более50мс отдельно не доказана.
- На этом GUI: Google и новая вкладка warm S1 **по5/5**; Google S2/S3/S4/S6/S7/S8/S9,
  Chrome address/input/textarea/contenteditable/PWA, Safari, Telegram, Notes и TextEdit —
  точный состав в matrix. Открытые поисковые подсказки Chrome/Google/newtab/Safari сохранены.
  Три возврата во все проверенные Chrome-поля и шесть приложений: фактический флаг совпадает.
- TextEdit smoke13/13, review12/12, stream80 **12/12,192 слова**. Telegram S7 дополнительно10/10;
  Chrome10 завершённых PASS и одна отдельно сохранённая frontmost_changed попытка.
  Notes/TextEdit S13 при подтверждённой автозамене в том же документе PASS.
  Universal OFF: TextEdit исправляет, Notes сохраняет исходный набор; затем ON восстановлен.
- Последние1000 после универсальных групп:0faults/0snapshot-failed; последующий итоговый
  отчёт содержит1snapshot-deadlineExceeded при временно выключенном universal mode.
  Итог **ready,pending/outstanding/uncertain0**. Это не полный trace всей сессии.
- Controller93/93, CLI1439/1439, корпуса4420/4420+22000/22000, audit4/4.
  CI39151757178 Linux/macOS success. Локальный XCTest отсутствует в CLT.
  Тесты MatrixProbe:3 метода (14 отказов,9 focus и8 completion policy), evidence tamper77/77.
- Настройки семантически равны исходным; yf сохранён, тестовое обучение удалено,
  universalON/plainPasteOFF, автозамена Notes/TextEdit восстановленаOFF,
  раскладка RussianWin. Caramba выключена. Статистика содержит тестовые увеличения:
  не откатывать вслепую. [Состояние](../research/evidence/mac-agent-p9-2026-10-18/state-after.json).

**P1 cold Chrome: user manual PASS.** Пользователь ответил «работает стабильно» на
протокол google.com/newtab по5 повторов после перезапуска, без CUA. Это подтверждение
пользователя, не наблюдение агента и не отдельный clean-profile тест.
[Evidence](../research/evidence/mac-agent-p9-2026-10-18/chrome-cold-user-manual.json).

**S14 пройден в выбранных сценариях:** native inline suffix Chrome5/5 и Safari5/5
на числовом адресном префиксе127; после каждой группы обычное автоисправление по5/5.
PWA AionUi home composer: /, /open и /open space по5; меню/SingleShift/source/flag,
затем auto5/5 и stream4words PASS. Продуктовый код не менялся; исправлен test helper
(клавиши slash/dot и строгая проверка выделенного продолжения).
[Итог S14](../research/evidence/mac-agent-s14-2026-10-18/verification.json).

**Осталось:** Safari S12 подтвердил
Secure Input и паузу TypeTune без ввода пароля, это не typed-password E2E.
Пять NOT_RUN в scaffold явно NOT_APPLICABLE: S14 у fixture без подсказок и TextEditS12.
Все5 оставшихся NOT_RUN — явно NOT_APPLICABLE scaffold. Картинки/S5, отсутствующие Slack/VS Code/Word,
Terminal/vim/Codex — SKIP_USER. Четыре часа отложены. U8/полная готовность не закрыты,
в main не сливать. Последний запрос S14 выполнен в зафиксированных сценариях;
все сайты/языки/окна PWA этим не принимаются. Password typed-E2E вне выполненного scope.

Пользователь разрешил NativeProbe для всей матрицы с прежними защитами и ввод без отправки.
При отказе сохранять trace; остановки — MAC_AGENT_GUIDE §2.7. Не запускать image helper.
Собственные fixture/UUID-документы оставлены для проверки в research/private; чужие черновики
не очищались. Локальный fixture server18763. Настройки после S14 равны началу, RussianWin восстановлен,
черновик PWA пуст, меню закрыто, pending/outstanding/uncertain0. В сохранившихся записях
новее прежнего checkpoint19587:0faults/0snapshot-failed/0rejections; старый legacy OFF fault
в ring оставлен. Это не полный trace. История — JOURNAL.

## Версии

- **Опубликован [v0.1.5 (11)](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.5)** — предварительный релиз из universal-input,
  тег → `a6e6213a4729`. Универсальный ввод, исправления Chrome/PWA и переносимого словаря.
  GUI8f554257; CI Linux/macOS на точном SHA прошёл, архив/93 manifest files/подпись/CLI
  проверены, скачанные GitHub assets совпали побайтно. Native релизного bundle NOT_RUN,
  установленный проверенный GUI ab020042 не заменён. Четыре часа не запускались,
  main не менялся. [Выпуск](RELEASE_0.1.5.md).
- **Опубликован [v0.1.4 (10)](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.4)** — предварительный релиз,
  тег → `39ee28e88270`, GUI `c722c3d7`. CI Linux/macOS прошёл на этом SHA;
  архив распакован, подпись/манифест/CLI проверены, файлы скачаны с GitHub и совпали.
  Native релизного bundle и четыре часа — NOT_RUN. [Выпуск](RELEASE_0.1.4.md).
  **Риск:** приложение ищет словарь по пути `.build` сборочной машины и, по всей видимости,
  падает при запуске на любом другом Mac (CI-проверка 2026-10-18, см. журнал). Исправлено в
  `universal-input` (`ec87be8`); перевыпуск 0.1.4 — решение пользователя.
- **Предыдущий локальный кандидат поверх `bcaf82a`** содержит исправления удержания,
  восстановления и быстрого потока.
  GUI SHA-256 `bdecb08fa24991ab1e19856736c59fe08fb433a4f0ded4886b93ce5b821befed`,
  ранее был установлен в `/Applications/TypeTune.app`; сейчас заменён сборкой `6e07197`, указанной выше.
  [Исправление подтверждения каретки Chrome](MAC_CHROME_CARET_FIX_2026-10-18.md). Результаты предыдущих бинарников
  сохранены отдельно и не переносятся на этот кандидат.

## Предыдущие проверки прежнего кандидата (исторические)

| Вид проверки | Результат |
| --- | --- |
| Release-сборка arm64, подпись, совпадение установленного bundle | успешно; два известных предупреждения путей CLT |
| Release CLI | 1336/1336 offline-инвариантов |
| Корпус v2 | 4420/4420 offline |
| Controller на hooks, без event tap | 70/70 |
| Защитные отказы production replace | 23/23, с управляемыми снимками |
| Audit gates / NativeProbe fixtures | 4/4 и 8/8, без событий |
| Chrome single-auto | 40/40: точные текст и каретка |
| Chrome остальные короткие случаи | 8/8: ручное действие, правильный текст, textarea, rich и поток |
| TextEdit 10 мс, Apple «Русская», ⌘⌥R | на текущем бинарнике не повторены; прежние результаты — в отдельном отчёте |
| Терминалы | текущая native-проверка не выполнялась; прежние попытки заблокированы Computer Use |
| XCTest на этом Mac | недоступен в CLT; прежний CI — отдельная версия |
| Четыре часа | NOT_RUN, отложено пользователем |

Evidence и границы — [текущая проверка](MAC_CHROME_CARET_FIX_2026-10-18.md).
Редкое промежуточное состояние воспроизведено на диагностической сборке;
новая ветвь проверена offline red/green, в итоговых 40 native-повторах не встретилась.
[Предыдущая сборка: Apple, быстрый ввод и восстановление](MAC_MANUAL_CHROME_FIX_2026-10-18.md).

## Изменения для v0.1.4 после v0.1.3

- Знак, набранный в другой раскладке, исправляется вместе со словом: `ghbdtn/` → «привет.».
  Таблица раскладки дополнена верхним рядом и строится из установленных раскладок macOS.
- Две заглавные в начале: `IDs`, `GHz` не меняются, `МИр` → «Мир».
- Полная пауза автоисправлений: меню «Автоисправления», жест обоих Shift, переключатель в настройках.
- Словарь вырос до ~30 тыс. слов на язык, CC BY-SA 4.0 ([LEXICON](LEXICON.md)).
- Прокрутка и перетаскивание мыши больше не сбрасывают контекст поля; предел барьера 512 событий.
- Барьер ввода и восстановление вынесены в `MutationSession` (Core); переходы покрыты проверками.
- CI (`.github/workflows/ci.yml`), сборка ядра на Linux, README с поддерживаемыми приложениями.

## Универсальная замена — ветка `universal-input`

По решению пользователя TypeTune работает во всех приложениях одним способом: свой буфер
набранного слова, Backspace и повторный набор, со сверкой через AX там, где поле читается.
Этапы U0–U7 сделаны: ядро проверено на Linux, приложение собирается в CI на macOS, проверки
`RuntimeRecoveryProbe` пройдены. **Native-проверки (U8) частично выполнены**, итог и оставшиеся условия выше; чек-лист в
[UNIVERSAL_INPUT_PLAN](UNIVERSAL_INPUT_PLAN.md#чек-лист-u8-для-mac-всё-not_run). До них ветку
не сливать в `main`. Native-PASS прежнего механизма к новому не переносятся.
Проверка на Mac — агентом по [MAC_AGENT_GUIDE](MAC_AGENT_GUIDE.md) или вручную по [MAC_MANUAL_CHECK](MAC_MANUAL_CHECK.md).

2026-10-18 в ветку влит `main` с v0.1.4. Конфликты: `replayIdentityMatches` (версия `main`
с повтором AX и ранним выходом для целей без поля) и `RuntimeRecoveryProbe` (оставлены проверки
обеих сторон). Универсальный путь обновляет `lastKeyDownTime`, чтобы новый таймер контекста
не читал поле во время набора. Проверки v0.1.4 на Mac относятся к прежнему механизму.

## Точка продолжения

0. Ветка `universal-input`: агент на Mac проходит [MAC_AGENT_GUIDE](MAC_AGENT_GUIDE.md) (DECISIONS п. 31).
   P1: warm Google/newtab5/5 на текущем GUI; cold Chrome подтверждён пользователем отдельно (user manual PASS).
   Затем — сниппеты S5–S7 (ветка `snippets`,
   [SNIPPETS_PLAN](SNIPPETS_PLAN.md)): решения S0 приняты (DECISIONS п. 28), ядро S1–S4 готово
   (Linux offline).
1. Chrome single-field: подтверждённая причина исправлена без ослабления
   проверки конечного текста/каретки. Ограниченная проверка 48/48 завершена.
   При новом отказе сохранить trace до перезапуска; все сайты не проверены.
   Для дальнейшей приёмки повторять Apple/10 мс/⌘⌥R на точном текущем бинарнике.
   Native Terminal/Ghostty ранее запрещён самим инструментом.
2. При новом отказе ⌘⌥R использовать добавленные `replay-identity`, `replay-route-rejected`
   и `replay-event-rejected`: конкретная причина исторического отказа bff09d98 не доказана.
3. Разобрать расхождение PC-таблицы: keyboardType=91, Shift+key50 → Ë,
   Shift+key10 → Ё. Fixture `corpus/native-pc-shift-grave-regression.json`.
4. Продолжить оставшиеся native-условия PLAN. Этапы 4, 5, 7 не закрыты целиком.
   Четырёхчасовой прогон отложен пользователем.

## Состояние Mac

Текущий checkpoint и незавершённое восстановление описаны выше; прежнее восстановление
из chrome-caret-fix относится к предыдущей сессии и не закрывает текущую.
