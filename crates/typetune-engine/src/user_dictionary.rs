use std::collections::BTreeSet;

/// Bounded immutable user vocabulary. Exclusions protect both source and target.
#[derive(Default)]
pub struct UserDictionary {
    words: BTreeSet<String>,
    exclusions: BTreeSet<String>,
}
impl UserDictionary {
    pub fn new(words: Vec<String>, exclusions: Vec<String>) -> Result<Self, &'static str> {
        fn validate(values: Vec<String>) -> Result<BTreeSet<String>, &'static str> {
            if values.len() > 500 {
                return Err("Too many entries");
            }
            values
                .into_iter()
                .map(|word| {
                    let word = word.to_lowercase();
                    let latin = word.chars().all(|c| c.is_ascii_lowercase());
                    let russian = word.chars().all(|c| ('а'..='я').contains(&c) || c == 'ё');
                    if !(2..=32).contains(&word.chars().count()) || !(latin || russian) {
                        return Err("Expected a 2-32 letter RU or EN word");
                    }
                    Ok(word)
                })
                .collect()
        }
        Ok(Self {
            words: validate(words)?,
            exclusions: validate(exclusions)?,
        })
    }
    pub(crate) fn contains(&self, word: &str) -> bool {
        self.words.contains(word)
    }
    pub(crate) fn excluded(&self, source: &str, target: &str) -> bool {
        self.exclusions.contains(source) || self.exclusions.contains(target)
    }
}
