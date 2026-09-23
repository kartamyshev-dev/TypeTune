//! Conservative offline frequency lexicons. No runtime dictionary I/O.
use super::*;
use manual::map_token;
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

/// Embedded lexicon sizes for diagnostics (counts only; no word content).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LexiconCounts {
    /// Merged frequency tables used for source protection (any rank).
    pub ru_merged: usize,
    pub en_merged: usize,
    /// Pilot fixtures always available as targets.
    pub ru_pilot: usize,
    pub en_pilot: usize,
}

pub fn lexicon_entry_counts() -> LexiconCounts {
    LexiconCounts {
        ru_merged: RU.len(),
        en_merged: EN.len(),
        ru_pilot: PILOT_RU.lines().filter(|line| !line.is_empty()).count(),
        en_pilot: PILOT_EN.lines().filter(|line| !line.is_empty()).count(),
    }
}

/// Pick direction from the actual committed token, never from a stale layout.
/// Tries UsToRu first; `Unsupported` (foreign script for that table) **and**
/// `InvalidRange` fall through to RuToUs. Any other rejection propagates.
pub fn prepare_toggle(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
) -> Result<(Plan, Direction), Rejection> {
    match prepare_manual(snapshot.clone(), Direction::UsToRu, now, ttl) {
        Ok(plan) => Ok((plan, Direction::UsToRu)),
        Err(Rejection::Unsupported | Rejection::InvalidRange) => {
            prepare_manual(snapshot, Direction::RuToUs, now, ttl)
                .map(|plan| (plan, Direction::RuToUs))
        }
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

pub fn prepare_automatic_with_policy(
    snapshot: Snapshot,
    now: Instant,
    ttl: Duration,
    dictionary: &UserDictionary,
    policy: &AutoPolicy,
) -> Result<Option<(Plan, Direction)>, Rejection> {
    let _ = policy; // layout-only is host-side; plan path always rewrites
    prepare_automatic_with_dictionary(snapshot, now, ttl, dictionary)
}

/// Leading/trailing sentence punctuation (D3). Comma/period/semicolon/
/// colon/apostrophe are also productive US letter keys (docs/42, docs/16:62),
/// so the full token is tried first; the stripped core is only a fallback.
const EDGE_PUNCT: &[char] = &[
    '.', ',', ';', ':', '!', '?', '(', ')', '"', '\'', '«', '»', '…', '–', '—',
];

fn is_edge_punct(c: char) -> bool {
    EDGE_PUNCT.contains(&c)
}

fn split_edge_punct(word: &str) -> (&str, &str, &str) {
    let lead_bytes: usize = word
        .chars()
        .take_while(|&c| is_edge_punct(c))
        .map(char::len_utf8)
        .sum();
    let rest = &word[lead_bytes..];
    let trail_bytes: usize = rest
        .chars()
        .rev()
        .take_while(|&c| is_edge_punct(c))
        .map(char::len_utf8)
        .sum();
    let core_end = rest.len() - trail_bytes;
    let (core, trail) = rest.split_at(core_end);
    (&word[..lead_bytes], core, trail)
}

/// Full-token URL/email/path/code heuristics (docs/16:57). Runs before any
/// edge-punctuation split so guards see exactly what the user committed.
/// Mid-token `.`/`,` are productive US letter keys (`ю`/`б`), so they are not
/// domain markers (`k.lb` → `люди`); unmappable `@ / \\ _ -` and digits already
/// fail `map_token`. A leading `:` would strip into `:привет` from the
/// `:ghbdtn` negative fixture and is therefore prohibited up front.
fn prohibited_token(word: &str) -> bool {
    word.contains("://")
        || word.contains('@')
        || word.contains('/')
        || word.contains('\\')
        || word.contains("::")
        || word.contains('_')
        || word.contains('-')
        || word.chars().any(|c| c.is_ascii_digit())
        || word.starts_with(':')
}

fn swap_yo_e(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            'е' => 'ё',
            'ё' => 'е',
            'Е' => 'Ё',
            'Ё' => 'Е',
            _ => c,
        })
        .collect()
}

