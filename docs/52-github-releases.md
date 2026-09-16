# 52 — публикация GitHub Releases

## Как устроено

Push в main запускает CI: Rust 1.98.1, форматирование, clippy, 120 Rust tests,
Python tests, GTK fixtures под Xvfb и сборка `.deb` на Ubuntu 26.04 amd64.
Зависимости GTK/GLib добавлены: прежний CI падал при сборке glib-sys из-за отсутствия
`glib-2.0.pc`. Набор проверок не ослаблен; добавлены поведенческие проверки.

Скрипт упаковки по-прежнему собирает проект без root. Для isolated-root dpkg теста
на runner используется sudo, а DPKG_ROOT запрещает hooks обращаться к host-сеансам.
Пакет содержит source_commit/source_dirty в package.json и notices зависимостей.

Push тега **`v0.1.0-preview52-1`** запускает те же проверки и собирает Debian version
`0.1.0~preview52-1`. После успешной сборки отдельный job с `contents: write` создаёт
**pre-release** и загружает `.deb` + `SHA256SUMS` в Assets.
Job сборки имеет только read permission. Официальные Actions закреплены полными SHA.
Формат тега проверяется до сборки; shell получает ref через переменные окружения.
При ошибке проверок release job не запускается.

Push обычного коммита и workflow_dispatch на main не публикуют релиз: пакет доступен
как временный Actions artifact (14 дней). `.deb` в Git не коммитится, dist игнорируется.
GitHub создаёт Source code архивы автоматически; они не заменяют установочный пакет.

## Следующий выпуск

1. Внести изменения и обновить release notes `docs/releases/preview.md`.
2. Проверить CI на main, выбрать новый preview/tag, например `v0.1.0-preview53-1`.
3. Создать annotated tag на проверенном коммите и отправить его в origin.
4. Дождаться успешных build/release jobs. Проверить Assets и скачать пакет для
   проверки SHA256SUMS и package.json/source_commit.

Не перемещать опубликованный тег и не заменять выпущенный `.deb` другим содержимым;
исправления публиковать новым тегом/версией. Примерный номер тега не означает
автоматическое повышение минимальных версий GNOME или Ubuntu.

Первая публикация включает накопленные этапы 40–51: частотные/пользовательские словари,
короткие слова, GUI/tray, сохранение настроек, автозапуск, application exclusions,
feedback с явным подтверждением, Debian setup и native migration.
Это GNOME 50 preview, не универсальный стабильный Linux-релиз.
