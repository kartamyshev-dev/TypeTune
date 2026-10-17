# Аналог Caramba Switcher Pro для macOS Apple Silicon

Актуальная ограниченная приёмка build9: [поток 80 мс и автоотмена с обучением](STREAM_2026-10-18.md).
Длительный прогон отложен пользователем; остальные условия остаются открытыми.

## Исправления по ревью 2026-10-17

Подробный план: [REVIEW_FIX_PLAN](REVIEW_FIX_PLAN.md). Вид проверки — Linux offline (ядро, CLI, XCTest), если не указано иное. GUI-изменения требуют
сборки и native-проверки на Mac; эти пункты остаются открытыми до неё.

- [x] Этап 0: Swift 6.0.3 для Linux, базовая линия, GUI-таргет только на macOS, fixtures дефектов ревью (12 падают до исправления): [evidence](../research/evidence/stage0-linux-2026-10-17/verification.json).
- [x] Этап 1 (ядро; GUI-часть не скомпилирована): физическая пунктуация, верхний цифровой ряд, learnAs — [evidence](../research/evidence/stage1-punctuation-2026-10-17/verification.json).
- [x] Этап 2 (ядро; статистика в GUI не скомпилирована): двойные заглавные в трёхбуквенных акронимах — [evidence](../research/evidence/stage2-doublecaps-2026-10-17/verification.json).
- [x] Этап 3 (ядро; меню/жест/настройки не скомпилированы): полная пауза `Settings.paused` — [evidence](../research/evidence/stage3-pause-2026-10-17/verification.json).
- [ ] Этап 4 (GUI): прокрутка/drag вне барьера, мёртвый код, предел буфера — код и Core-инварианты готовы ([evidence](../research/evidence/stage4-events-2026-10-17/verification.json)); открыто до сборки и native-проверки на Mac.
- [ ] Этап 5 (GUI): таблица раскладки из UCKeyTranslate — Core-сборка и проверка таблицы готовы ([evidence](../research/evidence/stage5-layout-mapping-2026-10-17/verification.json)); открыто до сборки и native-проверки на Mac.
- [ ] Этап 6: расширение собственного словаря, корпус v3, оценка на естественном тексте.
- [ ] Этап 7: MutationSession в Core.
- [ ] Этап 8: CI.
- [ ] Этап 9: README и реорганизация документации.

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


## Адресная строка Chrome0.1.2

- [x] Добавить auto/Double Shift с защитой всей строки от URL-замен: release CLI672/672, native omnibox12 наблюдений; [evidence](CHROME_OMNIBOX.md).
- [x] Установить0.1.2, проверить подпись/побайтовое совпадение, обновить прежние разрешения, запустить: omnibox-2026-10-17/installation.json и verification.json.
- [ ] Повторить native IP/порт без влияния автодополнения; текущая попытка stopped frames0, не PASS.

## Дефект раннего Chromium-исправления2026-10-17

- [ ] Исправить гонку раннего исправления с suffix/replay/source: runtime-fixture Tools/fixtures/chromium/early-regression.json. Пока early OFF; обычное auto и Double Shift дали ожидаемый результат в textarea. Evidence diagnosis-2026-10-17/chromium-early-comparison.json.
- [x] Получить пользовательский физический повтор ChatGPT после перезапуска; пользователь подтвердил работу. Только пользовательская проверка и внутренняя телеметрия: diagnosis-2026-10-17/final-state.json. Chrome omnibox намеренно не поддерживается.
- [ ] При повторном отказе ChatGPT собрать failing trace до перезапуска; точная причина прежнего сбоя не установлена.

## Повторный аудит2026-10-16

[Исправления и evidence](AUDIT_ROUND2_FIXES.md).

- [x] Отклонять канонически равный, но иной UTF-16 снимок до замены/восстановления: editor guard12/12 и CLI paste-regressions; audit-round2-2026-10-16/editor-guard.txt.
- [x] Записывать CLI/внешний bundle в build identity и отклонять подмену/неполную identity при упаковке: test_audit_gates3, audit-round2-2026-10-16/audit-gates.txt.
- [x] Согласовать Replay с общей пунктуацией и исключениями: CLI617/617, corpus4420/4420; cli-selftest.txt и corpus.txt в том же evidence.
- [ ] Собрать окончательный app и выполнить новые native-проверки; рабочий dist080bd487 пока сохранён.

