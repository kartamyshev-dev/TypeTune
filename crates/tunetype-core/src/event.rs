use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Pressed,
    Released,
}

#[derive(Debug, Clone)]
pub struct InputEvent {
    pub keycode: u32,
    pub state: KeyState,
    pub timestamp: Instant,
    pub character: Option<char>,
}

impl InputEvent {
    pub fn new(keycode: u32, state: KeyState) -> Self {
        Self {
            keycode,
            state,
            timestamp: Instant::now(),
            character: None,
        }
    }

    pub fn with_character(mut self, ch: char) -> Self {
        self.character = Some(ch);
        self
    }
}
