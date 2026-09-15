//! Conservative, offline pilot lexicon. No baseline dictionaries or I/O.
use super::*;
const RU: &str = include_str!("../data/ru.txt");
const EN: &str = include_str!("../data/en.txt");

/// Pick direction from the actual committed token, never from a stale layout.
pub fn prepare_toggle(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
) -> Result<(Plan, Direction), Rejection> {
    match prepare_manual(snapshot.clone(), Direction::UsToRu, now, ttl) {
        Ok(plan) => Ok((plan, Direction::UsToRu)),
        Err(Rejection::Unsupported) => prepare_manual(snapshot, Direction::RuToUs, now, ttl)
            .map(|plan| (plan, Direction::RuToUs)),
        Err(reason) => Err(reason),
    }
}

/// Only an already committed single Space can trigger automatic correction.
/// Unknown, ambiguous, short and code-like tokens remain unchanged.
pub fn prepare_automatic(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
) -> Result<Option<(Plan, Direction)>, Rejection> {
    snapshot.check()?;
    let byte = byte_offset(&snapshot.text, snapshot.caret).ok_or(Rejection::InvalidRange)?;
    if !snapshot.text[..byte].ends_with(' ') || snapshot.text[..byte].ends_with("  ") {
        return Ok(None);
    }
    let (plan, direction) = match prepare_toggle(snapshot, now, ttl) {
        Ok(value) => value,
        Err(Rejection::Unsupported | Rejection::InvalidRange) => return Ok(None),
        Err(reason) => return Err(reason),
    };
    let start = byte_offset(&plan.before.text, plan.range.start).ok_or(Rejection::InvalidRange)?;
    let word = plan.before.text[start..byte].trim_end_matches(' ');
    if !known_correction(word, plan.replacement.trim_end_matches(' '), direction) {
        return Ok(None);
    }
    Ok(Some((plan, direction)))
}

pub(crate) fn known_correction(word: &str, candidate: &str, direction: Direction) -> bool {
    if !(4..=32).contains(&word.chars().count()) {
        return false;
    }
    // Lower/title/upper case only; mixed case is often an identifier.
    let chars: Vec<_> = word.chars().filter(|c| c.is_alphabetic()).collect();
    if !(chars.iter().all(|c| c.is_lowercase())
        || chars.iter().all(|c| c.is_uppercase())
        || chars.first().is_some_and(|c| c.is_uppercase())
            && chars[1..].iter().all(|c| c.is_lowercase()))
    {
        return false;
    }
    let word = word.to_lowercase();
    let candidate = candidate.to_lowercase();
    if EN.lines().chain(RU.lines()).any(|s| s == word) {
        return false;
    }
    let target = match direction {
        Direction::UsToRu => RU,
        Direction::RuToUs => EN,
    };
    if !target.lines().any(|s| s == candidate) {
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state(text: &str) -> Snapshot {
        Snapshot {
            target: 1,
            epoch: 1,
            revision: 1,
            text: text.into(),
            caret: text.chars().count(),
            anchor: text.chars().count(),
            focused: Some(true),
            normal_field: Some(true),
            composing: Some(false),
            modifiers_clear: Some(true),
            unicode_range: Some(true),
        }
    }
    #[test]
    fn positive_case_and_direction_preserve_space_and_prefix() {
        for (before, after) in [
            ("ghbdtn ", "привет "),
            ("Prefix Ghbdtn ", "Привет "),
            ("GHBDTN ", "ПРИВЕТ "),
            ("руддщ ", "hello "),
        ] {
            let (plan, _) =
                prepare_automatic(state(before), Instant::now(), Duration::from_secs(1))
                    .unwrap()
                    .unwrap();
            assert_eq!(plan.replacement(), after);
        }
    }
    #[test]
    fn negative_corpus_stays_unchanged() {
        for word in [
            "hello ",
            "привет ",
            "yet ",
            "cat ",
            "hello@example.com ",
            "https://ghbdtn ",
            "/ghbdtn ",
            "ghbdtn42 ",
            "ghbdtn_ ",
            "GhBdTn ",
            "ghbdtn",
            "ghbdtn  ",
            "qwerty ",
            "привеt ",
            "e\u{301} ",
            "😀 ",
            ":ghbdtn ",
            "foo::ghbdtn ",
        ] {
            assert!(
                prepare_automatic(state(word), Instant::now(), Duration::from_secs(1))
                    .unwrap()
                    .is_none(),
                "{word}"
            );
        }
    }
    #[test]
    fn unknown_and_selection_fail_before_planning() {
        let mut s = state("ghbdtn ");
        s.composing = None;
        assert!(matches!(
            prepare_automatic(s, Instant::now(), Duration::from_secs(1)),
            Err(Rejection::Context)
        ));
        let mut s = state("ghbdtn ");
        s.anchor = 0;
        assert!(matches!(
            prepare_automatic(s, Instant::now(), Duration::from_secs(1)),
            Err(Rejection::Selection)
        ));
    }
    #[test]
    fn lexicons_are_unique_normalized_and_expected_script() {
        for (words, ru) in [(RU, true), (EN, false)] {
            let mut seen = std::collections::HashSet::new();
            for word in words.lines() {
                assert!(word.chars().count() >= 4 && word.chars().count() <= 32);
                assert!(word.chars().all(|c| if ru {
                    ('а'..='я').contains(&c) || c == 'ё'
                } else {
                    c.is_ascii_lowercase()
                }));
                assert!(seen.insert(word));
            }
        }
    }
}
