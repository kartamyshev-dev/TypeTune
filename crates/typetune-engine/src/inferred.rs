//! Explicit compatibility profile: suggestions from keymap-inferred history.
//! This is NOT a committed Snapshot, authorized range Plan, or confirmed edit.
use crate::{automatic::known_correction, manual::convert_suffix, Direction, UserDictionary};
pub struct Suggestion {
    pub remove: usize,
    pub replacement: String,
    pub direction: Direction,
}
pub fn suggest(text: &str, automatic: bool) -> Option<Suggestion> {
    suggest_with_dictionary(text, automatic, &UserDictionary::default())
}
pub fn suggest_with_dictionary(
    text: &str,
    automatic: bool,
    dictionary: &UserDictionary,
) -> Option<Suggestion> {
    if text.is_empty() || text.chars().count() > 128 {
        return None;
    }
    if automatic && (!text.ends_with(' ') || text.ends_with("  ")) {
        return None;
    }
    for direction in [Direction::UsToRu, Direction::RuToUs] {
        if let Ok((start, replacement)) = convert_suffix(text, direction) {
            let original = &text[start..];
            if automatic
                && !known_correction(
                    original.trim_end_matches(' '),
                    replacement.trim_end_matches(' '),
                    direction,
                    dictionary,
                )
            {
                return None;
            }
            return Some(Suggestion {
                remove: original.chars().count(),
                replacement,
                direction,
            });
        }
    }
    None
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn inferred_is_separate_from_committed_plan_and_uses_same_rules() {
        let s = suggest("ghbdtn ", true).unwrap();
        assert_eq!(s.remove, 7);
        assert_eq!(s.replacement, "привет ");
        assert_eq!(suggest("руддщ", false).unwrap().replacement, "hello");
        for word in ["hello ", "https://ghbdtn ", "ghbdtn  ", "ghbdtn", ""] {
            assert!(suggest(word, true).is_none());
        }
        assert!(suggest(&"a".repeat(129), false).is_none());
    }
}
