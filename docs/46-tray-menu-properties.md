# 46 — Неактивные команды меню индикатора

2026-09-16, base `18f366ed58ddb08799e527f0d4599a0bcf513f29` + этапы 40–46.
Пользователь видел доступным только «Открыть TypeTune». При диагностике runtime
был enabled/available, а прямой GetLayout возвращал enabled=true для команд.

GNOME AppIndicators кэширует свойства строк отдельно: LayoutUpdated обновляет
структуру с ограниченным набором свойств. Для существующих строк нужен
ItemsPropertiesUpdated. До исправления строки сохраняли начальное enabled=false
либо busy=true. Прямой вызов Event в предыдущем live test этого не проверял.

Теперь стабильное меню отправляет ItemsPropertiesUpdated с label/enabled/visible
и toggle-state. XML включает сигнатуру `(a(ia{sv})a(ias))`. Неизменная модель
по-прежнему не отправляет сигналы. Structural LayoutUpdated больше не используется
для изменения свойств строк.

TRAY-46: simulated caching host сначала воспроизвёл disabled после появления
runtime; после правки проходит initial→ready→busy→paused, включая label/checkbox.
33 IBus/controller/tray Python tests PASS, прежний GTK fixture PASS.
Ubuntu 26.04.1, GNOME Wayland. Исходная причина сверена с локальным
`ubuntu-appindicators@ubuntu.com/dbusMenu.js` (_onSignal/_doLayoutUpdate).
Обновлён и перезапущен только GUI/индикатор; runtime не перезапускался.
Визуальная приемка пользователем ещё ожидается.