## Восстановление браузерного ввода2026-10-16

[Разбор и evidence](BROWSER_INPUT_FIX.md), рабочий GUI080bd487.

- [x] Поддержать однострочные поля страниц Chrome с запретом password/toolbar: 14 новых CLI-инвариантов (всего608), runtime single auto/manual/correct/stream20; browser-single-line-2026-10-16/verification.json.
- [x] Отдельно проверять Мониторинг ввода; при отказе приостанавливаться и объяснять причину: permission-negative-ui.json той же сборки, затем восстановление разрешения и runtime readback.
- [x] Повторить ограниченные Chrome/TextEdit сценарии на окончательном бинарнике: 10/10 и13/13 наблюдений; identity неизменна, настройки/source/modifiers восстановлены, verification.json.
- [ ] Выполнить новую строгую длительную приёмку; LaunchServices-наблюдения не заменяют проверенный exit дочернего helper. F07/быстрый поток остаются открытыми.

## Проверенные исправления аудита2026-10-16

Это исправления исходников с изолированными проверками, не приёмка нового GUI.
Общий отчёт: [AUDIT_FIXES](AUDIT_FIXES.md),
[команды/exit codes](../research/evidence/audit-fixes-2026-10-16-checks.json),
[хеши исходников](../research/evidence/audit-fixes-2026-10-16-sources.json).

- [x] Сохранить повреждённые settings.v1 и блокировать их перезапись/обработку: Store34/34, audit-fixes-2026-10-16-store.txt.
- [x] Блокировать второй экземпляр до Store/event tap: lock4/4 в служебных процессах без перехвата ввода, audit-fixes-2026-10-16-singleton.txt.
- [x] Учитывать исключение полного слова до punctuation fallback в обычной и отложенной обработке: CLI594/594, audit-fixes-2026-10-16-cli-selftest.txt.
- [x] Отклонять проваленный/неполный native-прогон и отсутствующее подтверждение модификаторов: test_audit_gates, audit-fixes-2026-10-16-gates.txt.
- [x] Сверять полный набор Package.swift/Sources и ресурсы перед упаковкой готовой сборки: test_audit_gates с временным Git-репозиторием, тот же gates.txt.
- [ ] Выполнить новую native-приёмку GUI с этими исправлениями. Прежние PASS и архивы на него не переносятся.

## Условия

Самостоятельный LayoutPilot на Swift/AppKit/SwiftUI, arm64. Эталон: Caramba
2026.10.07 (20261007.1). Все локальные функции RU/EN, собственный интерфейс.
Облако, коммерческие сервисы и публикация исключены. Проверки на текущем Mac.
Проверку ввода в настоящем Codex по указанию от2026-10-15 пользователь
выполняет самостоятельно; агент продолжает остальные функции и проверки.
Результат этой ручной проверки пока не заявляется.
Ошибка оригинала не является обязательным поведением. Бинарники, словари и
графические материалы оригинала не поставляются с прототипом.

`[x]` означает созданный и проверенный результат. Доказательства указываются
рядом с пунктом либо в STATUS/FEATURES. Блокировка не означает выполнение.

## 1. Организация

- [x] Сохранить план: этот файл, проверка чтением.
- [x] Создать STATUS.md и FEATURES.md: файлы в docs, проверка чтением.
- [x] После завершённых этапов обновлять документы и сохранять отдельные коммиты (git log; незавершённые этапы остаются открытыми).

## 2. Воспроизводимая среда

