use std::collections::HashMap;
use std::time::{Duration, Instant};
use typetune_core::event::{InputEvent, KeyState};
use typetune_core::pipeline::PipelineStage;

#[derive(Default, Debug)]
pub struct ChatterStats {
    pub total_events: u64,
    pub suppressed_events: u64,
    pub per_key_suppressed: HashMap<u32, u64>,
}

pub struct AntiChatter {
    last_press: HashMap<u32, Instant>,
    debounce_window: Duration,
    modifier_debounce_window: Duration,
    modifier_keys: Vec<u32>,
    stats: ChatterStats,
}

impl AntiChatter {
    pub fn new(debounce_ms: u64, modifier_debounce_ms: u64) -> Self {
        Self {
            last_press: HashMap::new(),
            debounce_window: Duration::from_millis(debounce_ms),
            modifier_debounce_window: Duration::from_millis(modifier_debounce_ms),
            modifier_keys: vec![
                42, 54, // LEFT_SHIFT, RIGHT_SHIFT
                29, 97, // LEFT_CTRL, RIGHT_CTRL
                56, 100, // LEFT_ALT, RIGHT_ALT
                125, // LEFT_META
            ],
            stats: ChatterStats::default(),
        }
    }

    fn is_modifier(&self, keycode: u32) -> bool {
        self.modifier_keys.contains(&keycode)
    }

    fn get_window(&self, keycode: u32) -> Duration {
        if self.is_modifier(keycode) {
            self.modifier_debounce_window
        } else {
            self.debounce_window
        }
    }

    pub fn stats(&self) -> &ChatterStats {
        &self.stats
    }
}

impl PipelineStage for AntiChatter {
    fn name(&self) -> &str {
        "anti-chatter"
    }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        self.stats.total_events += 1;

        if event.state == KeyState::Pressed {
            let window = self.get_window(event.keycode);

            if let Some(last) = self.last_press.get(&event.keycode) {
                if event.timestamp.duration_since(*last) < window {
                    self.stats.suppressed_events += 1;
                    *self
                        .stats
                        .per_key_suppressed
                        .entry(event.keycode)
                        .or_insert(0) += 1;
                    tracing::trace!(
                        keycode = event.keycode,
                        "Chatter suppressed ({}ms < {}ms)",
                        event.timestamp.duration_since(*last).as_millis(),
                        window.as_millis()
                    );
                    return vec![];
                }
            }

            self.last_press.insert(event.keycode, event.timestamp);
        }

        vec![event]
    }
}
