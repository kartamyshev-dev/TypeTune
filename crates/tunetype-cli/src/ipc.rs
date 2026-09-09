use std::sync::{Arc, Mutex};
use tunetype_chatter::ChatterStats;
use zbus::{dbus_interface, dbus_proxy, ConnectionBuilder};

pub struct DaemonInterface {
    pub enabled: Arc<Mutex<bool>>,
    pub stats: Arc<Mutex<ChatterStats>>,
    pub config: Arc<Mutex<tunetype_config::Config>>,
}

#[dbus_interface(name = "org.tunetype.Daemon")]
impl DaemonInterface {
    fn get_status(&self) -> (bool, Vec<String>) {
        let e = *self.enabled.lock().unwrap();
        let mut features = Vec::new();
        let cfg = self.config.lock().unwrap();
        if cfg.chatter.enabled {
            features.push("anti-chatter".into());
        }
        if cfg.corrector.enabled {
            features.push("layout-corrector".into());
        }
        if cfg.snippets.enabled {
            features.push("snippets".into());
        }
        (e, features)
    }

    fn set_enabled(&self, enabled: bool) {
        *self.enabled.lock().unwrap() = enabled;
        tracing::info!("Daemon {}", if enabled { "enabled" } else { "disabled" });
    }

    fn get_stats(&self) -> (u64, u64) {
        let s = self.stats.lock().unwrap();
        (s.total_events, s.suppressed_events)
    }

    fn reload_config(&self) {
        let config_path = tunetype_config::config_path();
        match tunetype_config::load(&config_path) {
            Ok(new_config) => {
                *self.config.lock().unwrap() = new_config;
                tracing::info!("Config reloaded via D-Bus");
            }
            Err(e) => {
                tracing::error!("Failed to reload config: {}", e);
            }
        }
    }
}

pub async fn run_dbus_server(
    enabled: Arc<Mutex<bool>>,
    stats: Arc<Mutex<ChatterStats>>,
    config: Arc<Mutex<tunetype_config::Config>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let iface = DaemonInterface {
        enabled,
        stats,
        config,
    };

    let _conn = ConnectionBuilder::session()?
        .name("org.tunetype.Daemon")?
        .serve_at("/org/tunetype/Daemon", iface)?
        .build()
        .await?;

    tracing::info!("D-Bus interface registered at org.tunetype.Daemon");

    std::future::pending::<()>().await;
    Ok(())
}

#[dbus_proxy(
    interface = "org.tunetype.Daemon",
    default_service = "org.tunetype.Daemon",
    default_path = "/org/tunetype/Daemon"
)]
pub trait Daemon {
    fn get_status(&self) -> zbus::Result<(bool, Vec<String>)>;
    fn set_enabled(&self, enabled: bool) -> zbus::Result<()>;
    fn get_stats(&self) -> zbus::Result<(u64, u64)>;
    fn reload_config(&self) -> zbus::Result<()>;
}
