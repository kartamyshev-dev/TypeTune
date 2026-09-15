pub mod capabilities;
pub mod device_discovery;
pub mod hotplug;
pub mod relay;
pub mod watchdog;

use anyhow::Result;
use libc::{input_event, ENODEV, EWOULDBLOCK, O_CLOEXEC, O_NONBLOCK, O_RDONLY};
use std::fs::{File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use thiserror::Error;
use typetune_core::event::{
    DeviceId, EventOrigin, KeyAction, NativeCode, NativeEvdevCode, PhysicalKeyCode,
    PhysicalKeyEvent,
};

const EV_KEY: u16 = 1;
const EV_SYN: u16 = 0;
const SYN_DROPPED: u16 = 3;
const SYN_REPORT: u16 = 0;
const MAX_READ_EVENTS: usize = 256;

/// KEY_CNT = KEY_MAX + 1 = 0x300 bits, as in linux uapi/input-event-codes.h.
/// `EVIOCGKEY` returns a bitmap, so the snapshot is 768/8 bytes.
const KEY_STATE_BYTES: usize = 96;

// EVIOCGRAB = _IOW('E', 0x90, int).
// The kernel (drivers/input/evdev.c v6.12, evdev_do_ioctl EVIOCGRAB case) selects
// the action by the null-ness of the third argument only: non-NULL requests grab,
// NULL requests ungrab. The value stored behind a non-NULL pointer is ignored.
const EVIOCGRAB: libc::c_ulong = 0x4004_4590;

// EVIOCGKEY(len=<96>) = _IOR('E', 0x18, __u8[96]) = 0x80604518.
// Copies the current device key state (`dev->key`, all key slots for this
// device) out of the kernel. Used to reconstruct the hold state after an
// evdev client-buffer overflow (SYN_DROPPED) and, at grab time, as the
// neutral-state starting point so startup never re-presses held keys.
const EVIOCGKEY: libc::c_ulong = 0x8060_4518;

/// Maps the kernel EV_KEY event value to a transport action.
/// Linux defines: 0 = release, 1 = press, 2 = autorepeat. Any other value is
/// not a valid state transition and is filtered out rather than guessed.
pub fn evdev_value_to_action(value: i32) -> Option<KeyAction> {
    match value {
        0 => Some(KeyAction::Up),
        1 => Some(KeyAction::Down),
        2 => Some(KeyAction::Repeat),
        _ => None,
    }
}

/// Identity mapping for the physical relay layer, no offset applied.
/// evdev and uinput use the same Linux keycode space; the +8 XKB offset belongs
/// to the layout/decoding boundary only.
pub fn evdev_keycode_identity(code: u16) -> PhysicalKeyCode {
    PhysicalKeyCode(code)
}

/// Deterministic conversion of one raw EV_KEY event into the typed transport
/// event. Pure logic so device identity, action and keycode space can be tested
/// without /dev/input access.
pub fn convert_ev_key_event(
    device_id: DeviceId,
    sequence: u64,
    code: u16,
    value: i32,
    source_time: Instant,
) -> Option<PhysicalKeyEvent> {
    let action = evdev_value_to_action(value)?;
    Some(PhysicalKeyEvent {
        device_id,
        native_code: NativeCode::Evdev(NativeEvdevCode(code)),
        physical_key: evdev_keycode_identity(code),
        action,
        source_time,
        observed_time: source_time,
        sequence,
        origin: EventOrigin::Physical,
    })
}

/// Fixed mapping from kernel CLOCK_MONOTONIC to Rust Instant. No realtime
/// samples are used, so wall-clock corrections cannot reorder source events.
struct MonotonicClock {
    kernel: Duration,
    instant: Instant,
}

impl MonotonicClock {
    fn sample() -> Result<Self> {
        let mut ts: libc::timespec = unsafe { std::mem::zeroed() };
        anyhow::ensure!(
            unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) } == 0,
            "CLOCK_MONOTONIC unavailable: {}",
            std::io::Error::last_os_error()
        );
        Ok(Self {
            kernel: Duration::new(ts.tv_sec as u64, ts.tv_nsec as u32),
            instant: Instant::now(),
        })
    }
    fn convert(&self, sec: i64, usec: i64) -> Result<Instant> {
        anyhow::ensure!(
            sec >= 0 && (0..1_000_000).contains(&usec),
            "invalid monotonic input timestamp"
        );
        let time = Duration::new(sec as u64, usec as u32 * 1000);
        let mapped = if time >= self.kernel {
            self.instant.checked_add(time - self.kernel)
        } else {
            self.instant.checked_sub(self.kernel - time)
        };
        mapped.ok_or_else(|| anyhow::anyhow!("input timestamp outside Instant range"))
    }
}

/// Computes the Up/Down deltas between two 96-byte kernel key-state snapshots.
/// While a `SYN_DROPPED` overflow is in progress the kernel drops events, so the
/// only trustworthy data is the current state (`EVIOCGKEY`) versus the last
/// known one. Bit transitions are returned as (keycode, action).
/// Pure helper so reconciliation logic is testable without ioctls.
pub fn resync_deltas(
    old: &[u8; KEY_STATE_BYTES],
    new: &[u8; KEY_STATE_BYTES],
) -> Vec<(u16, KeyAction)> {
    let mut deltas = Vec::new();
    for byte in 0..KEY_STATE_BYTES {
        let diff = old[byte] ^ new[byte];
        if diff == 0 {
            continue;
        }
        for bit in 0..8u8 {
            if diff & (1 << bit) != 0 {
                let code = (byte as u16) * 8 + bit as u16;
                let now_held = new[byte] & (1 << bit) != 0;
                deltas.push((
                    code,
                    if now_held {
                        KeyAction::Down
                    } else {
                        KeyAction::Up
                    },
                ));
            }
        }
    }
    deltas
}

