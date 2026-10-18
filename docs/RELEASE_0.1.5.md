# TypeTune 0.1.5 (11)

Предварительный релиз для macOS14+ на Apple Silicon из ветки universal-input.
В main ветка не сливалась.

- Универсальный ввод: исправление и смена раскладки в приложениях вне прежнего списка.
- Chrome/Google: повтор временно недоступного AX-чтения в прежнем бюджете80мс.
- Быстрый поток: новая полная проверка при просроченной proof, максимум2 повтора;
  срок50мс, порядок событий и защитные проверки сохранены.
- Ресурсы словаря загружаются из bundle без зависимости от .build сборочной машины.
  Это исправляет известную проблему переносимости0.1.4.

На предшествующем кандидате6e07197 / GUI ab020042: Google/newtab warm по5/5,
cold Chrome подтверждён пользователем; TextEdit smoke13/13, review12/12,
stream80 12/12=192 слова. Ограниченная матрица Chrome/Safari/Telegram/Notes/PWA
и S14: inline numeric prefix Chrome/Safari по5/5, PWA home menu15/15.
[Точный scope S14](../research/evidence/mac-agent-s14-2026-10-18/verification.json),
[остальная матрица](../research/evidence/mac-agent-p9-2026-10-18/verification.json).
Эти native PASS не переносятся на новый релизный bundle автоматически.

Релизный bundle: native ввод NOT_RUN; установленный проверенный кандидат на Mac
не заменяется при публикации. Подпись ad-hoc, notarization отсутствует.
При обновлении macOS может потребовать обновить прежние разрешения приложения.
Картинки/S5 и согласованные приложения пропущены пользователем.
Password typed-E2E и полная приёмка PLAN/U8 не закрыты.
Четырёхчасовой прогон отложен пользователем и не запускался.

Опубликован [v0.1.5](https://github.com/kartamyshev-dev/TypeTune/releases/tag/v0.1.5).
Тег → `a6e6213a4729c53f42e2257d327f1c5287c2a1d5`.
[CI Linux/macOS](https://github.com/kartamyshev-dev/TypeTune/actions/runs/39161125663) прошёл,
включая запуск без .build. Релизные offline: CLI1439/1439, corpus4420/4420+22000/22000,
controller93/93, guard23/23, audit4/4, fixtures8/8.
ZIP SHA-256 `9e06df8b53b9c5d984e82392fecfd263d4fceb5120f96af5fbe9238c1aeb1482`.
GUI SHA-256 `8f554257fd8e01f014589afd37e357fb8279eafaddb5effcbf62d90ad38ed4f7`.
После ditto-unpack проверены93 файла манифеста, версия, подпись и CLI.
Оба GitHub assets скачаны обратно и побайтно совпали с локальными.
[Проверка](../research/evidence/release-0.1.5/verification.json),
[публикация](../research/evidence/release-0.1.5/publication.json).
