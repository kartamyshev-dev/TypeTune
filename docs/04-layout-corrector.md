# 04 — Layout Corrector (RU↔EN)

## Цель
Автоматически исправлять текст, набранный в неправильной раскладке.

## Шаг 4.1: Маппинг символов

### typetune-corrector/src/layout_map.rs

```rust
/// RU → EN маппинг (стандартная QWERTY ↔ ЙЦУКЕН)
pub const RU_TO_EN: &[(char, char)] = &[
    ('й', 'q'), ('ц', 'w'), ('у', 'e'), ('к', 'r'), ('е', 't'),
    ('н', 'y'), ('г', 'u'), ('ш', 'i'), ('щ', 'o'), ('з', 'p'),
    ('х', '['), ('ъ', ']'), ('ф', 'a'), ('ы', 's'), ('в', 'd'),
    ('а', 'f'), ('п', 'g'), ('р', 'h'), ('о', 'j'), ('л', 'k'),
    ('д', 'l'), ('ж', ';'), ('э', '\''), ('я', 'z'), ('ч', 'x'),
    ('с', 'c'), ('м', 'v'), ('и', 'b'), ('т', 'n'), ('ь', 'm'),
    ('б', ','), ('ю', '.'),
    ('Й', 'Q'), ('Ц', 'W'), ('У', 'E'), ('К', 'R'), ('Е', 'T'),
    ('Н', 'Y'), ('Г', 'U'), ('Ш', 'I'), ('Щ', 'O'), ('З', 'P'),
    ('Х', '{'), ('Ъ', '}'), ('Ф', 'A'), ('Ы', 'S'), ('В', 'D'),
    ('А', 'F'), ('П', 'G'), ('Р', 'H'), ('О', 'J'), ('Л', 'K'),
    ('Д', 'L'), ('Ж', ':'), ('Э', '"'), ('Я', 'Z'), ('Ч', 'X'),
    ('С', 'C'), ('М', 'V'), ('И', 'B'), ('Т', 'N'), ('Ь', 'M'),
    ('Б', '<'), ('Ю', '>'),
];

/// EN → RU (обратный маппинг)
pub const EN_TO_RU: &[(char, char)] = &[
    ('q', 'й'), ('w', 'ц'), ('e', 'у'), ('r', 'к'), ('t', 'е'),
    ('y', 'н'), ('u', 'г'), ('i', 'ш'), ('o', 'щ'), ('p', 'з'),
    ('[', 'х'), (']', 'ъ'), ('a', 'ф'), ('s', 'ы'), ('d', 'в'),
    ('f', 'а'), ('g', 'п'), ('h', 'р'), ('j', 'о'), ('k', 'л'),
    ('l', 'д'), (';', 'ж'), ('\'', 'э'), ('z', 'я'), ('x', 'ч'),
    ('c', 'с'), ('v', 'м'), ('b', 'и'), ('n', 'т'), ('m', 'ь'),
    (',', 'б'), ('.', 'ю'),
    ('Q', 'Й'), ('W', 'Ц'), ('E', 'У'), ('R', 'К'), ('T', 'Е'),
    ('Y', 'Н'), ('U', 'Г'), ('I', 'Ш'), ('O', 'Щ'), ('P', 'З'),
    ('{', 'Х'), ('}', 'Ъ'), ('A', 'Ф'), ('S', 'Ы'), ('D', 'В'),
    ('F', 'А'), ('G', 'П'), ('H', 'Р'), ('J', 'О'), ('K', 'Л'),
    ('L', 'Д'), (';', 'Ж'), ('"', 'Э'), ('Z', 'Я'), ('X', 'Ч'),
    ('C', 'С'), ('V', 'М'), ('B', 'И'), ('N', 'Т'), ('M', 'Ь'),
    ('<', 'Б'), ('>', 'Ю'),
];

/// Транслитерация строки
pub fn transliterate(input: &str, map: &[(char, char)]) -> String {
    let lookup: std::collections::HashMap<char, char> = map.iter().cloned().collect();
    input.chars().map(|c| lookup.get(&c).copied().unwrap_or(c)).collect()
}
```

## Шаг 4.2: Словари

### dict/en.txt и dict/ru.txt
Топ-10000 слов каждого языка. Загружаются в `HashSet<String>`.

```rust
use std::collections::HashSet;
use std::path::Path;

pub struct Dictionary {
    words: HashSet<String>,
}

impl Dictionary {
    pub fn load(path: &Path) -> Self {
        let content = std::fs::read_to_string(path).unwrap_or_default();
        let words: HashSet<String> = content.lines().map(|s| s.to_lowercase()).collect();
        tracing::info!("Загружен словарь {}: {} слов", path.display(), words.len());
        Self { words }
    }

    pub fn contains(&self, word: &str) -> bool {
        self.words.contains(&word.to_lowercase())
    }

    pub fn is_valid_word(&self, word: &str) -> bool {
        word.len() >= 2 && self.contains(word)
    }
}
```

