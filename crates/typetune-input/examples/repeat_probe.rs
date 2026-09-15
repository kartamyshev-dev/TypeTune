//! Minimal kernel probe: does the input core forward EV_KEY value=2
//! (autorepeat) written into a uinput device, and in what order?
//! No relay, no grab on the test device, readback on the same process
//! via the transport under test (`EvdevDevice::read_events`).

use evdev::uinput::VirtualDevice;
use evdev::{AttributeSet, EventType, InputEvent, KeyCode};
use std::thread;
use std::time::{Duration, Instant};
use typetune_core::event::DeviceId;
use typetune_input::EvdevDevice;

const PROBE_NAME: &str = "TypeTune Repeat Probe";

fn find_node_by_name(name: &str) -> Option<String> {
    for (path, dev) in evdev::enumerate() {
        if dev.name() == Some(name) {
            return Some(path.to_string_lossy().into_owned());
        }
    }
    None
}

fn key_event(code: u16, value: i32) -> InputEvent {
    InputEvent::new(EventType::KEY.0, KeyCode::new(code).0, value)
}

fn probe_case(label: &str, frames: &[(u16, i32)], grab: bool) {
    let mut keys = AttributeSet::<KeyCode>::new();
    for code in (0u16..=0x2ff).step_by(1) {
        keys.insert(KeyCode::new(code));
    }
    let mut dev = VirtualDevice::builder()
        .unwrap()
        .name(PROBE_NAME)
        .with_keys(&keys)
        .unwrap()
        .build()
        .unwrap();

    let deadline = Instant::now() + Duration::from_secs(3);
    let path = loop {
        if let Some(p) = find_node_by_name(PROBE_NAME) {
            break p;
        }
        if Instant::now() > deadline {
            panic!("device not found");
        }
        thread::sleep(Duration::from_millis(20));
    };

    let mut reader = EvdevDevice::open(&path, DeviceId(1)).unwrap();
    if grab {
        reader.grab().unwrap();
    }

    println!("[probe:{}] feeding {:?} (grab={})", label, frames, grab);
    for (code, value) in frames {
        dev.emit(&[key_event(*code, *value)]).unwrap();
        thread::sleep(Duration::from_millis(40));
        let mut seq = 0u64;
        loop {
            let read = reader.read_events(&mut seq).unwrap();
            if read.events.is_empty() {
                break;
            }
            for e in &read.events {
                println!(
                    "[probe:{}] got {:?} code {}",
                    label, e.action, e.physical_key.0
                );
            }
        }
    }

    let end = Instant::now() + Duration::from_millis(800);
    let mut seq = 100u64;
    loop {
        let read = reader.read_events(&mut seq).unwrap();
        for e in &read.events {
            println!(
                "[probe:{}] final got {:?} code {}",
                label, e.action, e.physical_key.0
            );
        }
        if Instant::now() > end {
            break;
        }
        thread::sleep(Duration::from_millis(30));
    }
}

fn main() {
    probe_case(
        "burst",
        &[(30, 1), (30, 2), (30, 2), (30, 2), (30, 0)],
        false,
    );
    probe_case("grab", &[(30, 1), (30, 2), (30, 2), (30, 2), (30, 0)], true);
}
