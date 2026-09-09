use anyhow::Result;
use libc::{input_event, O_CLOEXEC, O_RDONLY, O_NONBLOCK, EWOULDBLOCK, ENODEV};
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use thiserror::Error;
use tunetype_core::event::{InputEvent, KeyState};

const EVDEV_OFFSET: u32 = 8;
const EV_KEY: u16 = 1;
const KEY_STATE_PRESS: i32 = 1;
const KEY_STATE_RELEASE: i32 = 0;

pub struct EvdevDevice {
    path: String,
    file: File,
}

impl EvdevDevice {
    pub fn open(path: &str) -> Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(O_NONBLOCK | O_CLOEXEC | O_RDONLY)
            .open(path)?;

        Ok(Self {
            path: path.to_string(),
            file,
        })
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn fd(&self) -> i32 {
        self.file.as_raw_fd()
    }

    pub fn grab(&mut self) -> Result<()> {
        use evdev::Device;
        let mut dev = Device::from_file(self.file.try_clone()?)?;
        dev.grab()?;
        std::mem::forget(dev);
        Ok(())
    }

    pub fn ungrab(&mut self) {
        use evdev::Device;
        if let Ok(mut dev) = Device::from_file(self.file.try_clone()?) {
            let _ = dev.ungrab();
        }
    }

    pub fn read_events(&self) -> Result<Vec<EvdevRawEvent>> {
        let mut events = Vec::new();
        let mut evs: [input_event; 16] = unsafe { std::mem::zeroed() };

        loop {
            let len = unsafe {
                libc::read(
                    self.file.as_raw_fd(),
                    evs.as_mut_ptr() as *mut libc::c_void,
                    std::mem::size_of_val(&evs),
                )
            };

            if len <= 0 {
                let errno = unsafe { *libc::__errno_location() };
                if len < 0 && errno != EWOULDBLOCK {
                    if errno == ENODEV {
                        return Err(DeviceError::Disconnected(self.path.clone()).into());
                    }
                    return Err(DeviceError::ReadFailed(self.path.clone(), errno).into());
                }
                break;
            }

            let count = len as usize / std::mem::size_of::<input_event>();
            for i in 0..count {
                let ev = evs[i];
                if ev.type_ == EV_KEY {
                    let state = if ev.value == KEY_STATE_PRESS {
                        KeyState::Pressed
                    } else {
                        KeyState::Released
                    };
                    events.push(EvdevRawEvent {
                        keycode: ev.code as u32 + EVDEV_OFFSET,
                        state,
                    });
                }
            }
        }

        Ok(events)
    }
}

pub struct EvdevRawEvent {
    pub keycode: u32,
    pub state: KeyState,
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
