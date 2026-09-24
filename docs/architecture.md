# Архитектура

## Слои

```text
┌─────────────────────────────────────────────────────────┐
│  UI (GTK tray / macOS menu bar)                         │
│  один controller, generation ACK настройки              │
└───────────────────────────┬─────────────────────────────┘
                            │ configure / status
┌───────────────────────────▼─────────────────────────────┐
│  typetune-bridge  (JSON ABI, protocol)                  │
│  gesture, history, anti-loop, learned words             │
└───────────────────────────┬─────────────────────────────┘
                            │ plans / suggestions
┌───────────────────────────▼─────────────────────────────┐
│  typetune-engine                                        │
│  layout mapping, frequency scoring, snippets, guards    │
└─────────────────────────────────────────────────────────┘

Platform adapters (не смешивать с engine):
  Linux  — passive evdev/uinput + session helper
  macOS  — CGEvent tap + Accessibility + Text Input Source
```

## Принципы

1. **Физический ввод и текстовые правки — разные контракты.** Callback наблюдения не блокируется UI, диском, сетью или звуком. Обычные нажатия сразу идут приложению.
2. **Один план замены — один исполнитель.** Правила выдают план (диапазон + replacement); исполнитель удаляет, вставляет Unicode, следит за модификаторами и фиксирует результат. Нет «поправить +8 keycode» в общем пути.
3. **Свои события помечены.** Синтетические клавиши не считаются новым пользовательским вводом и не запускают коррекцию по кругу.
4. **Unknown ≠ успех.** Неизвестный фокус, selection, composition, чувствительность поля или раскладка не притворяются подтверждённой безопасностью. После неопределённого результата **нет** слепого повтора.
5. **Смена раскладки — явное действие.** После успешной правки целевой язык остаётся; скрытых переключений вне плана нет. Первое слово после смены раскладки авто не правится (анти-петля).
6. **Приватность.** История — только RAM; слова и clipboard не пишутся в обычные логи.

## Коррекция (engine)

| Режим | Триггер | Решение |
|---|---|---|
| Manual | Double Shift | Перекладка последнего слова (без требований словаря) |
| Auto | Space (граница слова) | Ratio-скоринг частотных словарей + охрана URL/кода/регистра |

Таблица соответствия — посимвольная US ↔ Русская (ПК), **не** транслитерация. Сложные раскладки, AltGr и dead keys — вне таблицы.

## Bridge protocol

JSON-операции (урезанно): `configure`, `key_event`, `edit_result`, `layout_notice`, `learned_add` / `learned_clear`, `reset_context`, `prepare` / `smart` / `authorize` / `observe`, `infer`.

`edit_result` — три состояния: `ok` | `failed_before` | `unknown_after` (старые имена принимаются как alias).

Лимиты ABI: вход ≤ 512 KiB, ответ ≤ 32 KiB; превышение отменяет транзакцию без retry.

## Платформенные границы

| | Linux | macOS |
|---|---|---|
| Наблюдение | evdev (без exclusive grab) | CGEvent session tap (listen-only) |
| Вывод | отдельное uinput-устройство | CGEvent post (Unicode / Backspace) |
| Раскладка | session helper / compositor | Text Input Source API + readback |
| Контекст текста | keymap-inferred (limited) | Accessibility (с timeout), fallback inferred |

Неизвестные capabilities остаются Unknown в статусе UI.

## Настройки (Linux)

`~/.config/typetune/settings.json` — schema v2 c `generation` ACK (uuid). Поля-тумблеры
совпадают с macOS `Settings.swift` по смыслу: auto/manual switching, switch-only-last-word,
dont-switch-words, dont-correct-after-layout-change, display-layout-flag, play-switching-sound,
active-keyboards. Слова и исключения приложений живут в отдельных файлах с собственным
generation (`words.json`, `applications.json`).

Политика передаётся в bridge через `configure.policy`; `infer` учитывает её
(`layout_only` при `dont_switch_words`). Внешняя смена раскладки вызывает `layout_notice`
и пропускает **одно** авто-слово (анти-петля).
