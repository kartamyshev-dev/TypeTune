# Сохранение и повторное открытие Ghidra project

REA Evidence snapshot и постоянный Ghidra project проверяются отдельно.
REA 6.5.0 запускает Ghidra с `-readOnly -deleteProject`: контракт и implementation
уже проверены в `research/evidence/ghidra-project-lifecycle.json`.
Повторное чтение Evidence не восстанавливает Program database и аннотации.

## Граница проверки

Используется только зафиксированный `research/private/caramba-arm64`, SHA-256
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Оригинал в /Applications, пользовательские данные, UI и настройки не затрагиваются.
Цель не исполняется. База, журналы и промежуточные отчёты остаются в игнорируемой
`research/private/ghidra-persistent`; в поставку не включаются.

До отдельного workflow рекурсивный поиск в private не нашёл `.gpr`, `.rep`, `.gzf`.
Найдены четыре Evidence snapshots: caramba, deep, extractor и phase2. Это отдельные
артефакты, а не сохранённые проекты.

## Авторский workflow

`scripts/ghidra_checkpoint.sh create` создаёт один отдельный постоянный project
через установленный Ghidra headless 12.1.4/JDK21, с heap2G, CPU2 и nice10.
Повторный create при наличии project отклоняется. Import ограничен600сек.
Авторский `scripts/ghidra_checkpoint.java` требует точный digest цели и функцию
`0x1002e0030`, вычисляет SHA-256 байтов её Ghidra AddressSet, сохраняет этот digest
и собственный marker в Program options. Это не извлечение псевдокода.

После выхода первого процесса сохраняются `.gpr` и `.rep`. Команда
`scripts/ghidra_checkpoint.sh reopen` запускает новый процесс только с
`-process caramba-arm64 -noanalysis -readOnly`: без import и повторного анализа.
Скрипт проверяет сохранённые marker и digest по открытой Program database.
Private manifests до/после нужны для проверки неизменности файлов базы.

Сверяются успешные script markers, отчёты обоих процессов, target/function hashes,
наличие project файлов и отсутствие повторного анализа в reopen. Headless exit0
сам по себе недостаточен: Ghidra может записать script error в журнал.

## Результат

15 октября2026 workflow выполнен: **PASS отдельного Ghidra headless save/reopen**.
Доказательство: `research/evidence/ghidra-persistent-reopen.json`.
Первый процесс завершился с exit0, reported analysis218сек и Save succeeded;
второй процесс с exit0 открыл существующий project в readOnly без нового import
и анализа. Оба авторских script markers и JSON получены, сохранённые Program
options прочитаны и проверены. Function count24472 относится только к этой базе.

Функция `0x1002e0030`:2060байт, SHA-256
`658ea9d830af0b5195253868172b7a18f18188122547c696932f688787d9442d`.
Её байты, digest цели и авторский marker совпали между процессами.
До reopening сохранены10 файлов project, после9: `.gpr` и основные файлы базы
не изменились, но Ghidra обновил `idata/~index.bak` и удалил `idata/~journal.bak`.
Поэтому readOnly Program не означает полного отсутствия файловых изменений
служебных project metadata. Оба полных manifests сохранены в private и evidence.

Default analysis сообщил ошибки Objective C type encoding:T и предупреждения
деманглинга внешних таблиц. Проверка сохранения не доказывает полноту анализа,
правильность сигнатур или исполнение исследуемой программы.

Это самостоятельная новая база, а не сохранение сессии REA; REA-аннотации в неё
не переносились. Save/reopen через установленный REA provider остаётся
неподдерживаемым. Snapshot replay остаётся отдельным результатом.
