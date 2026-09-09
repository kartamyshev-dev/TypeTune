mod ipc;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use typetune_chatter::AntiChatter;
use typetune_chatter::ChatterStats;
use typetune_config::Config;
use typetune_core::pipeline::Pipeline;
use typetune_corrector::dictionary::Dictionary;
use typetune_corrector::LayoutCorrector;
use typetune_inject::VirtualKeyboard;
use typetune_input::device_discovery::discover_keyboards;
use typetune_input::EvdevSource;
use typetune_snippets::SnippetExpander;

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
    Daemon,
    Start,
    Stop,
    Status,
    Stats,
    Config {
        #[command(subcommand)]
        action: Option<ConfigAction>,
    },
    ListDevices,
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
        Commands::Daemon => daemon_mode(config),
        Commands::Start => start_daemon(),
        Commands::Stop => stop_daemon(&config),
        Commands::Status => show_status(&config),
        Commands::Stats => show_stats(),
        Commands::Config { action } => match action {
            Some(ConfigAction::Path) => println!("{}", config_path.display()),
            Some(ConfigAction::Edit) => open_editor(&config_path),
            None => println!("{}", config_path.display()),
        },
        Commands::ListDevices => list_devices(&config),
        Commands::Reload => reload_config(&config),
        Commands::Version => println!("typetune {}", env!("CARGO_PKG_VERSION")),
    }
}

fn init_logging(level: &str) {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(level));
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

fn write_pid_file(path: &std::path::Path) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, std::process::id().to_string());
}

fn remove_pid_file(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
}

fn read_pid(path: &std::path::Path) -> Option<i32> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse::<i32>().ok())
}

fn process_alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

fn daemon_mode(config: Config) {
    tracing::info!("Starting TypeTune daemon...");

    let pid_path = config.general.pid_file.clone();
    if let Some(existing_pid) = read_pid(&pid_path) {
        if process_alive(existing_pid) {
            eprintln!("Daemon already running (PID: {})", existing_pid);
            std::process::exit(1);
        }
    }

    write_pid_file(&pid_path);

    let running = Arc::new(AtomicBool::new(true));

    signal_hook::flag::register(signal_hook::consts::SIGTERM, running.clone()).unwrap();
    signal_hook::flag::register(signal_hook::consts::SIGINT, running.clone()).unwrap();

    let config_arc = Arc::new(Mutex::new(config));
    let enabled = Arc::new(Mutex::new(true));
    let stats = Arc::new(Mutex::new(ChatterStats::default()));

    let sighup_config = config_arc.clone();
    std::thread::spawn(move || {
        let mut signals = signal_hook::iterator::Signals::new([libc::SIGHUP]).unwrap();
        for _ in signals.forever() {
            tracing::info!("SIGHUP received, reloading config...");
            let config_path = typetune_config::config_path();
            match typetune_config::load(&config_path) {
                Ok(new_config) => {
                    *sighup_config.lock().unwrap() = new_config;
                    tracing::info!("Config reloaded");
                }
                Err(e) => {
                    tracing::error!("Config reload failed: {}", e);
                }
            }
        }
    });

    let dbus_enabled = enabled.clone();
    let dbus_stats = stats.clone();
    let dbus_config = config_arc.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Err(e) = ipc::run_dbus_server(dbus_enabled, dbus_stats, dbus_config).await {
                tracing::error!("D-Bus server error: {}", e);
            }
        });
    });

    let config = config_arc.lock().unwrap().clone();
    let devices = if config.input.discovery == "auto" {
        discover_keyboards(&config.input.exclude_names)
    } else {
        config
            .input
            .device_paths
            .iter()
            .map(|p| (p.clone(), String::new()))
            .collect()
    };

    if devices.is_empty() {
        tracing::error!("No keyboard devices found!");
        remove_pid_file(&pid_path);
        std::process::exit(1);
    }

    tracing::info!("Found {} keyboard device(s)", devices.len());

    let mut pipeline = Pipeline::new();

    if config.chatter.enabled {
        pipeline.add_stage(Box::new(
            AntiChatter::new(
                config.chatter.debounce_ms,
                config.chatter.modifier_debounce_ms,
            )
            .with_shared_stats(stats.clone()),
        ));
    }

    if config.corrector.enabled {
        let dict_dir = shellexpand::tilde(&config.corrector.dict_dir);
        let dict_path = PathBuf::from(dict_dir.as_ref());

        let ru_dict_path = find_dict_file(&dict_path, "ru.txt")
            .or_else(|| find_dict_file(&PathBuf::from("/usr/share/typetune/dict"), "ru.txt"))
            .unwrap_or_else(|| dict_path.join("ru.txt"));
        let en_dict_path = find_dict_file(&dict_path, "en.txt")
            .or_else(|| find_dict_file(&PathBuf::from("/usr/share/typetune/dict"), "en.txt"))
            .unwrap_or_else(|| dict_path.join("en.txt"));

        pipeline.add_stage(Box::new(LayoutCorrector::new(
            Dictionary::load(&ru_dict_path),
            Dictionary::load(&en_dict_path),
            config.corrector.min_word_length,
            config.corrector.double_shift_corrects,
            config.corrector.double_shift_window_ms,
        )));
    }

    if config.snippets.enabled {
        pipeline.add_stage(Box::new(SnippetExpander::from_config(&config.snippets)));
    }

    let mut source = match EvdevSource::new(&devices) {
        Ok(s) => s,
        Err(e) => {
            tracing::error!("Failed to create input source: {}", e);
            remove_pid_file(&pid_path);
            std::process::exit(1);
        }
    };

    let vkb = match VirtualKeyboard::new() {
        Ok(v) => Arc::new(Mutex::new(v)),
        Err(e) => {
            tracing::error!("Failed to create virtual keyboard: {}", e);
            remove_pid_file(&pid_path);
            std::process::exit(1);
        }
    };

    let tray_config = config_arc.clone();
    let tray_enabled = enabled.clone();
    typetune_tray::run_tray(tray_config, tray_enabled);

    tracing::info!("TypeTune daemon started (PID: {})", std::process::id());

    let pipeline = Arc::new(Mutex::new(pipeline));
    let pipeline_clone = pipeline.clone();
    let enabled_clone = enabled.clone();
    let vkb_clone = vkb.clone();

    let result = source.run(Box::new(move |event| {
        let events = if *enabled_clone.lock().unwrap() {
            pipeline_clone.lock().unwrap().process(event)
        } else {
            vec![event]
        };
        let vkb = vkb_clone.lock().unwrap();
        for e in events {
            if let Err(err) = vkb.emit(&e) {
                tracing::error!("Failed to emit event: {}", err);
            }
        }
    }));

    if let Err(e) = result {
        tracing::error!("Event loop error: {}", e);
    }

    remove_pid_file(&pid_path);
    tracing::info!("TypeTune daemon stopped");
}

