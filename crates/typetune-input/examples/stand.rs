//! Isolated native physical-relay acceptance. Creates only synthetic devices.
//! Output is grabbed before any input is fed. A separate watchdog stops the
//! relay after 15 seconds. Any failed assertion exits nonzero.
use anyhow::{bail, ensure, Result};
use evdev::uinput::VirtualDevice;
use evdev::{AttributeSet, EventType, InputEvent, KeyCode};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use typetune_core::event::{DeviceId, KeyAction};
use typetune_inject::VirtualKeyboard;
use typetune_input::{EvdevDevice, EvdevSource};

fn node(name: &str) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        for (path, dev) in evdev::enumerate() {
            if dev.name() == Some(name) {
                return Ok(path.to_string_lossy().into_owned());
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    bail!("synthetic device not found: {name}")
}

fn keyboard(name: &str) -> Result<VirtualDevice> {
    let mut keys = AttributeSet::<KeyCode>::new();
    for code in 1..=0x2ff {
        keys.insert(KeyCode::new(code));
    }
    Ok(VirtualDevice::builder()?
        .name(name)
        .with_keys(&keys)?
        .build()?)
}

fn feed(device: &mut VirtualDevice, code: u16, values: &[i32]) -> Result<()> {
    for value in values {
        device.emit(&[InputEvent::new(EventType::KEY.0, code, *value)])?;
    }
    Ok(())
}

fn expect(observer: &mut EvdevDevice, expected: &[(KeyAction, u16)]) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut actual = Vec::new();
    let mut sequence = 0;
    while Instant::now() < deadline {
        let batch = observer.read_events(&mut sequence)?;
        ensure!(!batch.resynced, "observer overflow invalidates trace");
        actual.extend(
            batch
                .events
                .into_iter()
                .map(|e| (e.action, e.physical_key.0)),
        );
        ensure!(
            actual.len() <= expected.len() && expected.starts_with(&actual),
            "trace mismatch: {actual:?}, expected {expected:?}"
        );
        if actual.len() == expected.len() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(5));
    }
    bail!("trace timeout: {actual:?}, expected {expected:?}")
}