pub struct EvdevDevice {
    path: String,
    file: File,
    device_id: DeviceId,
    grabbed: bool,
    /// Last state returned to the caller, including ordinary EV_KEY edges.
    key_state: [u8; KEY_STATE_BYTES],
    dropping: bool,
    pending_frame: Vec<PhysicalKeyEvent>,
    clock: MonotonicClock,
}

pub struct ReadResult {
    /// Complete nonempty EV_KEY frames, delimited by SYN_REPORT.
    pub frames: Vec<Vec<PhysicalKeyEvent>>,
    pub events: Vec<PhysicalKeyEvent>,
    /// A loss marker or ongoing resync invalidates text history, even if the
    /// snapshot is still pending. Resync edges are individually tagged.
    pub resynced: bool,
}

impl EvdevDevice {
    pub fn open(path: &str, device_id: DeviceId) -> Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(O_NONBLOCK | O_CLOEXEC | O_RDONLY)
            .open(path)?;

        capabilities::check(&file)?;
        let clock_id: libc::c_int = libc::CLOCK_MONOTONIC;
        // EVIOCSCLOCKID = _IOW('E', 0xa0, int), Linux uapi/input.h.
        anyhow::ensure!(
            unsafe { libc::ioctl(file.as_raw_fd(), 0x4004_45a0 as libc::c_ulong, &clock_id) } == 0,
            "EVIOCSCLOCKID(CLOCK_MONOTONIC) failed: {}",
            std::io::Error::last_os_error()
        );

        Ok(Self {
            path: path.to_string(),
            file,
            device_id,
            grabbed: false,
            key_state: [0; KEY_STATE_BYTES],
            dropping: false,
            pending_frame: Vec::new(),
            clock: MonotonicClock::sample()?,
        })
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn fd(&self) -> i32 {
        self.file.as_raw_fd()
    }

    pub fn device_id(&self) -> DeviceId {
        self.device_id
    }

    /// Requires exclusive access to the device. Tracks grab-state so that
    /// ungrab is only issued while the device is actually owned by this fd and
    /// so that a failed grab never leaves a bogus "released" state.
    pub fn grab(&mut self) -> Result<()> {
        if self.grabbed {
            return Ok(());
        }
        let grab_val: i32 = 1;
        let ret = unsafe { libc::ioctl(self.file.as_raw_fd(), EVIOCGRAB, &grab_val as *const i32) };
        if ret != 0 {
            return Err(anyhow::Error::new(std::io::Error::last_os_error())
                .context(format!("EVIOCGRAB failed for {}", self.path)));
        }
        self.grabbed = true;
        tracing::info!("Grabbed: {}", self.path);
        if let Err(error) = self.sync_neutral_state() {
            let _ = self.ungrab();
            return Err(error);
        }
        Ok(())
    }

    /// Reads the current kernel key-hold bitmap (`EVIOCGKEY`).
    ///
    /// NOTE: `EVIOCGKEY` returns the number of bytes copied (96) on success,
    /// not 0, so the return value must be checked against `-1`, not equality
    /// with 0. A side effect of the ioctl is that pending EV_KEY events are
    /// flushed from the client queue, which is what keeps the snapshot
    /// consistent with the delivered stream.
    pub fn snapshot_key_state(&self) -> Result<[u8; KEY_STATE_BYTES]> {
        let mut state = [0u8; KEY_STATE_BYTES];
        let ret = unsafe {
            libc::ioctl(
                self.file.as_raw_fd(),
                EVIOCGKEY,
                state.as_mut_ptr() as *mut libc::c_void,
            )
        };
        if ret < 0 {
            return Err(anyhow::anyhow!(
                "EVIOCGKEY failed for {}: errno {}",
                self.path,
                std::io::Error::last_os_error()
            ));
        }
        Ok(state)
    }

    /// Refuse handover while keys are held: those holds belong to the physical
    /// device in the desktop, and cannot be released via a different uinput device.
    pub fn sync_neutral_state(&mut self) -> Result<()> {
        let state = self.snapshot_key_state()?;
        anyhow::ensure!(
            state.iter().all(|b| *b == 0),
            "device {} is not neutral; release all keys before attaching",
            self.path
        );
        self.key_state = state;
        self.dropping = false;
        self.pending_frame.clear();
        Ok(())
    }

    fn reconcile(
        &mut self,
        snapshot: [u8; KEY_STATE_BYTES],
        sequence: &mut u64,
    ) -> Vec<PhysicalKeyEvent> {
        let events = resync_deltas(&self.key_state, &snapshot)
            .into_iter()
            .map(|(code, action)| {
                let now = Instant::now();
                let event = PhysicalKeyEvent {
                    device_id: self.device_id,
                    native_code: NativeCode::Evdev(NativeEvdevCode(code)),
                    physical_key: evdev_keycode_identity(code),
                    action,
                    source_time: now,
                    observed_time: now,
                    sequence: *sequence,
                    origin: EventOrigin::Resync,
                };
                *sequence += 1;
                event
            })
            .collect();
        self.key_state = snapshot;
        events
    }

    /// Releases the grab while the device and fd are still alive. Passing NULL
    /// is the only way to select the ungrab branch of EVIOCGRAB.
    pub fn ungrab(&mut self) -> Result<()> {
        if !self.grabbed {
            return Ok(());
        }
        let ret = unsafe { libc::ioctl(self.file.as_raw_fd(), EVIOCGRAB, std::ptr::null::<i32>()) };
        if ret != 0 {
            return Err(anyhow::anyhow!(
                "EVIOCGRAB ungrab failed for {}: errno {}",
                self.path,
                std::io::Error::last_os_error()
            ));
        }
        self.grabbed = false;
        tracing::info!("Ungrabbed: {}", self.path);
        Ok(())
    }