#[allow(clippy::zombie_processes)]
fn start_daemon() {
    let pid_path = typetune_config::config_path()
        .parent()
        .unwrap_or(&std::path::PathBuf::from("/tmp"))
        .join("typetune.pid");

    if let Some(existing_pid) = read_pid(&pid_path) {
        if process_alive(existing_pid) {
            println!("Daemon already running (PID: {})", existing_pid);
            return;
        }
    }

    println!("Starting daemon in background...");
    let child = std::process::Command::new("typetune")
        .arg("daemon")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("Failed to start daemon");

    std::thread::sleep(std::time::Duration::from_millis(500));
    println!("Daemon started (PID: {})", child.id());
}

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
        Some(pid) if process_alive(pid) => {
            println!("TypeTune is running (PID: {})", pid);
        }
        Some(_) => {
            println!("TypeTune is not running (stale PID file)");
        }
        None => {
            println!("TypeTune is not running");
        }
    }
}

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

fn list_devices(config: &Config) {
    let devices = discover_keyboards(&config.input.exclude_names);
    if devices.is_empty() {
        println!("No keyboard devices found");
    } else {
        println!("Detected keyboards:");
        for (path, name) in &devices {
            println!("  {} - {}", path, name);
        }
    }
}

fn reload_config(config: &Config) {
    let pid_path = &config.general.pid_file;
    match read_pid(pid_path) {
        Some(pid) if process_alive(pid) => {
            unsafe { libc::kill(pid, libc::SIGHUP) };
            println!("Sent SIGHUP to PID {}", pid);
        }
        Some(_) => println!("Daemon not running"),
        None => println!("No PID file found"),
    }
}

fn open_editor(config_path: &PathBuf) {
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
    std::process::Command::new(editor)
        .arg(config_path)
        .status()
        .expect("Failed to open editor");
}

fn find_dict_file(dir: &std::path::Path, filename: &str) -> Option<PathBuf> {
    let path = dir.join(filename);
    if path.exists() {
        Some(path)
    } else {
        None
    }
}
