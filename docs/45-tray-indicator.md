# 45 — Индикатор в системной панели

2026-09-16. Base `18f366ed58ddb08799e527f0d4599a0bcf513f29` + этапы 40–45.

## Реализация

GTK4 приложение экспортирует StatusNotifierItem и DBusMenu через Gio session bus.
В текущем Ubuntu GNOME уже включён `ubuntu-appindicators@ubuntu.com`; новые
расширения/пакеты и изменения Shell bridge не потребовались. Протокольные
сигнатуры сверены с установленными interfaces-xml StatusNotifierItem/DBusMenu
этого host. Реализация TypeTune собственная, сторонний код не копировался.

Индикатор имеет подпись TT, status/tooltip и меняющийся значок: клавиатура при
работе, пауза, остановка или предупреждение. Меню: фактическое состояние, открыть
окно, пауза/продолжение, автокоррекция с отметкой, остановка/запуск совместимости.
Ошибки не выдаются за успешное переключение; команды проходят через тот же
Window dispatch → controller → runtime, с существующей сериализацией/readback.
Отображение обновляется только при изменении модели, без мигания на каждом poll.

Закрытие окна скрывает его, когда индикатор зарегистрирован; процесс и status poll
продолжаются. Меню открывает то же окно. Gtk.Application обеспечивает один
экземпляр; повторный запуск `--background` не создаёт ещё один значок и не
открывает окно. CLI запуск runtime запускает индикатор в фоне (кроме nested
acceptance stand). Сам по себе GUI не включает коррекцию. Автозапуск при входе
в систему этим этапом не добавлен.

Watcher отслеживается: при новом владельце выполняется повторная регистрация.
При отсутствии host индикатор не объявляется доступным; закрытие окна завершает
GUI, runtime остаётся независимым. На других рабочих столах требуется SNI host;
их native acceptance не проводилась.

## Проверки

TRAY-45-UNIT: четыре новых tests — menu actions/busy guard, XML и сериализация
layout/property filters, состояния/checkbox, отсутствие signals при неизменной модели.
32 IBus/controller/GUI/tray + 13 compatibility Python tests PASS.
GTK fixture: прежние действия, delayed poll без мигания; закрытие при доступном
tray скрывает окно, повторное открытие использует его же.

TRAY-45-LIVE: GNOME watcher содержит unique bus name приложения с `/StatusNotifierItem`.
GetLayout через настоящий D-Bus возвращает пять строк. Event меню меняет
pause/resume/automatic на работающем compatibility runtime, readback подтверждён;
исходные enabled/automatic восстановлены. Повторный фоновый запуск сохраняет
единственный объект в watcher. Логи GUI без ошибок.

Среда: Ubuntu 26.04.1, GNOME Wayland, GTK 4.22, Ubuntu AppIndicators extension.
[Evidence](evidence/45-tray.txt). Это проверка регистрации host и протокола меню;
визуальное подтверждение значка пользователем ожидается. IBus live menu control
и перезапуск самого GNOME host не проверялись. Rust/text engine не менялись.