    /// Read a bounded batch, preserving state across calls. During overflow,
    /// discard through SYN_REPORT before querying authoritative state. Valid
    /// events preceding the marker remain in the result, followed by deltas.
    pub fn read_events(&mut self, sequence: &mut u64) -> Result<ReadResult> {
        self.read_events_with_snapshot(sequence, |device| device.snapshot_key_state())
    }

    fn read_events_with_snapshot(
        &mut self,
        sequence: &mut u64,
        mut snapshot: impl FnMut(&Self) -> Result<[u8; KEY_STATE_BYTES]>,
    ) -> Result<ReadResult> {
        let mut events = Vec::new();
        let mut frames = Vec::new();
        let mut resynced = self.dropping;
        // One record per read prevents read-ahead past the resync boundary:
        // EVIOCGKEY flushes pending EV_KEY from the kernel client queue, but
        // cannot flush records already copied into a userspace read buffer.
        for _ in 0..MAX_READ_EVENTS {
            let mut raw: input_event = unsafe { std::mem::zeroed() };
            let len = unsafe {
                libc::read(
                    self.fd(),
                    &mut raw as *mut _ as *mut libc::c_void,
                    std::mem::size_of::<input_event>(),
                )
            };
            if len < 0 {
                let errno = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
                if errno == libc::EINTR {
                    continue;
                }
                if errno == EWOULDBLOCK {
                    break;
                }
                if !events.is_empty() {
                    break;
                } // deliver prior edges before disconnect
                if errno == ENODEV {
                    return Err(DeviceError::Disconnected(self.path.clone()).into());
                }
                return Err(DeviceError::ReadFailed(self.path.clone(), errno).into());
            }
            if len == 0 {
                if !events.is_empty() {
                    break;
                }
                return Err(DeviceError::Disconnected(self.path.clone()).into());
            }
            anyhow::ensure!(
                len as usize == std::mem::size_of::<input_event>(),
                "short input_event read"
            );
            if raw.type_ == EV_SYN && raw.code == SYN_DROPPED {
                self.dropping = true;
                self.pending_frame.clear();
                resynced = true;
                continue;
            }
            if self.dropping {
                if raw.type_ == EV_SYN && raw.code == SYN_REPORT {
                    let state = snapshot(self)?;
                    let frame = self.reconcile(state, sequence);
                    if !frame.is_empty() {
                        events.extend(frame.iter().cloned());
                        frames.push(frame);
                    }
                    self.dropping = false;
                    break;
                }
                continue;
            }
            if raw.type_ == EV_SYN && raw.code == SYN_REPORT {
                let frame = std::mem::take(&mut self.pending_frame);
                for event in &frame {
                    let code = event.physical_key.0;
                    let byte = &mut self.key_state[code as usize / 8];
                    let mask = 1 << (code % 8);
                    match event.action {
                        KeyAction::Down => *byte |= mask,
                        KeyAction::Up => *byte &= !mask,
                        KeyAction::Repeat => {}
                    }
                }
                if !frame.is_empty() {
                    events.extend(frame.iter().cloned());
                    frames.push(frame);
                }
            }
            if raw.type_ == EV_KEY {
                anyhow::ensure!(
                    (raw.code as usize) < KEY_STATE_BYTES * 8,
                    "unsupported evdev keycode"
                );
                if let Some(event) = convert_ev_key_event(
                    self.device_id,
                    *sequence,
                    raw.code,
                    raw.value,
                    self.clock.convert(raw.time.tv_sec, raw.time.tv_usec)?,
                ) {
                    anyhow::ensure!(
                        self.pending_frame.len() < 1024,
                        "input frame exceeds 1024 key events"
                    );
                    self.pending_frame.push(event);
                    *sequence += 1;
                }
            }
        }
        Ok(ReadResult {
            events,
            frames,
            resynced,
        })
    }
}

impl Drop for EvdevDevice {
    fn drop(&mut self) {
        if self.grabbed {
            let _ = self.ungrab();
        }
        // Closing the owning fd releases any remaining grab in the kernel.
    }
}

pub struct EvdevSource {
    // Interior mutability: `run()` owns the data plane (grab + typed reading)
    // on the relay thread, while the control plane (`add_device()`, IPC,
    // watchdog) may attach/stop devices from any other thread without
    // reentrancy. The hotplug pipe is the only cross-thread channel that the
    // data plane observes.
    devices: Mutex<Vec<EvdevDevice>>,
    running: Arc<AtomicBool>,
    // Hotplug control channel: run() picks new devices up through
    // `add_device()` writes, so a running relay can attach new keyboards
    // without restarting the event loop (IN-06). The write end is safe to
    // use from any thread because it only locks the kernel pipe.
    control_r: i32,
    control_w: i32,
    // Control-plane mutable state, locked separately from the device list.
    // Holds the partial line buffer for the hotplug pipe framing (IN-06) and
    // the monotonically increasing DeviceId counter for hotplugged devices.
    control: Mutex<(String, u64)>,
}

/// epoll data marker for the hotplug control pipe fd (a real device fd can
/// never equal `u64::MAX`).
const CONTROL_FD_MARKER: u64 = u64::MAX;

impl Drop for EvdevSource {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.control_r);
            libc::close(self.control_w);
        }
    }
}