/// Frequency score `ln(N / rank)` (ADR-010). `N = 50_000` FrequencyWords size.
const FREQ_N: f64 = 50_000.0;
/// Unknown form scores 0 so a known high-rank target beats it (ratio language ID).
const SCORE_UNKNOWN: f64 = 0.0;
/// Learned/user words act as very frequent targets.
const SCORE_USER: f64 = 12.0;
/// Pilot/tech curated forms are strong targets without inventing ranks.
const SCORE_PILOT: f64 = 8.0;

/// Aggressive auto-correction policy. Defaults fire often on word boundaries;
/// guards stay for URL/code/secure/mixed-case tokens.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AutoPolicy {
    pub switch_only_last_word: bool,
    pub dont_switch_words: bool,
    pub dont_correct_after_layout_change: bool,
}

impl Default for AutoPolicy {
    fn default() -> Self {
        Self {
            switch_only_last_word: true,
            dont_switch_words: false,
            dont_correct_after_layout_change: true,
        }
    }
}

/// Decision for one token. `Rewrite` replaces text (and switches layout);
/// `LayoutOnly` switches input source without touching text.
#[derive(Clone, Debug, PartialEq)]
pub enum AutoAction {
    None,
    LayoutOnly(Direction),
    Rewrite {
        direction: Direction,
        form: String,
        delta: f64,
    },
}

fn score_from_rank(rank: usize) -> f64 {
    (FREQ_N / rank as f64).ln()
}

/// Best frequency score of `form` in a language lexicon (rank or pilot).
fn form_score(target: (&[(&str, usize)], &str), form: &str) -> f64 {
    let mut best = SCORE_UNKNOWN;
    if let Some(r) = rank(target.0, form) {
        best = best.max(score_from_rank(r));
    }
    if target.1.lines().any(|s| s == form) {
        best = best.max(SCORE_PILOT);
    }
    best
}

/// Score of the source spelling in its *typed* language (raw ASCII → EN table,
/// Cyrillic → RU table). Wrong-layout garbage is typically unknown here.
fn source_score(raw: &str, direction: Direction) -> f64 {
    let table = match direction {
        Direction::UsToRu => EN,
        Direction::RuToUs => RU,
    };
    form_score((table, ""), raw)
}

fn target_lexicon(direction: Direction) -> (&'static [(&'static str, usize)], &'static str) {
    match direction {
        Direction::UsToRu => (RU, PILOT_RU),
        Direction::RuToUs => (EN, PILOT_EN),
    }
}

/// Enumerate е/ё orthographic variants of `form` (2^n, n ≤ 10) and return the
/// highest-scoring spelling (prefer the more frequent form, not a refuse).
fn best_yo_form(target: (&[(&str, usize)], &str), form: &str) -> (String, f64) {
    let chars: Vec<char> = form.chars().collect();
    let positions: Vec<usize> = chars
        .iter()
        .enumerate()
        .filter(|(_, &c)| c == 'е' || c == 'ё')
        .map(|(i, _)| i)
        .collect();
    if positions.is_empty() || positions.len() > 10 {
        let score = form_score(target, form);
        return (form.to_string(), score);
    }
    let mut best_form = form.to_string();
    let mut best = SCORE_UNKNOWN;
    for mask in 0u32..(1 << positions.len()) {
        let mut variant = chars.clone();
        for (bit, &idx) in positions.iter().enumerate() {
            variant[idx] = if mask & (1 << bit) == 0 { 'е' } else { 'ё' };
        }
        let candidate: String = variant.into_iter().collect();
        let score = form_score(target, &candidate);
        if score > best || (score == best && candidate == form) {
            best = score;
            best_form = candidate;
        }
    }
    (best_form, best)
}

/// Ratio margin by token length (aggressive, calibrated on dev; holdout records
/// false-rate). When the source is already a known word in its typed language,
/// a much larger gap is required (both-valid pairs stay put).
fn margin_for(length: usize, source_known: bool) -> f64 {
    let base = match length {
        2 => 3.5,
        3 => 2.0,
        _ => 1.0,
    };
    if source_known {
        base + 6.0
    } else {
        base
    }
}

fn floor_for(length: usize) -> f64 {
    match length {
        2 => 4.0,
        3 => 2.5,
        _ => 0.5,
    }
}

