#[cfg(target_os = "linux")]
mod ipc;
#[cfg(target_os = "linux")]
use typetune_input::watchdog;
#[cfg(target_os = "linux")]
mod helper;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use typetune_config::Config;

#[derive(Parser)]
#[command(
    name = "typetune",
    about = "Keyboard daemon: layout correction, anti-chatter, snippets"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    #[arg(long, global = true)]
    config: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// Read-only session capability diagnostics; independent of config and daemon.
    #[cfg(target_os = "linux")]
    Doctor {
        /// Probe the current session without opening input devices.
        #[arg(long, required = true)]
        session: bool,
    },
    #[cfg(target_os = "linux")]
    #[command(hide = true)]
    Watchdog {
        #[arg(long)]
        parent: u32,
    },
    #[cfg(target_os = "linux")]
    Daemon,
    #[cfg(target_os = "linux")]
    Start,
    #[cfg(target_os = "linux")]
    Stop,
    Status,
    #[cfg(target_os = "linux")]
    Stats,
    Config {
        #[command(subcommand)]
        action: Option<ConfigAction>,
    },
    #[cfg(target_os = "linux")]
    ListDevices,
    #[cfg(target_os = "linux")]
    Reload,
    Version,
}

#[derive(Subcommand)]
enum ConfigAction {
    Path,
    Edit,
}

fn main() {
    let cli = Cli::parse();
    #[cfg(target_os = "linux")]
    if let Commands::Watchdog { parent } = cli.command {
        if let Err(error) = watchdog::monitor(parent) {
            eprintln!("watchdog: {error}");
            std::process::exit(1);
        }
        return;
    }

    #[cfg(target_os = "linux")]
    if matches!(cli.command, Commands::Doctor { .. }) {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("cannot initialize diagnostic runtime");
        let report = runtime.block_on(typetune_session::probe());
        println!(
            "{}",
            serde_json::to_string_pretty(&report).expect("session report serialization")
        );
        return;
    }

    let config_path = cli
        .config
        .unwrap_or_else(typetune_config::ensure_config_exists);

    let config = match typetune_config::load(&config_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to load config: {}", e);
            std::process::exit(1);
        }
    };

    init_logging(&config.general.log_level);

    match cli.command {
        #[cfg(target_os = "linux")]
        Commands::Watchdog { .. } | Commands::Doctor { .. } => unreachable!(),
        #[cfg(target_os = "linux")]
        Commands::Daemon => daemon_mode(config),
        #[cfg(target_os = "linux")]
        Commands::Start => start_daemon(&config_path, &config),
        #[cfg(target_os = "linux")]
        Commands::Stop => stop_daemon(&config),
        Commands::Status => show_status(&config),
        #[cfg(target_os = "linux")]
        Commands::Stats => show_stats(),
        Commands::Config { action } => match action {
            Some(ConfigAction::Path) => println!("{}", config_path.display()),
            Some(ConfigAction::Edit) => open_editor(&config_path),
            None => println!("{}", config_path.display()),
        },
        #[cfg(target_os = "linux")]
        Commands::ListDevices => list_devices(&config),
        #[cfg(target_os = "linux")]
        Commands::Reload => reload_config(&config),
        Commands::Version => println!("typetune {}", env!("CARGO_PKG_VERSION")),
    }
}

fn init_logging(level: &str) {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(level));
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

#[cfg(target_os = "linux")]
fn write_pid_file(path: &std::path::Path) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, std::process::id().to_string());
}

#[cfg(target_os = "linux")]
fn remove_pid_file(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
}

fn read_pid(path: &std::path::Path) -> Option<i32> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse::<i32>().ok())
}

#[cfg(target_os = "linux")]
fn process_alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

