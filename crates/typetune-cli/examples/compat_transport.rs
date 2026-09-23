//! Private pipe transport: passive evdev observation + bounded uinput sequences.
//! No grab, text interpretation, clipboard, desktop APIs, or file logging.
use anyhow::{ensure, Result};
use serde_json::{json, Value};
use std::{
    collections::{BTreeSet, VecDeque},
    io::{BufRead, Write},
    path::Path,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
use typetune_core::event::{
    DeviceId, EventOrigin, KeyAction, NativeCode, NativeEvdevCode, PhysicalKeyCode,
    PhysicalKeyEvent,
};
use typetune_inject::VirtualKeyboard;
use typetune_input::{device_discovery::discover_keyboards, EvdevDevice};

trait Sink {
    fn key(&mut self, code: u16, down: bool) -> Result<()>;
}
impl Sink for VirtualKeyboard {
    fn key(&mut self, code: u16, down: bool) -> Result<()> {
        self.emit_physical(&PhysicalKeyEvent {
            device_id: DeviceId(0),
            native_code: NativeCode::Evdev(NativeEvdevCode(code)),
            physical_key: PhysicalKeyCode(code),
            action: if down { KeyAction::Down } else { KeyAction::Up },
            source_time: Instant::now(),
            observed_time: Instant::now(),
            sequence: 0,
            origin: EventOrigin::TextInjection(1),
        })
    }
}
struct Output<S: Sink> {
    keyboard: S,
    held: BTreeSet<u16>,
}
impl<S: Sink> Output<S> {
    fn emit(&mut self, code: u16, down: bool) -> Result<()> {
        // Track Down before writing: even a partial write requires cleanup.
        if down {
            self.held.insert(code);
        }
        self.keyboard.key(code, down)?;
        if !down {
            self.held.remove(&code);
        }
        Ok(())
    }
    fn release(&mut self) {
        for code in self.held.clone() {
            let _ = self.emit(code, false);
        }
    }
}
impl<S: Sink> Drop for Output<S> {
    fn drop(&mut self) {
        self.release();
    }
}
fn keys(value: &Value) -> Option<VecDeque<(u16, bool)>> {
    let array = value.as_array()?;
    if array.is_empty() || array.len() > 768 {
        return None;
    }
    let mut held = BTreeSet::new();
    let mut result = VecDeque::new();
    for item in array {
        let pair = item.as_array()?;
        if pair.len() != 2 {
            return None;
        }
        let code = u16::try_from(pair[0].as_u64()?).ok()?;
        if !matches!(code, 14 | 16..=27 | 30..=42 | 44..=53 | 57) {
            return None;
        }
        let down = pair[1].as_bool()?;
        if down {
            if !held.insert(code) {
                return None;
            }
        } else if !held.remove(&code) {
            return None;
        }
        result.push_back((code, down));
    }
    held.is_empty().then_some(result)
}
/// Device opens may block inside a driver. Never run enumeration in the reader.
struct Discovery {
    updates: mpsc::Receiver<Vec<(String, String)>>,
}
impl Discovery {
    fn start(
        stopped: std::sync::Arc<std::sync::atomic::AtomicBool>,
        mut scan: impl FnMut() -> Vec<(String, String)> + Send + 'static,
    ) -> Self {
        let (send, updates) = mpsc::sync_channel(1);
        thread::spawn(move || {
            while !stopped.load(std::sync::atomic::Ordering::Relaxed) {
                match send.try_send(scan()) {
                    Err(mpsc::TrySendError::Disconnected(_)) => break,
                    _ => {} // A pending snapshot is sufficient; never accumulate scans.
                }
                thread::sleep(Duration::from_millis(500));
            }
        });
        Self { updates }
    }
    fn poll(&self) -> Option<Vec<(String, String)>> {
        self.updates.try_recv().ok()
    }
}

fn main() -> Result<()> {
    let (send, receive) = mpsc::sync_channel::<Value>(256);
    thread::spawn(move || {
        let stdout = std::io::stdout();
        let mut out = stdout.lock();
        for value in receive {
            if writeln!(out, "{value}").and_then(|_| out.flush()).is_err() {
                break;
            }
        }
    });
    let (commands, incoming) = mpsc::sync_channel::<Value>(16);
    thread::spawn(move || {
        let stdin = std::io::stdin();
        let mut input = stdin.lock();
        loop {
            let mut line = Vec::new();
            // Limit protocol memory before parsing; no text payload is expected.
            use std::io::Read;
            match input.by_ref().take(32769).read_until(b'\n', &mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if line.len() > 32768 || line.last() != Some(&b'\n') {
                        break;
                    }
                    let Ok(value) = serde_json::from_slice(&line) else {
                        break;
                    };
                    if commands.try_send(value).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let report = |v| {
        send.try_send(v)
            .map_err(|_| anyhow::anyhow!("observer consumer unavailable"))
    };
    let stopped = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, stopped.clone())?;
    }
    let mut output = Output {
        keyboard: VirtualKeyboard::with_name("TypeTune Compatibility Output")?,
        held: BTreeSet::new(),
    };
    let mut devices: Vec<EvdevDevice> = Vec::new();
    let mut identity = 0u64;
    let mut sequence = 1u64;
    let mut lease = Instant::now();
    let discovery = Discovery::start(stopped.clone(), || discover_keyboards(&[]));
    let start = Instant::now();
    let mut pending = VecDeque::new();
    let mut action = None;
    let mut edited = false;
    let mut next = Instant::now();
    let mut held = BTreeSet::new();
    let mut blocked = false;
    let mut health = (0usize, false);
    report(json!({"kind":"ready","proof":"keymap-inferred"}))?;
    loop {
        if stopped.load(std::sync::atomic::Ordering::Relaxed)
            || lease.elapsed() > Duration::from_secs(2)
        {
            break;
        }
        if let Some(discovered) = discovery.poll() {
            blocked = false;
            for (path, _) in discovered {
                let Some(name) = Path::new(&path).file_name() else {
                    continue;
                };
                let sys = std::fs::canonicalize(Path::new("/sys/class/input").join(name));
                if !sys.is_ok_and(|p| !p.to_string_lossy().contains("/virtual/")) {
                    continue;
                }
                if devices.iter().any(|d| d.path() == path) {
                    continue;
                }
                identity += 1;
                match EvdevDevice::open(&path, DeviceId(identity)) {
                    Ok(device)
                        if device
                            .snapshot_key_state()
                            .is_ok_and(|s| s.iter().all(|b| *b == 0)) =>
                    {
                        devices.push(device);
                    }
                    _ => {
                        blocked = true;
                    }
                }
            }
        }
        if health != (devices.len(), blocked) {
            health = (devices.len(), blocked);
            sequence += 1;
            if let Some(id) = action.take() {
                output.release();
                pending.clear();
                report(
                    json!({"kind":"result","id":id,"status":if edited {"indeterminate"}else{"rejected"}}),
                )?;
            }
            report(
                json!({"kind":"reset","seq":sequence,"devices":if blocked {0}else{devices.len()}}),
            )?;
        }
        let mut lost = Vec::new();
        for (index, device) in devices.iter_mut().enumerate() {
            match device.read_events(&mut sequence) {
                Ok(batch) => {
                    if batch.resynced {
                        lost.push(index);
                        continue;
                    }
                    for event in batch.events {
                        if let Some(id) = action.take() {
                            output.release();
                            pending.clear();
                            report(
                                json!({"kind":"result","id":id,"status":if edited {"indeterminate"}else{"rejected"}}),
                            )?;
                        }
                        let code = event.physical_key.0;
                        match event.action {
                            KeyAction::Down => {
                                held.insert((device.device_id().0, code));
                            }
                            KeyAction::Up => {
                                held.remove(&(device.device_id().0, code));
                            }
                            _ => {}
                        }
                        report(
                            json!({"kind":"key","device":device.device_id().0,"code":code,
                            "value":match event.action {KeyAction::Down=>1,KeyAction::Up=>0,KeyAction::Repeat=>2},
                            "seq":sequence,"time":event.source_time.checked_duration_since(start).unwrap_or_default().as_secs_f64(),
                            "neutral":held.is_empty()}),
                        )?;
                    }
                }
                Err(_) => lost.push(index),
            }
        }
        if !lost.is_empty() {
            for index in lost.into_iter().rev() {
                devices.remove(index);
            }
            held.retain(|(id, _)| devices.iter().any(|d| d.device_id().0 == *id));
            blocked = true;
            sequence += 1;
            if let Some(id) = action.take() {
                output.release();
                pending.clear();
                report(
                    json!({"kind":"result","id":id,"status":if edited {"indeterminate"}else{"rejected"}}),
                )?;
            }
            report(json!({"kind":"reset","seq":sequence,"devices":0}))?;
        }
        while let Ok(command) = incoming.try_recv() {
            lease = Instant::now();
            match command["op"].as_str() {
                Some("ping") => {}
                Some("stop") => return Ok(()),
                Some("cancel") => {
                    if let Some(id) = action.take() {
                        output.release();
                        pending.clear();
                        report(
                            json!({"kind":"result","id":id,"status":if edited {"indeterminate"}else{"rejected"}}),
                        )?;
                    }
                }
                Some("emit") => {
                    let id = command["id"].as_u64().unwrap_or(0);
                    if blocked
                        || action.is_some()
                        || !held.is_empty()
                        || devices.is_empty()
                        || command["seq"].as_u64() != Some(sequence)
                    {
                        report(json!({"kind":"result","id":id,"status":"rejected"}))?;
                        continue;
                    }
                    if let Some(events) = keys(&command["keys"]) {
                        pending = events;
                        action = Some(id);
                        edited = false;
                        next = Instant::now();
                    } else {
                        report(json!({"kind":"result","id":id,"status":"rejected"}))?;
                    }
                }
                _ => return Err(anyhow::anyhow!("invalid transport operation")),
            }
        }
        if action.is_some() && Instant::now() >= next {
            if let Some((code, down)) = pending.pop_front() {
                edited = true;
                output.emit(code, down)?;
                next = Instant::now() + Duration::from_millis(8);
            } else {
                let id = action.take().unwrap();
                ensure!(output.held.is_empty(), "unbalanced output");
                report(json!({"kind":"result","id":id,"status":"injected-unverified"}))?;
            }
        }
        thread::sleep(Duration::from_millis(2));
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stalled_discovery_does_not_block_reader_poll() {
        use std::sync::{
            atomic::{AtomicBool, Ordering},
            Arc, Barrier,
        };
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let stopped = Arc::new(AtomicBool::new(false));
        let e = entered.clone();
        let r = release.clone();
        let discovery = Discovery::start(stopped.clone(), move || {
            e.wait();
            r.wait();
            vec![("fixture".into(), "keyboard".into())]
        });
        entered.wait(); // Driver is blocked until this test explicitly releases it.
        assert!(discovery.poll().is_none());
        stopped.store(true, Ordering::Relaxed);
        release.wait();
        assert_eq!(discovery.updates.recv().unwrap()[0].0, "fixture");
    }
    #[test]
    fn partial_write_and_shutdown_release_owned_modifiers() {
        use std::{cell::RefCell, rc::Rc};
        struct Fake(Rc<RefCell<Vec<(u16, bool)>>>);
        impl Sink for Fake {
            fn key(&mut self, code: u16, down: bool) -> Result<()> {
                self.0.borrow_mut().push((code, down));
                if code == 30 && down {
                    anyhow::bail!("partial output");
                }
                Ok(())
            }
        }
        let events = Rc::new(RefCell::new(Vec::new()));
        {
            let mut output = Output {
                keyboard: Fake(events.clone()),
                held: BTreeSet::new(),
            };
            output.emit(42, true).unwrap();
            assert!(output.emit(30, true).is_err());
        }
        assert_eq!(
            *events.borrow(),
            vec![(42, true), (30, true), (30, false), (42, false)]
        );
    }
    #[test]
    fn rejects_unbalanced_or_command_keys_before_output() {
        for v in [
            json!([[42, true]]),
            json!([[29, true], [29, false]]),
            json!([[14, false]]),
            json!([[30, true], [30, true], [30, false]]),
        ] {
            assert!(keys(&v).is_none());
        }
        assert_eq!(
            keys(&json!([[42, true], [30, true], [30, false], [42, false]]))
                .unwrap()
                .len(),
            4
        );
    }
}
