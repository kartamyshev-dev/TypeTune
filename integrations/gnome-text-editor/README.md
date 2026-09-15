# GNOME Text Editor: native capability probe

Проверенный профиль: GNOME Text Editor 50.1, GTK 4.22.4, GtkSourceView 5.18.0,
AT-SPI 2.60.4, GNOME/Mutter 50.1, native Wayland на Ubuntu 26.04.1.

Запуск из корня TypeTune:

```sh
cargo build -p typetune-cli --offline
python3 integrations/gnome/tests/native_stand.py --editor-stand
```

Стенд создаёт отдельные compositor, session/accessibility buses и временные
config/data/runtime. Запускается реальный `/usr/bin/gnome-text-editor` с новым
синтетическим файлом. Нужны Python GI Atspi 2.0, at-spi-bus-launcher и сам редактор.
Ранее запущенные пользовательские окна не используются; поиск ограничен PID
процесса fixture. В логах нет содержимого полей и названий пользовательских файлов.
`probe.py` не является инструментом для запуска в основной сессии.

Проверяются точный Unicode-текст, scalar offsets каретки, выделение и, при наличии
EditableText, delete/insert/readback. Временный файл не сохраняется после изменения.
Это тест примитивов API, не подключённая функция коррекции. Между delete и insert
нет атомарности, наблюдаемого revision token или проверки composition. Рабочая
замена остаётся недоступной, а не получает фиктивные успешные guards.

[Результаты и дальнейшее решение](../../docs/29-real-editor-checkpoint.md).
