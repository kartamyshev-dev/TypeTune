# TypeTune frontend

Общий Python controller, настройки, GUI, трей и feedback. Единственный input runtime
находится в `../compat`, общий Rust ABI — `../../crates/typetune-bridge`.
Зависимости frontend: Python 3, PyGObject / Gio / GLib / GTK4. IBus/AT-SPI adapter удалён.

`controller.py` оставляет только миграционный cleanup прежних TypeTune IBus sources,
component XML и environment.d, не затрагивая другие engines и системный IBus.
Настройки v1 с mode=ibus читаются как compatibility; новые попытки выбрать ibus отвергаются.

Проверки из корня: `/usr/bin/python3 -m unittest discover -s integrations/app -p 'test_*.py'`.
