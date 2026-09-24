//! Session D-Bus clients for the GNOME preview runtime.
use serde_json::Value;
use zbus::dbus_proxy;

#[dbus_proxy(
    interface = "org.typetune.Compat1",
    default_service = "org.typetune.Compat",
    default_path = "/org/typetune/Compat1"
)]
trait Compat {
    fn get_status(&self) -> zbus::Result<String>;
    fn set_enabled(&self, enabled: bool) -> zbus::Result<bool>;
    fn set_automatic(&self, automatic: bool) -> zbus::Result<bool>;
    fn reload_words(&self, generation: &str) -> zbus::Result<String>;
    fn reload_applications(&self, generation: &str) -> zbus::Result<String>;
    fn quit(&self) -> zbus::Result<()>;
}

#[dbus_proxy(
    interface = "org.typetune.Session1",
    default_service = "org.gnome.Shell",
    default_path = "/org/typetune/Session1"
)]
trait Session {
    fn get_snapshot(&self) -> zbus::Result<String>;
}

/// Snapshot of the compatibility runtime plus the GNOME session flag.
#[derive(Debug, Clone, Default)]
pub struct RuntimeStatus {
    pub running: bool,
    pub enabled: bool,
    pub automatic: bool,
    pub available: bool,
    pub devices: i64,
    pub mode: String,
    pub suggestion_count: i64,
    pub last_result: String,
    pub words_error: String,
    pub applications_error: String,
    pub automatic_blocked: String,
    pub flag: String,
    pub helper_ok: bool,
    pub session_ok: bool,
    pub raw: String,
}

pub async fn fetch_status() -> RuntimeStatus {
    let mut status = RuntimeStatus::default();
    let Ok(conn) = zbus::Connection::session().await else {
        status.raw = "Нет доступа к session bus".into();
        return status;
    };
    // GNOME session bridge (layout flag + doctor).
    if let Ok(session) = SessionProxy::new(&conn).await {
        match session.get_snapshot().await {
            Ok(json) => {
                status.session_ok = true;
                if let Ok(value) = serde_json::from_str::<Value>(&json) {
                    status.flag =
                        flag_of(value.get("source_id").and_then(Value::as_str).unwrap_or(""));
                }
            }
            Err(_) => status.flag = "?".into(),
        }
    }
    // Compatibility runtime.
    match CompatProxy::new(&conn).await {
        Ok(compat) => match compat.get_status().await {
            Ok(json) => {
                status.helper_ok = true;
                status.raw = json.clone();
                if let Ok(value) = serde_json::from_str::<Value>(&json) {
                    status.running = true;
                    status.enabled = value
                        .get("enabled")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    status.automatic = value
                        .get("automatic")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    status.available = value
                        .get("available")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    status.devices = value.get("devices").and_then(Value::as_i64).unwrap_or(0);
                    status.mode = value
                        .get("mode")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string();
                    if status.flag.is_empty() || status.flag == "?" {
                        status.flag = flag_of(&status.mode);
                    }
                    status.suggestion_count = value
                        .get("suggestion_count")
                        .and_then(Value::as_i64)
                        .unwrap_or(0);
                    status.last_result = value
                        .get("last_result")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string();
                    status.words_error = value
                        .get("words_error")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string();
                    status.applications_error = value
                        .get("applications_error")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string();
                    status.automatic_blocked = value
                        .get("automatic_blocked")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string();
                }
            }
            Err(_) => {
                status.raw = "Runtime не отвечает".into();
            }
        },
        Err(_) => status.raw = "Runtime не запущен".into(),
    }
    status
}

pub async fn set_enabled(enabled: bool) -> Result<bool, String> {
    let conn = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    let proxy = CompatProxy::new(&conn).await.map_err(|e| e.to_string())?;
    proxy.set_enabled(enabled).await.map_err(|e| e.to_string())
}

pub async fn set_automatic(automatic: bool) -> Result<bool, String> {
    let conn = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    let proxy = CompatProxy::new(&conn).await.map_err(|e| e.to_string())?;
    proxy
        .set_automatic(automatic)
        .await
        .map_err(|e| e.to_string())
}

pub async fn quit() -> Result<(), String> {
    let conn = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    let proxy = CompatProxy::new(&conn).await.map_err(|e| e.to_string())?;
    proxy.quit().await.map_err(|e| e.to_string())
}

pub fn flag_of(source_id: &str) -> String {
    match source_id {
        "us" | "en" => "us".into(),
        "ru" => "ru".into(),
        _ => "?".into(),
    }
}

/// Lightweight local doctor: device nodes and extension presence.
pub fn local_doctor() -> Vec<(String, bool, String)> {
    let mut rows = Vec::new();
    let input = std::path::Path::new("/dev/input");
    let input_ok = input.is_dir()
        && std::fs::read_dir(input)
            .map(|mut d| d.next().is_some())
            .unwrap_or(false);
    rows.push((
        "Клавиатуры /dev/input".into(),
        input_ok,
        if input_ok {
            "доступны".into()
        } else {
            "нет доступа — откройте «Настроить доступ»".into()
        },
    ));
    let uinput = std::path::Path::new("/dev/uinput").exists();
    rows.push((
        "uinput".into(),
        uinput,
        if uinput {
            "модуль загружен".into()
        } else {
            "модуль uinput не загружен".into()
        },
    ));
    let helper = std::path::Path::new("/usr/lib/typetune-preview/compat/compat_transport")
        .is_file()
        || std::path::Path::new("integrations/compat/compat_transport").is_file();
    rows.push((
        "Helper ввода".into(),
        helper,
        if helper {
            "установлен".into()
        } else {
            "не найден".into()
        },
    ));
    rows
}