#[cfg(target_os = "linux")]
fn daemon_mode(config: Config) {
    use std::sync::{Arc, Mutex};
    use typetune_chatter::ChatterStats;

    if let Err(reason) = validate_relay_config(&config) {
        eprintln!("Cannot start daemon: {}", reason);
        std::process::exit(1);
    }
    tracing::info!("Starting TypeTune physical relay; text and debounce backends unavailable");

    let pid_path = config.general.pid_file.clone();
    if let Some(existing_pid) = read_pid(&pid_path) {
        if process_alive(existing_pid) {
            eprintln!("Daemon already running (PID: {})", existing_pid);
            std::process::exit(1);
        }
    }

    write_pid_file(&pid_path);

    let enabled = Arc::new(Mutex::new(false));
    let stats = Arc::new(Mutex::new(ChatterStats::default()));

    std::thread::spawn(move || {
        let mut signals = signal_hook::iterator::Signals::new([libc::SIGHUP]).unwrap();
        for _ in signals.forever() {
            tracing::error!(
                "restart-required: live configuration apply is not supported by physical relay"
            );
        }
    });

    let dbus_enabled = enabled.clone();
    let dbus_stats = stats.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Err(e) = ipc::run_dbus_server(dbus_enabled, dbus_stats).await {
                tracing::error!("D-Bus server error: {}", e);
            }
        });
    });

    let stop_token = Arc::new(std::sync::atomic::AtomicBool::new(false));
    signal_hook::flag::register(libc::SIGTERM, stop_token.clone()).unwrap();
    signal_hook::flag::register(libc::SIGINT, stop_token.clone()).unwrap();
    let result = helper::run(&config.input.device_paths, stop_token, || {
        *enabled.lock().unwrap() = true;
        tracing::info!(
            "TypeTune physical relay started (PID: {})",
            std::process::id()
        );
    });
    *enabled.lock().unwrap() = false;

    if let Err(e) = result {
        tracing::error!("Event loop error: {}", e);
        remove_pid_file(&pid_path);
        std::process::exit(1);
    }

    remove_pid_file(&pid_path);
    tracing::info!("TypeTune daemon stopped");
}

#[cfg(target_os = "linux")]
#[allow(clippy::zombie_processes)]
fn start_daemon(config_path: &std::path::Path, config: &Config) {
    if let Err(reason) = validate_relay_config(config) {
        eprintln!("Cannot start daemon: {}", reason);
        std::process::exit(1);
    }
    if let Some(existing_pid) = read_pid(&config.general.pid_file) {
        if process_alive(existing_pid) {
            println!("Daemon already running (PID: {})", existing_pid);
            return;
        }
    }
    let executable = std::env::current_exe().expect("Failed to locate current executable");
    let mut child = std::process::Command::new(executable)
        .arg("--config")
        .arg(config_path)
        .arg("daemon")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::inherit())
        .spawn()
        .expect("Failed to spawn daemon");
    std::thread::sleep(std::time::Duration::from_millis(500));
    match child.try_wait() {
        Ok(Some(status)) => {
            eprintln!("Daemon exited during startup: {}", status);
            std::process::exit(1);
        }
        Ok(None) => println!(
            "Daemon process spawned (PID: {}); runtime acceptance is not implied",
            child.id()
        ),
        Err(error) => {
            eprintln!("Cannot check daemon startup: {}", error);
            std::process::exit(1);
        }
    }
}

#[cfg(target_os = "linux")]
fn stop_daemon(config: &Config) {
    let pid_path = &config.general.pid_file;
    match read_pid(pid_path) {
        Some(pid) if process_alive(pid) => {
            unsafe { libc::kill(pid, libc::SIGTERM) };
            println!("Sent SIGTERM to PID {}", pid);
            for _ in 0..50 {
                std::thread::sleep(std::time::Duration::from_millis(100));
                if !process_alive(pid) {
                    println!("Daemon stopped");
                    return;
                }
            }
            println!("Warning: daemon did not stop within 5 seconds");
        }
        Some(_) => {
            println!("Daemon not running (stale PID file)");
            let _ = std::fs::remove_file(pid_path);
        }
        None => {
            println!("No PID file found");
        }
    }
}

