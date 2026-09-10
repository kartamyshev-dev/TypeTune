pub mod dictionary;
pub mod layout_map;

use dictionary::Dictionary;
use layout_map::{EN_TO_RU, RU_TO_EN};
use std::time::{Duration, Instant};
use typetune_core::event::{InputEvent, KeyState};
use typetune_core::pipeline::PipelineStage;

const LEFT_SHIFT_KEYCODE: u32 = 42;
const RIGHT_SHIFT_KEYCODE: u32 = 54;
const BACKSPACE_KEYCODE: u32 = 14;

pub struct LayoutCorrector {
    ru_dict: Dictionary,
    en_dict: Dictionary,
    word_buffer: Vec<char>,
    min_word_length: usize,
    last_shift_press: Option<Instant>,
    double_shift_corrects: bool,
    double_shift_window: Duration,
}

impl LayoutCorrector {
    pub fn new(
        ru_dict: Dictionary,
        en_dict: Dictionary,
        min_word_length: usize,
        double_shift_corrects: bool,
        double_shift_window_ms: u64,
    ) -> Self {
        Self {
            ru_dict,
            en_dict,
            word_buffer: Vec::new(),
            min_word_length,
            last_shift_press: None,
            double_shift_corrects,
            double_shift_window: Duration::from_millis(double_shift_window_ms),
        }
    }

    fn is_word_char(ch: char) -> bool {
        ch.is_alphabetic()
    }

    fn is_word_separator(ch: char) -> bool {
        ch == ' '
            || ch == '\t'
            || ch == '\n'
            || ch == '\r'
            || ch == '.'
            || ch == ','
            || ch == '!'
            || ch == '?'
            || ch == ';'
            || ch == ':'
            || ch == '('
            || ch == ')'
            || ch == '['
            || ch == ']'
            || ch == '{'
            || ch == '}'
    }

    fn try_correct(&self) -> Option<Vec<InputEvent>> {
        if self.word_buffer.len() < self.min_word_length {
            return None;
        }

        let word: String = self.word_buffer.iter().collect();
        let word_lower = word.to_lowercase();

        let current_is_en = word_lower.is_ascii();
        let current_is_ru = !current_is_en;

        if current_is_en && self.en_dict.is_valid_word(&word_lower) {
            return None;
        }
        if current_is_ru && self.ru_dict.is_valid_word(&word_lower) {
            return None;
        }

        let transliterated = if current_is_en {
            layout_map::transliterate(&word_lower, EN_TO_RU)
        } else {
            layout_map::transliterate(&word_lower, RU_TO_EN)
        };

        let dict = if current_is_en {
            &self.ru_dict
        } else {
            &self.en_dict
        };

        if dict.is_valid_word(&transliterated) {
            tracing::info!("Layout correction: '{}' -> '{}'", word, transliterated);

            let mut events = Vec::new();
            for _ in 0..self.word_buffer.len() {
                events.push(InputEvent::new(BACKSPACE_KEYCODE, KeyState::Pressed));
                events.push(InputEvent::new(BACKSPACE_KEYCODE, KeyState::Released));
            }
            for ch in transliterated.chars() {
                if let Some(kc) = char_to_keycode(ch) {
                    events.push(InputEvent::new(kc, KeyState::Pressed));
                    events.push(InputEvent::new(kc, KeyState::Released));
                }
            }
            return Some(events);
        }

        None
    }

    fn force_correct(&mut self) -> Vec<InputEvent> {
        if self.word_buffer.is_empty() {
            return Vec::new();
        }

        let word: String = self.word_buffer.iter().collect();
        let word_lower = word.to_lowercase();

        let current_is_en = word_lower.is_ascii();

        let transliterated = if current_is_en {
            layout_map::transliterate(&word_lower, EN_TO_RU)
        } else {
            layout_map::transliterate(&word_lower, RU_TO_EN)
        };

        tracing::info!(
            "Manual layout switch (double-Shift): '{}' -> '{}'",
            word,
            transliterated
        );

        let mut events = Vec::new();
        for _ in 0..self.word_buffer.len() {
            events.push(InputEvent::new(BACKSPACE_KEYCODE, KeyState::Pressed));
            events.push(InputEvent::new(BACKSPACE_KEYCODE, KeyState::Released));
        }
        for ch in transliterated.chars() {
            if let Some(kc) = char_to_keycode(ch) {
                events.push(InputEvent::new(kc, KeyState::Pressed));
                events.push(InputEvent::new(kc, KeyState::Released));
            }
        }

        self.word_buffer.clear();
        events
    }

