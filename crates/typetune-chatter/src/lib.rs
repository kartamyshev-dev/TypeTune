use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use typetune_core::event::{InputEvent, KeyState};
use typetune_core::pipeline::PipelineStage;

#[derive(Default, Debug, Clone)]
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
    shared_stats: Arc<Mutex<ChatterStats>>,
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
            shared_stats: Arc::new(Mutex::new(ChatterStats::default())),
        }
    }

    pub fn with_shared_stats(mut self, stats: Arc<Mutex<ChatterStats>>) -> Self {
        self.shared_stats = stats;
        self
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

    pub fn stats(&self) -> ChatterStats {
        self.shared_stats.lock().unwrap().clone()
    }
}

impl PipelineStage for AntiChatter {
    fn name(&self) -> &str {
        "anti-chatter"
    }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        {
            let mut stats = self.shared_stats.lock().unwrap();
            stats.total_events += 1;
        }

        if event.state == KeyState::Pressed {
            let window = self.get_window(event.keycode);

            if let Some(last) = self.last_press.get(&event.keycode) {
                if event.timestamp.duration_since(*last) < window {
                    {
                        let mut stats = self.shared_stats.lock().unwrap();
                        stats.suppressed_events += 1;
                        *stats.per_key_suppressed.entry(event.keycode).or_insert(0) += 1;
                    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use typetune_core::testing::fake_capture::{key_down, key_up};

    fn run_through(events: Vec<InputEvent>, debounce_ms: u64) -> Vec<InputEvent> {
        let mut chatter = AntiChatter::new(debounce_ms, 30);
        let mut output = Vec::new();
        for ev in events {
            output.extend(chatter.process(ev));
        }
        output
    }

    fn actions(events: &[InputEvent]) -> Vec<KeyState> {
        events.iter().map(|e| e.state).collect()
    }

    // Regression: audit L09 trace 1
    // Input: Down@0, Up@10, Down@15, Up@20 with debounce=50ms
    // Current broken behavior: 0↓,10↑,20↑ (second Down suppressed, orphan Up)
    // This test DOCUMENTS the current broken behavior. After fix, expected should be
    // balanced Down/Up pairs.
    #[test]
    fn l09_rapid_press_suppresses_down_but_not_up() {
        let t = Instant::now();
        let events = vec![
            key_down(30, t),
            key_up(30, t + Duration::from_millis(10)),
            key_down(30, t + Duration::from_millis(15)),
            key_up(30, t + Duration::from_millis(20)),
        ];
        let result = run_through(events, 50);
        let acts = actions(&result);
        // Current behavior: second Down is suppressed but its Up passes through
        // This creates an orphan Up (release without matching press)
        assert_eq!(
            result.len(),
            3,
            "Expected 3 events (current broken behavior)"
        );
        assert_eq!(
            acts,
            vec![KeyState::Pressed, KeyState::Released, KeyState::Released],
            "Current behavior: orphan Up after suppressed Down"
        );
    }

    // Regression: audit L09 trace 2
    // Input: Down@0, Up@1000, Down@1005, Up@1010 with debounce=50ms
    // Long hold then quick re-press: should not suppress the second press
    #[test]
    fn l09_long_hold_then_quick_repress_not_suppressed() {
        let t = Instant::now();
        let events = vec![
            key_down(30, t),
            key_up(30, t + Duration::from_millis(1000)),
            key_down(30, t + Duration::from_millis(1005)),
            key_up(30, t + Duration::from_millis(1010)),
        ];
        let result = run_through(events, 50);
        assert_eq!(result.len(), 4, "All 4 events should pass after long hold");
        assert_eq!(
            actions(&result),
            vec![
                KeyState::Pressed,
                KeyState::Released,
                KeyState::Pressed,
                KeyState::Released
            ]
        );
    }

    // Regression: audit L09 trace 3
    // Two devices pressing same key: D1:0↓, D2:20↓, D1:30↑, D2:70↑
    // Current behavior without device identity: D2 Down is suppressed because
    // the filter only tracks keycode, not (device, keycode).
    // This test DOCUMENTS the current broken behavior.
    #[test]
    fn l09_two_devices_same_key_no_identity() {
        let t = Instant::now();
        let events = vec![
            key_down(30, t),                             // D1 press
            key_down(30, t + Duration::from_millis(20)), // D2 press (different device, same keycode)
            key_up(30, t + Duration::from_millis(30)),   // D1 release
            key_up(30, t + Duration::from_millis(70)),   // D2 release
        ];
        let result = run_through(events, 50);
        // Current broken behavior: D2's Down is suppressed because filter
        // sees same keycode within debounce window without device identity
        assert_eq!(
            result.len(),
            3,
            "Current behavior: D2 Down suppressed (no device identity)"
        );
    }

    // Verify that normal typing is not affected by chatter filter
    #[test]
    fn normal_typing_passes_through() {
        let t = Instant::now();
        let events = vec![
            key_down(30, t), // 'a'
            key_up(30, t + Duration::from_millis(50)),
            key_down(31, t + Duration::from_millis(100)), // 's'
            key_up(31, t + Duration::from_millis(150)),
            key_down(32, t + Duration::from_millis(200)), // 'd'
            key_up(32, t + Duration::from_millis(250)),
        ];
        let result = run_through(events, 50);
        assert_eq!(result.len(), 6, "Normal typing should pass through");
    }

    // Verify repeat events are passed through (they are not Pressed)
    #[test]
    fn repeat_events_not_filtered() {
        let t = Instant::now();
        let events = vec![
            key_down(30, t),
            // Simulate repeat as another Pressed (current model doesn't have Repeat)
            key_down(30, t + Duration::from_millis(50)),
            key_down(30, t + Duration::from_millis(100)),
            key_up(30, t + Duration::from_millis(150)),
        ];
        let result = run_through(events, 50);
        // Downs spaced exactly 50ms apart = window, so all pass
        assert_eq!(
            result.len(),
            4,
            "Downs at 50ms intervals equal to window pass"
        );
    }

    // Stats tracking
    #[test]
    fn stats_count_suppressed() {
        let stats = Arc::new(Mutex::new(ChatterStats::default()));
        let mut chatter = AntiChatter::new(50, 30).with_shared_stats(stats.clone());
        let t = Instant::now();

        chatter.process(key_down(30, t));
        chatter.process(key_down(30, t + Duration::from_millis(10))); // suppressed
        chatter.process(key_up(30, t + Duration::from_millis(20)));

        let s = chatter.stats();
        assert_eq!(s.total_events, 3);
        assert_eq!(s.suppressed_events, 1);
        assert_eq!(s.per_key_suppressed.get(&30), Some(&1));
    }
}