- [x] Перепроверить версию, подпись, архитектуры, frameworks и helpers.
- [x] Создать исследовательскую копию и SHA-256-манифест всех файлов.
- [x] Зафиксировать macOS, архитектуру, источники ввода и средства сборки.
- [x] Найти настройки и данные; сохранить согласованные резервные копии с WAL. — accelerated-quiescent-backup.json: оригинал остановлен, DB handles закрыты, redb-копия побайтно совпала со стабильным источником; SQLite backup API + integrity_check. Семантическая проверка формата redb не заявляется.
- [x] Зафиксировать исходные настройки и автозапуск для восстановления.
- [x] Проверить Pro через UI; недоступные функции отметить блокировкой.
- [x] Закрепить опубликованную REA, документацию и каталог инструментов.
- [x] Проверить/установить REA, Ghidra и JDK из официальных источников.
- [x] Просмотреть настройку REA для Codex и резервные копии конфигурации.
- [x] Подключить MCP и соответствующий skill, проверить после перезапуска.
- [x] Получить строки, функции, xrefs, дизассемблирование и псевдокод arm64.
- [x] Проверить повторное открытие сохранённого проекта анализа: отдельный Ghidra headless project, новый процесс -process/-noanalysis/-readOnly; marker/target/function hash совпали. docs/GHIDRA_PROJECT.md и research/evidence/ghidra-persistent-reopen.json. REA session save по-прежнему unsupported.

Критерий: анализ воспроизводится на копии, установленный оригинал не изменён.

## 3. Спецификация и наблюдения

- [ ] Обойти все меню, окна, настройки, подсказки и первоначальную настройку.
- [ ] Сопоставить UI со строками, ресурсами, настройками и компонентами.
- [ ] Присвоить функциям ID; описать вход, триггер, результат и исключения.
- [x] Разделить локальные, облачные и неподтверждённые функции.
- [ ] Для каждой функции составить положительный, отрицательный и граничный тест.
- [ ] Исследовать автоопределение и момент переключения.
- [ ] Исследовать ручное исправление слова/текста/выделения.
- [ ] Исследовать горячие клавиши, повторные нажатия и отмену.
- [ ] Исследовать регистр, пунктуацию, цифры и смешанные токены.
- [ ] Исследовать исключения приложений, слов и контекста.
- [ ] Исследовать словарь, обучение и сохранение решений.
- [ ] Исследовать индикацию, уведомления и паузу.
- [ ] Исследовать автозапуск, разрешения и сохранение настроек.
- [ ] Включить остальные обнаруженные локальные функции.
- [x] Подготовить отдельные тестовые документы и синтетические тексты.
- [x] Только один переключатель одновременно; исходные состояния зафиксировать.
- [ ] Записывать приложение, настройки, раскладку, клавиши, ожидаемый/фактический текст.
- [ ] Проверить скорость, паузы, разделители, Backspace, курсор, выделение и фокус.
- [ ] Повторить неоднозначные случаи; отделить влияние обучения.
- [ ] Сохранить воспроизводимые примеры и снимки только тестовых окон.

Критерий: каждая функция имеет спецификацию и наблюдение либо явную блокировку.

## 4. REA и восстановление алгоритмов

- [x] Инвентаризировать весь bundle и login item.
- [x] Выделить arm64; сохранить связь с хешами оригинальных файлов.
- [x] Изучить импорты, символы, строки и Swift/ObjC metadata.
- [x] Найти обработку клавиатуры, AX, источников ввода и замены текста.
- [ ] Найти настройки, исключения, словари, обучение и хранение состояния.
- [ ] Изучить Core Data и проверить на синтетических изменениях.
- [ ] Проследить событие → контекст → решение → преобразование → замена → отмена.
- [ ] Восстановить сброс буфера, границы слов, исключения и приоритеты.
- [ ] Определить роль словарей, статистики, эвристик и обучения.
- [x] Спорный псевдокод сверить с arm64-инструкциями и xrefs.
- [ ] Каждую гипотезу проверить отдельным поведенческим экспериментом.
- [x] Сохранять компонент, SHA-256, адрес, инструмент и ограничения доказательства.
- [x] Гипотезы и самостоятельные замены явно отделять от восстановленного.

SIP не отключать, подпись установленного оригинала не менять. Запрет attach
не мешает статическому анализу и наблюдениям через UI.

## 5. Самостоятельный прототип

