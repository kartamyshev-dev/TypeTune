# Системный ввод через IBus: прототип наблюдателя — 2026-09-16

## Результат

Продолжение [системного управления раскладкой](31-system-layout-checkpoint.md)
и [общесистемного плана](30-systemwide-product-direction.md).
HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без commit.

Добавлен проходной IBus engine и отдельный `--ibus-stand`. GNOME выбирает его
как источник ввода; он получает нажатия и сообщения о контексте **неизменённого
GNOME Text Editor**, без расширения редактора. Обычный ввод сразу продолжает путь
в приложение. Это подтверждённая основа системного наблюдения для проверенных
клиентов, пока не реализация коррекции слова.

Новый engine всегда возвращает False, не вызывает commit_text,
delete_surrounding_text или forward_key_event. Полезная логика Rust не дублируется;
в прототипе есть только счётчики и synthetic fixture oracle. Физический helper
не менялся, callback не запускает shell/сеть и не пишет файлы: агрегация сохраняется
отдельным таймером раз в 50 ms.

## Native результаты

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic; GNOME Shell/Mutter 50.1;
IBus 1.5.34-rc2; GTK 4.22.4; GNOME Text Editor 50.1 / GtkSourceView 5.18.0;
AT-SPI 2.60.4. Backend — native Wayland в отдельном headless compositor.
GTK_IM_MODULE не форсируется; используется путь по умолчанию этой сессии.

[IBus evidence](evidence/32-ibus-native.txt),
[регрессия прежнего стенда](evidence/32-ibus-regression.txt).

| Case | Результат |
|---|---|
| IBUS-01 | GTK Entry получает все шесть букв fixture; engine видит 6 Down и 6 Up, сообщения surrounding text; capability mask 41 включает SURROUNDING_TEXT |
| IBUS-02 | Реальный GNOME Text Editor получает все шесть букв через тот же engine; отдельный AT-SPI oracle проверяет полный текст, каретку и отсутствие выделения после ввода |
| Selection probe | В редакторе через AT-SPI установлено и прочитано выделение 7..13, затем отправлена пара Shift; IBus-метрика selection_seen осталась false |
| Content purpose | У начального GTK Entry не было set_content_type, purpose остаётся Unknown; у GNOME Text Editor получен FREE_FORM=0 |
| IBUS-03 | В GTK password fixture синтетический ввод сохранён; зарегистрирован sensitive purpose; нажатия всё ещё проходят через engine (6 Down/6 Up), поэтому исключение password обязательно в самом обработчике |
| Lifecycle | Engine выходит при disconnected; runner дополнительно убирает всю собственную группу процессов. После успешного запуска процессов probe_engine не осталось |
| Regression | GNOME-01…07, SWITCH-01…04 в IBus run; отдельно прежний совмещённый text/editor run с TEXT/MANUAL/LOCAL/EDITOR cases прошёл |

Текст и key values в агрегатах отсутствуют. Содержимое surrounding text
просматривается только при известном FREE_FORM, хранится лишь boolean наличия
заданного synthetic token; Unknown/PASSWORD/PIN не читаются. Назначение поля
хранится отдельно в каждом экземпляре engine и сбрасывается на focus transitions.
Сам API может передать строку до такой проверки — это не обещание, что пароль
никогда не попадёт в память процесса через IBus.

## Изоляция и исправления стенда

Runner создаёт отдельный IBus socket внутри временного XDG_RUNTIME_DIR и XML
component в временном каталоге. Не использует `ibus --replace`, не меняет
пользовательские источники или системную установку. Удаляет унаследованные адреса
IBus/AT-SPI и переменные выбора input module. Все вводимые тексты синтетические;
редактор открывает новый временный файл и не сохраняет изменения.

Первый прогон терял первую букву: каждый новый RemoteDesktop session создаёт
новую виртуальную клавиатуру. Добавлена подготовительная сбалансированная пара
Shift до измеряемого ввода, как в прежних stand cases. Ожидание настройки engine
и paced keys — инфраструктура теста, не реализация очереди product input; burst
и задержки отдельно не приняты.

Обнаружены оставшиеся после ранних прогонов процессы engine: GLib loop не
завершался с потерей шины. Добавлен disconnected handler и уборка выделенной
process group даже после успешного завершения runner. Старые тестовые процессы
завершены; процессы основной сессии не затрагивались.

Python syntax, локальные ссылки и git diff проверены. Rust не изменён;
workspace unit tests заново не запускались. Новое поведение проверено native
fixtures, а не количеством тестов компилятора.

## Вывод для выбора backend

IBus остаётся рабочим кандидатом для общей интеграции в системный ввод. Однако
он наблюдает ввод **когда выбран TypeTune engine**, а не все источники одновременно.
Простое переключение на штатный xkb us/ru отключит этот путь наблюдения. Для продукта
нужны собственные согласованные RU/US режимы/источники и их отдельная приёмка.

Не подтверждены Firefox, Qt/Electron, терминалы, XWayland и клиенты, обходящие IBus.
Один реальный редактор не равен всему desktop. Обнаруженные пробелы назначения
поля и выделения не превращаются в Known. Автоисправление и удаление по истории
не включены. Native password test не является универсальной защитой password fields.

Контракт [IBus Engine](https://ibus.github.io/docs/ibus-1.5/IBusEngine.html)
предоставляет process_key_event, focus, content_type и surrounding text. Он отдельно
указывает, что равенство cursor/anchor может означать отсутствие поддержки получения
выделения. Наш selection probe подтверждает необходимость независимой проверки
этого свойства в текущем пути, а не догадки по равным offsets.

Следующий шаг — расширить матрицу IBus до браузера и других toolkit-клиентов,
проверить сброс на навигацию/мышь и выделение, затем принять backend либо сравнить
его с глобальным наблюдением клавиатуры. Общесистемная ручная коррекция остаётся
целевым следующим функциональным результатом; интеграции по отдельным приложениям
не становятся основным продуктовым путём.

## Повторение

```sh
cargo build -p typetune-cli --offline
python3 integrations/gnome/tests/native_stand.py --ibus-stand
python3 integrations/gnome/tests/native_stand.py --text-stand --editor-stand
```

Продолжение: [проверка IBus в браузере](33-browser-ibus-checkpoint.md).
