use anyhow::Result;
use libc::{c_uint, close, ioctl, open, write, O_CLOEXEC, O_NONBLOCK, O_WRONLY};
use std::ffi::CString;
use thiserror::Error;
use typetune_core::event::{InputEvent, KeyAction, KeyState, NativeCode, PhysicalKeyEvent};

const UI_SET_EVBIT: libc::c_ulong = 0x40045564;
const UI_SET_KEYBIT: libc::c_ulong = 0x40045565;
const UI_DEV_CREATE: libc::c_ulong = 0x5501;
const UI_DEV_DESTROY: libc::c_ulong = 0x5502;
const EV_KEY: c_uint = 1;
const EV_SYN: c_uint = 0;
const SYN_REPORT: u16 = 0;

#[repr(C)]
struct UInputUserDev {
    name: [u8; 80],
    id: InputId,
    ff_effects_max: u32,
    absmax: [i32; 64],
    absmin: [i32; 64],
    absfuzz: [i32; 64],
    absflat: [i32; 64],
}

#[repr(C)]
struct InputId {
    bustype: u16,
    vendor: u16,
    product: u16,
    version: u16,
}

#[repr(C)]
struct UInputEvent {
    time: libc::timeval,
    type_: u16,
    code: u16,
    value: i32,
}

/// Writes the full buffer to the fd, restarting on EINTR and looping through
/// partial writes. Short writes are an error condition for raw uinput framing.
fn write_all_fd(fd: i32, buf: *const libc::c_void, len: usize) -> Result<()> {
    let mut written = 0usize;
    while written < len {
        let n = unsafe {
            write(
                fd,
                (buf as *const u8).add(written) as *const libc::c_void,
                len - written,
            )
        };
        if n < 0 {
            let errno = std::io::Error::last_os_error();
            if errno.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(anyhow::anyhow!("write failed: errno {}", errno));
        }
        if n == 0 {
            return Err(anyhow::anyhow!("write returned 0"));
        }
        written += n as usize;
    }
    Ok(())
}

pub struct VirtualKeyboard {
    fd: i32,
}

impl VirtualKeyboard {
    pub fn fd(&self) -> i32 {
        self.fd
    }

    pub fn new() -> Result<Self> {
        Self::with_name("TypeTune Virtual Keyboard")
    }

    pub fn with_name(name: &str) -> Result<Self> {
        Self::with_name_at_path(name, std::path::Path::new("/dev/uinput"))
    }

    /// Explicit device path also permits isolated open-failure acceptance tests.
    pub fn with_name_at_path(name: &str, path: &std::path::Path) -> Result<Self> {
        use std::os::unix::ffi::OsStrExt;
        anyhow::ensure!(
            !name.is_empty() && name.len() < 80 && !name.contains('\0'),
            "invalid uinput device name"
        );
        let uinput_path = CString::new(path.as_os_str().as_bytes())?;
        let fd = unsafe { open(uinput_path.as_ptr(), O_WRONLY | O_NONBLOCK | O_CLOEXEC) };
        if fd < 0 {
            return Err(anyhow::Error::new(std::io::Error::last_os_error())
                .context(format!("cannot open output {}", path.display())));
        }

        unsafe {
            if ioctl(fd, UI_SET_EVBIT, EV_KEY) != 0 {
                close(fd);
                return Err(VirtualKeyboardError::SetEvBitFailed.into());
            }

            // Full evdev keycode range up to KEY_MAX (0x2ff). A virtual
            // keyboard must be able to carry media/extended codes (>255);
            // a narrower keybit set would silently reject them in the input
            // core (is_event_supported at the disposition stage).
            for code in 0..=0x2ffu32 {
                if ioctl(fd, UI_SET_KEYBIT, code) != 0 {
                    close(fd);
                    return Err(VirtualKeyboardError::SetKeyBitFailed.into());
                }
            }

            let mut uidev: UInputUserDev = std::mem::zeroed();
            uidev.name[..name.len()].copy_from_slice(name.as_bytes());
            uidev.id.bustype = 0x03;
            uidev.id.vendor = 0x1234;
            uidev.id.product = 0x5678;
            uidev.id.version = 1;

            let ret = write_all_fd(
                fd,
                &uidev as *const UInputUserDev as *const libc::c_void,
                std::mem::size_of::<UInputUserDev>(),
            );
            if ret.is_err() {
                close(fd);
                return Err(VirtualKeyboardError::WriteFailed.into());
            }

            if ioctl(fd, UI_DEV_CREATE) != 0 {
                close(fd);
                return Err(VirtualKeyboardError::CreateFailed.into());
            }
        }

        tracing::info!("Virtual keyboard created via /dev/uinput");
        Ok(Self { fd })
    }

    fn emit_raw(&self, type_: u16, code: u16, value: i32) -> Result<()> {
        let ev = UInputEvent {
            time: libc::timeval {
                tv_sec: 0,
                tv_usec: 0,
            },
            type_,
            code,
            value,
        };
        write_all_fd(
            self.fd,
            &ev as *const UInputEvent as *const libc::c_void,
            std::mem::size_of::<UInputEvent>(),
        )
    }