- [x] Создать Swift-проект LayoutPilot с отдельным ID и хранилищем.
- [x] Выделить ядро: события + контекст → решение + причина.
- [x] Отделить адаптеры клавиатуры, AX, раскладки и замены текста.
- [x] Сделать replay без глобального перехвата.
- [x] Версионировать fixture: ID, состояние, события, ожидание, оригинал, происхождение.
- [x] Разделить настройки/обучение/диагностику; текст по умолчанию не записывать.
- [x] Проверить вертикаль запуск → разрешения → ручная замена → отмена → выход: final smoke/manualUndo, permission-lifecycle; NATIVE/STATUS.
- [ ] Реализовать автоопределение и преобразование по спецификации.
- [ ] Реализовать все остальные локальные функции реестра.
- [x] Использовать собственные/совместимо лицензированные данные с источниками.
- [ ] Меню, настройки, статус разрешений, пауза, исключения, понятные ошибки.
- [ ] Автозапуск и сохранение настроек.
- [ ] Unicode, выделение, регистр и позиция курсора.
- [ ] Защита от своих событий и замены после смены фокуса.
- [ ] Недостоверный контекст/защищённый ввод → пропуск исправления.
- [ ] Если используется clipboard: сохранение и защита нового содержимого.
- [ ] Быстрое отключение, восстановление после сна/смены приложения/отзыва доступа.

Критерий: реализации и проверки всех функций; заглушки не считаются готовностью.

## 6. Корпус, приёмка и поставка

- [x] ≥1000 RU/EN-примеров всех согласованных категорий.
- [x] Разделение 70/30; контроль не использовать при настройке.
- [ ] Результаты оригинала и прототипа при одинаковых условиях.
- [ ] Метрики исправлений, false positives, пропусков, задержек по категориям.
- [x] Классифицировать 203 различия: native-comparison-classified.json; R01 → FIFO27/stream20/integrity oracle. Четыре неисправленных пропуска записаны отдельно.
- [ ] TextEdit, Safari, Electron editor, терминал; версии зафиксировать.
- [ ] Скорость, удержание, вставка, выделение, курсор, фокус, отмена.
- [ ] Нет потери/дублирования текста, повреждения Unicode, зацикливания.
- [ ] Отказ/отзыв разрешений, перезапуск, сон/пробуждение.
- [x] 36мин10сек синтетической тестовой сессии с короткими служебными паузами, CPU/RSS/сохранность: native-session-final-fifo/{summary,verification,telemetry}.json; границы в NATIVE.
- [x] Восстановить настройки и состояния остановленных переключателей: delivery-verification.json и restored-helper-status.json; статистика опытов не откатывалась.
- [ ] Все локальные функции RU/EN реализованы и проверены.
- [ ] Все обязательные функциональные и регрессионные тесты проходят.
- [ ] На контроле FP ≤ оригинала, правильные исправления ≥ оригинала.
- [ ] Live p95 ≤ p95 оригинала + 50 мс в одинаковых условиях.
- [x] Отличия и непроверенные окружения описаны в STATUS/COMPARISON/DECISIONS; статус experimental сохранён.
- [x] arm64 .app из 3173cfd, запуск извлечённой копии проверен: delivery-verification.json.
- [x] Ad-hoc, deep strict verification пройден; нотариализация не заявлена: DELIVERY.md.
- [x] Исходники/корпус в sources.tar.gz, docs и CLI в архиве; сборка/доступ/удаление в README, сравнение в COMPARISON.
- [x] SHA коммита/архива и подпись: DELIVERY.md и delivery-verification.json.
- [x] Итоговый STATUS обновлён после проверки извлечения и восстановления оригинала.

## Доказательства выполненных пунктов

- Подготовка: research/evidence/{environment,original-manifest,unchanged-original}.json;
  scripts/snapshot_original.py. SQLite backup integrity_check=ok; redb скопирован
  как артефакт, его транзакционная согласованность не заявляется.
- REA: setup previews/results, rea-codex-connection.json (6.5.0, aligned);
  installed skill совпадает с pinned package. Документация в игнорируемом
  research/tools/rea-6.5.0; Ghidra12.1.4/JDK21.
