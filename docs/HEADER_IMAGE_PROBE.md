# Standalone-проверка настоящего Store F19

`scripts/header_image_probe.sh` компилирует `Tools/HeaderImageProbe.swift`
вместе с текущим `Sources/LayoutPilot/Store.swift` и уже собранным debug-модулем
LayoutPilotCore. Он не собирает GUI и не переписывает dist. Нужен собственный
синтетический PNG128×64 `.build/settings-fixtures/header.png` и предварительно
собранный Core.

```sh
scripts/header_image_probe.sh
```

Probe явно передаёт каждому Store уникальный `UserDefaults(suiteName: UUID)`.
UserDefaults.standard, UI, AX, клавиатура, clipboard, оригинал Caramba и его
настройки не используются. Проверяется именно production Store, не зеркальная
реализация импорта.

Проверяются URL/data import, точность собственной копии, сохранность исходника,
повторный Store-init с тем же suite, malformed/empty/>32MiB data, >32MiB file,
валидный PNG с шириной8193, nonfile URL, directory URL, missing own copy,
отказ восстановления внешнего пути, reset и сохранность обычных settings/counter.
Все отказы должны оставить предыдущий выбор. Собственные тестовые UUID-копии,
временная папка и ключи уникального suite очищаются; существовавшие ранее пути
в HeaderImages сохраняются.

Результат2026-10-15: **25/25 standalone Store runtime checks**,
`research/evidence/phase3-header-image-store-probe.json`. Это не проверка
диалога/drag-and-drop в GUI и не native-приёмка глобального ввода.
Идентичность исходников/помощника — `phase3-header-image-store-probe-identity.json`.
Первый прогон21/22 сохранён в `...-initial.json`: cleanup-проверка помощника
ожидала nil, но Darwin возвращал пустой persistentDomain после удаления.
Проверка исправлена на точный readback нулевого числа ключей. Store не менялся.
