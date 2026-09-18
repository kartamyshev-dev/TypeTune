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

## Проверка первого релиза

Коммит пакета: `bb1a407ddb852e430ca1248302e0e0d836df8fc5`, тег
`v0.1.0-preview52-1`. Main CI и tag CI прошли: 120 Rust / 84 Python tests,
GTK fixtures, isolated dpkg lifecycle. Скачанный release-пакет содержит тот же
source_commit и source_dirty=false.

GitHub при загрузке Assets заменил `~` в имени файла на точку. Содержимое `.deb`
не изменилось; Debian version внутри остаётся `0.1.0~preview52-1`. Первоначальный
SHA256SUMS исправлен под фактическое имя Assets без замены пакета или тега.
Workflow теперь заранее нормализует имя перед вычислением суммы и после публикации
повторно скачивает Assets и проверяет SHA256SUMS.

## Выпуск preview55-2 — 2026-09-18

Тег `v0.1.0-preview55-2`, Debian version `0.1.0~preview55-2`.
Включает этапы 53–55 и скрытый отдельный setup launcher (`NoDisplay=true`),
с сохранением действия Setup у основного ярлыка и автоматической первоначальной настройки.
План Windows/macOS — документ 56; бинарные assets этих ОС не выпускаются.
Пакет и SHA256SUMS публикуются tag workflow после всех CI checks.
