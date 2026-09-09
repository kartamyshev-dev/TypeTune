use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Config {
    pub general: GeneralConfig,
    pub input: InputConfig,
    pub corrector: CorrectorConfig,
    pub chatter: ChatterConfig,
    pub snippets: SnippetsConfig,
    pub typography: TypographyConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GeneralConfig {
    pub log_level: String,
    pub pid_file: PathBuf,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct InputConfig {
    pub discovery: String,
    pub device_paths: Vec<String>,
    pub exclude_names: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CorrectorConfig {
    pub enabled: bool,
    pub min_word_length: usize,
    pub layouts: Vec<String>,
    pub dict_dir: String,
    pub exclude_classes: Vec<String>,
    pub exclude_titles: Vec<String>,
    pub double_shift_corrects: bool,
    pub double_shift_window_ms: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ChatterConfig {
    pub enabled: bool,
    pub debounce_ms: u64,
    pub modifier_debounce_ms: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SnippetsConfig {
    pub enabled: bool,
    pub trigger_prefix: String,
    pub word_separators: Vec<String>,
    pub entries: std::collections::HashMap<String, String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TypographyConfig {
    pub enabled: bool,
    pub smart_quotes: bool,
    pub em_dash: bool,
}

pub fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("/etc"))
        .join("typetune")
        .join("config.toml")
}

pub fn load(path: &PathBuf) -> Result<Config, Box<dyn std::error::Error>> {
    let content = std::fs::read_to_string(path)?;
    let config: Config = toml::from_str(&content)?;
    Ok(config)
}

pub fn ensure_config_exists() -> PathBuf {
    let path = config_path();
    if !path.exists() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, include_str!("../../../config/default.toml")).unwrap();
        tracing::info!("Created default config at {}", path.display());
    }
    path
}
