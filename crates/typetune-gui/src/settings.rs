//! Persistent settings at ~/.config/typetune/settings.json (schema v2).
//! Mirrors integrations/app/app_settings.py; generation is an optimistic ACK.
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

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

impl Settings {
    pub fn load() -> Settings {
        Self::load_from(&settings_path())
    }

    pub fn load_from(path: &std::path::Path) -> Settings {
        let Ok(raw) = std::fs::read(path) else {
            return Settings::default();
        };
        if raw.len() > 4096 {
            return Settings::default();
        }
        let mut value: Settings = serde_json::from_slice(&raw).unwrap_or_default();
        value.version = 2;
        value.mode = "compatibility".into();
        value.validate();
        value
    }

    pub fn validate(&self) {
        assert!(
            !(self.switch_only_last_word && self.dont_switch_words),
            "mutex: switch_only_last_word x dont_switch_words"
        );
    }

    pub fn save(&mut self) -> Result<(), String> {
        self.save_to(&settings_path())
    }

    pub fn save_to(&mut self, path: &std::path::Path) -> Result<(), String> {
        if self.switch_only_last_word && self.dont_switch_words {
            return Err(
                "Нельзя одновременно: «Переключать только последнее слово» и «Не переключать слова»".into(),
            );
        }
        self.version = 2;
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
        let controller = std::path::Path::new("/usr/lib/typetune-preview/controller.py");
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
    fn roundtrip_json() {
        let dir = std::env::temp_dir().join(format!("typetune-settings-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.automatic = false;
        s.save_to(&path).unwrap();
        let loaded = Settings::load_from(&path);
        assert!(!loaded.automatic);
        assert_ne!(loaded.generation, "0");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
