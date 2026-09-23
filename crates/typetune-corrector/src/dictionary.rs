use std::collections::HashSet;
use std::path::Path;

pub struct Dictionary {
    words: HashSet<String>,
}

impl Dictionary {
    /// Legacy file loader for the disabled `LayoutCorrector` pipeline stage
    /// and its tests. Production auto-correction embeds frequency tables via
    /// `typetune-engine` (`lexicon_entry_counts` / `known_correction`) and
    /// never reads `dict/` at runtime (plan 57 D2/F08).
    pub fn load(path: &Path) -> Self {
        let content = std::fs::read_to_string(path).unwrap_or_default();
        let words: HashSet<String> = content.lines().map(|s| s.to_lowercase()).collect();
        tracing::info!(
            "Loaded dictionary {}: {} words",
            path.display(),
            words.len()
        );
        Self { words }
    }

    pub fn contains(&self, word: &str) -> bool {
        self.words.contains(&word.to_lowercase())
    }

    pub fn is_valid_word(&self, word: &str) -> bool {
        word.len() >= 2 && self.contains(word)
    }
}