- Статический анализ: docs/RESEARCH.md и native/algorithm-finding-ledger.json,
  полный экспорт и snapshot в private. Snapshot replay отдельно; сохранённый
  Ghidra .gpr открыт новым процессом, hash/marker проверены: GHIDRA_PROJECT.md.
- Код и replay: Sources/, corpus/fixture.schema.json, context-regressions.jsonl;
  CLI selftest и соответствующие evidence-файлы.
- Корпус: docs/CORPUS.md, manifest-v2.json; native выборка 1000 (700/300)
  зафиксирована до измерения: native-case-selection.json.
- Native начальные проверки: native-prototype-suite.json, metadata с бинарным
  SHA, learned-exception.json. Результаты относятся к первоначальной сборке;
  окончательная сборка должна быть проверена отдельно.

Общие пункты с формулировками «все», «каждую», «полный» остаются открытыми,
если восстановлена/проверена только часть функций. Подробный текущий статус — STATUS.

Последняя native-фаза: [COMPARISON](COMPARISON.md), [NATIVE](NATIVE.md).
Строгий повтор с единой версией помощника, p95 и межприложенная приёмка не закрыты.

## Checkpoint быстрого ввода 2026-10-15

- [x] Добавить проверку FIFO при отказе маршрута/устаревших ACK и UTF16-прогноз: CLI163/163, research/evidence/route-recovery-selftest.txt.
- [x] Сохранить короткие нагрузочные опыты, включая неудачные: docs/PERFORMANCE.md и native-load-*/summary.json.
- [x] Снять прежнюю блокировку RAM-буфера и перезапустить кандидат: пользователь перезагрузил Mac, старого процесса нет; AX обновлён, UI проверен. research/evidence/reboot-resumption.json.
- [ ] Native-проверить пропуск нового ввода при recovery, новую сборку и повтор нагрузки без ухудшения исправлений.
- [ ] Повторить smoke13, четыре train-пропуска и длительный прогон на окончательном бинарнике.
- [x] Собрать отдельный экспериментальный архив чистого3be783b, проверить32 файла/запуск/CLI204 и восстановить исходный Lang Switcher; DELIVERY.md, delivery-3be783b6fe0f-verification.json и restoration-after-3be783b.json. Полная native-приёмка остаётся открытой.

После reboot: [REBOOT_VALIDATION](REBOOT_VALIDATION.md). Native-критерии текущего
бинарника не закрыты; остановки AXCannotComplete сохранены, новый архив не создан.

## Checkpoint контекста и отмены 2026-10-15

- [x] Проверить ожидание AX-суффикса и release-only replay: CLI204/204, INPUT_TIMING.
- [x] GUI ac35b53/b911718f: smoke13/13, прежние train-пропуски40/40, controls6/6 и Unicode-case; research/evidence/modifier-frame-*-verification.json.
- [x] Разделить AX-тайм-ауты по режимам: baseline12, observer12, typo12 и RU/EN12; все исходные результаты сохранены, INPUT_TIMING. Устранение причины не заявлено.
- [x] Проверить RU/EN-поток interval80:12/12,192 исправления, ax-duration-paced12-after-inspection-verification.json.
- [ ] Завершить30мин на неизменном бинарнике: paced80-barrier остановлен после252,73сек и129 случаев; полный checkpoint сохранён, PASS не заявлен.
- [ ] Устранить/проверить AX-задержки при частых сменах RU/EN interval10.

## CODEX-001 — приоритет сохранности текста

- [x] Зафиксировать сообщение пользователя без выдуманного слова/воспроизведения: CODEX_TEXT_LOSS.md.
- [x] Запретить непроверенным hosts обработку до выделения/AX-записи: EditorSupport, CLI212/212, production-entry probe6/6; codex-loss-containment.json.
- [x] Собрать защищённый arm64 app и оставить выключенным: codex-loss-guard-final-app-build.txt.
- [ ] Воспроизвести и исправить совместимость с Codex на синтетическом вводе, без вмешательства в текущую переписку.
- [ ] Native-проверить новую TextEdit-ветвь и новые ограничения; старые PASS не переносить.

## CODEX-001: адаптер Chromium, 2026-10-15

