use crate::event::{InputEvent, KeyState};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditorAction {
    Insert(char),
    DeleteBackward,
    FocusChange,
    None,
}

#[derive(Debug, Clone)]
pub struct EditorState {
    pub text: Vec<char>,
    pub cursor: usize,
    pub focused: bool,
}

impl EditorState {
    pub fn new() -> Self {
        Self {
            text: Vec::new(),
            cursor: 0,
            focused: true,
        }
    }

    pub fn text_string(&self) -> String {
        self.text.iter().collect()
    }

    pub fn insert(&mut self, ch: char) {
        if !self.focused {
            return;
        }
        self.text.insert(self.cursor, ch);
        self.cursor += 1;
    }

    pub fn delete_backward(&mut self) {
        if !self.focused || self.cursor == 0 {
            return;
        }
        self.cursor -= 1;
        self.text.remove(self.cursor);
    }

    pub fn unfocus(&mut self) {
        self.focused = false;
    }

    pub fn focus(&mut self) {
        self.focused = true;
    }
}

impl Default for EditorState {
    fn default() -> Self {
        Self::new()
    }
}

pub struct TestEditor {
    pub state: EditorState,
    keycode_to_char: HashMap<u32, char>,
}

impl TestEditor {
    pub fn new() -> Self {
        let mut keycode_to_char = HashMap::new();
        // Standard US QWERTY layout for testing
        keycode_to_char.insert(16, 'q');
        keycode_to_char.insert(17, 'w');
        keycode_to_char.insert(18, 'e');
        keycode_to_char.insert(19, 'r');
        keycode_to_char.insert(20, 't');
        keycode_to_char.insert(21, 'y');
        keycode_to_char.insert(22, 'u');
        keycode_to_char.insert(23, 'i');
        keycode_to_char.insert(24, 'o');
        keycode_to_char.insert(25, 'p');
        keycode_to_char.insert(30, 'a');
        keycode_to_char.insert(31, 's');
        keycode_to_char.insert(32, 'd');
        keycode_to_char.insert(33, 'f');
        keycode_to_char.insert(34, 'g');
        keycode_to_char.insert(35, 'h');
        keycode_to_char.insert(36, 'j');
        keycode_to_char.insert(37, 'k');
        keycode_to_char.insert(38, 'l');
        keycode_to_char.insert(44, 'z');
        keycode_to_char.insert(45, 'x');
        keycode_to_char.insert(46, 'c');
        keycode_to_char.insert(47, 'v');
        keycode_to_char.insert(48, 'b');
        keycode_to_char.insert(49, 'n');
        keycode_to_char.insert(50, 'm');
        keycode_to_char.insert(57, ' ');
        keycode_to_char.insert(28, '\n');
        keycode_to_char.insert(15, '\t');

        Self {
            state: EditorState::new(),
            keycode_to_char,
        }
    }

    pub fn with_ru_layout(mut self) -> Self {
        self.keycode_to_char.insert(16, 'й');
        self.keycode_to_char.insert(17, 'ц');
        self.keycode_to_char.insert(18, 'у');
        self.keycode_to_char.insert(19, 'к');
        self.keycode_to_char.insert(20, 'е');
        self.keycode_to_char.insert(21, 'н');
        self.keycode_to_char.insert(22, 'г');
        self.keycode_to_char.insert(23, 'ш');
        self.keycode_to_char.insert(24, 'щ');
        self.keycode_to_char.insert(25, 'з');
        self.keycode_to_char.insert(30, 'ф');
        self.keycode_to_char.insert(31, 'ы');
        self.keycode_to_char.insert(32, 'в');
        self.keycode_to_char.insert(33, 'а');
        self.keycode_to_char.insert(34, 'п');
        self.keycode_to_char.insert(35, 'р');
        self.keycode_to_char.insert(36, 'о');
        self.keycode_to_char.insert(37, 'л');
        self.keycode_to_char.insert(38, 'д');
        keycode_to_char_russian(&mut self.keycode_to_char);
        self
    }

    pub fn apply(&mut self, event: &InputEvent) -> EditorAction {
        if !self.state.focused {
            return EditorAction::None;
        }

        match event.state {
            KeyState::Pressed => {
                if event.keycode == 14 {
                    // Backspace
                    self.state.delete_backward();
                    EditorAction::DeleteBackward
                } else if let Some(ch) = event.character {
                    self.state.insert(ch);
                    EditorAction::Insert(ch)
                } else if let Some(&ch) = self.keycode_to_char.get(&event.keycode) {
                    self.state.insert(ch);
                    EditorAction::Insert(ch)
                } else {
                    EditorAction::None
                }
            }
            KeyState::Released => EditorAction::None,
        }
    }

    pub fn apply_sequence(&mut self, events: &[InputEvent]) -> Vec<EditorAction> {
        events.iter().map(|e| self.apply(e)).collect()
    }

    pub fn text(&self) -> String {
        self.state.text_string()
    }

    pub fn cursor(&self) -> usize {
        self.state.cursor
    }

    pub fn unfocus(&mut self) {
        self.state.unfocus();
    }

    pub fn focus(&mut self) {
        self.state.focus();
    }
}

impl Default for TestEditor {
    fn default() -> Self {
        Self::new()
    }
}

fn keycode_to_char_russian(map: &mut HashMap<u32, char>) {
    map.insert(44, 'я');
    map.insert(45, 'ч');
    map.insert(46, 'с');
    map.insert(47, 'м');
    map.insert(48, 'и');
    map.insert(49, 'т');
    map.insert(50, 'ь');
    map.insert(51, 'б');
    map.insert(52, 'ю');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn editor_insert_and_text() {
        let mut editor = TestEditor::new();
        let t = std::time::Instant::now();
        editor.apply(&InputEvent::new(30, KeyState::Pressed).with_timestamp(t)); // 'a'
        editor.apply(&InputEvent::new(31, KeyState::Pressed).with_timestamp(t)); // 's'
        assert_eq!(editor.text(), "as");
        assert_eq!(editor.cursor(), 2);
    }

    #[test]
    fn editor_delete_backward() {
        let mut editor = TestEditor::new();
        let t = std::time::Instant::now();
        editor.apply(&InputEvent::new(30, KeyState::Pressed).with_timestamp(t)); // 'a'
        editor.apply(&InputEvent::new(14, KeyState::Pressed).with_timestamp(t)); // backspace
        assert_eq!(editor.text(), "");
        assert_eq!(editor.cursor(), 0);
    }

    #[test]
    fn editor_backspace_at_start_noop() {
        let mut editor = TestEditor::new();
        let t = std::time::Instant::now();
        editor.apply(&InputEvent::new(14, KeyState::Pressed).with_timestamp(t));
        assert_eq!(editor.text(), "");
    }

    #[test]
    fn editor_unfocused_ignores_input() {
        let mut editor = TestEditor::new();
        let t = std::time::Instant::now();
        editor.unfocus();
        editor.apply(&InputEvent::new(30, KeyState::Pressed).with_timestamp(t));
        assert_eq!(editor.text(), "");
    }

    #[test]
    fn editor_focus_change() {
        let mut editor = TestEditor::new();
        assert!(editor.state.focused);
        editor.unfocus();
        assert!(!editor.state.focused);
        editor.focus();
        assert!(editor.state.focused);
    }

    #[test]
    fn editor_with_ru_layout() {
        let mut editor = TestEditor::new().with_ru_layout();
        let t = std::time::Instant::now();
        editor.apply(&InputEvent::new(30, KeyState::Pressed).with_timestamp(t)); // 'ф'
        assert_eq!(editor.text(), "ф");
    }
}
