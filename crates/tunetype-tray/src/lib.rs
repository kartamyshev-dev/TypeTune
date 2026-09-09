use ksni::menu::{MenuItem, StandardItem};
use ksni::Tray;
use std::sync::{Arc, Mutex};
use zbus::dbus_proxy;

#[dbus_proxy(
    interface = "org.tunetype.Daemon",
    default_service = "org.tunetype.Daemon",
    default_path = "/org/tunetype/Daemon"
)]
trait Daemon {
    fn get_status(&self) -> zbus::Result<(bool, Vec<String>)>;
    fn set_enabled(&self, enabled: bool) -> zbus::Result<()>;
    fn reload_config(&self) -> zbus::Result<()>;
}

pub struct TuneTypeTray {
    pub config: Arc<Mutex<tunetype_config::Config>>,
    pub enabled: Arc<Mutex<bool>>,
}

impl Tray for TuneTypeTray {
    fn id(&self) -> String {
        "tunetype".into()
    }

    fn title(&self) -> String {
        "TuneType".into()
    }

    fn icon_name(&self) -> String {
        if *self.enabled.lock().unwrap() {
            "input-keyboard".into()
        } else {
            "input-keyboard-disabled".into()
        }
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let enabled = *self.enabled.lock().unwrap();
        vec![
            StandardItem {
                label: if enabled {
                    "TuneType: enabled".into()
                } else {
                    "TuneType: disabled".into()
                },
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: if enabled {
                    "Disable".into()
                } else {
                    "Enable".into()
                },
                activate: Box::new(|tray: &mut TuneTypeTray| {
                    let mut e = tray.enabled.lock().unwrap();
                    *e = !*e;
                    let new_state = *e;
                    drop(e);
                    std::thread::spawn(move || {
                        let rt = tokio::runtime::Runtime::new().unwrap();
                        rt.block_on(async {
                            if let Ok(conn) = zbus::Connection::session().await {
                                if let Ok(proxy) = DaemonProxy::new(&conn).await {
                                    let _ = proxy.set_enabled(new_state).await;
                                }
                            }
                        });
                    });
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Reload config".into(),
                activate: Box::new(|_tray: &mut TuneTypeTray| {
                    std::thread::spawn(|| {
                        let rt = tokio::runtime::Runtime::new().unwrap();
                        rt.block_on(async {
                            if let Ok(conn) = zbus::Connection::session().await {
                                if let Ok(proxy) = DaemonProxy::new(&conn).await {
                                    let _ = proxy.reload_config().await;
                                }
                            }
                        });
                    });
                }),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Exit".into(),
                activate: Box::new(|_| {
                    let pid_path = tunetype_config::config_path()
                        .parent()
                        .unwrap_or(&std::path::PathBuf::from("/tmp"))
                        .join("tunetype.pid");
                    if let Ok(pid_str) = std::fs::read_to_string(&pid_path) {
                        if let Ok(pid) = pid_str.trim().parse::<i32>() {
                            unsafe { libc::kill(pid, libc::SIGTERM) };
                        }
                    }
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

pub fn run_tray(config: Arc<Mutex<tunetype_config::Config>>, enabled: Arc<Mutex<bool>>) {
    let tray = TuneTypeTray { config, enabled };
    ksni::TrayService::new(tray).spawn();
}
