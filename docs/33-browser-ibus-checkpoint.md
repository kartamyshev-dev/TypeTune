# IBus в браузере: контекст, выделение и мышь — 2026-09-16

## Результат

Продолжение [IBus-прототипа](32-ibus-observation-checkpoint.md).
HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.

Общий проходной IBus engine проверен в **Google Chrome 153.0.8010.36** на native
Wayland. Расширений браузера и отдельного browser text adapter нет. Тот же engine
получает ввод неизменённого GNOME Text Editor и браузерного textarea.

В браузере подтверждены все шесть Down/Up, surrounding text, обычное назначение
поля, навигация, сведения о выделении, смена поля настоящим pointer click и
PASSWORD purpose. Это существенное расширение измеренного охвата общего input
method, но ещё не реализация удаления/коррекции слова.

## Стенд и профили

Добавлен `integrations/ibus/browser_client.py`: отдельный временный профиль Chrome
и локальная HTTP-страница с двумя textarea и password input. Она проверяет DOM
value/selection и публикует только booleans, offsets и координаты. Текст поля не
передаётся в отчёт. Страница — тестовый oracle, не устанавливаемое расширение.

Ввод букв, Left, Shift+Left и pointer click идут через внутренний RemoteDesktop
API disposable Mutter. DOM не вставляет текст и не создаёт клавиатурные события.
Начальный фокус и переход в password input устанавливаются кодом тестовой страницы;
переход между textarea выполняется настоящим кликом. Все события синтетические,
физическая клавиатура и пользовательские вкладки не затронуты.

Два запуска с отдельными профилями:

1. `--ozone-platform=wayland --gtk-version=3`, без явных IME flags.
2. Те же параметры плюс `--enable-wayland-ime --wayland-text-input-version=3`.

Оба запуска передают ввод IBus. Это проверка двух наборов аргументов установленного
Chrome, не доказательство разных внутренних транспортов: согласованная версия
text-input protocol отдельно не измерялась. Значение native Wayland подтверждено
session bridge. Флаги соотносятся с [Chromium ozone switches](https://github.com/chromium/chromium/blob/main/ui/ozone/public/ozone_switches.cc).

При запуске без `--gtk-version=3` установленный Chrome завершался SIGSEGV, перед
этим сообщая об отсутствующем свойстве GtkSettings `gtk-modules`. Это наблюдаемая
ошибка запуска; её первопричина не установлена. Успешная приёмка относится к явному
GTK 3 профилю. Sandbox браузера не отключался. Firefox Snap обнаружен, но его
совместимость этим этапом не проверялась.

## Проверки и evidence

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1;
IBus 1.5.34-rc2; Google Chrome 153.0.8010.36; GTK 4.22.4 для прежних fixtures,
Chrome с явно выбранным GTK 3. Отдельные session/IBus buses, headless compositor,
временные config/data/runtime/browser profiles, источник TypeTune Probe.

[Успешный native-прогон](evidence/33-browser-ibus-native.txt).

| Свойство | Оба браузерных профиля |
|---|---|
| Обычный ввод | DOM содержит ровно fixture `ghbdtn`, collapsed selection на offset 6; observer delta 6 Down и 6 Up |
| Surrounding text | 6 обновлений; purpose FREE_FORM=0 |
| Навигация | Native Left перемещает DOM-каретку с 6 на 5; IBus видит navigation key |
| Выделение | Native Shift+Left даёт DOM range 4..5; IBus сообщает различные cursor/anchor с теми же границами |
| Мышь и смена поля | Pointer доведён до фактического центра второго textarea по DOM pointermove feedback; клик меняет focused field; IBus сообщает focus/reset |
| Password | DOM подтверждает точный синтетический ввод; observer видит purpose 8 (PASSWORD) и всё ещё получает клавиши — исключение чувствительного ввода обязательно в engine |

При выделении IBus сообщил cursor=5, anchor=4. DOM selectionStart/selectionEnd
равны 4/5; тест подтверждает наличие и границы выделения, не утверждает, что
selectionStart обозначает активный конец выделения. Интерпретация направления
выделения для будущего range adapter отдельно не принята.

Старые IBUS-01…03, GNOME-01…07, SWITCH-01…04 прошли в том же запуске.
Python syntax, локальные ссылки, diff и остановка дочерних процессов проверены.
Rust не изменён; workspace unit tests повторно не запускались.

Новый observer instrumentation считает navigation/selection events и последние
offsets, не сохраняет key values или текст. Политика чтения surrounding text
по-прежнему требует известного FREE_FORM; иначе содержимое не просматривается.
Это не универсальная гарантия распознавания чувствительного поля: назначение
предоставляет клиент, оно может отсутствовать или меняться с задержкой.

## Обновлённая матрица и решение

| Клиент / профиль | Клавиши | Surrounding | Назначение | Выделение |
|---|---|---|---|---|
| GTK Entry fixture, default Wayland | Да | Обновления есть | При начальном focus Unknown | Не принято |
| GNOME Text Editor 50.1 | Да | Точный synthetic token наблюдался | FREE_FORM наблюдался | Установленное AT-SPI выделение не отразилось в observer |
| Chrome 153, Wayland, GTK 3 | Да | Обновляется | FREE_FORM и PASSWORD наблюдались | Клавиатурное выделение подтверждено |
| Chrome 153, те же условия + IME v3 flags | Да | Обновляется | FREE_FORM и PASSWORD наблюдались | Клавиатурное выделение подтверждено |
| Firefox, Qt/Electron, терминалы, XWayland | Не проверено | Не проверено | Не проверено | Не проверено |

IBus сохраняется как основной исследуемый кандидат. Следующий функциональный
срез — ручная коррекция через общий engine с отдельным контрактом IBus backend:
ограниченная история/epoch, сброс на navigation/reset/focus, refusal для Unknown
или selection, проверка результата и запрет повторения частичного edit. Разные
возможности клиентов должны оставаться явно различимыми; положительный Chrome
case не разрешает удаление в GNOME Text Editor автоматически.

Не подтверждены мышиное выделение внутри одного поля, navigation через JS без
событий IME, быстрый burst, сложный IME, исправление в password, undo и рабочая
коррекция. Проходной engine всё ещё ничего не заменяет. При смене источника со
TypeTune на штатный xkb наблюдение прекращается — нужны согласованные RU/US
режимы будущего продукта.

## Повторение

```sh
cargo build -p typetune-cli --offline
python3 integrations/gnome/tests/native_stand.py --ibus-stand
```

Теперь `--ibus-stand` также требует установленный `google-chrome`. Используются
временные профили; существующая конфигурация Chrome не меняется.
