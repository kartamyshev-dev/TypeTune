use crate::event::{InputEvent, KeyState};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmittedEvent {
    pub keycode: u32,
    pub state: KeyState,
    pub character: Option<char>,
}

impl From<&InputEvent> for EmittedEvent {
    fn from(ev: &InputEvent) -> Self {
        Self {
            keycode: ev.keycode,
            state: ev.state,
            character: ev.character,
        }
    }
}

#[derive(Clone)]
pub struct FakeOutput {
    emitted: Arc<Mutex<Vec<EmittedEvent>>>,
}

impl FakeOutput {
    pub fn new() -> Self {
        Self {
            emitted: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn emit(&self, event: &InputEvent) {
        self.emitted.lock().unwrap().push(EmittedEvent::from(event));
    }

    pub fn emitted(&self) -> Vec<EmittedEvent> {
        self.emitted.lock().unwrap().clone()
    }

    pub fn clear(&self) {
        self.emitted.lock().unwrap().clear();
    }

    pub fn len(&self) -> usize {
        self.emitted.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.emitted.lock().unwrap().is_empty()
    }

    pub fn pressed_keycodes(&self) -> Vec<u32> {
        self.emitted
            .lock()
            .unwrap()
            .iter()
            .filter(|e| e.state == KeyState::Pressed)
            .map(|e| e.keycode)
            .collect()
    }

    pub fn released_keycodes(&self) -> Vec<u32> {
        self.emitted
            .lock()
            .unwrap()
            .iter()
            .filter(|e| e.state == KeyState::Released)
            .map(|e| e.keycode)
            .collect()
    }

    pub fn summary(&self) -> String {
        let events = self.emitted.lock().unwrap();
        let parts: Vec<String> = events
            .iter()
            .map(|e| {
                let action = match e.state {
                    KeyState::Pressed => "↓",
                    KeyState::Released => "↑",
                };
                if let Some(ch) = e.character {
                    format!("{}{}({})", e.keycode, action, ch)
                } else {
                    format!("{}{}", e.keycode, action)
                }
            })
            .collect();
        parts.join(" ")
    }
}

impl Default for FakeOutput {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_output_records_events() {
        let out = FakeOutput::new();
        let ev = InputEvent::new(30, KeyState::Pressed);
        out.emit(&ev);
        assert_eq!(out.len(), 1);
        assert_eq!(out.emitted()[0].keycode, 30);
        assert_eq!(out.emitted()[0].state, KeyState::Pressed);
    }

    #[test]
    fn fake_output_pressed_released() {
        let out = FakeOutput::new();
        out.emit(&InputEvent::new(30, KeyState::Pressed));
        out.emit(&InputEvent::new(30, KeyState::Released));
        out.emit(&InputEvent::new(31, KeyState::Pressed));
        assert_eq!(out.pressed_keycodes(), vec![30, 31]);
        assert_eq!(out.released_keycodes(), vec![30]);
    }

    #[test]
    fn fake_output_clear() {
        let out = FakeOutput::new();
        out.emit(&InputEvent::new(30, KeyState::Pressed));
        out.clear();
        assert!(out.is_empty());
    }
}