fn wait_grabbed(path: &str) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut probe = EvdevDevice::open(path, DeviceId(999))?;
    while Instant::now() < deadline {
        match probe.grab() {
            Ok(()) => probe.ungrab()?,
            Err(error) => {
                if error
                    .downcast_ref::<std::io::Error>()
                    .and_then(|e| e.raw_os_error())
                    == Some(libc::EBUSY)
                {
                    return Ok(());
                }
                return Err(error);
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    bail!("relay failed to grab synthetic input")
}

struct StopOnDrop(Arc<EvdevSource>);
impl Drop for StopOnDrop {
    fn drop(&mut self) {
        self.0.stop();
    }
}

fn resync_and_neutral(prefix: &str) -> Result<()> {
    use KeyAction::{Down, Up};
    let mut c = keyboard(&format!("{prefix} Resync"))?;
    let path = node(&format!("{prefix} Resync"))?;
    let mut reader = EvdevDevice::open(&path, DeviceId(700))?;
    reader.grab()?; // every synthetic edge is isolated before we feed it
    let output = VirtualKeyboard::with_name(&format!("{prefix} Resync Output"))?;
    let mut observer =
        EvdevDevice::open(&node(&format!("{prefix} Resync Output"))?, DeviceId(701))?;
    observer.grab()?;
    let mut relay = typetune_input::relay::Relay::default();
    let mut emit = |frame: &[typetune_core::event::PhysicalKeyEvent]| output.emit_frame(frame);
    let mut sequence = 0;
    let before = Instant::now();
    feed(&mut c, 29, &[1])?;
    let read = reader.read_events(&mut sequence)?;
    ensure!(!read.events.is_empty(), "IN-04 initial Ctrl frame missing");
    let after = Instant::now();
    ensure!(
        read.events
            .iter()
            .all(|e| e.source_time >= before - Duration::from_millis(2)
                && e.source_time <= after + Duration::from_millis(2)),
        "input timestamp is not in the monotonic domain"
    );
    println!("PASS IN-03-clock: kernel timestamp maps into monotonic feed/read interval");
    for frame in read.frames {
        relay.forward_frame(frame, &mut emit)?;
    }
    expect(&mut observer, &[(Down, 29)])?;
    // Reader is deliberately not drained: force real kernel evdev overflow.
    feed(&mut c, 29, &[0])?;
    for _ in 0..512 {
        feed(&mut c, 30, &[1, 0])?;
    }
    feed(&mut c, 42, &[1])?;
    let read = reader.read_events(&mut sequence)?;
    ensure!(read.resynced, "IN-04 did not cause SYN_DROPPED");
    ensure!(
        read.events
            .iter()
            .any(|e| e.origin == typetune_core::event::EventOrigin::Resync
                && e.action == Up
                && e.physical_key.0 == 29),
        "IN-04 lost Ctrl release was not reconstructed"
    );
    for frame in read.frames {
        relay.forward_frame(frame, &mut emit)?;
    }
    expect(&mut observer, &[(Up, 29), (Down, 42)])?;
    let state = observer.snapshot_key_state()?;
    ensure!(
        state[29 / 8] & (1 << (29 % 8)) == 0 && state[42 / 8] & (1 << (42 % 8)) != 0,
        "IN-04 wrong output holds after overflow"
    );
    feed(&mut c, 42, &[0])?;
    let read = reader.read_events(&mut sequence)?;
    ensure!(!read.resynced, "IN-04 resync did not finish");
    for frame in read.frames {
        relay.forward_frame(frame, &mut emit)?;
    }
    expect(&mut observer, &[(Up, 42)])?;
    println!("PASS IN-04: real overflow restores lost Ctrl Up and held Shift; stream resumes");

    // Held startup: no physical event is exposed to the session. The initial
    // Down occurs under reader's grab, and the final Up under recovery's grab.
    feed(&mut c, 29, &[1])?;
    reader.ungrab()?;
    let mut rejected = EvdevDevice::open(&path, DeviceId(702))?;
    let error = rejected.grab().expect_err("IN-11 must reject held startup");
    ensure!(
        error.to_string().contains("not neutral"),
        "unexpected attach refusal: {error}"
    );
    let mut recovery = evdev::Device::open(&path)?;
    recovery.grab()?; // proves refusal released its exclusive grab
    feed(&mut c, 29, &[0])?;
    recovery.ungrab()?;
    rejected.grab()?;
    rejected.ungrab()?;
    println!("PASS IN-11: held startup rejected, grab released, neutral retry succeeds");
    Ok(())
}

fn failures(prefix: &str) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let root = std::env::temp_dir().join(format!("typetune-faults-{}", std::process::id()));
    std::fs::create_dir(&root)?;
    let missing = root.join("missing-uinput");
    let error = VirtualKeyboard::with_name_at_path("fault-output", &missing)
        .err()
        .ok_or_else(|| anyhow::anyhow!("missing output accepted"))?;
    ensure!(
        error
            .downcast_ref::<std::io::Error>()
            .and_then(|e| e.raw_os_error())
            == Some(libc::ENOENT),
        "wrong missing-output error: {error}"
    );
    let denied = root.join("denied-device");
    std::fs::write(&denied, b"")?;
    std::fs::set_permissions(&denied, std::fs::Permissions::from_mode(0o0))?;
    ensure!(
        unsafe { libc::geteuid() } != 0,
        "permission fault case must run as session user, not root"
    );
    let error = VirtualKeyboard::with_name_at_path("fault-output", &denied)
        .err()
        .ok_or_else(|| anyhow::anyhow!("denied output accepted"))?;
    ensure!(
        error
            .downcast_ref::<std::io::Error>()
            .and_then(|e| e.raw_os_error())
            == Some(libc::EACCES),
        "wrong output permission error: {error}"
    );
    ensure!(
        EvdevDevice::open(denied.to_str().unwrap(), DeviceId(800)).is_err(),
        "denied input accepted"
    );
    std::fs::remove_dir_all(&root)?;

    let _a = keyboard(&format!("{prefix} Busy A"))?;
    let a_path = node(&format!("{prefix} Busy A"))?;
    let _b = keyboard(&format!("{prefix} Busy B"))?;
    let b_path = node(&format!("{prefix} Busy B"))?;
    let mut owner = EvdevDevice::open(&b_path, DeviceId(800))?;
    owner.grab()?;
    let source = EvdevSource::new(&[(a_path.clone(), "A".into()), (b_path, "B".into())])?;
    let mut writes = 0;
    ensure!(
        source
            .run(|_| {
                writes += 1;
                Ok(())
            })
            .is_err(),
        "busy input did not reject startup"
    );
    ensure!(writes == 0, "output was written during failed startup");
    let mut probe = EvdevDevice::open(&a_path, DeviceId(801))?;
    probe.grab()?; // rollback must release A when the subsequent grab B fails
    probe.ungrab()?;
    owner.ungrab()?;
    println!("PASS IN-08: ENOENT/EACCES input/output, busy grab rollback, no output writes");

    let mut keys = AttributeSet::<KeyCode>::new();
    keys.insert(KeyCode::KEY_A);
    let mut axes = AttributeSet::<evdev::RelativeAxisCode>::new();
    axes.insert(evdev::RelativeAxisCode::REL_X);
    let name = format!("{prefix} Unsupported");
    let _unsupported = VirtualDevice::builder()?
        .name(&name)
        .with_keys(&keys)?
        .with_relative_axes(&axes)?
        .build()?;
    let path = node(&name)?;
    let error = EvdevDevice::open(&path, DeviceId(802))
        .err()
        .ok_or_else(|| anyhow::anyhow!("REL device was accepted"))?;
    ensure!(
        error.to_string().contains("unsupported input event type"),
        "wrong capability error: {error}"
    );
    let mut probe = evdev::Device::open(&path)?;
    probe.grab()?;
    probe.ungrab()?;
    println!("PASS IN-08-capabilities: composite REL device rejected without grab");
    Ok(())
}

fn main() -> Result<()> {
    use KeyAction::{Down, Repeat, Up};
    let prefix = format!("TypeTune Stand {}", std::process::id());
    failures(&prefix)?;
    resync_and_neutral(&prefix)?;
    let mut a = keyboard(&format!("{prefix} A"))?;
    let a_path = node(&format!("{prefix} A"))?;
    let output = VirtualKeyboard::with_name(&format!("{prefix} Output"))?;
    let output_path = node(&format!("{prefix} Output"))?;
    let mut observer = EvdevDevice::open(&output_path, DeviceId(900))?;
    observer.grab()?;

    let source = Arc::new(EvdevSource::new(&[(a_path.clone(), "synthetic A".into())])?);
    let _stop_guard = StopOnDrop(source.clone());
    let watchdog_stop = source.stop_token();
    let watchdog_done = Arc::new(AtomicBool::new(false));
    let done = watchdog_done.clone();
    thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(15);
        while !done.load(Ordering::SeqCst) && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        if !done.load(Ordering::SeqCst) {
            watchdog_stop.store(true, Ordering::SeqCst);
        }
    });
    let fail_output = Arc::new(AtomicBool::new(false));
    let fail = fail_output.clone();
    let runner = source.clone();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let relay = thread::spawn(move || {
        runner.run_frames(
            |event| {
                // Inject the failure through the real shared output contract. Never
                // close a borrowed raw fd (it might be reused before Drop closes it).
                if fail.load(Ordering::SeqCst) {
                    bail!("stand injected output failure");
                }
                output.emit_frame(event)
            },
            || {
                let _ = ready_tx.send(());
            },
            || Ok(()),
        )
    });
    ready_rx.recv_timeout(Duration::from_secs(2))?;
    for code in [30, 42, 29, 28, 2, 7, 14, 1, 256, 274] {
        feed(&mut a, code, &[1, 0])?;
        expect(&mut observer, &[(Down, code), (Up, code)])?;
    }
    println!("PASS IN-01/IN-07: identity and media trace");
    feed(&mut a, 30, &[1, 2, 2, 2, 0])?;
    expect(
        &mut observer,
        &[
            (Down, 30),
            (Repeat, 30),
            (Repeat, 30),
            (Repeat, 30),
            (Up, 30),
        ],
    )?;
    println!("PASS IN-02: repeat trace");
    let burst = [
        vec![(29, 1), (30, 1)],
        vec![(30, 0), (29, 0)],
        vec![(31, 1), (31, 0)],
    ];
    for frame in &burst {
        a.emit(
            &frame
                .iter()
                .map(|(code, value)| InputEvent::new(EventType::KEY.0, *code, *value))
                .collect::<Vec<_>>(),
        )?;
    }
    let mut actual_frames = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(2);
    while actual_frames.len() < 3 && Instant::now() < deadline {
        let read = observer.read_events(&mut 0)?;
        ensure!(!read.resynced, "IN-03 observer overflow");
        actual_frames.extend(read.frames.into_iter().map(|frame| {
            frame
                .into_iter()
                .map(|e| (e.action, e.physical_key.0))
                .collect::<Vec<_>>()
        }));
        thread::sleep(Duration::from_millis(5));
    }
    ensure!(
        actual_frames
            == [
                vec![(Down, 29), (Down, 30)],
                vec![(Up, 30), (Up, 29)],
                vec![(Down, 31), (Up, 31)]
            ],
        "IN-03 frame mismatch: {actual_frames:?}"
    );
    println!("PASS IN-03: three source frame boundaries preserved");

    let mut b = keyboard(&format!("{prefix} B"))?;
    let b_path = node(&format!("{prefix} B"))?;
    source.add_device(&b_path, "synthetic B")?;
    wait_grabbed(&b_path)?;
    // A barrier key on each device proves its preceding edge was processed.
    // This tests overlapping holds rather than two sequential down/up pairs.
    feed(&mut a, 42, &[1])?;
    expect(&mut observer, &[(Down, 42)])?;
    feed(&mut b, 42, &[1])?;
    feed(&mut b, 31, &[1, 0])?;
    expect(&mut observer, &[(Down, 31), (Up, 31)])?;
    feed(&mut a, 42, &[0])?;
    feed(&mut a, 32, &[1, 0])?;
    expect(&mut observer, &[(Down, 32), (Up, 32)])?;
    let state = observer.snapshot_key_state()?;
    ensure!(
        state[42 / 8] & (1 << (42 % 8)) != 0,
        "IN-05 second Shift hold was lost"
    );
    feed(&mut b, 42, &[0])?;
    expect(&mut observer, &[(Up, 42)])?;
    println!("PASS IN-05: overlapping Shift ownership from two devices");

    feed(&mut b, 46, &[1])?;
    expect(&mut observer, &[(Down, 46)])?;
    drop(b);
    expect(&mut observer, &[(Up, 46)])?;
    println!("PASS IN-06: hotplug and disconnect releases held key");

    // Observe before failure, while the output still exists. Native stop and
    // resync acceptance are separate from this output-error case.
    fail_output.store(true, Ordering::SeqCst);
    feed(&mut a, 30, &[1])?;
    let deadline = Instant::now() + Duration::from_secs(2);
    while !relay.is_finished() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(10));
    }
    ensure!(
        relay.is_finished(),
        "IN-09 failed: relay did not stop itself"
    );
    let result = relay
        .join()
        .map_err(|_| anyhow::anyhow!("relay panicked"))?;
    let error = result.expect_err("output failure must return an error");
    ensure!(
        error.to_string().contains("stand injected output failure"),
        "unexpected error: {error}"
    );
    // Release synthetic physical hold before checking a neutral re-attach.
    feed(&mut a, 30, &[0])?;
    let mut probe = EvdevDevice::open(&a_path, DeviceId(901))?;
    probe.grab()?;
    probe.ungrab()?;
    watchdog_done.store(true, Ordering::SeqCst);
    println!("PASS IN-09: error propagated and grab released");
    println!(
        "STAND PASS: IN-01, IN-02, IN-03, IN-04, IN-05, IN-06, IN-07, IN-08, IN-09, IN-11(start)"
    );
    Ok(())
}
