//! Minimal Linux transport process: no config parser, GUI, D-Bus, text engine,
//! dictionaries, shell templates or network client. Runs as the session user.
use anyhow::{ensure, Result};
use clap::{Parser, Subcommand};
use std::io;
use std::sync::Arc;
use std::time::{Duration, Instant};
use typetune_input::{watchdog::Watchdog, EvdevSource};

#[derive(Parser)]
struct Args {
    #[command(subcommand)]
    command: Mode,
}
#[derive(Subcommand)]
enum Mode {
    Run {
        #[arg(long)]
        parent: u32,
        #[arg(long, required = true)]
        device: Vec<String>,
        #[arg(long)]
        output_name: String,
    },
    #[command(hide = true)]
    Watchdog {
        #[arg(long)]
        parent: u32,
    },
}

struct ParentLease {
    last: Instant,
}
impl ParentLease {
    fn new(parent: u32) -> Result<Self> {
        ensure!(
            parent > 1 && unsafe { libc::getppid() } as u32 == parent,
            "helper parent identity mismatch"
        );
        ensure!(
            unsafe { libc::geteuid() } == unsafe { libc::getuid() },
            "setuid helper execution is unsupported"
        );
        let mut stat: libc::stat = unsafe { std::mem::zeroed() };
        ensure!(
            unsafe { libc::fstat(0, &mut stat) } == 0
                && stat.st_mode & libc::S_IFMT == libc::S_IFIFO,
            "helper requires a private parent control pipe"
        );
        let flags = unsafe { libc::fcntl(0, libc::F_GETFL) };
        ensure!(
            flags >= 0 && unsafe { libc::fcntl(0, libc::F_SETFL, flags | libc::O_NONBLOCK) } >= 0,
            "cannot configure parent pipe"
        );
        Ok(Self {
            last: Instant::now(),
        })
    }
    fn check(&mut self) -> Result<()> {
        let mut bytes = [0u8; 64];
        let n = unsafe { libc::read(0, bytes.as_mut_ptr() as *mut libc::c_void, bytes.len()) };
        if n == 0 {
            anyhow::bail!("parent control pipe closed");
        }
        if n > 0 {
            ensure!(
                bytes[..n as usize].iter().all(|b| *b == b'P'),
                "invalid parent control message"
            );
            self.last = Instant::now();
        } else {
            let error = io::Error::last_os_error();
            ensure!(
                matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                ),
                "parent pipe error: {error}"
            );
        }
        ensure!(
            self.last.elapsed() < Duration::from_secs(2),
            "parent lease expired"
        );
        Ok(())
    }
}

fn run(parent: u32, devices: Vec<String>, output_name: String) -> Result<()> {
    let mut parent_lease = ParentLease::new(parent)?;
    let selections: Vec<_> = devices
        .iter()
        .map(|path| (path.clone(), "selected device".into()))
        .collect();
    let source = Arc::new(EvdevSource::new(&selections)?);
    let stop = source.stop_token();
    signal_hook::flag::register(libc::SIGTERM, stop.clone())?;
    signal_hook::flag::register(libc::SIGINT, stop)?;
    let output = typetune_inject::VirtualKeyboard::with_name(&output_name)?;
    let mut watchdog = Watchdog::start()?;
    let watcher = typetune_input::hotplug::watch_selected_paths(source.clone(), devices);
    let result = source.run_frames(
        |frame| output.emit_frame(frame),
        || {
            // One-byte readiness protocol; logging uses stderr, never this pipe.
            unsafe {
                libc::write(1, b"R".as_ptr() as *const libc::c_void, 1);
            }
        },
        || {
            parent_lease.check()?;
            watchdog.beat()?;
            Ok(())
        },
    );
    source.stop();
    let _ = watcher.join();
    drop(output);
    watchdog.disarm()?;
    result
}

fn main() {
    let args = Args::parse();
    let result = match args.command {
        Mode::Watchdog { parent } => typetune_input::watchdog::monitor(parent).map_err(Into::into),
        Mode::Run {
            parent,
            device,
            output_name,
        } => {
            tracing_subscriber::fmt()
                .with_writer(std::io::stderr)
                .with_env_filter(
                    tracing_subscriber::EnvFilter::try_from_default_env()
                        .unwrap_or_else(|_| "info".into()),
                )
                .init();
            run(parent, device, output_name)
        }
    };
    if let Err(error) = result {
        eprintln!("helper: {error:#}");
        std::process::exit(1);
    }
}
