use anyhow::Result;
use libc::{c_uint, close, ioctl, open, write, O_NONBLOCK, O_WRONLY};
use std::ffi::CString;
use thiserror::Error;
use tunetype_core::event::{InputEvent, KeyState};

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

pub struct VirtualKeyboard {
    fd: i32,
}

impl VirtualKeyboard {
    pub fn new() -> Result<Self> {
        let uinput_path = CString::new("/dev/uinput")?;
        let fd = unsafe { open(uinput_path.as_ptr(), O_WRONLY | O_NONBLOCK) };
        if fd < 0 {
            return Err(VirtualKeyboardError::OpenFailed.into());
        }

        unsafe {
            if ioctl(fd, UI_SET_EVBIT, EV_KEY) != 0 {
                close(fd);
                return Err(VirtualKeyboardError::SetEvBitFailed.into());
            }

            for code in 0..256u32 {
                if ioctl(fd, UI_SET_KEYBIT, code) != 0 {
                    close(fd);
                    return Err(VirtualKeyboardError::SetKeyBitFailed.into());
                }
            }

            let mut uidev: UInputUserDev = std::mem::zeroed();
            let name = b"TuneType Virtual Keyboard\0";
            uidev.name[..name.len()].copy_from_slice(name);
            uidev.id.bustype = 0x03;
            uidev.id.vendor = 0x1234;
            uidev.id.product = 0x5678;
            uidev.id.version = 1;

            let ret = write(
                fd,
                &uidev as *const UInputUserDev as *const libc::c_void,
                std::mem::size_of::<UInputUserDev>(),
            );
            if ret < 0 {
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
        let ret = unsafe {
            write(
                self.fd,
                &ev as *const UInputEvent as *const libc::c_void,
                std::mem::size_of::<UInputEvent>(),
            )
        };
        if ret < 0 {
            return Err(anyhow::anyhow!("emit failed"));
        }
        Ok(())
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
        'a'..='z' => Some((ch as u32) - ('a' as u32) + 30),
        'A'..='Z' => Some((ch.to_lowercase().next()? as u32) - ('a' as u32) + 30),
        '0'..='9' => Some((ch as u32) - ('0' as u32) + 2),
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
        ',' => Some(44),
        '.' => Some(45),
        '/' => Some(46),
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
