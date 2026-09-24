//! Persistent settings at ~/.config/typetune/settings.json (schema v2).
//! Mirrors integrations/app/app_settings.py: flock + generation ACK.
//! Corrupt files are never silently replaced by defaults.
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

pub fn settings_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let mut home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
            home.push(".config");
            home
        });
    base.join("typetune").join("settings.json")
}

pub fn autostart_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let mut home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
            home.push(".config");
            home
        });
    base.join("autostart")
        .join("dev.kartamyshev.TypeTune.Preview.desktop")
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Settings {
    #[serde(default = "default_version")]
    pub version: u32,
    #[serde(default = "default_generation")]
    pub generation: String,
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default = "default_true")]
    pub automatic: bool,
    #[serde(default = "default_true")]
    pub manual_switching: bool,
    #[serde(default = "default_true")]
    pub switch_only_last_word: bool,
    #[serde(default)]
    pub dont_switch_words: bool,
    #[serde(default = "default_true")]
    pub dont_correct_after_layout_change: bool,
    #[serde(default = "default_true")]
    pub display_layout_flag: bool,
    #[serde(default)]
    pub play_switching_sound: bool,
    #[serde(default)]
    pub autostart: bool,
    #[serde(default = "default_threshold")]
    pub learn_threshold: i32,
    #[serde(default = "default_boards")]
    pub active_keyboards: Vec<String>,
}

fn default_version() -> u32 {
    2
}
fn default_generation() -> String {
    "0".into()
}
fn default_mode() -> String {
    "compatibility".into()
}
fn default_true() -> bool {
    true
}
fn default_threshold() -> i32 {
    3
}
fn default_boards() -> Vec<String> {
    vec!["us".into(), "ru".into()]
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: 2,
            generation: "0".into(),
            mode: "compatibility".into(),
            automatic: true,
            manual_switching: true,
            switch_only_last_word: true,
            dont_switch_words: false,
            dont_correct_after_layout_change: true,
            display_layout_flag: true,
            play_switching_sound: false,
            autostart: false,
            learn_threshold: 3,
            active_keyboards: default_boards(),
        }
    }
}

/// Result of opening the store. `error` is set when a file exists but is
/// unusable; callers must not overwrite it with defaults.
#[derive(Debug, Clone)]
pub struct Store {
    pub settings: Settings,
    pub error: Option<String>,
}

impl Store {
    pub fn load() -> Store {
        Self::load_from(&settings_path())
    }

    pub fn load_from(path: &Path) -> Store {
        let raw = match std::fs::read(path) {
            Ok(raw) => raw,
            Err(_) => {
                return Store {
                    settings: Settings::default(),
                    error: None,
                }
            }
        };
        if raw.len() > 4096 {
            return Store {
                settings: Settings::default(),
                error: Some("Файл настроек слишком большой".into()),
            };
        }
        match parse(&raw) {
            Ok(settings) => Store {
                settings,
                error: None,
            },
            Err(error) => Store {
                settings: Settings::default(),
                error: Some(error),
            },
        }
    }

    pub fn save(&mut self) -> Result<(), String> {
        if self.error.is_some() {
            return Err(
                "Файл настроек повреждён — не перезаписываю. Исправьте или удалите его.".into(),
            );
        }
        let path = settings_path();
        let expected = if self.settings.generation == "0" {
            None
        } else {
            Some(self.settings.generation.clone())
        };
        self.settings.save_to(&path, expected.as_deref())
    }
}

fn parse(raw: &[u8]) -> Result<Settings, String> {
    let mut value: Settings =
        serde_json::from_slice(raw).map_err(|_| "Файл настроек TypeTune повреждён".to_string())?;
    value.version = 2;
    value.mode = "compatibility".into();
    value.validate()?;
    Ok(value)
}

impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        if self.switch_only_last_word && self.dont_switch_words {
            return Err(
                "Нельзя одновременно: «Переключать только последнее слово» и «Не переключать слова»"
                    .into(),
            );
        }
        if !(1..=10).contains(&self.learn_threshold) {
            return Err("Порог предложений: целое число от 1 до 10".into());
        }
        if self.active_keyboards.is_empty() || self.active_keyboards.len() > 16 {
            return Err("Активные раскладки: список идентификаторов xkb".into());
        }
        Ok(())
    }

    /// Optimistic ACK: `expected` must match the on-disk generation.
    pub fn save_to(&mut self, path: &Path, expected: Option<&str>) -> Result<(), String> {
        self.validate()?;
        self.version = 2;
        let _lock = LockFile::acquire(path)?;
        if path.exists() {
            let raw = std::fs::read(path).map_err(|e| e.to_string())?;
            if let Some(want) = expected {
                let current = parse(&raw)
                    .map_err(|_| "Настройки изменены другим окном; обновите данные".to_string())?;
                if current.generation != want {
                    return Err("Настройки изменены другим окном; обновите данные".into());
                }
            }
        }
        self.generation = new_generation();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let text = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, text + "\n").map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, path).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Mutual exclusion: enabling one policy unchecks the other.
    pub fn toggling_switch_only_last_word(&mut self, on: bool) {
        self.switch_only_last_word = on;
        if on {
            self.dont_switch_words = false;
        }
    }

    pub fn toggling_dont_switch_words(&mut self, on: bool) {
        self.dont_switch_words = on;
        if on {
            self.switch_only_last_word = false;
        }
    }
}

/// Exclusive lock on `<settings>.lock`, same file the Python side uses.
struct LockFile {
    file: std::fs::File,
}

impl LockFile {
    fn acquire(path: &Path) -> Result<LockFile, String> {
        use std::os::unix::io::AsRawFd;
        let lock_path = path.with_extension("lock");
        if let Some(parent) = lock_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&lock_path)
            .map_err(|e| e.to_string())?;
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
            return Err("Не удалось заблокировать файл настроек".into());
        }
        Ok(LockFile { file })
    }
}

impl Drop for LockFile {
    fn drop(&mut self) {
        use std::os::unix::io::AsRawFd;
        unsafe {
            libc::flock(self.file.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

fn new_generation() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:016x}", nanos)
}

pub fn write_autostart(enabled: bool) -> Result<(), String> {
    let path = autostart_path();
    if enabled {
        let controller = Path::new("/usr/lib/typetune-preview/controller.py");
        if !controller.is_file() {
            return Err("Сначала установите TypeTune".into());
        }
        let body = format!(
            "[Desktop Entry]\nType=Application\nName=TypeTune\nExec=/usr/bin/python3 \"{}\" autostart\nTryExec=/usr/bin/typetune-preview\nIcon=input-keyboard\nTerminal=false\nOnlyShowIn=GNOME;\nX-GNOME-Autostart-enabled=true\n",
            controller.display()
        );
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(&path, body).map_err(|e| e.to_string())?;
    } else {
        let _ = std::fs::remove_file(&path);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_valid_v2() {
        let s = Settings::default();
        assert_eq!(s.version, 2);
        assert!(s.automatic);
        assert!(s.manual_switching);
        assert!(!s.dont_switch_words);
        s.validate().unwrap();
    }

    #[test]
    fn mutex_helpers() {
        let mut s = Settings::default();
        s.toggling_dont_switch_words(true);
        assert!(s.dont_switch_words);
        assert!(!s.switch_only_last_word);
        s.toggling_switch_only_last_word(true);
        assert!(s.switch_only_last_word);
        assert!(!s.dont_switch_words);
    }

    #[test]
    fn validate_rejects_mutex_without_panic() {
        let mut s = Settings::default();
        s.switch_only_last_word = true;
        s.dont_switch_words = true;
        assert!(s.validate().is_err());
        assert!(s
            .save_to(&std::env::temp_dir().join("no-write"), None)
            .is_err());
    }

    #[test]
    fn roundtrip_json() {
        let dir = std::env::temp_dir().join(format!("typetune-settings-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.automatic = false;
        s.save_to(&path, None).unwrap();
        let store = Store::load_from(&path);
        assert!(store.error.is_none());
        assert!(!store.settings.automatic);
        assert_ne!(store.settings.generation, "0");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_file_is_not_replaced_by_defaults() {
        let dir = std::env::temp_dir().join(format!("typetune-corrupt-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        std::fs::write(&path, b"{ not json").unwrap();
        let mut store = Store::load_from(&path);
        assert!(store.error.is_some());
        assert!(
            store.save().is_err(),
            "must not clobber a corrupt-but-real file"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_generation_is_rejected() {
        let dir = std::env::temp_dir().join(format!("typetune-stale-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut first = Settings::default();
        first.save_to(&path, None).unwrap();
        let mut second = Settings::default();
        second.automatic = false;
        let stale = "deadbeef".to_string();
        assert!(second.save_to(&path, Some(&stale)).is_err());
        let live = first.generation.clone();
        second.save_to(&path, Some(&live)).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
    }
}
