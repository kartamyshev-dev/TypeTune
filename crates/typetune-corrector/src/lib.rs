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

#[cfg(test)]
mod tests {
    use super::*;
    use dictionary::Dictionary;
    fn make_corrector(dict_content_ru: &str, dict_content_en: &str) -> LayoutCorrector {
        let unique = std::process::id().to_string()
            + &std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
                .to_string();
        let tmp = std::env::temp_dir().join(format!("typetune-test-dicts-{}", unique));
        let _ = std::fs::create_dir_all(&tmp);
        std::fs::write(tmp.join("ru.txt"), dict_content_ru).unwrap();
        std::fs::write(tmp.join("en.txt"), dict_content_en).unwrap();
        LayoutCorrector::new(
            Dictionary::load(&tmp.join("ru.txt")),
            Dictionary::load(&tmp.join("en.txt")),
            2,
            true,
            400,
        )
    }

    fn pressed_with_char(keycode: u32, ch: char) -> InputEvent {
        InputEvent::new(keycode, KeyState::Pressed)
            .with_character(ch)
            .with_timestamp(Instant::now())
    }

    fn released(keycode: u32) -> InputEvent {
        InputEvent::new(keycode, KeyState::Released).with_timestamp(Instant::now())
    }

    fn separator(ch: char) -> InputEvent {
        pressed_with_char(57, ch)
    }

    // Regression: audit F09
    // Input: g↓ h↓ b↓ d↓ t↓ n↓ (each with character), then Space↓
    // Expected by current code: 6 Pressed suppressed (buffered), then
    // 6 Backspace + 6 letter keycodes + Space
    // BUG: Backspaces delete text BEFORE the word because letters were never
    // sent to the application. The corrector assumes letters are already visible.
    // This test DOCUMENTS the current broken behavior.
    #[test]
    fn f09_corrector_deletes_before_word() {
        let mut corrector = make_corrector("привет", "hello");

        // Type "ghbdtn" — each letter is buffered, nothing returned
        let letters = vec![
            pressed_with_char(34, 'g'),
            pressed_with_char(35, 'h'),
            pressed_with_char(48, 'b'),
            pressed_with_char(32, 'd'),
            pressed_with_char(20, 't'),
            pressed_with_char(49, 'n'),
        ];

        let mut buffered_count = 0;
        for ev in &letters {
            let result = corrector.process(ev.clone());
            if result.is_empty() {
                buffered_count += 1;
            }
        }
        assert_eq!(
            buffered_count, 6,
            "All 6 letters are buffered (not forwarded)"
        );

        // Space triggers correction
        let space = separator(' ');
        let result = corrector.process(space);

        // Current behavior: 6 Backspace Down+Up + 6 letter Down+Up + Space Down+Up
        // = 12 + 12 + 2 = 26 events... but Backspaces delete pre-existing text!
        let backspace_count = result.iter().filter(|e| e.keycode == 14).count();
        let letter_press_count = result
            .iter()
            .filter(|e| e.keycode != 14 && e.keycode != 57 && e.state == KeyState::Pressed)
            .count();

        assert_eq!(backspace_count, 12, "6 Backspace Down+Up generated");
        assert_eq!(
            letter_press_count, 6,
            "6 replacement letter Down+Up generated"
        );

        // This is the documented bug: Backspaces will delete 6 chars before the cursor
        // that were never part of this word
    }

    // Regression: audit F10
    // Pressed with character, Released without character → orphan Up
    #[test]
    fn f10_orphan_release_without_character() {
        let mut corrector = make_corrector("привет", "hello");

        // Down with character — buffered
        let down = pressed_with_char(30, 'a');
        let result = corrector.process(down);
        assert!(result.is_empty(), "Letter Down is buffered");

        // Up without character — passes through None branch
        let up = released(30);
        let result = corrector.process(up);
        assert_eq!(result.len(), 1, "Release passes through");
        assert_eq!(result[0].state, KeyState::Released);
        assert_eq!(result[0].keycode, 30);
    }

    // Verify that non-matching words are flushed as-is
    #[test]
    fn non_matching_word_flushed() {
        let mut corrector = make_corrector("привет", "hello");

        let result = corrector.process(pressed_with_char(30, 'x'));
        assert!(result.is_empty(), "First letter buffered");

        let result = corrector.process(pressed_with_char(31, 'z'));
        assert!(result.is_empty(), "Second letter buffered");

        // Space after unknown word — flush buffered letters
        let result = corrector.process(separator(' '));
        assert!(!result.is_empty(), "Buffered letters flushed on separator");
        // Should contain the original letters + space
        let pressed: Vec<u32> = result
            .iter()
            .filter(|e| e.state == KeyState::Pressed)
            .map(|e| e.keycode)
            .collect();
        // Buffered chars are converted via char_to_keycode on flush:
        // 'x' -> 45, 'z' -> 44, ' ' -> 57
        assert!(pressed.contains(&45), "Flushed keycode for 'x'");
        assert!(pressed.contains(&44), "Flushed keycode for 'z'");
        assert!(pressed.contains(&57), "Space keycode");
    }

    // Verify short words are not corrected
    #[test]
    fn short_word_not_corrected() {
        let mut corrector = make_corrector("привет", "hi");

        corrector.process(pressed_with_char(34, 'g'));
        let result = corrector.process(separator(' '));
        // 'g' is only 1 char, min_word_length=2, so no correction
        let has_backspace = result.iter().any(|e| e.keycode == 14);
        assert!(!has_backspace, "Short word should not trigger correction");
    }
}