fn case_ok(word: &str) -> bool {
    let chars: Vec<_> = word.chars().filter(|c| c.is_alphabetic()).collect();
    chars.iter().all(|c| c.is_lowercase())
        || chars.iter().all(|c| c.is_uppercase())
        || (chars.first().is_some_and(|c| c.is_uppercase())
            && chars[1..].iter().all(|c| c.is_lowercase()))
}

fn preserve_case(template: &str, form: &str) -> String {
    let upper = template
        .chars()
        .filter(|c| c.is_alphabetic())
        .all(|c| c.is_uppercase())
        && template.chars().any(|c| c.is_alphabetic());
    let title = template
        .chars()
        .find(|c| c.is_alphabetic())
        .is_some_and(|c| c.is_uppercase());
    if upper {
        form.to_uppercase()
    } else if title {
        form.chars()
            .next()
            .map(|c| c.to_uppercase().collect::<String>() + &form[c.len_utf8()..])
            .unwrap_or_else(|| form.to_string())
    } else {
        form.to_string()
    }
}

/// Lang ID for one already-lowercased core token: score raw vs remapped form
/// and fire when the remapped language wins by `margin` (or the source is
/// unknown and the target is frequent enough).
fn lang_id_core(core: &str, dictionary: &UserDictionary) -> Option<(Direction, String, f64)> {
    let length = core.chars().count();
    if !(2..=32).contains(&length) {
        return None;
    }
    // User-typed spelling is intentional (learned/proper names).
    let core_alt = swap_yo_e(core);
    if dictionary.contains(core) || dictionary.contains(&core_alt) {
        return None;
    }
    let mut best: Option<(Direction, String, f64)> = None;
    for direction in [Direction::UsToRu, Direction::RuToUs] {
        let Ok(converted) = map_token(core, direction) else {
            continue;
        };
        let converted = converted.to_lowercase();
        if dictionary.excluded(core, &converted) || dictionary.excluded(&core_alt, &converted) {
            continue;
        }
        // User/learned target always wins that direction.
        if dictionary.contains(&converted) {
            let delta = SCORE_USER;
            if best.as_ref().is_none_or(|(_, _, d)| delta > *d) {
                best = Some((direction, converted, delta));
            }
            continue;
        }
        let target = target_lexicon(direction);
        let (form, score_t) = best_yo_form(target, &converted);
        let score_s = source_score(core, direction).max(source_score(&core_alt, direction));
        let source_known = score_s > SCORE_UNKNOWN;
        // Short tokens that are already words in the typed language stay put.
        if source_known && length <= 3 {
            continue;
        }
        let delta = score_t - score_s;
        let accept = score_t > SCORE_UNKNOWN
            && (delta >= margin_for(length, source_known)
                || (!source_known && score_t >= floor_for(length)));
        if accept && best.as_ref().is_none_or(|(_, _, d)| delta > *d) {
            best = Some((direction, form, delta));
        }
    }
    best
}

/// Shared automatic-correction decision for one whitespace-delimited token.
/// Full token first (productive letter keys win); edge-punct core only as
/// fallback when the full conversion is unknown or rejected by `lang_id_core`.
pub(crate) fn automatic_decision(
    word: &str,
    dictionary: &UserDictionary,
    policy: &AutoPolicy,
) -> AutoAction {
    if word.is_empty() || prohibited_token(word) || !case_ok(word) {
        return AutoAction::None;
    }
    let lower = word.to_lowercase();
    let hit = lang_id_core(&lower, dictionary).map(|(d, f, delta)| {
        // Preserve mapping case (`<s` → `Бы`) when the lower form is unchanged.
        (d, f, delta, lower.as_str())
    });
    let hit = match hit {
        Some((d, f, delta, _)) => Some((d, f, delta)),
        None => {
            let (lead, core, trail) = split_edge_punct(&lower);
            if core.is_empty() || core.len() == lower.len() {
                None
            } else {
                lang_id_core(core, dictionary).map(|(direction, form, delta)| {
                    (direction, format!("{lead}{form}{trail}"), delta)
                })
            }
        }
    };
    let Some((direction, form_l, delta)) = hit else {
        if policy.dont_switch_words {
            return layout_only_action(&lower, dictionary);
        }
        return AutoAction::None;
    };
    if policy.dont_switch_words {
        return AutoAction::LayoutOnly(direction);
    }
    // Re-map the original-cased token so shifted keys keep case (`<s` → `Бы`).
    let cased = map_token(word, direction).ok();
    let form = match cased {
        Some(c) if c.to_lowercase() == form_l => c,
        _ => preserve_case(word, &form_l),
    };
    AutoAction::Rewrite {
        direction,
        form,
        delta,
    }
}