/// Splits buffered `path\nname\n` hotplug messages into completed request pairs
/// plus the partial tail to carry into the next drain (IN-06). The tail is
/// carried byte-verbatim: `add_device` writes a whole message atomically
/// (< `PIPE_BUF`), and `drain_control` reads until `EAGAIN`, so any partial
/// state is only a prefix of one not-yet-completed message. Reparsing the raw
/// accumulated buffer then converges to the true message sequence even when a
/// read splits a message at an arbitrary byte.
fn parse_control_messages(buf: &str) -> (Vec<(String, String)>, String) {
    if buf.is_empty() {
        return (Vec::new(), String::new());
    }

    // No newline at all: the whole buffer is an unterminated prefix of a
    // message still being written; keep it verbatim.
    let Some(idx) = buf.rfind('\n') else {
        return (Vec::new(), buf.to_string());
    };

    let complete = &buf[..idx];
    let pending = buf[idx + 1..].to_string();
    let mut lines: Vec<&str> = complete.split('\n').collect();
    let leftover = if lines.len() % 2 == 1 {
        // A lone complete line is a message whose path arrived, but its name
        // line has not; the `\n` below is the verbatim terminator of `lone`.
        let lone = lines.pop().unwrap_or("");
        format!("{}\n{}", lone, pending)
    } else {
        pending
    };

    let requests = lines
        .chunks(2)
        .map(|pair| (pair[0].to_string(), pair[1].to_string()))
        .collect();
    (requests, leftover)
}

impl EvdevSource {
    pub fn new(device_paths: &[(String, String)]) -> Result<Self> {
        anyhow::ensure!(
            device_paths.len() <= 32,
            "at most 32 selected devices are supported"
        );
        let mut devices = Vec::new();
        for (i, (path, name)) in device_paths.iter().enumerate() {
            let device_id = DeviceId(i as u64 + 1);
            match EvdevDevice::open(path, device_id) {
                Ok(dev) => {
                    tracing::info!("Opened device: {} ({})", name, path);
                    devices.push(dev);
                }
                Err(e) => {
                    return Err(e.context(format!("could not open selected device {path}")));
                }
            }
        }

        if devices.is_empty() {
            return Err(DeviceError::NoDevicesFound.into());
        }

        let mut pfd = [0i32; 2];
        if unsafe { libc::pipe2(pfd.as_mut_ptr(), libc::O_CLOEXEC | libc::O_NONBLOCK) } != 0 {
            return Err(anyhow::anyhow!(
                "pipe2 failed: {}",
                std::io::Error::last_os_error()
            ));
        }

        let next_device_id = device_paths.len() as u64 + 1;

        Ok(Self {
            devices: Mutex::new(devices),
            running: Arc::new(AtomicBool::new(false)),
            control_r: pfd[0],
            control_w: pfd[1],
            control: Mutex::new((String::new(), next_device_id)),
        })
    }

    /// Requests a hotplug attach of `path` to the running event loop (IN-06).
    /// The call returns once the request is queued; actual open/grab happens in
    /// the loop thread, and failures there are logged without disturbing the
    /// relay. Uses a pipe so the loop's epoll set can be mutated safely without
    /// locking `&mut self` from another thread.
    pub fn add_device(&self, path: &str, name: &str) -> Result<()> {
        anyhow::ensure!(
            !path.is_empty() && !path.contains('\n') && !name.contains('\n'),
            "invalid hotplug message"
        );
        let msg = format!("{}\n{}\n", path, name);
        if msg.len() > libc::PIPE_BUF {
            return Err(anyhow::anyhow!("device identity message too large"));
        }
        let written = unsafe {
            libc::write(
                self.control_w,
                msg.as_ptr() as *const libc::c_void,
                msg.len(),
            )
        };
        if written < 0 {
            return Err(anyhow::anyhow!(
                "add_device write failed: {}",
                std::io::Error::last_os_error()
            ));
        }
        anyhow::ensure!(written as usize == msg.len(), "incomplete hotplug message");
        tracing::info!("Hotplug request queued: {} ({})", name, path);
        Ok(())
    }

    /// Shared shutdown token. `run()` observes its value; the owning process
    /// (CLI signal handler, IPC client, watchdog) writes `true` through the
    /// same Arc to stop the loop. There is exactly one cancellation source.
    pub fn stop_token(&self) -> Arc<AtomicBool> {
        self.running.clone()
    }

    pub fn run(&self, output: impl FnMut(&PhysicalKeyEvent) -> Result<()>) -> Result<()> {
        self.run_with_ready(output, || {})
    }

    /// `ready` runs once after every selected device is grabbed and epoll is
    /// configured, before reading any input. Keep this callback nonblocking.
    pub fn run_with_ready(
        &self,
        mut output: impl FnMut(&PhysicalKeyEvent) -> Result<()>,
        ready: impl FnOnce(),
    ) -> Result<()> {
        self.run_frames(
            |frame| {
                for event in frame {
                    output(event)?;
                }
                Ok(())
            },
            ready,
            || Ok(()),
        )
    }

