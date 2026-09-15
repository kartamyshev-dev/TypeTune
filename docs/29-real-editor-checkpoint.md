# Реальное приложение: GNOME Text Editor — 2026-09-16

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.
Продолжение [checkpoint 28](28-local-shortcuts-checkpoint.md).

Выбран установленный **GNOME Text Editor 50.1**. Добавлен воспроизводимый native
стенд `integrations/gnome-text-editor/probe.py` и опция `--editor-stand` общего
изолированного GNOME runner. Проверено реальное приложение, не собственный TextView.

AT-SPI действительно даёт Text и EditableText: удалось прочитать точный текст,
переместить каретку, создать/удалить выделение, заменить синтетическое `ghbdtn`
на `привет` отдельными delete/insert вызовами и проверить результат чтением.
Существующий пользовательский runtime при этом **не подключён к редактору**.

Выявлен блокер безопасного адаптера: проверенный интерфейс не предоставляет
доказательства неактивной композиции и условного изменения с ожидаемой revision
и контекстом. Между внешним чтением и delete пользователь может изменить документ
или фокус. Результат readback после удаления не предотвращает повреждение уже
изменившегося диапазона. Поэтому snapshot.composing остаётся Unknown, а ручная
замена через основной engine должна отвергаться до изменения. Это не утверждение,
что AT-SPI вообще бесполезен: чтение, каретка и обычные edit primitives подтверждены.

## Контракт и источники

- [Text/EditableText interfaces](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Accessible.get_interfaces.html)
  показывают доступные интерфейсы, но не доказывают весь контекст замены.
- [DeleteText](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.EditableText.delete_text.html)
  принимает scalar start/end без expected revision.
- [InsertText](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.EditableText.insert_text.html)
  принимает character position и UTF-8 byte length. Эти единицы отдельно учтены
  в fixture; кириллица, emoji и combining mark прочитаны без потерь.

Вывод о непригодности для текущего строгого executor — архитектурная оценка этих
контрактов, не результат имитации конкурентной гонки. Наличие двух успешных API
вызовов не названо атомарной или безопасной продуктовой коррекцией.

## Проверки

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1;
gnome-text-editor 50.1-0ubuntu0.1; GTK 4.22.4; GtkSourceView 5.18.0;
GI Atspi / at-spi2-core 2.60.4-0ubuntu0.1. Backend — native Wayland, отдельный
headless compositor, private session bus и запущенный в нём accessibility bus.

[Native evidence](evidence/29-editor-native-stand.txt).

| Case | Результат |
|---|---|
| EDITOR-01 | Поиск ограничен PID запущенного редактора; обход максимум 512 nodes за проход, child fanout 128, D-Bus timeout 1 s; размер текста сверяется до чтения; точный Unicode fixture подтверждён |
| EDITOR-02 | Caret offset 9, selection 3..9, удаление selection и повторное чтение значений |
| EDITOR-03 | EditableText=True; удаление 3..9, проверка промежуточного текста, Unicode insert, проверка полного текста и установленной каретки; исходный временный файл не сохранён |
| Engine regression | Новый simulated test: ручной план с Unknown composition отклонён, snapshot/каретка сохранены, apply не вызван |
| GNOME-01…07 | Старые native bridge cases пройдены вместе с editor probe |

Это не native keyboard/shortcut acceptance: текст загружен из временного fixture,
операции идут по AT-SPI. Editor-03 выполняется исключительно в изолированном
синтетическом документе для исследования API. Он не обходит guards рабочего engine.

Первые запуски выявили пересечение имён методов GI Accessible/Text (`get_text`,
`get_selection`); используется явный вызов интерфейса Atspi.Text. Итоговый прогон
успешен. Процесс редактора завершается в finally; launch/accessibility процессы
останавливает общий runner. Общий timeout — 90 s, probe timeout — 25 s.

Повторение:

```sh
cargo build -p typetune-cli --offline
python3 integrations/gnome/tests/native_stand.py --editor-stand
cargo test -p typetune-engine --offline
```

## Ограничения и следующее решение

Этот этап завершает **проверку интеграционного API выбранного приложения** и
фиксирует его непригодность для прямого подключения существующего строгого executor.
Рабочая коррекция в GNOME Text Editor пока не реализована. Возможности других
приложений, XWayland/X11, настоящий IME, lock/logout и глобальные shortcuts не приняты.
Полный workspace повторно не тестировался: изменены Python fixture и один engine test.

Дальше нужен адаптер внутри приложения с доступом к composition, revision,
focus и range API в одном потоке. Практический следующий срез — расширение Firefox
для обычных textarea на явно разрешённых страницах с командой пользователя,
без password/contenteditable на первом этапе, с вызовом общего Rust engine через
ограниченный протокол. Это предложение для следующего этапа, ещё не реализация
и не доказанная совместимость. Использовать слепые Backspace/clipboard для обхода
обнаруженного ограничения не планируется.

**Пересмотр следующего этапа:** пользователь уточнил требование общесистемной
работы; предложение Firefox-only заменено [системным направлением](30-systemwide-product-direction.md).