## Шаг 4.3: Логика коррекции

### typetune-corrector/src/lib.rs — PipelineStage

```rust
pub struct LayoutCorrector {
    ru_dict: Dictionary,
    en_dict: Dictionary,
    word_buffer: Vec<char>,
    min_word_length: usize,
    exclude_classes: Vec<String>,
}

impl PipelineStage for LayoutCorrector {
    fn name(&self) -> &str { "layout-corrector" }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        // 1. Если символ — разделитель слова (пробел, enter, пунктуация):
        //    - Проверить word_buffer
        //    - Если не является словом в текущей раскладке → попробовать транслитерацию
        //    - Если транслитерация = валидное слово → выдать backspace*N + исправленный текст
        //    - Очистить буфер
        //
        // 2. Если символ — буква:
        //    - Добавить в word_buffer
        //    - Вернуть пустой вектор (не инжектить промежуточные буквы)
        //
        // 3. Если символ — другое (цифра, спецсимвол):
        //    - Очистить буфер
        //    - Пропустить как есть
        vec![event]
    }
}
```

Алгоритм на псевдокоде:
```
on_key(char c):
    if is_word_char(c):
        word_buffer.push(c)
        return []  // не инжектить промежуточные буквы

    if word_buffer.len() >= min_word_length:
        word: String = word_buffer.collect()
        if !is_valid_word(word, current_layout):
            other = transliterate(word, opposite_map)
            if is_valid_word(other, opposite_layout):
                backspaces = word.len()
                return [BACKSPACE * backspaces] + string_to_events(other)

    result = string_to_events(word_buffer) + [event]
    word_buffer.clear()
    return result
```

## Шаг 4.4: Буферизация и инжект

LayoutCorrector **буферизует** нажатия и **не передаёт** их дальше, пока не встретит разделитель слова. Это позволяет:
- Набрать слово целиком перед проверкой
- Не "моргать" промежуточными символами

```rust
fn inject_correction(&self, wrong: &str, correct: &str) -> Vec<InputEvent> {
    let mut events = Vec::new();
    // Backspace для удаления неправильного слова
    for _ in 0..wrong.len() {
        events.push(InputEvent::new(KEY_BACKSPACE, KeyState::Pressed));
        events.push(InputEvent::new(KEY_BACKSPACE, KeyState::Released));
    }
    // Набор правильного слова
    for ch in correct.chars() {
        events.extend(char_to_key_events(ch));
    }
    events
}
```

## Шаг 4.5: Определение текущей раскладки

### typetune-layout/src/lib.rs

```rust
use xkbcommon::xkb;

pub struct LayoutManager {
    context: xkb::Context,
    keymap: xkb::Keymap,
    state: xkb::State,
}

impl LayoutManager {
    pub fn new() -> Self {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap = xkb::Keymap::new_from_names(
            &context,
            "evdev",
            Some("pc105"),
            Some("us,ru"),
            None,
            None,
        ).expect("Failed to create keymap");
        let state = xkb::State::new(&keymap);
        Self { context, keymap, state }
    }

    pub fn keycode_to_char(&mut self, keycode: u32) -> Option<char> {
        let utf8 = self.state.key_get_utf8(keycode + 8); // +8 для evdev offset
        if utf8.is_empty() { None } else { utf8.chars().next() }
    }

    pub fn update_key(&mut self, keycode: u32, direction: xkb::KeyDirection) {
        self.state.update_key(keycode + 8, direction);
    }

    pub fn current_layout(&self) -> LayoutId {
        let name = self.state.layout_name(0);
        match name.as_deref() {
            Some("ru") | Some("Russian") => LayoutId::Russian,
            _ => LayoutId::English,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LayoutId {
    English,
    Russian,
}
```

## Шаг 4.6: Контекстные исключения

```rust
/// Определить класс активного окна
/// Wayland: ограничено (нет глобального доступа к tree окон)
/// Для GNOME/Wayland: D-Bus → org.gnome.Shell
fn get_active_window_class() -> Option<String> {
    // busctl --user call org.gnome.Shell /org/gnome/shell org.gnome.Shell Eval s
    //   "global.display.focus_window.wm_class"
    None // TODO: реализовать для Wayland
}
```

## Шаг 4.7: Конфигурация

```toml
[corrector]
enabled = true
min_word_length = 3
layouts = ["us", "ru"]
dict_dir = "~/.config/typetune/dict/"
exclude_classes = ["Alacritty", "kitty", "Code", "jetbrains-idea"]
exclude_titles = ["vim", "nano", "emacs"]
```

## Проверочный лист
- [ ] `ghbdtn` → `привет` (EN→RU)
- [ ] `руддщ` → `hello` (RU→EN)
- [ ] Короткие слова (< 3 символов) не исправляются
- [ ] Валидные слова не исправляются
- [ ] Словарь загружается корректно
- [ ] Backspace + инжект работает через uinput