    /// Forward complete key frames. `progress` must be nonblocking and is
    /// called by this loop itself, even when idle, for an independent watchdog.
    pub fn run_frames(
        &self,
        mut output: impl FnMut(&[PhysicalKeyEvent]) -> Result<()>,
        ready: impl FnOnce(),
        mut progress: impl FnMut() -> Result<()>,
    ) -> Result<()> {
        if self.running.load(Ordering::SeqCst) {
            return Ok(());
        }
        let mut devices = self.devices.lock().unwrap();
        let mut ctrl = self.control.lock().unwrap();

        let grabbed_indices = grab_all_locked(&mut devices)?;

        if grabbed_indices.is_empty() {
            return Err(anyhow::anyhow!("No devices could be grabbed"));
        }

        let mut sequence: u64 = 0;

        let epfd = unsafe { libc::epoll_create1(libc::EPOLL_CLOEXEC) };
        if epfd < 0 {
            ungrab_all_locked(&mut devices);
            return Err(anyhow::anyhow!("epoll_create1 failed"));
        }

        for &i in &grabbed_indices {
            let dev_path = devices[i].path().to_string();
            let mut ev: libc::epoll_event = unsafe { std::mem::zeroed() };
            ev.events = libc::EPOLLIN as u32;
            ev.u64 = devices[i].fd() as u64;
            if unsafe { libc::epoll_ctl(epfd, libc::EPOLL_CTL_ADD, devices[i].fd(), &mut ev) } != 0
            {
                unsafe { libc::close(epfd) };
                ungrab_all_locked(&mut devices);
                return Err(anyhow::anyhow!("epoll_ctl failed for {}", dev_path));
            }
        }

        {
            let mut ev: libc::epoll_event = unsafe { std::mem::zeroed() };
            ev.events = libc::EPOLLIN as u32;
            ev.u64 = CONTROL_FD_MARKER;
            if unsafe { libc::epoll_ctl(epfd, libc::EPOLL_CTL_ADD, self.control_r, &mut ev) } != 0 {
                unsafe { libc::close(epfd) };
                ungrab_all_locked(&mut devices);
                return Err(anyhow::anyhow!("epoll_ctl failed for hotplug control pipe"));
            }
        }

        tracing::info!(
            "Event loop started ({} grabbed of {} devices, epoll)",
            grabbed_indices.len(),
            devices.len()
        );

        let mut epoll_events: [libc::epoll_event; 16] = unsafe { std::mem::zeroed() };

        ready();
        let mut relay = relay::Relay::default();
        let outcome = 'relay: loop {
            if let Err(error) = progress() {
                break Err(error);
            }
            if self.running.load(Ordering::SeqCst) {
                break Ok(());
            }
            let nfds = unsafe { libc::epoll_wait(epfd, epoll_events.as_mut_ptr(), 16, 100) };
            if nfds < 0 {
                let error = std::io::Error::last_os_error();
                if error.raw_os_error() == Some(libc::EINTR) {
                    continue;
                }
                break Err(error.into());
            }
            for ev in epoll_events.iter().take(nfds as usize) {
                if self.running.load(Ordering::SeqCst) {
                    break 'relay Ok(());
                }
                if ev.u64 == CONTROL_FD_MARKER {
                    drain_control(self.control_r, &mut ctrl, epfd, &mut devices);
                    continue;
                }
                let fd = ev.u64 as i32;
                let Some(idx) = devices.iter().position(|d| d.fd() == fd) else {
                    continue;
                };
                match devices[idx].read_events(&mut sequence) {
                    Ok(read) => {
                        for frame in read.frames {
                            if self.running.load(Ordering::SeqCst) {
                                break 'relay Ok(());
                            }
                            if let Err(error) = relay.forward_frame(frame, &mut output) {
                                break 'relay Err(error);
                            }
                        }
                    }
                    Err(error) => {
                        let disconnected = matches!(
                            error.downcast_ref::<DeviceError>(),
                            Some(DeviceError::Disconnected(_))
                        );
                        if !disconnected {
                            break 'relay Err(error);
                        }
                        if let Err(error) =
                            relay.disconnect_frame(devices[idx].device_id(), &mut output)
                        {
                            break 'relay Err(error);
                        }
                        unsafe {
                            libc::epoll_ctl(epfd, libc::EPOLL_CTL_DEL, fd, std::ptr::null_mut());
                        }
                        devices.swap_remove(idx);
                    }
                }
            }
        };
        // An output error is terminal. Relay::finish never writes again to a
        // failed sink; the caller must destroy that sink after this returns.
        let cleanup = relay.finish_frames(&mut output);
        self.running.store(true, Ordering::SeqCst);
        unsafe { libc::close(epfd) };
        ungrab_all_locked(&mut devices);
        tracing::info!("Event loop stopped");
        outcome.and(cleanup)
    }

    pub fn stop(&self) {
        self.running.store(true, Ordering::SeqCst);
    }
}

fn grab_all_locked(devices: &mut [EvdevDevice]) -> Result<Vec<usize>> {
    let mut grabbed = Vec::new();
    for (i, dev) in devices.iter_mut().enumerate() {
        match dev.grab() {
            Ok(_) => grabbed.push(i),
            Err(e) => {
                ungrab_all_locked(devices);
                return Err(e);
            }
        }
    }
    Ok(grabbed)
}

fn ungrab_all_locked(devices: &mut [EvdevDevice]) {
    for dev in devices.iter_mut() {
        if let Err(e) = dev.ungrab() {
            tracing::warn!("Failed to ungrab {}: {}", dev.path(), e);
        }
    }
}

