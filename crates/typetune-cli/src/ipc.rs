use std::sync::{Arc, Mutex};
use typetune_chatter::ChatterStats;
use zbus::{dbus_interface, dbus_proxy, ConnectionBuilder};

pub struct DaemonInterface {
    pub enabled: Arc<Mutex<bool>>,
    pub stats: Arc<Mutex<ChatterStats>>,
}

#[dbus_interface(name = "org.typetune.Daemon")]
impl DaemonInterface {
    fn get_status(&self) -> (bool, Vec<String>) {
        let e = *self.enabled.lock().unwrap();
        (e, vec!["physical-relay".into()])
    }

    fn set_enabled(&self, _enabled: bool) -> zbus::fdo::Result<()> {
        Err(zbus::fdo::Error::NotSupported(
            "physical relay has no optional processing to pause; stop the daemon to detach".into(),
        ))
    }

    fn get_stats(&self) -> (u64, u64) {
        let s = self.stats.lock().unwrap();
        (s.total_events, s.suppressed_events)
    }

    fn reload_config(&self) -> zbus::fdo::Result<()> {
        Err(zbus::fdo::Error::NotSupported(
            "restart-required: physical relay configuration cannot be applied live".into(),
        ))
    }
}

pub async fn run_dbus_server(
    enabled: Arc<Mutex<bool>>,
    stats: Arc<Mutex<ChatterStats>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let iface = DaemonInterface { enabled, stats };

    let _conn = ConnectionBuilder::session()?
        .name("org.typetune.Daemon")?
        .serve_at("/org/typetune/Daemon", iface)?
        .build()
        .await?;

    tracing::info!("D-Bus interface registered at org.typetune.Daemon");

    std::future::pending::<()>().await;
    Ok(())
}

#[dbus_proxy(
    interface = "org.typetune.Daemon",
    default_service = "org.typetune.Daemon",
    default_path = "/org/typetune/Daemon"
)]
pub trait Daemon {
    fn get_status(&self) -> zbus::Result<(bool, Vec<String>)>;
    fn set_enabled(&self, enabled: bool) -> zbus::Result<()>;
    fn get_stats(&self) -> zbus::Result<(u64, u64)>;
    fn reload_config(&self) -> zbus::Result<()>;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn status_and_reload_do_not_claim_unavailable_features() {
        let interface = DaemonInterface {
            enabled: Arc::new(Mutex::new(true)),
            stats: Arc::new(Mutex::new(ChatterStats::default())),
        };
        assert_eq!(
            interface.get_status(),
            (true, vec!["physical-relay".into()])
        );
        let error = interface.reload_config().unwrap_err().to_string();
        assert!(error.contains("restart-required"));
        assert!(interface.set_enabled(false).is_err());
        assert!(interface.get_status().0);
    }
}
