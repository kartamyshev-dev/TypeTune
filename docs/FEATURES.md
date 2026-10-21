# Реестр функций

UI refresh, 2026-10-21: вариант А реализован в `ui-refresh`, исходники `01b42fc`,
установлен локально. [Карта и границы проверки](UI_REFRESH.md),
[evidence](../research/evidence/ui-implementation-2026-10-21/verification.json).
Source/build/offline прошли; окно открыто, user manual UI1–UI11 ещё NOT_RUN.
Прежняя native-приёмка на этот бинарник не переносится.

Актуальная ограниченная приёмка build9: [поток 80 мс и автоотмена с обучением](STREAM_2026-10-18.md).
Длительный прогон отложен пользователем; остальные условия остаются открытыми.

## Записи журнала, совпадавшие со STATUS

Разделы «Подзаголовок TypeTune — 2026-10-17», «Переименование в TypeTune — 2026-10-17», «Стабильная пауза и выравнивание флага — 2026-10-17», «Крупные флаги — 2026-10-17», «Флаг раскладки в строке меню — 2026-10-17», «Стабилизация ядра 0.1.3 (6) — первое слово остаётся FAIL» дословно повторяли STATUS и перенесены в [журнал](JOURNAL.md).

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


2026-10-17: ранний режим в Chromium воспроизвёл смешанное `приdtn` вместо `привет`.
Оставлен OFF; обычное автоисправление и Double Shift в Chrome textarea проверены
ограниченными UI-наблюдениями на установленной0.1.1. Это обход, не ремонт раннего режима.
[Evidence](../research/evidence/diagnosis-2026-10-17/chromium-early-comparison.json).
ChatGPT composer проверяет пользователь; общего native PASS нет.

После повторного аудита исходники F15 сравнивают точный UTF-16, Replay F01/F10
использует общую пунктуационную политику. CLI617/617, editor guard12/12,
Python gates3 и corpus4420/4420. Это исторический checkpoint компиляции/offline; текущая0.1.2 указана выше.
[Разбор и evidence](AUDIT_ROUND2_FIXES.md).

Исторический GUI080bd487: Chrome single/textarea/contenteditable — auto,
сохранение правильного слова и Double Shift; 10/10 ограниченных наблюдений,
TextEdit13/13 text/source/caret, CLI608/608. Мониторинг ввода проверяется отдельно;
отказ показан в UI до запуска tap. На том checkpoint пароли/адресная строка не поддерживались; omnibox добавлен в0.1.2.
[Точный охват и evidence](BROWSER_INPUT_FIX.md). Это не новая полная приёмка.

Исходники после аудита2026-10-16: CLI594/594, Store34/34, lock4/4 и
offline-проверки валидаторов; F10 учитывает исключения полного токена с
пунктуацией, F12 блокирует обработку при ошибке настроек и второй запуск.
[Исправления и evidence](AUDIT_FIXES.md). На том checkpoint GUI только скомпилирован;
native-результаты следующего абзаца относятся к прежней сборке38a0d4fd.

Предыдущий GUI38a0d4fd из7e0ad86: release CLI584/584, авторский corpus4420/4420;
обычный TextEdit smoke13/13, doublecaps16/16, punctuation5/5, seeded Unicode3/3;
Chrome plain/rich wrong/correct/stream20/manual→Space8/8. Gesture interception
before/after при delay80:3/3 после исправления, два пропуска до него.
[GESTURE_REPLAY_FIX](GESTURE_REPLAY_FIX.md). Новая сессия32мин48сек:1000/1000 expected; stability integrity100/100, но
fully corrected59/100 (51 пропуск из1600 слов), качество быстрого потока открыто.
F07 plain-paste остаётся открытым: повторный rich FAIL без потери исходного текста;
clipboard восстановлен. Не переносить прежние PASS на эту функцию.
Статистика реализована; её старые UI-проверки относятся к указанным в evidence SHA.
[STATUS](STATUS.md). Реальный Codex ввод проверяет пользователь. Полное parity не принято.
Исторические результаты ниже относятся только к SHA в их evidence.

UI/строка/статический код, реализация и native-приёмка — отдельные статусы.
Начальные native-результаты относятся к SHA в native-prototype-suite-metadata.json.
После изменения бинарника они не переносятся автоматически.