    fn flush_buffer(&mut self) -> Vec<InputEvent> {
        let mut events = Vec::new();
        for &ch in &self.word_buffer {
            if let Some(kc) = char_to_keycode(ch) {
                events.push(InputEvent::new(kc, KeyState::Pressed));
                events.push(InputEvent::new(kc, KeyState::Released));
            }
        }
        self.word_buffer.clear();
        events
    }
}

impl PipelineStage for LayoutCorrector {
    fn name(&self) -> &str {
        "layout-corrector"
    }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        if self.double_shift_corrects
            && event.state == KeyState::Pressed
            && (event.keycode == LEFT_SHIFT_KEYCODE || event.keycode == RIGHT_SHIFT_KEYCODE)
        {
            let now = Instant::now();
            if let Some(last) = self.last_shift_press {
                if now.duration_since(last) < self.double_shift_window {
                    self.last_shift_press = None;
                    return self.force_correct();
                }
            }
            self.last_shift_press = Some(now);
        }

        let ch = match event.character {
            Some(c) => c,
            None => return vec![event],
        };

        if Self::is_word_char(ch) {
            self.word_buffer.push(ch);
            return vec![];
        }

        if Self::is_word_separator(ch) {
            let mut result = Vec::new();

            if let Some(correction) = self.try_correct() {
                result.extend(correction);
            } else {
                result.extend(self.flush_buffer());
            }

            result.push(event);
            self.word_buffer.clear();
            return result;
        }

        let mut result = self.flush_buffer();
        result.push(event);
        result
    }

    fn reset(&mut self) {
        self.word_buffer.clear();
    }
}

fn char_to_keycode(ch: char) -> Option<u32> {
    match ch {
        'q' | 'Q' => Some(16),
        'w' | 'W' => Some(17),
        'e' | 'E' => Some(18),
        'r' | 'R' => Some(19),
        't' | 'T' => Some(20),
        'y' | 'Y' => Some(21),
        'u' | 'U' => Some(22),
        'i' | 'I' => Some(23),
        'o' | 'O' => Some(24),
        'p' | 'P' => Some(25),
        'a' | 'A' => Some(30),
        's' | 'S' => Some(31),
        'd' | 'D' => Some(32),
        'f' | 'F' => Some(33),
        'g' | 'G' => Some(34),
        'h' | 'H' => Some(35),
        'j' | 'J' => Some(36),
        'k' | 'K' => Some(37),
        'l' | 'L' => Some(38),
        'z' | 'Z' => Some(44),
        'x' | 'X' => Some(45),
        'c' | 'C' => Some(46),
        'v' | 'V' => Some(47),
        'b' | 'B' => Some(48),
        'n' | 'N' => Some(49),
        'm' | 'M' => Some(50),
        'ё' | 'Ё' => Some(41),
        'й' | 'Й' => Some(16),
        'ц' | 'Ц' => Some(17),
        'у' | 'У' => Some(18),
        'к' | 'К' => Some(19),
        'е' | 'Е' => Some(20),
        'н' | 'Н' => Some(21),
        'г' | 'Г' => Some(22),
        'ш' | 'Ш' => Some(23),
        'щ' | 'Щ' => Some(24),
        'з' | 'З' => Some(25),
        'х' | 'Х' => Some(26),
        'ъ' | 'Ъ' => Some(27),
        'ф' | 'Ф' => Some(30),
        'ы' | 'Ы' => Some(31),
        'в' | 'В' => Some(32),
        'а' | 'А' => Some(33),
        'п' | 'П' => Some(34),
        'р' | 'Р' => Some(35),
        'о' | 'О' => Some(36),
        'л' | 'Л' => Some(37),
        'д' | 'Д' => Some(38),
        'ж' | 'Ж' => Some(39),
        'э' | 'Э' => Some(40),
        'я' | 'Я' => Some(44),
        'ч' | 'Ч' => Some(45),
        'с' | 'С' => Some(46),
        'м' | 'М' => Some(47),
        'и' | 'И' => Some(48),
        'т' | 'Т' => Some(49),
        'ь' | 'Ь' => Some(50),
        'б' | 'Б' => Some(51),
        'ю' | 'Ю' => Some(52),
        ' ' => Some(57),
        _ => None,
    }
}