- [x] Воспроизвести no-op AX setter и удаление слова следующим Space в отдельном Chrome contenteditable: chrome-old-ax-selectedtext.json, chrome-old-ax-then-space.json.
- [x] Проверить рабочий AccessibilityEditor с native Unicode-вставкой, курсором и восстановлением после no-op: chromium-selection-ack-production.json, chromium-noop-restored-selection.json, chromium-noop-next-space.json.
- [x] Собрать arm64 e1c52501, выполнить release CLI222/222, guard7/7 и корпус4420/4420: chromium-app-build.txt, chromium-release-selftest.txt, chromium-editor-guard.json, chromium-corpus.txt.
- [x] Проследить в REA обычный физический retype оригинала: CARAMBA_REPLACEMENT.md и caramba-replacement-findings.json; это bounded static evidence.
- [x] Проверить глобальный Space в Chrome через запущенный GUI e1c52501:6/6 — оба поля, правильное слово/коррекция/повторный Space,20 слов потоком; chromium-gui-verification.json. AX обновлён через системный UI; приложение оставлено работающим по запросу пользователя.
- [ ] Подтвердить реальный composer Codex на отдельном вводе; текущая переписка не затрагивается.

Авторизация пользователя: изолированная страница Chrome LP-CODEX-001 и ограниченный
помощник ввода для неё. Эта авторизация не распространяется на другие вкладки.

## Проверенные подэтапы третьего прохода (2026-10-15)

- [x] Сверить текущую модель Core Data и восемь поставленных версий: [STORAGE_RESEARCH](STORAGE_RESEARCH.md), storage-resource-verification.json; чтение plist/schema, не runtime-семантика.
- [x] Проверить exact String Set-предикат исключений через REA pseudo+ASM и bridge: [PHASE3_STATIC](PHASE3_STATIC.md), phase3-static-findings.json.
- [x] Провести синтетическое добавление/удаление слова и Chrome-rule с UI и SQLite readback: phase3-original-word-*.json, phase3-app-rule-*.json, phase3-original-restored.json.
- [x] Реализовать app auto off/on с миграцией Settings и проверить на промежуточном f3c47452: phase3-app-policy-selftest.txt, phase3-pilot-*.json, STATUS. Эти native результаты не относятся к будущему GUI.
- [x] Сопоставить private/HID в отсутствии переключателей и с одним оригиналом при неизменных настройках: phase3-origin-baseline-*.json, phase3-origin-original-*-control.json; оба источника исправляются оригиналом.
- [x] Проверить ограниченный production plain-paste адаптер на425e44e3: LF/TAB, пустое rich-поле, clipboard, следующий Space иtimeout2.3с. [15-case native verification](../research/evidence/phase3-handshake-native-verification.json). Это не закрывает полную F07/PLAN.
- [ ] Закрыть остальные пробелы [COVERAGE_GAPS](COVERAGE_GAPS.md); предыдущие подэтапы не означают полноту F01–F16.

- [x] Через REA+ASM установить выдаваемую plain-paste команду оригинала: enum21→V/key9, modifier index1→Command, source1/HID0 down/up. [LOCAL_SETTINGS_RESEARCH](LOCAL_SETTINGS_RESEARCH.md), local-settings-research.json. Это не runtime гарантия clipboard/focus.
- [x] Восстановить main callbacks и storage writers reset custom sound/header color: тот же отчёт,11pseudo+6ASM, export118; UI-доступность/слышимость отдельно.
- [ ] Проверить F18 через UI оригинала и реализовать самостоятельный выбор цвета заголовка.

## Проверенные промежуточные результаты 2026-10-15

Эти пункты не закрывают общие приёмочные условия выше.

- [x] Внести F18/F19 в реестр по REA framework и UI наблюдениям: FEATURES,
  [UI_FRAMEWORK_RESEARCH](UI_FRAMEWORK_RESEARCH.md), [evidence](../research/evidence/ui-framework-findings.json); ссылки/адреса проверены.
- [x] Создать собственный image adapter и проверить настоящий Store25/25:
  [HEADER_IMAGE_PROBE](HEADER_IMAGE_PROBE.md), [evidence](../research/evidence/phase3-header-image-store-probe.json); native drop открыт.