| ID | Функция и триггер | Оригинал | Реализация | Проверка и остаток |
|---|---|---|---|---|
| F01 | RU/EN до/после разделителя | UI/HID/static overlapping weighted byte patterns | собственный whole-word detector + opt-in partial prefix detector, AX-замена | CLI584/584; новый GUI/native partial пока не принят; полный parity открыт |
| F02 | Опечатка после слова | UI, отдельная ветка static; «превет» не исправлено в опыте | 9 собственных правил; опциональный macOS provider | offline + final smoke13; полный набор оригинала неизвестен |
| F03 | Е/ё после слова | UI/static; «еще» → «ещё» live | 28 самостоятельных правил, неоднозначные формы исключены | offline + final smoke13 |
| F04 | Single Shift меняет источник | UI + live | отложенное одиночное нажатие, подавление удержания | 36 gesture-инвариантов + final smoke13 |
| F05 | Double Shift, опциональный Option: слово/выделение | UI/static | физическая конверсия RU/EN; также ⌘⌥Space, каретка после результата | final smoke13: слово/цифры/выделение; controls6: Option |
| F06 | Оба Shift: пауза auto | UI, checkbox по умолчанию off | отдельный переключатель, без отключения typo/ё | offline gesture + final controls6 |
| F07 | ⌘⇧V plain paste | UI/default on + REA временный clipboard path | TextEdit AX; Chromium native CmdAltShiftV после подтверждённого отпускания; clipboard только читается | 425e44e3 plain/rich LF/TAB/cursor/clipboard/followingSpace иtimeout2.3с PASS; формат rich absent, CmdV control present; полный F07/другие hosts открыты |
| F08 | Звук при исправлении | UI + REA cached override/reset | стандартный/выбранный локальный файл | 803c UI выбор/restart/reset с собственным WAV проверены, файл неизменен; слышимость не проверена; HOTKEY_RESEARCH |
| F09 | Правило auto off/on по bundle ID и отдельная полная блокировка | UI + Core Data AppException.enabled; Chrome off/on и global priority наблюдались | appAutomatic off/on + прежний excludedApps; совместимый decoder Settings | CLI309/309; native off/on/global off/ё иrestart на425e44e3, phase3-handshake-native-verification.json |
| F10 | Исключения слов; собственные буквальные правила отдельно | UI/Core Data + exact String Set static; synthetic lpfixture add/remove | persisted exclusions; source→replacement — самостоятельная дополнительная функция | phase3-original-word-*.json, PHASE3_STATIC; регистр/Unicode normalization оригинала неизвестны |
| F11 | Автозапуск | UI/resource/login helper | SMAppService.mainApp, readback статуса | UI регистрация on→off проверена; реальный вход не проверен |
| F12 | AX/защищённый ввод/конфликт | UI/static gate 0x1000411fc | explicit permission, Secure Input gate, stop при другом switcher | idle revoke/restore без restart проверен; Secure Input и отзыв во время AX открыты |
| F13 | Статистика | UI/static: категории и default-веса | отдельные категории, веса10/10/3/7/2/1сек; старый итог сохранён отдельно | Store22/22, GUI944f9cce UI и restart PASS; STATS_RESEARCH; полный parity открыт |
| F14 | Отмена и обучение | частично static, исходная семантика не восстановлена | ⌘⌥Z, только последняя подтверждённая транзакция; auto-слово в исключения | final smoke13 auto-undo + manualUndo с промежуточной заменой; ⌘Z редактору |
| F15 | Сброс контекста/Unicode | Tab/Backspace/keyUp static частично | AX-снимки/ревизии, own-event tag, защита графем/UTF16 | offline + final Unicode/NFD, delay80 FIFO20; фокус/прочие редакторы открыты |
| F16 | Тема, статус, временная пауза | UI | собственный SwiftUI интерфейс и меню | UI и сохранение темы после restart проверены; все режимы/уведомления не приняты |
| F17 | Исправление двух начальных заглавных | static + original native4/4, header-phase-original-double-caps-verification.json | В составе typos, all-letter source, собственные3veto, staged case→layout→spelling | 94aa34c2 native16/16, punctuation5/5; whole-token-*; модель/early timing приближены, полный F17 открыт |
| F18 | Цвет и контраст заголовка | REA: 25-cycle, resetOrange, titleWhite; UI original cycle/reset/contrast | самостоятельные 5 цветов + светлая/тёмная надпись | 803c UI + restart/reset проверены, header-pilot-ui-verification.json; палитра намеренно отличается, UI_FRAMEWORK_RESEARCH |
| F19 | Изображение заголовка | REA framework: fileURL/TIFF, persistence/remove | собственный ограниченный ImageIO import, копии в HeaderImages, picker/drop/reset | Store runtime25/25; 803c picker/restart/reset PASS; native drop UI ещё не проверен, HEADER_IMAGE_ADAPTER/PROBE |
| X01 | Облачные правила | resource | вне прототипа | excluded |
| X02 | iCloud sync | entitlement; использование не доказано | вне прототипа | excluded |
| X03 | Лицензирование/покупки/обновления | UI/resource | вне прототипа | excluded |

Каждый локальный ID остаётся открытым для полного положительного, отрицательного
и граничного native-набора. Предположение о полном покрытии отсутствует.
Доказательства: [RESEARCH](RESEARCH.md), [CORPUS](CORPUS.md), [STATUS](STATUS.md).

Контракт прототипа и сценарии трёх типов: [SPECIFICATION](SPECIFICATION.md).
Final здесь — кандидат ae3f565, точный digest в native-session-preflight.json.
Сравнение и длительная стабильность отмечаются отдельно в STATUS.

## Продолжение 2026-10-15

Текущий GUI ac35b53, бинарник b911718f071b06d166c09a2648fa67cc21fe6c7d84651ae1ef1b6c8a88773957.
CLI204/204 и авторский корпус4420/4420. F01–F05/F07/F14 прошли ограниченный
native smoke13; повтор четырёх train-пропусков40/40. F05/F06 controls6/6,
включая Option и независимость опечаток при паузе auto. F15: emoji/NFD-prefix
сохранён, курсорUTF16=13. Точные ожидания, источники и digest привязаны к
`modifier-frame-*.json`, verification рядом; детали в [INPUT_TIMING](INPUT_TIMING.md).

Исправлены ожидание появления введённого суффикса в AX, сохранение отмены при
replay отпусканий и отложенное восстановление точного источника. NativeProbe
теперь посылает физические кадры модификаторов. Это не приёмка произвольного
фокуса/редактора/скорости. Два плотных опыта остановлены AXCannotComplete,
30-минутный тест текущего бинарника не завершён. Старые final и36мин выше
остаются историческими и не закрывают текущие ограничения.

Новый узкий settings-проход: [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md),
[LOCAL_FEATURE_CANDIDATES](LOCAL_FEATURE_CANDIDATES.md). Сброс звука статически
привязан к main writer (в прототипе уже есть кнопка «Стандартный»). Произвольный
plain-paste hotkey и focusEN остаются кандидатами; поле focusEN — repeated
delimited model field, не установленный Boolean toggle.
