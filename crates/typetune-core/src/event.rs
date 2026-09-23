use std::fmt;
use std::time::Instant;

use crate::clock::Clock;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum KeyAction {
    Down,
    Up,
    Repeat,
}

impl fmt::Display for KeyAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            KeyAction::Down => write!(f, "Down"),
            KeyAction::Up => write!(f, "Up"),
            KeyAction::Repeat => write!(f, "Repeat"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct DeviceId(pub u64);

impl DeviceId {
    pub const UNKNOWN: DeviceId = DeviceId(0);
}

impl fmt::Display for DeviceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Device({})", self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct DeviceGeneration(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct NativeEvdevCode(pub u16);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct PhysicalKeyCode(pub u16);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NativeCode {
    Evdev(NativeEvdevCode),
    Unknown(u32),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventOrigin {
    Physical,
    HardwareRelay(DeviceId, DeviceGeneration),
    TextInjection(u64),
    /// Reconstructed key state after a kernel `SYN_DROPPED` (evdev overflow).
    /// Carries the up-to-date hold state only; the lost event history is not
    /// reconstructable and must not be treated as fresh key presses.
    Resync,
    OtherSynthetic,
    Unknown,
}

impl fmt::Display for EventOrigin {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EventOrigin::Physical => write!(f, "Physical"),
            EventOrigin::HardwareRelay(dev, gen) => {
                write!(f, "HardwareRelay({}, gen={})", dev, gen.0)
            }
            EventOrigin::TextInjection(id) => write!(f, "TextInjection({})", id),
            EventOrigin::Resync => write!(f, "Resync"),
            EventOrigin::OtherSynthetic => write!(f, "OtherSynthetic"),
            EventOrigin::Unknown => write!(f, "Unknown"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct PhysicalKeyEvent {
    pub device_id: DeviceId,
    pub native_code: NativeCode,
    pub physical_key: PhysicalKeyCode,
    pub action: KeyAction,
    pub source_time: Instant,
    pub observed_time: Instant,
    pub sequence: u64,
    pub origin: EventOrigin,
}

impl PhysicalKeyEvent {
    pub fn new(
        native_code: NativeCode,
        physical_key: PhysicalKeyCode,
        action: KeyAction,
        clock: &dyn Clock,
    ) -> Self {
        let now = clock.now();
        Self {
            device_id: DeviceId::UNKNOWN,
            native_code,
            physical_key,
            action,
            source_time: now,
            observed_time: now,
            sequence: 0,
            origin: EventOrigin::Unknown,
        }
    }

    pub fn with_device(mut self, device_id: DeviceId) -> Self {
        self.device_id = device_id;
        self
    }

    pub fn with_origin(mut self, origin: EventOrigin) -> Self {
        self.origin = origin;
        self
    }

    pub fn with_source_time(mut self, time: Instant) -> Self {
        self.source_time = time;
        self
    }

    pub fn with_sequence(mut self, seq: u64) -> Self {
        self.sequence = seq;
        self
    }

    pub fn is_down(&self) -> bool {
        self.action == KeyAction::Down
    }

    pub fn is_up(&self) -> bool {
        self.action == KeyAction::Up
    }

    pub fn is_repeat(&self) -> bool {
        self.action == KeyAction::Repeat
    }
}

// Legacy compatibility: convert from old InputEvent for gradual migration
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

    pub fn with_timestamp(mut self, ts: Instant) -> Self {
        self.timestamp = ts;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clock::FakeClock;

    #[test]
    fn physical_key_event_creation() {
        let clock = FakeClock::at_zero();
        let ev = PhysicalKeyEvent::new(
            NativeCode::Evdev(NativeEvdevCode(30)),
            PhysicalKeyCode(30),
            KeyAction::Down,
            &clock,
        );
        assert_eq!(ev.device_id, DeviceId::UNKNOWN);
        assert_eq!(ev.action, KeyAction::Down);
        assert!(ev.is_down());
        assert!(!ev.is_up());
        assert!(!ev.is_repeat());
    }

    #[test]
    fn physical_key_event_builders() {
        let clock = FakeClock::at_zero();
        let dev = DeviceId(42);
        let ev = PhysicalKeyEvent::new(
            NativeCode::Evdev(NativeEvdevCode(30)),
            PhysicalKeyCode(30),
            KeyAction::Down,
            &clock,
        )
        .with_device(dev)
        .with_origin(EventOrigin::Physical)
        .with_sequence(7);

        assert_eq!(ev.device_id, dev);
        assert_eq!(ev.origin, EventOrigin::Physical);
        assert_eq!(ev.sequence, 7);
    }

    #[test]
    fn key_action_display() {
        assert_eq!(format!("{}", KeyAction::Down), "Down");
        assert_eq!(format!("{}", KeyAction::Up), "Up");
        assert_eq!(format!("{}", KeyAction::Repeat), "Repeat");
    }

    #[test]
    fn device_id_display() {
        assert_eq!(format!("{}", DeviceId(42)), "Device(42)");
        assert_eq!(format!("{}", DeviceId::UNKNOWN), "Device(0)");
    }

    #[test]
    fn event_origin_display() {
        assert_eq!(format!("{}", EventOrigin::Physical), "Physical");
        assert_eq!(
            format!(
                "{}",
                EventOrigin::HardwareRelay(DeviceId(1), DeviceGeneration(2))
            ),
            "HardwareRelay(Device(1), gen=2)"
        );
        assert_eq!(
            format!("{}", EventOrigin::TextInjection(99)),
            "TextInjection(99)"
        );
    }

    #[test]
    fn key_actions_are_distinct() {
        assert_ne!(KeyAction::Down, KeyAction::Up);
        assert_ne!(KeyAction::Down, KeyAction::Repeat);
        assert_ne!(KeyAction::Up, KeyAction::Repeat);
    }

    #[test]
    fn native_code_types() {
        let evdev = NativeCode::Evdev(NativeEvdevCode(30));
        let unknown = NativeCode::Unknown(42);
        assert_ne!(evdev, unknown);
    }
}