fn show_status(config: &Config) {
    let pid_path = &config.general.pid_file;
    match read_pid(pid_path) {
        Some(pid) => {
            #[cfg(target_os = "linux")]
            {
                if process_alive(pid) {
                    println!("TypeTune is running (PID: {})", pid);
                } else {
                    println!("TypeTune is not running (stale PID file)");
                }
            }
            #[cfg(not(target_os = "linux"))]
            {
                println!("TypeTune PID file found (PID: {}), status check not available on this platform", pid);
            }
        }
        None => {
            println!("TypeTune is not running");
        }
    }
}

#[cfg(target_os = "linux")]
fn show_stats() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        match zbus::Connection::session().await {
            Ok(conn) => {
                let proxy = ipc::DaemonProxy::new(&conn).await.unwrap();
                match proxy.get_stats().await {
                    Ok((total, suppressed)) => {
                        println!("Anti-Chatter Statistics:");
                        println!("  Total events:  {}", total);
                        println!("  Suppressed:    {}", suppressed);
                        if total > 0 {
                            println!(
                                "  Rate:          {:.2}%",
                                (suppressed as f64 / total as f64) * 100.0
                            );
                        }
                    }
                    Err(e) => eprintln!("Failed to get stats: {}", e),
                }
            }
            Err(e) => eprintln!("Failed to connect to D-Bus: {}", e),
        }
    });
}

#[cfg(target_os = "linux")]
fn list_devices(config: &Config) {
    let devices = typetune_input::device_discovery::discover_keyboards(&config.input.exclude_names);
    if devices.is_empty() {
        println!("No keyboard devices found");
    } else {
        println!("Detected keyboards:");
        for (path, name) in &devices {
            println!("  {} - {}", path, name);
        }
    }
}

#[cfg(target_os = "linux")]
fn reload_config(_config: &Config) {
    eprintln!("restart-required: physical relay configuration cannot be applied live");
    std::process::exit(1);
}

fn open_editor(config_path: &PathBuf) {
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
    std::process::Command::new(editor)
        .arg(config_path)
        .status()
        .expect("Failed to open editor");
}

/// Fail before opening or grabbing any device. Legacy text/chatter stages have
/// no accepted runtime backend and must not be advertised as effective.
fn validate_relay_config(config: &Config) -> Result<(), String> {
    let mut unavailable = Vec::new();
    if config.chatter.enabled {
        unavailable.push("chatter");
    }
    if config.corrector.enabled {
        unavailable.push("corrector");
    }
    if config.snippets.enabled {
        unavailable.push("snippets");
    }
    if config.typography.enabled {
        unavailable.push("typography");
    }
    if !unavailable.is_empty() {
        return Err(format!("unavailable backends: {}. Only physical relay is currently supported; explicitly disable these features to test it", unavailable.join(", ")));
    }
    if config.input.discovery != "manual" || config.input.device_paths.is_empty() {
        return Err("physical relay requires input.discovery=manual and explicit device_paths; automatic grab is disabled".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> Config {
        typetune_config::load(
            &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../config/default.toml"),
        )
        .unwrap()
    }

    #[test]
    fn unavailable_features_fail_before_device_access() {
        let cfg = config();
        let reason = validate_relay_config(&cfg).unwrap_err();
        assert!(reason.contains("corrector"));
        assert!(reason.contains("snippets"));
        assert!(reason.contains("chatter"));
    }

    #[test]
    fn relay_requires_explicit_device_selection() {
        let mut cfg = config();
        cfg.corrector.enabled = false;
        cfg.snippets.enabled = false;
        cfg.chatter.enabled = false;
        assert!(validate_relay_config(&cfg).is_err());
        cfg.input.discovery = "manual".into();
        cfg.input.device_paths = vec!["/synthetic/test-device".into()];
        assert!(validate_relay_config(&cfg).is_ok());
    }
}
