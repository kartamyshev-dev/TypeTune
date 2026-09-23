//! Explicit compatibility profile: suggestions from keymap-inferred history.
//! This is NOT a committed Snapshot, authorized range Plan, or confirmed edit.
use crate::{
    automatic::{automatic_decision, AutoAction, AutoPolicy},
    manual::convert_suffix,
    Direction, UserDictionary,
};
pub struct Suggestion {
    pub remove: usize,
    pub replacement: String,
    pub direction: Direction,
    /// True when policy says switch layout only (no text rewrite).
    pub layout_only: bool,
}
pub fn suggest(text: &str, automatic: bool) -> Option<Suggestion> {
    suggest_with_dictionary(text, automatic, &UserDictionary::default())
}
pub fn suggest_with_dictionary(
    text: &str,
    automatic: bool,
    dictionary: &UserDictionary,
) -> Option<Suggestion> {
    suggest_with_policy(text, automatic, dictionary, &AutoPolicy::default())
}

pub fn suggest_with_policy(
    text: &str,
    automatic: bool,
    dictionary: &UserDictionary,
    policy: &AutoPolicy,
) -> Option<Suggestion> {
    if text.is_empty() || text.chars().count() > 128 {
        return None;
    }
    if automatic && (!text.ends_with(' ') || text.ends_with("  ")) {
        return None;
    }
    if automatic {
        // Mirror prepare_automatic: whitespace-delimited token before caret.
        let word_end = text.trim_end_matches(' ');
        let start = word_end
            .rfind(char::is_whitespace)
            .map_or(0, |i| i + word_end[i..].chars().next().unwrap().len_utf8());
        let word = &word_end[start..];
        let (direction, corrected) = match automatic_decision(word, dictionary, policy) {
            AutoAction::Rewrite {
                direction, form, ..
            } => (direction, form),
            AutoAction::LayoutOnly(direction) => {
                return Some(Suggestion {
                    remove: 0,
                    replacement: String::new(),
                    direction,
                    layout_only: true,
                })
            }
            _ => return None,
        };
        let tail = &text[word_end.len()..];
        return Some(Suggestion {
            remove: word.chars().count() + tail.chars().count(),
            replacement: format!("{corrected}{tail}"),
            direction,
            layout_only: false,
        });
    }
    for direction in [Direction::UsToRu, Direction::RuToUs] {
        if let Ok((start, replacement)) = convert_suffix(text, direction) {
            return Some(Suggestion {
                remove: text[start..].chars().count(),
                replacement,
                direction,
                layout_only: false,
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
    #[test]
    fn inferred_shares_punctuation_and_yo_e_rules_with_editor() {
        // D3 boundary punctuation parity with prepare_automatic.
        assert_eq!(suggest("ghbdtn, ", true).unwrap().replacement, "привет, ");
        assert_eq!(suggest("(ghbdtn) ", true).unwrap().replacement, "(привет) ");
        assert_eq!(suggest("'nj ", true).unwrap().replacement, "это ");
        assert_eq!(suggest(",s ", true).unwrap().replacement, "бы ");
        // Full-token URL/code guards.
        for word in ["ghbdtn.com ", "example.com ", ":ghbdtn ", "ghbdtn_ "] {
            assert!(suggest(word, true).is_none(), "{word}");
        }
        // Aggressive yo/e pick (not refuse).
        assert_eq!(suggest("dct ", true).unwrap().replacement, "все ");
    }
}
