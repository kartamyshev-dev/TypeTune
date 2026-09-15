//! Independent process lease for the physical input loop. The child never owns
//! input/output fds. A pidfd pins its parent identity even after PID reuse.
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::time::{Duration, Instant};

const TIMEOUT: Duration = Duration::from_secs(2);
const GRACE: Duration = Duration::from_millis(500);
const BEAT_INTERVAL: Duration = Duration::from_millis(100);

pub struct Watchdog {
    child: Child,
    pipe: Option<ChildStdin>,
    last_beat: Instant,
}

impl Watchdog {
    pub fn start() -> io::Result<Self> {
        let mut child = Command::new(std::env::current_exe()?)
            .process_group(0)
            .arg("watchdog")
            .arg("--parent")
            .arg(std::process::id().to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;
        let result = (|| {
            let mut stdout = child
                .stdout
                .take()
                .ok_or_else(|| io::Error::other("no watchdog stdout"))?;
            let mut ready = [0];
            if !poll_readable(stdout.as_raw_fd(), TIMEOUT)? {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "watchdog startup timeout",
                ));
            }
            stdout.read_exact(&mut ready)?;
            if ready != *b"R" {
                return Err(io::Error::other("invalid watchdog handshake"));
            }
            let pipe = child
                .stdin
                .take()
                .ok_or_else(|| io::Error::other("no watchdog stdin"))?;
            let flags = unsafe { libc::fcntl(pipe.as_raw_fd(), libc::F_GETFL) };
            if flags < 0
                || unsafe { libc::fcntl(pipe.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK) }
                    < 0
            {
                return Err(io::Error::last_os_error());
            }
            Ok(pipe)
        })();
        match result {
            Ok(pipe) => Ok(Self {
                child,
                pipe: Some(pipe),
                last_beat: Instant::now() - BEAT_INTERVAL,
            }),
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                Err(error)
            }
        }
    }

    /// Called only by the input loop, never by an independent heartbeat thread.
    pub fn beat(&mut self) -> io::Result<()> {
        if self.last_beat.elapsed() >= BEAT_INTERVAL {
            self.pipe
                .as_mut()
                .ok_or_else(|| io::Error::other("watchdog disarmed"))?
                .write_all(b"P")?;
            self.last_beat = Instant::now();
        }
        Ok(())
    }

    /// Call only after loop cleanup/ungrab and output destruction.
    pub fn disarm(mut self) -> io::Result<()> {
        if let Some(mut pipe) = self.pipe.take() {
            pipe.write_all(b"D")?;
        }
        let deadline = Instant::now() + GRACE;
        while Instant::now() < deadline {
            if let Some(status) = self.child.try_wait()? {
                return if status.success() {
                    Ok(())
                } else {
                    Err(io::Error::other("watchdog exited with error"))
                };
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "watchdog disarm timeout",
        ))
    }
}

impl Drop for Watchdog {
    fn drop(&mut self) {
        // No implicit disarm on unwind: EOF still revokes the lease. Reap if
        // already exited; otherwise parent exit/timeout lets the monitor finish.
        self.pipe.take();
        let _ = self.child.try_wait();
    }
}

fn poll_readable(fd: i32, duration: Duration) -> io::Result<bool> {
    let deadline = Instant::now() + duration;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let mut pollfd = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let n = unsafe {
            libc::poll(
                &mut pollfd,
                1,
                remaining.as_millis().min(i32::MAX as u128) as i32,
            )
        };
        if n >= 0 {
            return Ok(n > 0);
        }
        let error = io::Error::last_os_error();
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(error);
        }
    }
}

fn signal(pidfd: i32, sig: i32) -> io::Result<()> {
    let n = unsafe {
        libc::syscall(
            libc::SYS_pidfd_send_signal,
            pidfd,
            sig,
            std::ptr::null::<libc::siginfo_t>(),
            0,
        )
    };
    if n < 0 {
        let error = io::Error::last_os_error();
        if error.raw_os_error() != Some(libc::ESRCH) {
            return Err(error);
        }
    }
    Ok(())
}

pub fn monitor(parent: u32) -> io::Result<()> {
    if parent <= 1 || unsafe { libc::getppid() } as u32 != parent {
        return Err(io::Error::other("watchdog can only monitor its own parent"));
    }
    let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, parent, 0) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let pidfd = unsafe { OwnedFd::from_raw_fd(fd as i32) };
    if unsafe { libc::getppid() } as u32 != parent {
        return Err(io::Error::other("parent exited during setup"));
    }
    std::io::stdout().write_all(b"R")?;
    std::io::stdout().flush()?;
    let mut last_beat = Instant::now();
    'monitor: loop {
        let remaining = TIMEOUT.saturating_sub(last_beat.elapsed());
        if remaining.is_zero() {
            break;
        }
        let mut fds = [
            libc::pollfd {
                fd: pidfd.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: libc::STDIN_FILENO,
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let n = unsafe { libc::poll(fds.as_mut_ptr(), 2, remaining.as_millis() as i32) };
        if n < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            break; // fail closed: revoke lease on monitor I/O failure
        }
        if fds[0].revents != 0 {
            return Ok(());
        }
        if fds[1].revents != 0 {
            let mut buf = [0; 64];
            // Use the fd directly: std::io::Stdin may read ahead internally,
            // which would make poll miss already buffered heartbeat/disarm bytes.
            let n = unsafe {
                libc::read(
                    libc::STDIN_FILENO,
                    buf.as_mut_ptr() as *mut libc::c_void,
                    buf.len(),
                )
            };
            if n < 0 {
                if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                break;
            }
            let n = n as usize;
            if n == 0 {
                break;
            }
            for byte in &buf[..n] {
                match byte {
                    b'D' => return Ok(()),
                    b'P' => last_beat = Instant::now(),
                    _ => break 'monitor,
                }
            }
        }
    }
    signal(pidfd.as_raw_fd(), libc::SIGTERM)?;
    if !poll_readable(pidfd.as_raw_fd(), GRACE)? {
        signal(pidfd.as_raw_fd(), libc::SIGKILL)?;
        eprintln!("watchdog: lease expired; sent SIGTERM then SIGKILL");
    }
    Ok(())
}