fn drain_control(
    control_r: i32,
    ctrl: &mut (String, u64),
    epfd: i32,
    devices: &mut Vec<EvdevDevice>,
) {
    let mut buf = [0u8; 4096];
    for _ in 0..4 {
        let n = unsafe { libc::read(control_r, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };
        if n < 0 {
            let errno = unsafe { *libc::__errno_location() };
            if errno == libc::EAGAIN || errno == libc::EWOULDBLOCK {
                break;
            }
            tracing::warn!("Hotplug control read error: errno {}", errno);
            break;
        }
        if n == 0 {
            break;
        }
        ctrl.0
            .push_str(&String::from_utf8_lossy(&buf[..n as usize]));
    }

    let (requests, leftover) = parse_control_messages(&ctrl.0);
    ctrl.0 = leftover;

    for (path, name) in requests {
        if path.is_empty() {
            continue;
        }
        try_add_device(epfd, &path, &name, devices, &mut ctrl.1);
    }
}

fn try_add_device(
    epfd: i32,
    path: &str,
    name: &str,
    devices: &mut Vec<EvdevDevice>,
    next_device_id: &mut u64,
) {
    if devices.iter().any(|device| device.path() == path) || devices.len() >= 32 {
        return;
    }
    let id = DeviceId(*next_device_id);
    *next_device_id += 1;

    let mut dev = match EvdevDevice::open(path, id) {
        Ok(dev) => dev,
        Err(e) => {
            tracing::warn!("Hotplug: could not open {} ({}): {}", name, path, e);
            return;
        }
    };

    if let Err(e) = dev.grab() {
        tracing::warn!(
            "Hotplug: grab of {} ({}) failed, skipping: {}",
            name,
            path,
            e
        );
        return;
    }

    let fd = dev.fd();
    let mut ev: libc::epoll_event = unsafe { std::mem::zeroed() };
    ev.events = libc::EPOLLIN as u32;
    ev.u64 = fd as u64;
    if unsafe { libc::epoll_ctl(epfd, libc::EPOLL_CTL_ADD, fd, &mut ev) } != 0 {
        let errno = unsafe { *libc::__errno_location() };
        tracing::warn!(
            "Hotplug: epoll add of {} ({}) failed: errno {}",
            name,
            path,
            errno
        );
        return;
    }

    devices.push(dev);
    tracing::info!("Hotplug: attached {} ({}) as {}", name, path, id);
}

#[derive(Error, Debug)]
pub enum DeviceError {
    #[error("device disconnected: {0}")]
    Disconnected(String),

    #[error("read failed on {0}: errno {1}")]
    ReadFailed(String, i32),

    #[error("no keyboard devices found")]
    NoDevicesFound,
}

#[cfg(test)]
mod tests {
    #[test]
    fn in03_incomplete_frame_is_not_forwarded() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_KEY, 29, 1);
        assert!(dev.read_events(&mut 0).unwrap().events.is_empty());
        send(&mut writer, EV_KEY, 30, 1);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev.read_events(&mut 0).unwrap();
        assert_eq!(read.events.len(), 2);
        assert_eq!(read.frames.len(), 1);
        assert_eq!(read.frames[0].len(), 2);
    }

    #[test]
    fn in08_regular_file_is_rejected_before_grab() {
        let path = std::env::temp_dir().join(format!("typetune-not-device-{}", std::process::id()));
        std::fs::write(&path, b"not an evdev device").unwrap();
        let result = EvdevDevice::open(path.to_str().unwrap(), DeviceId(1));
        std::fs::remove_file(path).unwrap();
        assert!(
            result.is_err(),
            "non-evdev file was accepted as keyboard input"
        );
    }

    #[test]
    fn in04_loss_discards_incomplete_frame_without_orphan_release() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_KEY, 29, 1);
        assert!(dev.read_events(&mut 0).unwrap().events.is_empty());
        send(&mut writer, EV_SYN, SYN_DROPPED, 0);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev
            .read_events_with_snapshot(&mut 0, |_| Ok([0; KEY_STATE_BYTES]))
            .unwrap();
        assert!(read.resynced);
        assert!(read.frames.is_empty());
        assert!(dev.pending_frame.is_empty());
        assert!(dev.key_state.iter().all(|b| *b == 0));
    }

    fn fake_device() -> (EvdevDevice, std::os::unix::net::UnixStream) {
        use std::os::fd::OwnedFd;
        use std::os::unix::net::UnixStream;
        let (reader, writer) = UnixStream::pair().unwrap();
        reader.set_nonblocking(true).unwrap();
        (
            EvdevDevice {
                path: "synthetic-stream".into(),
                file: File::from(OwnedFd::from(reader)),
                device_id: DeviceId(1),
                grabbed: false,
                key_state: [0; KEY_STATE_BYTES],
                dropping: false,
                pending_frame: Vec::new(),
                clock: MonotonicClock {
                    kernel: Duration::ZERO,
                    instant: Instant::now(),
                },
            },
            writer,
        )
    }

    fn send(writer: &mut std::os::unix::net::UnixStream, type_: u16, code: u16, value: i32) {
        use std::io::Write;
        let mut raw: input_event = unsafe { std::mem::zeroed() };
        raw.type_ = type_;
        raw.code = code;
        raw.value = value;
        let bytes = unsafe {
            std::slice::from_raw_parts(
                &raw as *const input_event as *const u8,
                std::mem::size_of::<input_event>(),
            )
        };
        writer.write_all(bytes).unwrap();
    }

    #[test]
    fn in04_normal_down_is_remembered_for_lost_release() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_KEY, 30, 1);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev.read_events(&mut 0).unwrap();
        assert_eq!(read.events.len(), 1);
        assert_eq!(
            resync_deltas(&dev.key_state, &[0; KEY_STATE_BYTES]),
            vec![(30, KeyAction::Up)]
        );
        send(&mut writer, EV_SYN, SYN_DROPPED, 0);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev
            .read_events_with_snapshot(&mut 1, |_| Ok([0; KEY_STATE_BYTES]))
            .unwrap();
        assert!(read.resynced);
        assert_eq!(read.events.len(), 1);
        assert_eq!(read.events[0].action, KeyAction::Up);
        assert_eq!(read.events[0].origin, EventOrigin::Resync);
        assert!(dev.key_state.iter().all(|b| *b == 0));
    }

    #[test]
    fn in04_discard_persists_across_reads_until_syn_report() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_SYN, SYN_DROPPED, 0);
        send(&mut writer, EV_KEY, 30, 1);
        let read = dev
            .read_events_with_snapshot(&mut 0, |_| panic!("snapshot before SYN_REPORT"))
            .unwrap();
        assert!(read.resynced && read.events.is_empty());
        send(&mut writer, EV_KEY, 31, 1);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev
            .read_events_with_snapshot(&mut 0, |_| Ok([0; KEY_STATE_BYTES]))
            .unwrap();
        assert!(read.resynced && read.events.is_empty());
        send(&mut writer, EV_KEY, 32, 1);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev.read_events(&mut 0).unwrap();
        assert!(!read.resynced);
        assert_eq!(read.events.len(), 1);
        assert_eq!(read.events[0].physical_key.0, 32);
    }

    #[test]
    fn in04_snapshot_failure_is_not_reported_as_success() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_SYN, SYN_DROPPED, 0);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        assert!(dev
            .read_events_with_snapshot(&mut 0, |_| anyhow::bail!("snapshot failure"))
            .is_err());
        assert!(dev.dropping);
    }

    #[test]
    fn in04_valid_prefix_and_reconciliation_are_balanced() {
        let (mut dev, mut writer) = fake_device();
        send(&mut writer, EV_KEY, 30, 1);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        send(&mut writer, EV_SYN, SYN_DROPPED, 0);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        let read = dev
            .read_events_with_snapshot(&mut 0, |_| Ok([0; KEY_STATE_BYTES]))
            .unwrap();
        assert_eq!(
            read.events.iter().map(|e| e.action).collect::<Vec<_>>(),
            [KeyAction::Down, KeyAction::Up]
        );
    }

    #[test]
    fn in03_read_batch_is_bounded_and_keeps_remaining_records() {
        let (mut dev, mut writer) = fake_device();
        // A stream is used for the fixture, so write the whole burst in one
        // syscall rather than fill its per-write socket buffer accounting.
        use std::io::Write;
        let records: Vec<input_event> = (0..MAX_READ_EVENTS + 2)
            .map(|i| {
                let mut raw: input_event = unsafe { std::mem::zeroed() };
                raw.type_ = if i % 2 == 0 { EV_KEY } else { EV_SYN };
                raw.code = if i % 2 == 0 { 30 } else { SYN_REPORT };
                raw.value = if i % 4 == 0 { 1 } else { 0 };
                raw
            })
            .collect();
        let bytes = unsafe {
            std::slice::from_raw_parts(
                records.as_ptr() as *const u8,
                records.len() * std::mem::size_of::<input_event>(),
            )
        };
        writer.write_all(bytes).unwrap();
        let mut seq = 0;
        assert_eq!(
            dev.read_events(&mut seq).unwrap().events.len(),
            MAX_READ_EVENTS / 2
        );
        assert_eq!(dev.read_events(&mut seq).unwrap().events.len(), 1);
        send(&mut writer, EV_KEY, 30, 0);
        send(&mut writer, EV_SYN, SYN_REPORT, 0);
        dev.read_events(&mut seq).unwrap();
        assert!(dev.key_state.iter().all(|b| *b == 0));
    }

    use super::*;
    use std::time::Instant;

    #[test]
    fn in06_parse_control_single_message() {
        assert_eq!(
            parse_control_messages("/dev/input/event9\nFoo Bar\n"),
            (
                vec![("/dev/input/event9".into(), "Foo Bar".into())],
                String::new()
            )
        );
    }

    #[test]
    fn in06_parse_control_two_messages() {
        let (req, pend) = parse_control_messages("p1\nn1\np2\nn2\n");
        assert_eq!(
            req,
            vec![("p1".into(), "n1".into()), ("p2".into(), "n2".into())]
        );
        assert!(pend.is_empty());
    }

    #[test]
    fn in06_parse_control_split_across_drains() {
        let (_, pend) = parse_control_messages("/dev/input/event9\nFo");
        assert_eq!(pend, "/dev/input/event9\nFo");

        let (req, pend) = parse_control_messages("/dev/input/event9\nFo");
        let (req2, pend2) = parse_control_messages(&format!("{}o\n", pend));
        assert!(req.is_empty());
        assert_eq!(req2, vec![("/dev/input/event9".into(), "Foo".into())]);
        assert!(pend2.is_empty());
    }

    #[test]
    fn in06_parse_control_split_after_path_newline() {
        // Read cut exactly after the path's newline; name arrives in the next
        // drain of the same atomic message.
        let (req, pend) = parse_control_messages("dev\n");
        assert!(req.is_empty());
        assert_eq!(pend, "dev\n");

        let (req, pend2) = parse_control_messages(&format!("{}name\n", pend));
        assert_eq!(req, vec![("dev".into(), "name".into())]);
        assert!(pend2.is_empty());
    }

    #[test]
    fn in06_parse_control_split_inside_path() {
        // Prefix split inside the path string; the suffix completes the single
        // atomic message. The tail must stay verbatim (no invented newline).
        let (req, pend) = parse_control_messages("/dev/input/even");
        assert!(req.is_empty());
        assert_eq!(pend, "/dev/input/even");

        let (req, pend2) = parse_control_messages(&format!("{}t9\nFoo\n", pend));
        assert_eq!(req, vec![("/dev/input/event9".into(), "Foo".into())]);
        assert!(pend2.is_empty());
    }

    #[test]
    fn in06_parse_control_empty() {
        let (req, pend) = parse_control_messages("");
        assert!(req.is_empty());
        assert!(pend.is_empty());
    }

    #[test]
    fn in06_parse_control_exact_boundary_after_name() {
        // Read cut exactly after the name, newline not yet visible.
        let (req, pend) = parse_control_messages("dev\nN");
        assert!(req.is_empty());
        assert_eq!(pend, "dev\nN");
    }

    #[test]
    fn evdev_value_maps_to_action() {
        assert_eq!(evdev_value_to_action(0), Some(KeyAction::Up));
        assert_eq!(evdev_value_to_action(1), Some(KeyAction::Down));
        assert_eq!(evdev_value_to_action(2), Some(KeyAction::Repeat));
        assert_eq!(evdev_value_to_action(-1), None);
        assert_eq!(evdev_value_to_action(3), None);
        assert_eq!(evdev_value_to_action(100), None);
    }

    #[test]
    fn in01_identity_keycode_preserved_across_physical_surface() {
        // Physical keys from the audit trace: A, Shift, Enter, Esc and digits.
        // The relay must emit the same Linux keycode that arrived from evdev.
        for code in [
            1,  // KEY_ESC
            2,  // KEY_1
            3,  // KEY_2
            6,  // KEY_5
            7,  // KEY_6
            28, // KEY_ENTER
            30, // KEY_A
            42, // KEY_LEFTSHIFT
            54, // KEY_RIGHTSHIFT
            // media/extra keys outside the 0..255 range decoded by uinput
            256, 274,
        ] {
            let event = convert_ev_key_event(DeviceId(1), 0, code, 1, Instant::now())
                .expect("valid Down event");
            assert_eq!(event.physical_key.0, code);
            assert_eq!(event.action, KeyAction::Down);
            match event.native_code {
                NativeCode::Evdev(NativeEvdevCode(c)) => assert_eq!(c, code),
                _ => panic!("expected Evdev native code"),
            }
        }
    }

    #[test]
    fn in02_repeat_stream_preserved_as_distinct_actions() {
        let ts = Instant::now();
        let down = convert_ev_key_event(DeviceId(1), 0, 30, 1, ts).unwrap();
        let repeat1 = convert_ev_key_event(DeviceId(1), 1, 30, 2, ts).unwrap();
        let repeat2 = convert_ev_key_event(DeviceId(1), 2, 30, 2, ts).unwrap();
        let up = convert_ev_key_event(DeviceId(1), 3, 30, 0, ts).unwrap();

        assert_eq!(down.action, KeyAction::Down);
        assert_eq!(repeat1.action, KeyAction::Repeat);
        assert_eq!(repeat2.action, KeyAction::Repeat);
        assert_eq!(up.action, KeyAction::Up);

        assert!(!repeat1.is_up(), "autorepeat must not collapse into Up");
        assert!(repeat1.is_repeat());
        assert_ne!(repeat1.action, down.action);
        assert_ne!(repeat1.action, up.action);
    }

    #[test]
    fn source_time_and_sequence_carried_on_event() {
        let ts = Instant::now();
        let event = convert_ev_key_event(DeviceId(7), 42, 30, 1, ts).unwrap();
        assert_eq!(event.device_id, DeviceId(7));
        assert_eq!(event.sequence, 42);
        assert_eq!(event.source_time, ts);
        assert_eq!(event.origin, EventOrigin::Physical);
    }

    #[test]
    fn monotonic_clock_keeps_deltas_without_realtime_samples() {
        let clock = MonotonicClock {
            kernel: Duration::from_secs(10),
            instant: Instant::now(),
        };
        let a = clock.convert(10, 900_000).unwrap();
        let b = clock.convert(11, 0).unwrap();
        assert_eq!(b.duration_since(a), Duration::from_millis(100));
        assert_eq!(clock.convert(10, 0).unwrap(), clock.instant);
        assert!(clock.convert(-1, 0).is_err());
        assert!(clock.convert(10, 1_000_000).is_err());
    }

    #[test]
    fn resync_deltas_reports_hold_and_release() {
        // old holds key 30 (byte 3, bit 6), new holds 30 and 46 (byte 5, bit 6)
        let mut old = [0u8; KEY_STATE_BYTES];
        let mut new = [0u8; KEY_STATE_BYTES];
        old[3] |= 1 << 6;
        new[3] |= 1 << 6;
        new[5] |= 1 << 6;
        let deltas = resync_deltas(&old, &new);
        assert_eq!(deltas, vec![(46, KeyAction::Down)]);
    }

    #[test]
    fn resync_deltas_reports_release() {
        let mut old = [0u8; KEY_STATE_BYTES];
        let new = [0u8; KEY_STATE_BYTES];
        old[0] |= 1; // key 0 held before, now released
        let deltas = resync_deltas(&old, &new);
        assert_eq!(deltas, vec![(0, KeyAction::Up)]);
    }

    #[test]
    fn resync_deltas_handles_adjacent_bits() {
        // keys 8 and 9 (byte 1, bits 0 and 1) both newly held
        let old = [0u8; KEY_STATE_BYTES];
        let mut new = [0u8; KEY_STATE_BYTES];
        new[1] |= 0b11;
        let deltas = resync_deltas(&old, &new);
        assert_eq!(deltas.len(), 2);
        assert!(deltas.contains(&(8, KeyAction::Down)));
        assert!(deltas.contains(&(9, KeyAction::Down)));
    }

    #[test]
    fn resync_deltas_empty_on_identical_state() {
        let state = [0u8; KEY_STATE_BYTES];
        assert!(resync_deltas(&state, &state).is_empty());
    }
}
