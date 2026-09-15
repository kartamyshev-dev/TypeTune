# Локальные клавиши коррекции и pointer acceptance — 2026-09-16

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, commit не создан.
Продолжение [checkpoint 27](27-manual-correction-checkpoint.md).

В собственном GTK-поле можно нажать и отпустить **F8** для US → RU или **F9**
для RU → US. В demo команды установлены явно один раз; повторная установка
возвращает Unsupported. Кнопки предыдущего этапа сохранены.

```sh
cargo run -p typetune-gtk --example snippet_demo --offline
```

Это локальные функциональные клавиши без Shift/Ctrl/Alt/Super. Работа построена
на [GTK EventControllerKey](https://docs.gtk.org/gtk4/class.EventControllerKey.html)
и [key-released](https://docs.gtk.org/gtk4/signal.EventControllerKey.key-released.html).
Нажатие создаёт план с текущими текстом, кареткой, epoch и revision, отпускание
передаёт его существующему executor. До отпускания замены нет. Срок плана —
1 секунда от первого нажатия; повторы не обновляют срок и не создают новые планы.
Маска удерживаемых F8/F9 предотвращает повторное вооружение после вмешательства
другой клавиши. Другие нажатия отменяют pending command, обычный ввод проходит.

Модификаторы проверяются при нажатии и отпускании; Unknown не разрешает замену.
Перемещение каретки, изменение текста, состава выделения или focus epoch отменяет
план. Даже уход фокуса и возврат в исходное поле не делает старый план пригодным.
Изменения делаются исключительно через прежний range executor, без key injection.

## Проверки

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic, GNOME Shell/Mutter 50.1,
GTK 4.22 / gtk4-rs 0.9.7, Rust/Cargo 1.98.1. Native backend — отдельный headless
GNOME Wayland и private session bus. Основные приложения и keyboard grab не
использовались. Синтетические тексты fixtures не содержат пользовательских данных.

[Успешный вывод стенда](evidence/28-local-native-stand.txt).

| Case | Проверено |
|---|---|
| LOCAL-01 | Настоящие pointer events от disposable Mutter → GTK кнопки US → RU и RU → US; точный текст, Space, каретка, collapsed selection и сохранённый focus |
| LOCAL-02 | Wayland F8/F9 Down/Up; пока клавиша удерживается, текст исходный; после отпускания ровно один результат, точные текст/каретка; F8 удерживается 650 ms |
| LOCAL-03 | Shift+F8 отвергается; изменение buffer между Down и Up отвергает старый план; исходный либо дополненный пользователем текст сохранён |
| LOCAL-04 | Удержание 1.1 s превышает deadline; focus round trip между Down/Up меняет epoch; оба случая отказывают без изменения текста/каретки |
| Regression | TEXT-01…08, MANUAL-01…02, GNOME-01…07 проходят в том же стенде |
| Portable/workspace | 100 unit + 2 CLI integration tests проходят; новых unit tests в этом срезе нет, новое поведение проверено native cases |
| Static/build | GTK examples build; engine/gtk Clippy all-targets `-D warnings`; fmt/diff |

Staged keyboard fixtures синхронизируются временными ready/held/release markers;
markers не содержат текст поля. Все виртуальные Down имеют Up, после проверок
внутренняя RemoteDesktop session останавливается. Общий timeout и уничтожение
тестовых процессов остаются независимой защитой стенда.

Pointer fixture разворачивает только собственное тестовое окно на весь виртуальный
монитор. Координаты кнопок берутся из GTK geometry. Относительное движение Mutter
корректируется по фактическим GTK enter/motion координатам, перед кликом проверяется
попадание в центр. Координаты записываются атомарно; рабочий desktop не затрагивается.
Первый запуск выявил неверное имя метода тестового API: introspection установленного
Mutter подтвердил NotifyPointerMotionRelative. Другой запуск выявил отсутствие
motion при начальном enter; fixture теперь учитывает оба сигнала.

Повторение:

```sh
cargo build -p typetune-gtk --examples --offline
python3 integrations/gnome/tests/native_stand.py --text-stand
cargo test --workspace --offline
cargo clippy -p typetune-engine -p typetune-gtk --all-targets --offline -- -D warnings
cargo fmt --all -- --check
```

## Ограничения и следующий этап

Это команды только собственного TextView. Глобальные shortcuts, double Shift,
конфигурируемые сочетания, настоящие IME и другие приложения этим этапом не приняты.
F8/F9 заняты только в установленном локальном профиле. Удержание более секунды
требует нового короткого нажатия. Если release потерян при потере фокуса, первое
последующее нажатие/отпускание той же клавиши может только сбросить latch; старая
замена не исполняется благодаря epoch/deadline guards.

Native fixtures проверяют события внутреннего API Mutter, не portal permissions
и не аппаратную клавиатуру. Число repeat events отдельно не измерялось; проверен
однократный результат при удержании. Focus round trip и intervening edit выполняет
сам fixture; pointer clicks и F8/F9 проходят настоящий Wayland/GDK путь.

Следующий этап — выбрать одно реальное приложение и проверить его доступный
текстовый API, контекст поля и range replacement. Общий daemon пока остаётся
physical-relay-only; глобальные text capabilities и завершение G3 не заявлены.

Продолжение: [проверка GNOME Text Editor](29-real-editor-checkpoint.md).
