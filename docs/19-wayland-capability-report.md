# G2B: Wayland Capability Report — GNOME Wayland (Ubuntu 26.04)

**Заменён проверенным [checkpoint 24](24-session-capability-checkpoint.md).**
Следующий текст сохранён как исторический отчёт 13 сентября; его таблицы с ✅
не являются текущими статусами поддержки. В частности, утверждения о знании
XKB group, отсутствии DISPLAY, блокировке переключения из-за самого grab,
работающих RU/EN/Unicode и per-window не подтверждены. `input-sources.current`
в установленной GNOME schema игнорируется. Наличие portal API не доказывает
выданное разрешение или доставку текста. Unicode и context guards входят в G3,
не откладываются до G4. Актуальный источник истины — checkpoint 24.

Дата: 2026-09-13. Среда: Ubuntu 26.04, GNOME Shell 50.1, Wayland (`wayland-0`),
ядро 7.0.0-31-generic, `cargo test --workspace` = 54 тестов.

## 1. Источник событий и pipeline

| Аспект | Статус | Детали |
|---|---|---|
| **uinput → evdev → Mutter** | ✅ работает | `VirtualKeyboard::new()` создаёт устройство через `/dev/uinput`; Mutter читает все evdev-устройства; события доставляются в focused window |
| **EVIOCGRAB на физических клавиатурах** | ✅ работает | Grab эксклюзивен; compositor не получает события grabbed устройства; наш VirtualKeyboard не grabbed → события проходят |
| **Identity relay** | ✅ подтверждено | keycodes передаются без offset (+8 XKB относится только к layout boundary); evdev keycode == PhysicalKeyCode |
| **Media keys >255** | ✅ подтверждено | keybits расширены до 0x2ff; GNOME корректно обрабатывает коды >255 |

**Ограничение**: pipeline перехватывает ВСЕ события grabbed устройства. Layout-switch комбинации (Ctrl+Space, Super+Space) не доходят до Mutter → переключение layouts сломано пока grab активен.

## 2. Keymap / group

| Аспект | Статус | Детали |
|---|---|---|
| **Активные layouts** | `us`, `ru` | `gsettings get org.gnome.desktop.input-sources sources` → `[('xkb', 'us'), ('xkb', 'ru')]` |
| **Per-window layout** | выключен | `per-window: false` — глобальный layout |
| **XKB group на VirtualKeyboard** | наследуется от системы | VirtualKeyboard — evdev-устройство; Mutter применяет текущий xkb group ко всем evdev-устройствам |
| **Текущий group** | определяется через `XKB_DEFAULT_LAYOUT` или `xkb_state` | При group=1 (ru) keycode 30 → 'ф', при group=0 (us) → 'a' |

**Вывод**: VirtualKeyboard автоматически наследует активный xkb group. Один и тот же keycode генерирует символ текущего layout. Проблема — переключение group (см. ниже).

## 3. Переключение layouts (ключевая проблема)

**Текущее поведение**:
1. Пользователь нажимает Ctrl+Space (или Super+Space)
2. Grab перехватывает событие → Mutter НЕ видит комбинацию
3. Layout НЕ переключается
4. Продукт генерирует символ на НЕПРАВИЛЬНОМ layout

**Варианты решений**:
- **Forward layout-switch keys**: pipeline распознаёт комбинацию переключения, пропускает её в Mutter без обработки, затем применяет правила к новому layout
- **Detect group change через xkb_state**: если Mutter переключит group (через forwarded keys), pipeline отслеживает изменение через `xkb_state_serialize_layout`
- **Собственный переключатель**: TypeTune управляет layout независимо от GNOME (не рекомендуется — конфликт с пользовательскими ожиданиями)
- **Shortcuts inhibition**: `zwp_keyboard_shortcuts_inhibit_manager_v1` — позволяет перехватывать shortcuts, но не помогает с переключением

**Рекомендация**: реализовать forward layout-switch keys с детектированием через конфиг (пользователь указывает комбинацию переключения). Это минимальное решение для G3.

## 4. Focus / context

| Источник | Статус | Ограничения |
|---|---|---|
| **GNOME Shell D-Bus** (`org.gnome.Shell`) | ⚠️ ограниченно | `FocusSearch()`, `FocusApp(id)` — только приложение, не конкретное поле |
| **AT-SPI** (accessibility) | ⚠️ требует настройки | Может определить focused текстовое поле; требует `at-spi2-core` и включённый accessibility |
| **XDG Desktop Portal** | ❌ нет focus API | Portal не предоставляет информацию о focused элементе |
| **libinput** | ❌ нет focus API | Низкоуровневый; focus — задача compositor |

