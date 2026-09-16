//! Conservative offline frequency lexicons. No runtime dictionary I/O.
use super::*;
const PILOT_RU: &str = include_str!("../data/ru.txt");
const PILOT_EN: &str = include_str!("../data/en.txt");

include!(concat!(env!("OUT_DIR"), "/lexicons.rs"));
// First rollout: candidate must occur in upstream top 20k. The whole 50k list
// protects already valid input. Rank is evidence of frequency, not probability.
fn rank(words: &[(&str, usize)], word: &str) -> Option<usize> {
    words
        .binary_search_by_key(&word, |entry| entry.0)
        .ok()
        .map(|i| words[i].1)
}

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
/// Unknown, ambiguous, very short and code-like tokens remain unchanged.
pub fn prepare_automatic(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
) -> Result<Option<(Plan, Direction)>, Rejection> {
    prepare_automatic_with_dictionary(snapshot, now, ttl, &UserDictionary::default())
}

pub fn prepare_automatic_with_dictionary(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
    dictionary: &UserDictionary,
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
    if !known_correction(
        word,
        plan.replacement.trim_end_matches(' '),
        direction,
        dictionary,
    ) {
        return Ok(None);
    }
    Ok(Some((plan, direction)))
}

pub(crate) fn known_correction(
    word: &str,
    candidate: &str,
    direction: Direction,
    dictionary: &UserDictionary,
) -> bool {
    let length = word.chars().count();
    if !(2..=32).contains(&length) {
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
    if dictionary.excluded(&word, &candidate) || dictionary.contains(&word) {
        return false;
    }
    if rank(EN, &word).is_some()
        || rank(RU, &word).is_some()
        || PILOT_EN.lines().chain(PILOT_RU.lines()).any(|s| s == word)
    {
        return false;
    }
    if dictionary.contains(&candidate) {
        return true;
    }
    let target = match direction {
        Direction::UsToRu => (RU, PILOT_RU),
        Direction::RuToUs => (EN, PILOT_EN),
    };
    // Short words have more accidental keyboard-layout matches. Admit
    // only very frequent targets; valid source words still win above.
    if length == 2 {
        return rank(target.0, &candidate).is_some_and(|r| r <= 100);
    }
    if length == 3 {
        return rank(target.0, &candidate).is_some_and(|r| r <= 1_000);
    }
    if !rank(target.0, &candidate).is_some_and(|r| r <= 20_000)
        && !target.1.lines().any(|s| s == candidate)
    {
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
        for (words, ru) in [(PILOT_RU, true), (PILOT_EN, false)] {
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