    pub fn emit(&self, event: &InputEvent) -> Result<()> {
        let value = match event.state {
            KeyState::Pressed => 1i32,
            KeyState::Released => 0i32,
        };
        self.emit_raw(EV_KEY as u16, event.keycode as u16, value)?;
        self.emit_raw(EV_SYN as u16, SYN_REPORT, 0)?;
        Ok(())
    }

    /// Physical identity relay: Down is written as value 1, Up as 0, Repeat as 2.
    /// This is the native frame boundary; text stages operate above it.
    pub fn emit_physical(&self, event: &PhysicalKeyEvent) -> Result<()> {
        self.emit_frame(std::slice::from_ref(event))
    }

    /// Preserve one nonempty source key frame with exactly one SYN_REPORT.
    pub fn emit_frame(&self, events: &[PhysicalKeyEvent]) -> Result<()> {
        for event in events {
            anyhow::ensure!(
                matches!(event.native_code, NativeCode::Evdev(c) if c.0 > 0 && c.0 <= 0x2ff && c.0 == event.physical_key.0),
                "unsupported native code"
            );
        }
        for event in events {
            let code = match event.native_code {
                NativeCode::Evdev(c) => c.0,
                _ => return Err(anyhow::anyhow!("unsupported native code")),
            };
            let value = match event.action {
                KeyAction::Down => 1i32,
                KeyAction::Up => 0i32,
                KeyAction::Repeat => 2i32,
            };
            self.emit_raw(EV_KEY as u16, code, value)?;
        }
        if !events.is_empty() {
            self.emit_raw(EV_SYN as u16, SYN_REPORT, 0)?;
        }
        Ok(())
    }

    pub fn emit_syn(&self) -> Result<()> {
        self.emit_raw(EV_SYN as u16, SYN_REPORT, 0)
    }

    pub fn emit_text(&self, text: &str) -> Result<()> {
        for ch in text.chars() {
            if let Some((press, release)) = char_to_press_release(ch) {
                self.emit(&press)?;
                self.emit(&release)?;
            }
        }
        Ok(())
    }
}

impl Drop for VirtualKeyboard {
    fn drop(&mut self) {
        unsafe {
            ioctl(self.fd, UI_DEV_DESTROY);
            close(self.fd);
        }
        tracing::info!("Virtual keyboard destroyed");
    }
}

fn char_to_press_release(ch: char) -> Option<(InputEvent, InputEvent)> {
    let keycode = char_to_keycode(ch)?;
    Some((
        InputEvent::new(keycode, KeyState::Pressed),
        InputEvent::new(keycode, KeyState::Released),
    ))
}

fn char_to_keycode(ch: char) -> Option<u32> {
    match ch {
        'q' | 'Q' => Some(16),
        'w' | 'W' => Some(17),
        'e' | 'E' => Some(18),
        'r' | 'R' => Some(19),
        't' | 'T' => Some(20),
        'y' | 'Y' => Some(21),
        'u' | 'U' => Some(22),
        'i' | 'I' => Some(23),
        'o' | 'O' => Some(24),
        'p' | 'P' => Some(25),
        'a' | 'A' => Some(30),
        's' | 'S' => Some(31),
        'd' | 'D' => Some(32),
        'f' | 'F' => Some(33),
        'g' | 'G' => Some(34),
        'h' | 'H' => Some(35),
        'j' | 'J' => Some(36),
        'k' | 'K' => Some(37),
        'l' | 'L' => Some(38),
        'z' | 'Z' => Some(44),
        'x' | 'X' => Some(45),
        'c' | 'C' => Some(46),
        'v' | 'V' => Some(47),
        'b' | 'B' => Some(48),
        'n' | 'N' => Some(49),
        'm' | 'M' => Some(50),
        '0' => Some(11),
        '1' => Some(2),
        '2' => Some(3),
        '3' => Some(4),
        '4' => Some(5),
        '5' => Some(6),
        '6' => Some(7),
        '7' => Some(8),
        '8' => Some(9),
        '9' => Some(10),
        ' ' => Some(57),
        '\n' => Some(28),
        '\t' => Some(15),
        '-' => Some(12),
        '=' => Some(13),
        '[' => Some(26),
        ']' => Some(27),
        ';' => Some(39),
        '\'' => Some(40),
        '`' => Some(41),
        '\\' => Some(43),
        ',' => Some(51),
        '.' => Some(52),
        '/' => Some(53),
        _ => None,
    }
}

#[derive(Error, Debug)]
pub enum VirtualKeyboardError {
    #[error("failed to open /dev/uinput")]
    OpenFailed,

    #[error("failed to set EV_KEY evbit")]
    SetEvBitFailed,

    #[error("failed to set keybit")]
    SetKeyBitFailed,

    #[error("failed to write uinput device")]
    WriteFailed,

    #[error("failed to create uinput device")]
    CreateFailed,
}
