pub mod device_discovery;

use anyhow::Result;
use libc::{input_event, ENODEV, EWOULDBLOCK, O_CLOEXEC, O_NONBLOCK, O_RDONLY};
use std::fs::{File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use thiserror::Error;
use typetune_core::event::{InputEvent, KeyState};

const EVDEV_OFFSET: u32 = 8;
const EV_KEY: u16 = 1;

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
        let evdev_code: libc::c_ulong = 0x40044590;
        let grab_val: i32 = 1;
        let ret = unsafe { libc::ioctl(self.file.as_raw_fd(), evdev_code, &grab_val) };
        if ret != 0 {
            return Err(anyhow::anyhow!("EVIOCGRAB failed for {}", self.path));
        }
        tracing::info!("Grabbed: {}", self.path);
        Ok(())
    }

    pub fn ungrab(&mut self) {
        let evdev_code: libc::c_ulong = 0x40044590;
        let grab_val: i32 = 0;
        unsafe {
            libc::ioctl(self.file.as_raw_fd(), evdev_code, &grab_val);
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
            for ev in evs.iter().take(count) {
                if ev.type_ == EV_KEY {
                    let state = if ev.value == 1 {
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

impl Drop for EvdevDevice {
    fn drop(&mut self) {
        self.ungrab();
    }
}

pub struct EvdevRawEvent {
    pub keycode: u32,
    pub state: KeyState,
}

pub struct EvdevSource {
    devices: Vec<EvdevDevice>,
    running: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl EvdevSource {
    pub fn new(device_paths: &[(String, String)]) -> Result<Self> {
        let mut devices = Vec::new();
        for (path, name) in device_paths {
            match EvdevDevice::open(path) {
                Ok(dev) => {
                    tracing::info!("Opened device: {} ({})", name, path);
                    devices.push(dev);
                }
                Err(e) => {
                    tracing::warn!("Failed to open {}: {}", path, e);
                }
            }
        }

        if devices.is_empty() {
            return Err(DeviceError::NoDevicesFound.into());
        }

        Ok(Self {
            devices,
            running: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        })
    }

    pub fn grab_all(&mut self) -> Vec<usize> {
        let mut grabbed = Vec::new();
        for (i, dev) in self.devices.iter_mut().enumerate() {
            match dev.grab() {
                Ok(_) => grabbed.push(i),
                Err(e) => {
                    tracing::warn!("Skipping device {}: {}", dev.path(), e);
                }
            }
        }
        grabbed
    }

    pub fn ungrab_all(&mut self) {
        for dev in &mut self.devices {
            dev.ungrab();
        }
    }

    pub fn run(&mut self, callback: Box<dyn Fn(InputEvent) + Send>) -> Result<()> {
        let grabbed_indices = self.grab_all();

        if grabbed_indices.is_empty() {
            return Err(anyhow::anyhow!("No devices could be grabbed"));
        }

        self.running
            .store(true, std::sync::atomic::Ordering::SeqCst);

        let epfd = unsafe { libc::epoll_create1(0) };
        if epfd < 0 {
            return Err(anyhow::anyhow!("epoll_create1 failed"));
        }

        for &i in &grabbed_indices {
            let dev = &self.devices[i];
            let mut ev: libc::epoll_event = unsafe { std::mem::zeroed() };
            ev.events = libc::EPOLLIN as u32;
            ev.u64 = i as u64;
            if unsafe { libc::epoll_ctl(epfd, libc::EPOLL_CTL_ADD, dev.fd(), &mut ev) } != 0 {
                return Err(anyhow::anyhow!("epoll_ctl failed for {}", dev.path()));
            }
        }

        tracing::info!(
            "Event loop started ({} grabbed of {} devices, epoll)",
            grabbed_indices.len(),
            self.devices.len()
        );

        let mut epoll_events: [libc::epoll_event; 16] = unsafe { std::mem::zeroed() };

        loop {
            if !self.running.load(std::sync::atomic::Ordering::SeqCst) {
                break;
            }

            let nfds = unsafe { libc::epoll_wait(epfd, epoll_events.as_mut_ptr(), 16, 100) };

            if nfds < 0 {
                let errno = unsafe { *libc::__errno_location() };
                if errno == libc::EINTR {
                    continue;
                }
                tracing::error!("epoll_wait failed: errno {}", errno);
                break;
            }

            for ev in epoll_events.iter().take(nfds as usize) {
                let idx = ev.u64 as usize;
                let dev = &self.devices[idx];

                match dev.read_events() {
                    Ok(raw_events) => {
                        for raw in raw_events {
                            let event = InputEvent::new(raw.keycode, raw.state);
                            callback(event);
                        }
                    }
                    Err(e) => {
                        tracing::warn!("Device {} read error: {}", dev.path(), e);
                        if let Some(DeviceError::Disconnected(_)) = e.downcast_ref::<DeviceError>()
                        {
                            tracing::info!("Removing disconnected device: {}", dev.path());
                            unsafe {
                                libc::epoll_ctl(
                                    epfd,
                                    libc::EPOLL_CTL_DEL,
                                    dev.fd(),
                                    std::ptr::null_mut(),
                                );
                            }
                        }
                    }
                }
            }
        }

        unsafe { libc::close(epfd) };
        self.ungrab_all();
        tracing::info!("Event loop stopped");
        Ok(())
    }

    pub fn stop(&mut self) {
        self.running
            .store(false, std::sync::atomic::Ordering::SeqCst);
    }
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
