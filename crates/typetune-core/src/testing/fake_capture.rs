use crate::event::{InputEvent, KeyState};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

pub struct FakeCapture {
    events: Arc<Mutex<VecDeque<InputEvent>>>,
}

impl FakeCapture {
    pub fn new() -> Self {
        Self {
            events: Arc::new(Mutex::new(VecDeque::new())),
        }
    }

    pub fn enqueue(&self, event: InputEvent) {
        self.events.lock().unwrap().push_back(event);
    }

    pub fn enqueue_sequence(&self, events: Vec<InputEvent>) {
        let mut queue = self.events.lock().unwrap();
        for ev in events {
            queue.push_back(ev);
        }
    }

    pub fn drain(&self) -> Vec<InputEvent> {
        let mut queue = self.events.lock().unwrap();
        queue.drain(..).collect()
    }

    pub fn is_empty(&self) -> bool {
        self.events.lock().unwrap().is_empty()
    }

    pub fn len(&self) -> usize {
        self.events.lock().unwrap().len()
    }
}

impl Default for FakeCapture {
    fn default() -> Self {
        Self::new()
    }
}

pub fn key_down(keycode: u32, ts: std::time::Instant) -> InputEvent {
    InputEvent::new(keycode, KeyState::Pressed).with_timestamp(ts)
}

pub fn key_up(keycode: u32, ts: std::time::Instant) -> InputEvent {
    InputEvent::new(keycode, KeyState::Released).with_timestamp(ts)
}

pub fn key_down_char(keycode: u32, ch: char, ts: std::time::Instant) -> InputEvent {
    InputEvent::new(keycode, KeyState::Pressed)
        .with_character(ch)
        .with_timestamp(ts)
}

pub fn key_up_char(keycode: u32, ch: char, ts: std::time::Instant) -> InputEvent {
    InputEvent::new(keycode, KeyState::Released)
        .with_character(ch)
        .with_timestamp(ts)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_capture_enqueue_drain() {
        let cap = FakeCapture::new();
        let t = std::time::Instant::now();
        cap.enqueue(key_down(30, t));
        cap.enqueue(key_up(30, t));
        assert_eq!(cap.len(), 2);
        let events = cap.drain();
        assert_eq!(events.len(), 2);
        assert!(cap.is_empty());
    }

    #[test]
    fn fake_capture_enqueue_sequence() {
        let cap = FakeCapture::new();
        let t = std::time::Instant::now();
        cap.enqueue_sequence(vec![key_down(30, t), key_up(30, t), key_down(31, t)]);
        assert_eq!(cap.len(), 3);
    }
}