- [x] Проверить собственные color/contrast/image picker/restart/reset на803c:
  [evidence](../research/evidence/header-pilot-ui-verification.json); результат не перенесён на новые app.
- [x] Исправить воспроизведённое расхождение ПРи→При собственным словарём:
  [native4/4](../research/evidence/short-caps-textedit-verification.json) и [CLI313/313](../research/evidence/short-caps-release-selftest.txt), [CORPUS](CORPUS.md).
- [x] Сохранить и проверить новый native checkpoint6a93: TextEdit13/13 и Chrome
  word6/6 без удаления послеSpace; [проверка](../research/evidence/short-caps-limited-verification.json).
- [ ] Закрыть непостоянный plain paste и2 исторических gesture-пропуска:
  NATIVE_PASTE_INVESTIGATION.md, STATUS; успешные повторы не заменяют причину.

## Проверенные подзадачи15–16октября (не закрывают общие «все»)

- [x] Раскрыть F17 modelgate и проверить staged case/layout/spelling: DOUBLE_CAPS_RESEARCH; whole-token-caps-verification.json16/16.
- [x] Исправить premature punctuation boundary и проверить filename/code/known physical keys/sentence: whole-token-punctuation-verification.json5/5.
- [x] Проверить многострочное выделение/Unicode/отмену с caret collapse: whole-token-selections/verification.json3/3.
- [x] Проверить новый GUI94aa34c2 базовым TextEdit smoke13 и Shift2: whole-token-{smoke,shift}-verification.json.
- [x] Восстановить default percategory formula статистики статически: STATS_RESEARCH и stats-research-findings.json; это не native реализация/приёмка F13.
- [ ] Исправить/проверить Chrome queued-stream пропуск; два FAIL сохранены, trace-on standalone PASS не считается исправлением.
- [ ] Перенести F13 categories/weights в самостоятельную реализацию и проверить сохранение/пограничные значения.

- [x] Отдельный Chrome manual→выделение→DoubleShift→дваSpace без удаления: whole-token-manual-chrome-{plain,rich}-ack.json, trace ON; Codex не использовался.

## Повторная проверка сборки38a0d4fd, 16октября

Эти пункты относятся только к executable38a0d4fd из source7e0ad86 и не закрывают
общие условия функционального равенства выше.

- [x] Воспроизвести и исправить состояние жестов после FIFO: prefix3 при delay80, before2 пропуска/after3 из3; [GESTURE_REPLAY_FIX](GESTURE_REPLAY_FIX.md).
- [x] Проверить обычный TextEdit13/13, регистр16/16, пунктуацию5/5 и seeded selection/Unicode/undo3/3: research/evidence/gesture-fix-{textedit,double-caps,punctuation}-verification.json и gesture-fix-unicode/verification.json.
- [x] Проверить Chrome plain/rich wrong/correct/stream20/manual→Space8/8: research/evidence/gesture-fix-chrome-{plain,rich}.json. Настоящий Codex остаётся пользовательской проверкой.
- [x] Убрать trace/delay, сохранить ранний режим OFF и удалить только своё ghbdtn исключение: research/evidence/gesture-fix-native-settings.json, collections0.
- [x] Новая сессия32мин48сек:1000/1000 expected,100/100 stability integrity; native-session-gesture-fix-38a0d4fd/{summary,verification}.json. Полностью исправлены лишь59/100 длинных последовательностей; качество потока остаётся открытым (gesture-fix-stream-quality.json).
- [x] Повторить четыре исторических train-пропуска по10раз:40/40 text/source/caret, gesture-fix-misses-repeat-verification.json.
- [x] Архив той же сборки a840f0415c12:60 manifest files, SHA-256, подпись, extracted CLI584/584 и запуск из извлечённого bundle по прежнему разрешённому пути; TextEdit/Chrome после запуска PASS. research/evidence/gesture-fix-archive-verification.json и gesture-fix-archive-{launch-native,chrome}.json.
- [ ] Закрыть F07: fresh Chrome rich paste FAIL в research/evidence/gesture-fix-paste-rich.json; clipboard восстановлен, причина этим опытом не установлена.
