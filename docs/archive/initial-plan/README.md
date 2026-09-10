# Архив первоначальных планов

Документы 01–10 перемещены сюда 2026-09-10 из ревизии TypeTune `8cc19d0` **без изменения содержимого**. В них смешаны первоначальный замысел, примерный код, устаревшие API и непроверенные предположения.

**Это исторический материал. Он не служит инструкцией к реализации, установке или запуску.** Буферизация текста с последующим Backspace, сигнальный lifecycle, единый physical/text pipeline и заявленная универсальность Wayland заменены новыми контрактами.

Актуальные документы: [обзор](../../00-overview.md), [архитектура](../../13-target-architecture.md), [план разработки](../../14-development-plan.md), [поведение функций](../../16-product-spec.md).

| Исходный документ | Заменивший контракт |
|---|---|
| [01 — Окружение](01-environment-setup.md) | План, раздел 4: стенды и проверки |
| [02 — Scaffolding](02-project-scaffolding.md) | Архитектура, разделы 2–3 |
| [03 — Pipeline](03-core-pipeline.md) | Архитектура: physical/text separation и Linux helper |
| [04 — Корректор](04-layout-corrector.md) | Product spec: коррекция; архитектура: replacement |
| [05 — Anti-chatter](05-anti-chatter.md) | Product spec: физический автомат |
| [06 — Config](06-config-system.md) | Архитектура: config generations/control |
| [07 — Snippets](07-snippets.md) | Product spec: matcher/renderers |
| [08 — CLI/daemon](08-cli-daemon.md) | Архитектура: lifecycle; план G2A |
| [09 — GUI/tray](09-gui-tray.md) | План G6; product spec: effective status |
| [10 — Packaging](10-packaging.md) | План G6 и package acceptance |