fn layout_only_action(lower: &str, dictionary: &UserDictionary) -> AutoAction {
    let hit = lang_id_core(lower, dictionary).or_else(|| {
        let (_, core, _) = split_edge_punct(lower);
        lang_id_core(core, dictionary)
    });
    match hit {
        Some((direction, _, _)) => AutoAction::LayoutOnly(direction),
        None => AutoAction::None,
    }
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
    let prefix = &snapshot.text[..byte];
    let word_end = prefix.trim_end_matches(' ');
    let start_byte = word_end
        .rfind(char::is_whitespace)
        .map_or(0, |i| i + word_end[i..].chars().next().unwrap().len_utf8());
    let word = &word_end[start_byte..];
    if word.is_empty() {
        return Ok(None);
    }
    let Some((direction, corrected)) =
        (match automatic_decision(word, dictionary, &AutoPolicy::default()) {
            AutoAction::Rewrite {
                direction, form, ..
            } => Some((direction, form)),
            AutoAction::LayoutOnly(direction) => Some((direction, String::new())),
            AutoAction::None => None,
        })
    else {
        return Ok(None);
    };
    if corrected.is_empty() {
        return Ok(None);
    }
    // Delimiter spaces (and any non-space tail before caret) stay in place.
    let tail = &prefix[word_end.len()..];
    let replacement = format!("{corrected}{tail}");
    if replacement.len() > MAX_REPLACEMENT_BYTES {
        return Err(Rejection::Limit);
    }
    let range = word_end[..start_byte].chars().count()..snapshot.caret;
    let after_text = replace_chars(&snapshot.text, range.clone(), &replacement)?;
    let after_caret = range.start + replacement.chars().count();
    Ok(Some((
        Plan {
            before: snapshot,
            range,
            replacement,
            after_text,
            after_caret,
            created: now,
            ttl,
        },
        direction,
    )))
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
    fn automatic(text: &str) -> Option<(Plan, Direction)> {
        prepare_automatic(state(text), Instant::now(), Duration::from_secs(1)).unwrap()
    }
    #[test]
    fn positive_case_and_direction_preserve_space_and_prefix() {
        for (before, after) in [
            ("ghbdtn ", "привет "),
            ("Prefix Ghbdtn ", "Привет "),
            ("GHBDTN ", "ПРИВЕТ "),
            ("руддщ ", "hello "),
        ] {
            let (plan, _) = automatic(before).unwrap();
            assert_eq!(plan.replacement(), after, "{before}");
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
            "ghbdtn.com ",
            "example.com ",
            "foo::bar_baz ",
            "snake_case_name ",
            "https://example.com/path ",
            "hyphen-word ",
            "enum-variant ",
            ", ",
            ",. ",
            // Typographic quotes around an already-valid Russian word.
            "«привет» ",
        ] {
            assert!(automatic(word).is_none(), "{word}");
        }
    }
    #[test]
    fn boundary_punctuation_is_restored_exactly_once() {
        for (before, after) in [
            ("ghbdtn, ", "привет, "),
            ("ghbdtn. ", "привет. "),
            ("ghbdtn! ", "привет! "),
            ("ghbdtn? ", "привет? "),
            ("ghbdtn; ", "привет; "),
            ("ghbdtn: ", "привет: "),
            ("ghbdtn... ", "привет... "),
            ("(ghbdtn) ", "(привет) "),
            ("\"ghbdtn\" ", "\"привет\" "),
            ("Ghbdtn, ", "Привет, "),
            ("GHBDTN. ", "ПРИВЕТ. "),
            // Full token wins over strip: `'` is the US `э` key (docs/16:62).
            ("'nj ", "это "),
            // docs/42: comma is the `б` key; full token is `бы`.
            (",s ", "бы "),
            ("<s ", "Бы "),
            ("yt, ", "не, "),
            // Mid-token `.` is the US `ю` key, not a domain separator.
            ("k.lb ", "люди "),
        ] {
            let (plan, _) = automatic(before).unwrap();
            assert_eq!(plan.replacement(), after, "{before}");
        }
    }
    #[test]
    fn yo_e_lookup_picks_higher_score_form() {
        // Aggressive: ambiguous ё/е pairs pick the higher-score spelling
        // instead of refusing. Conversion form wins ties.
        for (before, after) in [
            ("dct ", "все "),
            ("bltn ", "идет "),
            ("lytv ", "днем "),
            ("to` ", "еще "),
            ("ht,tyjr ", "ребенок "),
        ] {
            let (plan, _) = automatic(before).unwrap();
            assert_eq!(plan.replacement(), after, "{before}");
        }
        // `tot` is a known English word (short source protection).
        assert!(automatic("tot ").is_none());
        // Score unit probes still hold for rank gates used as floors.
        assert!((score_from_rank(100) - 6.214_608_098_422_191).abs() < 1e-12);
        // Single-spelling ё target still corrects (`словарём`, no `словарем`).
        assert_eq!(swap_yo_e("все"), "всё");
        assert_eq!(swap_yo_e("ВСЁ"), "ВСЕ");
        assert_eq!(swap_yo_e("привет"), "привёт");
        assert_eq!(swap_yo_e("hello"), "hello");
        let (plan, _) = automatic("ckjdfh`v ").unwrap();
        assert_eq!(plan.replacement(), "словарём ");
    }
    #[test]
    fn toggle_falls_through_to_reverse_direction_without_swallowing_context() {
        let now = Instant::now();
        let ttl = Duration::from_secs(1);
        // RU token: UsToRu map fails with Unsupported → RuToUs succeeds.
        let (plan, dir) = prepare_toggle(state("руддщ "), now, ttl).unwrap();
        assert!(matches!(dir, Direction::RuToUs));
        assert_eq!(plan.replacement(), "hello ");
        // US token: UsToRu succeeds on the first try.
        let (plan, dir) = prepare_toggle(state("ghbdtn "), now, ttl).unwrap();
        assert!(matches!(dir, Direction::UsToRu));
        assert_eq!(plan.replacement(), "привет ");
        // Context rejections are not direction-retried.
        let mut s = state("руддщ ");
        s.focused = None;
        assert!(matches!(
            prepare_toggle(s, now, ttl),
            Err(Rejection::Context)
        ));
        // Selection rejections are not direction-retried.
        let mut s = state("руддщ ");
        s.anchor = 0;
        assert!(matches!(
            prepare_toggle(s, now, ttl),
            Err(Rejection::Selection)
        ));
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
    /// Inventory of EN plural generation (review P0): garbage forms must not
    /// exist in the merged `EN` table; required regular forms must be present.
    /// Uses the same `rank()` binary search as production scoring.
    #[test]
    fn en_plural_inventory_matches_regular_rules() {
        for word in ["boxs", "catss", "horsees", "flys", "busss"] {
            assert!(rank(EN, word).is_none(), "{word} must be absent from EN");
        }
        // `cat` must not emit the old `+es` twin; `cats` is the only form.
        assert!(rank(EN, "cats").is_some());
        // `cates` may remain via legitimate lemma `cate` (and upstream row) —
        // only the former `cat`+`es` twin is forbidden, covered by `catss`
        // absence plus single-form rules above.
        for word in ["boxes", "buses", "stories", "horses"] {
            assert!(rank(EN, word).is_some(), "{word} must be present in EN");
        }
    }

    #[test]
    fn lexicon_entry_counts_match_embedded_tables() {
        let counts = lexicon_entry_counts();
        assert_eq!(counts.ru_merged, RU.len());
        assert_eq!(counts.en_merged, EN.len());
        assert_eq!(counts.ru_pilot, 150);
        assert_eq!(counts.en_pilot, 149);
        assert!(counts.ru_merged > counts.ru_pilot);
        assert!(counts.en_merged > counts.en_pilot);
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
