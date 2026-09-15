//! Native daemon lifecycle acceptance using only explicitly selected synthetic
//! devices. Build typetune-cli first; pass its executable as the only argument.
use anyhow::{bail, ensure, Result};
use evdev::uinput::VirtualDevice;
use evdev::{AttributeSet, EventType, InputEvent, KeyCode};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use typetune_core::event::{DeviceId, KeyAction};
use typetune_input::EvdevDevice;

struct Process(Child);
impl Drop for Process {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
}
struct Scratch(PathBuf);
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn node(name: &str) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        for (path, dev) in evdev::enumerate() {
            if dev.name() == Some(name) {
                return Ok(path.to_string_lossy().into_owned());
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    bail!("device not found: {name}")
}
fn feed(device: &mut VirtualDevice, value: i32) -> Result<()> {
    device.emit(&[InputEvent::new(EventType::KEY.0, 29, value)])?;
    Ok(())
}

fn case(executable: &Path, scratch: &Path, sig: i32, label: &str) -> Result<()> {
    let name = format!("TypeTune Lifecycle {} {label}", std::process::id());
    let mut keys = AttributeSet::<KeyCode>::new();
    keys.insert(KeyCode::KEY_LEFTCTRL);
    let mut device = VirtualDevice::builder()?
        .name(&name)
        .with_keys(&keys)?
        .build()?;
    let mut input_path = node(&name)?;
    let selection = scratch.join(format!("{label}.device"));
    std::os::unix::fs::symlink(&input_path, &selection)?;
    let config = include_str!("../../../config/default.toml")
        .replace("enabled = true", "enabled = false")
        .replace("discovery = \"auto\"", "discovery = \"manual\"")
        .replace(
            "device_paths = []",
            &format!("device_paths = [\"{}\"]", selection.display()),
        )
        .replace(
            "/tmp/typetune.pid",
            &scratch.join(format!("{label}.pid")).to_string_lossy(),
        );
    let config_path = scratch.join(format!("{label}.toml"));
    std::fs::write(&config_path, config)?;
    let stderr = std::fs::File::create(scratch.join(format!("{label}.stderr")))?;
    let stdout = std::fs::File::create(scratch.join(format!("{label}.stdout")))?;
    let mut daemon = Process(
        Command::new(executable)
            .arg("--config")
            .arg(&config_path)
            .arg("daemon")
            .process_group(0)
            .env("RUST_LOG", "info")
            .stdin(Stdio::null())
            .stdout(stdout)
            .stderr(stderr)
            .spawn()?,
    );
    let pid = daemon.0.id();
    let output_name = format!("TypeTune Relay {pid}");
    let output_path = node(&output_name)?;
    let mut observer = EvdevDevice::open(&output_path, DeviceId(800))?;
    observer.grab()?;
    // Readiness is a log marker, not a sleep guess. It is written only after
    // the watchdog handshake, all grabs and epoll registration succeeded.
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        ensure!(
            daemon.0.try_wait()?.is_none(),
            "daemon failed before readiness"
        );
        if std::fs::read_to_string(scratch.join(format!("{label}.stdout")))?
            .contains("physical relay started")
        {
            break;
        }
        ensure!(
            Instant::now() < deadline,
            "daemon readiness timeout: stdout={} stderr={}",
            std::fs::read_to_string(scratch.join(format!("{label}.stdout")))?,
            std::fs::read_to_string(scratch.join(format!("{label}.stderr")))?
        );
        thread::sleep(Duration::from_millis(10));
    }
    let children = std::fs::read_to_string(format!("/proc/{pid}/task/{pid}/children"))?;
    let children: Vec<u32> = children
        .split_whitespace()
        .map(str::parse)
        .collect::<std::result::Result<_, _>>()?;
    let helper_pid = children
        .iter()
        .copied()
        .find(|child| {
            std::fs::read(format!("/proc/{child}/cmdline"))
                .is_ok_and(|args| args.split(|b| *b == 0).any(|arg| arg == b"run"))
        })
        .ok_or_else(|| anyhow::anyhow!("separate helper process not found"))?;
    let status = std::fs::read_to_string(format!("/proc/{helper_pid}/status"))?;
    let uid = unsafe { libc::getuid() };
    ensure!(
        status.lines().any(|line| line.starts_with("Uid:")
            && line
                .split_whitespace()
                .skip(1)
                .all(|s| s == uid.to_string())),
        "helper UID differs from session user"
    );
    for fd in std::fs::read_dir(format!("/proc/{pid}/fd"))? {
        if let Ok(path) = std::fs::read_link(fd?.path()) {
            ensure!(
                !path.starts_with("/dev/input") && path != Path::new("/dev/uinput"),
                "controller owns input device fd"
            );
        }
    }
    if sig == libc::SIGTERM {
        drop(device);
        device = VirtualDevice::builder()?
            .name(&name)
            .with_keys(&keys)?
            .build()?;
        input_path = node(&name)?;
        std::fs::remove_file(&selection)?;
        std::os::unix::fs::symlink(&input_path, &selection)?;
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            let log = std::fs::read_to_string(scratch.join(format!("{label}.stderr")))?;
            if log.contains("Hotplug: attached") {
                break;
            }
            ensure!(
                Instant::now() < deadline,
                "automatic selected reconnect timed out: {log}"
            );
            thread::sleep(Duration::from_millis(20));
        }
        println!("PASS IN-06-daemon: selected symlink automatically reattached");
    }
    feed(&mut device, 1)?;
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut down = false;
    while Instant::now() < deadline {
        let read = observer.read_events(&mut 0)?;
        ensure!(!read.resynced, "observer overflow");
        if read
            .events
            .iter()
            .any(|e| e.action == KeyAction::Down && e.physical_key.0 == 29)
        {
            down = true;
            break;
        }
        thread::sleep(Duration::from_millis(5));
    }
    ensure!(down, "Ctrl Down was not forwarded");
    let before = observer.snapshot_key_state()?;
    ensure!(
        before[29 / 8] & (1 << (29 % 8)) != 0,
        "output Ctrl not held"
    );
    if sig == libc::SIGTERM {
        // Idle loop must renew its lease: no input events arrive for > timeout.
        thread::sleep(Duration::from_millis(2300));
        ensure!(
            daemon.0.try_wait()?.is_none(),
            "watchdog killed a healthy idle loop"
        );
    }
    let start = Instant::now();
    if sig == -libc::SIGSTOP || sig == -libc::SIGKILL {
        ensure!(
            unsafe { libc::kill(helper_pid as i32, -sig) } == 0,
            "cannot signal test helper"
        );
    } else if sig == 0 {
        let children = std::fs::read_to_string(format!("/proc/{pid}/task/{pid}/children"))?;
        let child_ids: Vec<u32> = children
            .split_whitespace()
            .map(str::parse)
            .collect::<std::result::Result<_, _>>()?;
        let watchdog_pid = child_ids
            .into_iter()
            .find(|child| {
                std::fs::read(format!("/proc/{child}/cmdline"))
                    .is_ok_and(|args| args.split(|b| *b == 0).any(|arg| arg == b"watchdog"))
            })
            .ok_or_else(|| anyhow::anyhow!("watchdog child not found"))?;
        let args = std::fs::read(format!("/proc/{watchdog_pid}/cmdline"))?;
        ensure!(
            args.split(|b| *b == 0).any(|arg| arg == b"watchdog"),
            "child is not watchdog"
        );
        ensure!(
            unsafe { libc::kill(watchdog_pid as i32, libc::SIGKILL) } == 0,
            "could not stop test watchdog"
        );
    } else {
        ensure!(
            unsafe {
                libc::kill(
                    if sig == libc::SIGINT {
                        -(pid as i32)
                    } else {
                        pid as i32
                    },
                    sig,
                )
            } == 0,
            "could not signal test daemon"
        );
    }
    let deadline = start + Duration::from_secs(5);
    let status = loop {
        if let Some(status) = daemon.0.try_wait()? {
            break status;
        }
        ensure!(
            Instant::now() < deadline,
            "daemon did not terminate; independent test cleanup will kill it"
        );
        thread::sleep(Duration::from_millis(10));
    };
    let stderr = std::fs::read_to_string(scratch.join(format!("{label}.stderr")))?;
    if sig == libc::SIGSTOP {
        ensure!(
            status.signal() == Some(libc::SIGKILL),
            "watchdog did not kill stopped daemon: {status}"
        );
        ensure!(
            stderr.contains("lease expired") && stderr.contains("SIGKILL"),
            "watchdog evidence missing: {stderr}"
        );
    } else if sig <= 0 {
        ensure!(
            status.code() == Some(1),
            "dead watchdog must cause daemon error exit: {status}"
        );
    } else {
        ensure!(
            status.success(),
            "signal shutdown failed: {status}; {stderr}"
        );
        ensure!(
            !stderr.contains("lease expired"),
            "watchdog was needed for normal shutdown"
        );
        ensure!(
            !scratch.join(format!("{label}.pid")).exists(),
            "normal shutdown left PID file"
        );
    }
    // Device disappearance releases the virtual keyboard in consumers. We do
    // not claim to have observed its final Up edge after destruction of uinput.
    ensure!(
        !Path::new(&output_path).exists(),
        "output device survived daemon exit"
    );
    // Original device has a held physical Ctrl; raw evdev grab proves previous
    // owner released it. Keep that recovery grab while generating the final Up.
    let mut recovery = evdev::Device::open(&input_path)?;
    recovery.grab()?;
    feed(&mut device, 0)?;
    recovery.ungrab()?;
    let mut retry = EvdevDevice::open(&input_path, DeviceId(801))?;
    retry.grab()?;
    retry.ungrab()?;
    println!(
        "PASS {label}: {status}, {:.0} ms; output removed, input re-grabbed",
        start.elapsed().as_secs_f64() * 1000.0
    );
    Ok(())
}

fn main() -> Result<()> {
    let executable = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .ok_or_else(|| anyhow::anyhow!("usage: lifecycle_stand /absolute/path/to/typetune"))?
        .canonicalize()?;
    let scratch =
        Scratch(std::env::temp_dir().join(format!("typetune-lifecycle-{}", std::process::id())));
    std::fs::create_dir(&scratch.0)?;
    case(
        &executable,
        &scratch.0,
        libc::SIGTERM,
        "IN-10-TERM-IN-11-stop",
    )?;
    case(
        &executable,
        &scratch.0,
        libc::SIGINT,
        "IN-10-INT-IN-11-stop",
    )?;
    case(&executable, &scratch.0, libc::SIGSTOP, "WD-01-SIGSTOP")?;
    case(&executable, &scratch.0, 0, "WD-02-monitor-death")?;
    case(
        &executable,
        &scratch.0,
        -libc::SIGSTOP,
        "WD-03-helper-freeze",
    )?;
    case(
        &executable,
        &scratch.0,
        -libc::SIGKILL,
        "WD-04-helper-death",
    )?;
    println!("LIFECYCLE STAND PASS");
    Ok(())
}
