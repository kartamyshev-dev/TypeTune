//! Unprivileged controller for the separate, explicitly selected input helper.
use anyhow::{ensure, Result};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use typetune_input::watchdog::Watchdog;

struct ChildGuard(Child);
impl Drop for ChildGuard {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
}
fn nonblocking(fd: i32) -> Result<()> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    ensure!(
        flags >= 0 && unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } >= 0,
        "cannot configure helper pipe: {}",
        std::io::Error::last_os_error()
    );
    Ok(())
}

pub fn run(devices: &[String], stop: Arc<AtomicBool>, ready: impl FnOnce()) -> Result<()> {
    let executable = std::env::current_exe()?.with_file_name("typetune-helper");
    ensure!(
        executable.is_file(),
        "missing input helper: {}",
        executable.display()
    );
    let mut watchdog = Watchdog::start()?;
    let mut command = Command::new(executable);
    command
        .arg("run")
        .arg("--parent")
        .arg(std::process::id().to_string())
        .arg("--output-name")
        .arg(format!("TypeTune Relay {}", std::process::id()));
    for path in devices {
        command.arg("--device").arg(path);
    }
    let mut child = ChildGuard(
        command
            .process_group(0)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?,
    );
    let mut control = child.0.stdin.take().unwrap();
    let mut status_pipe = child.0.stdout.take().unwrap();
    nonblocking(control.as_raw_fd())?;
    nonblocking(status_pipe.as_raw_fd())?;
    let mut ready = Some(ready);
    let mut shutdown = None;
    let mut last_beat = Instant::now() - Duration::from_secs(1);
    let start = Instant::now();
    let result = (|| -> Result<()> {
        loop {
            watchdog.beat()?;
            if let Some(status) = child.0.try_wait()? {
                ensure!(status.success(), "input helper exited: {status}");
                ensure!(ready.is_none(), "input helper exited before readiness");
                return Ok(());
            }
            if stop.load(Ordering::SeqCst) && shutdown.is_none() {
                ensure!(
                    unsafe { libc::kill(child.0.id() as i32, libc::SIGTERM) } == 0,
                    "cannot stop helper"
                );
                shutdown = Some(Instant::now());
            }
            if shutdown.is_some_and(|time: Instant| time.elapsed() > Duration::from_secs(2)) {
                child.0.kill()?;
                anyhow::bail!("input helper shutdown timed out");
            }
            if last_beat.elapsed() >= Duration::from_millis(100) {
                control.write_all(b"P")?;
                last_beat = Instant::now();
            }
            let mut message = [0u8; 16];
            match status_pipe.read(&mut message) {
                Ok(n) if n > 0 => {
                    ensure!(
                        n == 1 && message[0] == b'R' && ready.is_some(),
                        "invalid helper readiness protocol"
                    );
                    ready.take().unwrap()();
                }
                Ok(_) => {}
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::Interrupted
                    ) => {}
                Err(error) => return Err(error.into()),
            }
            ensure!(
                ready.is_none() || start.elapsed() < Duration::from_secs(3),
                "input helper startup timed out"
            );
            std::thread::sleep(Duration::from_millis(20));
        }
    })();
    drop(control);
    drop(child);
    watchdog.disarm()?;
    result
}