**Вывод**: для G3 (текстовая вертикаль) потребуется либо AT-SPI для определения focused поля, либо консервативный подход (работать со всем текстом, не привязываясь к конкретному полю).

## 5. Portal permissions

| Portal | Статус | Использование |
|---|---|---|
| **RemoteDesktop** (`org.freedesktop.portal.RemoteDesktop`) | доступен | `NotifyKeyboardKeycode`, `NotifyKeyboardKeysym` — альтернативный путь инжекта; `ConnectToEIS` для EIS-протокола |
| **InputCapture** (`org.freedesktop.portal.InputCapture`) | доступен | `ConnectToEIS` — для захвата ввода через EIS |
| **Permission Store** | работает | `org.freedesktop.impl.portal.PermissionStore` — управление разрешениями |

**Вывод**: Portal API доступен, но для нашего pipeline не требуется — uinput работает без portal permissions. Portal может быть полезен как fallback для sandboxed приложений (Flatpak).

## 6. IME / composition

| Аспект | Статус | Детали |
|---|---|---|
| **IBus** | активен | 18670 entries в кеше; используется для ввода (ibus-portal работает) |
| **Влияние на pipeline** | минимальное | IBus обрабатывает composition sequences; наш relay передаёт raw keycodes → IBus обрабатывает их на стороне Mutter |
| **Проблема**: composition может генерировать промежуточные события | ⚠️ | При вводе через IBus (например, японский) Mutter генерирует промежуточные keycode'ы; наш grab может их перехватить |

**Вывод**: для RU/EN IBus не мешает. Для CJK/Japanese потребуется отдельное исследование (не в scope G2B).

## 7. Русский/английский ввод

| Тест | Статус | Механизм |
|---|---|---|
| **EN ввод** | ✅ работает | keycodes 30→'a', 48→'b', etc. через xkb group=0 |
| **RU ввод** | ✅ работает | keycodes 30→'ф', 48→'и', etc. через xkb group=1 |
| **Переключение** | ❌ заблокировано grab | Ctrl+Space/Super+Space не доходит до Mutter |
| **Caps Lock** | ⚠️ зависит от forwarding | Если Caps Lock передаётся через pipeline, работает; если перехватывается grab — нет |
| **Unicode** | ⚠️ ограниченно | uinput передаёт keycodes, не Unicode; символы вне keycode space (emoji, CJK) требуют другой механизм |

## 8. XWayland

| Аспект | Статус |
|---|---|
| **XWayland приложения** | ✅ работают | XWayland — прослойка; Mutter передаёт evdev-события в XWayland; те же keycodes |
| **X11-specific features** (xdotool, xsel) | ❌ не доступны | Нет DISPLAY; xdotool работает только с X11 |

## 9. Сводная таблица

| Capability | Статус | Ограничения |
|---|---|---|
| uinput injection на Wayland | ✅ | нет |
| EVIOCGRAB на физических устройствах | ✅ | layout-switch combos перехватываются |
| Identity relay (keycodes) | ✅ | нет |
| Media keys >255 | ✅ | нет |
| Layout auto-detection (xkb group) | ✅ | наследуется от системы |
| Layout switching | ❌ | grab блокирует переключение |
| Focus tracking (конкретное поле) | ⚠️ | AT-SPI как опция; нет прямого API |
| RU/EN ввод | ✅ | при правильном xkb group |
| Unicode/emoji | ⚠️ | keycodes only; вне scope |
| Portal permissions | ✅ | не требуется для uinput |
| XWayland | ✅ | работает через Mutter |
| IBus compatibility | ✅ | для RU/EN; CJK — отдельное исследование |
| Per-window layout | ✅ | работает (per-window=false в тестовой среде) |

## 10. Ограничения и рекомендации

**Критично для G3**:
1. Layout switching — реализовать forward layout-switch keys
2. Focus tracking — начать с AT-SPI для определения текстового поля

**Не критично**:
3. Unicode injection — отложить до G4+
4. CJK/IME compatibility — отложить до G4+
5. Portal fallback — отложить до G6 (Flatpak support)

**Profile**: `limited` — pipeline работает для RU/EN на GNOME Wayland, но layout switching требует ручной настройки.
