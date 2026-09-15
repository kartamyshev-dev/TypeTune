# 38 — Отказ обоих триггеров на физической клавиатуре

2026-09-16. HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения.
Ubuntu 26.04.1, kernel 7.0.0-31-generic, GNOME/Mutter 50.1 / Wayland.

## Воспроизведение и причина

Пользователь запустил compat-on; в браузере не работали ни Space, ни Double Shift.
Runtime был enabled/available, две клавиатуры открыты, last_result оставался idle.
Добавлены только агрегированные счётчики, без текста и последовательности кодов.
В повторной проверке: 60 key events, 23 stale events, максимум задержки 480 мс,
ни одного auto/manual trigger или плана.

`cargo run -p typetune-cli --example discovery_timing --offline` измерил поиск
устройств: **613, 607, 607, 519, 607 мс** (две клавиатуры).
Поиск выполнялся прямо в reader loop каждые 500 мс. Он задерживал чтение и
повторялся почти непрерывно; порог свежести 250 мс закономерно отбрасывал события.
Предыдущий native stand подавал события через Feed и не покрывал эту задержку
реального evdev transport. Отсутствие этой проверки было существенным пробелом.

Независимый воспроизведённый дефект: auto prepare назначался через 60 мс после
Space Down, и при ещё удерживаемом пробеле просто завершался без повторного запуска.

## Исправление

- Discovery вынесен в отдельный thread с bounded каналом одного снимка; reader
  получает готовые результаты через try_recv и продолжает читать устройства.
- Порог свежести не увеличен и проверки контекста не ослаблены.
- Триггер ожидает отпускания клавиш (до 500 мс), затем запускает prepare с задержкой
  60 мс. Новый Down, смена revision/context или timeout отменяют запрос.
- Status показывает keys_seen/stale_events, число triggers/plans/invalidations,
  min/max/last event lag в мс и причины stale-input/no-candidate.
- Обновлены runtime и release helper в пользовательской установке; работавший
  compatibility runtime остановлен и снова запущен. Перезагрузка GNOME не нужна.

## Проверки

- 3 Rust tests compat_transport PASS: в том числе заблокированный scanner с
  управляемым barrier не блокирует poll читателя; balance и partial-write cleanup.
- 9 Python compatibility tests PASS: добавлены release timing и отмена новым вводом.
- [Native compatibility stand](evidence/38-compat-native.txt) PASS: два направления,
  Double Shift обоих видов, auto с удержанием Space более 120 мс, exact GTK
  text/caret, следующий RU символ и pause. Stand по-прежнему использует Feed и
  Clutter output; реальный transport проверяется отдельно в основной сессии.
- Установленные runtime/helper сверяются с исходниками/собранным release.

Пользователю отправлен запрос повторной проверки в браузере после исправления.
Не считать исправление подтверждённым пользователем до его ответа.

## Подтверждение пользователя

После обновления пользователь повторил проверку в браузере и ответил:
**«Теперь работает»**. Не уточнял, проверены ли оба триггера отдельно; не расширять
это подтверждение до всех браузеров/полей/приложений.

Агрегированный status после ответа: keys_seen=204, stale_events=0,
auto_triggers=3, manual_triggers=3, plans=5, max_event_lag_ms=2
(ранее 480), last_result=injected-unverified. Это подтверждает устранение
задержки reader loop и наличие обоих типов запросов, но не заменяет readback
результата каждой операции в compatibility profile.
