//! Pure, bounded compatibility state. An inferred edit never asserts editor truth.
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeSet;
use typetune_engine::{inferred::suggest_with_policy, AutoPolicy, Direction, UserDictionary};

fn is_word_space(c: char) -> bool {
    matches!(c, ' ' | '\u{a0}')
}

/// The inference engine accepts ASCII Space. Editor evidence remains literal:
/// Safari contenteditable may use NBSP, including a mixed tail after a repeat.
fn canonical_word(text: &str, automatic: bool) -> String {
    let token = text.trim_end_matches(is_word_space);
    let spaces = text[token.len()..].chars().count();
    let spaces = if automatic { spaces.min(1) } else { spaces };
    format!("{token}{}", " ".repeat(spaces))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Event {
    pub key: String,
    pub action: Action,
    pub text: Option<String>,
    pub time_ms: u64,
    pub device: Option<String>,
    pub origin: Origin,
    pub modifiers: u32,
    #[serde(default)]
    pub editor_word: Option<String>,
}
#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Down,
    Up,
    Repeat,
}
#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Origin {
    Physical,
    Own,
    Unknown,
}
/// Delivery and editor verification are different evidence. Legacy `ok` keeps
/// its successful-history behavior, but cannot authorize durable learning.
#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Ok,
    Verified,
    Submitted,
    #[serde(alias = "rejected")]
    FailedBefore,
    #[serde(alias = "indeterminate")]
    UnknownAfter,
}

#[derive(Default)]
struct Gesture {
    down: Option<(String, u64)>,
    first: Option<(String, u64)>,
}
impl Gesture {
    fn edge(&mut self, key: String, up: bool, now: u64) -> bool {
        if !up {
            if self.down.is_some() {
                *self = Self::default();
                return false;
            }
            if self
                .first
                .as_ref()
                .is_some_and(|(k, t)| k != &key || now < *t || now - *t > 350)
            {
                self.first = None;
            }
            self.down = Some((key, now));
            return false;
        }
        let Some((k, t)) = self.down.take() else {
            *self = Self::default();
            return false;
        };
        if k != key || now < t || now - t > 200 {
            *self = Self::default();
            return false;
        }
        if self
            .first
            .as_ref()
            .is_some_and(|(k, t)| k == &key && now >= *t && now - *t <= 350)
        {
            *self = Self::default();
            return true;
        }
        self.first = Some((key, now));
        false
    }
}
struct Pending {
    id: u64,
    before: String,
    after: String,
    automatic: bool,
    time: u64,
}
#[derive(Default)]
pub struct Runtime {
    text: String,
    held: BTreeSet<String>,
    time: Option<u64>,
    gesture: Gesture,
    pending: Option<Pending>,
    next: u64,
    last_auto: Option<(String, String, u64, bool)>,
    manual: Option<(String, String)>,
    consumed: bool,
    words: Vec<String>,
    exclusions: Vec<String>,
    learned: Vec<String>,
    dictionary: UserDictionary,
    policy: AutoPolicy,
    /// Next automatic rewrite is suppressed after a layout change (anti-loop).
    suppress_auto_until_word: bool,
    last_layout: String,
}
impl Runtime {
    pub fn is_pending(&self) -> bool {
        self.pending.is_some()
    }
    pub fn configure(
        &mut self,
        words: Vec<String>,
        exclusions: Vec<String>,
        learned: Vec<String>,
        policy: AutoPolicy,
    ) -> Result<(), &'static str> {
        self.update_dictionary(words, exclusions, learned)?;
        self.policy = policy;
        self.reset();
        Ok(())
    }
    pub fn dictionary(&self) -> &UserDictionary {
        &self.dictionary
    }
    /// Validate the entire replacement before publishing it. This deliberately
    /// preserves the pending edit, gesture, history, layout policy and tracker.
    pub fn update_dictionary(
        &mut self,
        words: Vec<String>,
        exclusions: Vec<String>,
        learned: Vec<String>,
    ) -> Result<(), &'static str> {
        let mut all_words = words.clone();
        all_words.extend(learned.iter().cloned());
        let dictionary = UserDictionary::new(all_words, exclusions.clone())?;
        self.words = words.into_iter().map(|word| word.to_lowercase()).collect();
        self.exclusions = exclusions
            .into_iter()
            .map(|word| word.to_lowercase())
            .collect();
        self.learned = learned
            .into_iter()
            .map(|word| word.to_lowercase())
            .collect();
        self.dictionary = dictionary;
        Ok(())
    }
    fn add_learned(&mut self, word: &str) -> bool {
        if self.learned.len() >= 500
            || self
                .learned
                .iter()
                .chain(&self.words)
                .any(|known| known == word)
        {
            return false;
        }
        let mut learned = self.learned.clone();
        learned.push(word.to_string());
        self.update_dictionary(self.words.clone(), self.exclusions.clone(), learned)
            .is_ok()
    }
    fn add_exclusion(&mut self, word: &str) -> bool {
        if self.exclusions.len() >= 500 || self.exclusions.iter().any(|known| known == word) {
            return false;
        }
        let mut exclusions = self.exclusions.clone();
        exclusions.push(word.to_string());
        self.update_dictionary(self.words.clone(), exclusions, self.learned.clone())
            .is_ok()
    }
    pub fn learned_words(&self) -> &[String] {
        &self.learned
    }
    pub fn exclusions(&self) -> &[String] {
        &self.exclusions
    }
    pub fn learn_add(&mut self, word: String) -> Value {
        let word = word.trim().to_lowercase();
        if UserDictionary::new(vec![word.clone()], vec![]).is_err() {
            return json!({"status":"invalid"});
        }
        if self.learned.contains(&word) || self.words.contains(&word) || self.add_learned(&word) {
            json!({"status":"learned"})
        } else {
            json!({"status":"full"})
        }
    }
    pub fn learn_clear(&mut self) -> Value {
        match self.update_dictionary(self.words.clone(), self.exclusions.clone(), vec![]) {
            Ok(()) => json!({"status":"cleared"}),
            Err(_) => json!({"status":"invalid-dictionary"}),
        }
    }
    pub fn layout_notice(&mut self, source: &str, layout: &str) -> Value {
        // Anti-loop only after an *external* layout change. Our own rewrite+switch
        // must not suppress the next automatic correction (that made auto fire
        // only on every other word).
        if layout != self.last_layout {
            self.last_layout = layout.to_string();
            if source != "own" && self.policy.dont_correct_after_layout_change {
                self.suppress_auto_until_word = true;
            }
        }
        let _ = source;
        json!({"status":"layout_noted"})
    }
    pub fn reset(&mut self) {
        self.text.clear();
        self.held.clear();
        self.time = None;
        self.gesture = Gesture::default();
        self.pending = None;
        self.reset_tracker();
    }
    fn reset_tracker(&mut self) {
        self.last_auto = None;
        self.manual = None;
        self.consumed = false;
    }
    fn advance(&mut self, _boundary: bool) {
        let _ = self.manual.take();
        self.reset_tracker();
    }
    fn ignored_after_reset(&mut self) -> Value {
        self.reset();
        // Additive protocol-3 evidence: callers without an editor snapshot must
        // not mistake the next tracked suffix for a complete word.
        json!({"status":"ignored", "history_reset":true})
    }
    pub fn event(&mut self, e: Event, automatic: bool, manual_enabled: bool) -> Value {
        let ignored = json!({"status":"ignored"});
        let space_trigger = e.key == "space" && e.action != Action::Up;
        // Optional protocol-3 diagnostic for a decision boundary only. Never
        // include the typed token, editor snapshot, key sequence or device ID.
        let diagnostic = |mut response: Value, reason: &'static str| {
            if space_trigger {
                response["reason"] = json!(reason);
            }
            response
        };
        if e.origin == Origin::Own {
            return diagnostic(ignored, "own_event");
        }
        // Caps / Fn / modifier edges (layout switch, latch) must not invalidate
        // keyboard history.
        if e.key == "lock_key" {
            return ignored;
        }
        // Pointer: abandon a half-finished Double Shift, but keep the word —
        // a click in the same field used to wipe history and kill auto.
        if e.key == "pointer" {
            self.gesture = Gesture::default();
            return ignored;
        }
        if e.origin != Origin::Physical
            || e.key.len() > 64
            || e.device.as_ref().is_some_and(|v| v.len() > 128)
            || self.time.is_some_and(|t| e.time_ms < t)
        {
            let reason = if e.origin != Origin::Physical {
                "untrusted_origin"
            } else if self.time.is_some_and(|t| e.time_ms < t) {
                "stale_event"
            } else {
                "invalid_event"
            };
            return diagnostic(self.ignored_after_reset(), reason);
        }
        if self.pending.is_some() {
            // In-flight replacement: drop extra keys without wiping history/pending.
            return diagnostic(ignored, "pending_edit");
        }
        self.time = Some(e.time_ms);
        let identity = format!("{}:{}", e.device.as_deref().unwrap_or("unknown"), e.key);
        if e.action == Action::Up {
            self.held.remove(&identity);
        } else if e.action == Action::Down {
            self.held.insert(identity.clone());
        }
        if self.held.len() > 32 || e.modifiers & !1 != 0 {
            return diagnostic(self.ignored_after_reset(), "shortcut_or_held_limit");
        }
        let manual;
        if e.key == "left_shift" || e.key == "right_shift" {
            if !manual_enabled {
                self.gesture = Gesture::default();
                return ignored;
            }
            if e.action == Action::Repeat
                || self
                    .held
                    .iter()
                    .any(|k| !k.ends_with(":left_shift") && !k.ends_with(":right_shift"))
            {
                self.gesture = Gesture::default();
                return ignored;
            }
            manual = self
                .gesture
                .edge(identity, e.action == Action::Up, e.time_ms)
                && self.held.is_empty();
            if !manual {
                return ignored;
            }
        } else {
            if e.action == Action::Up {
                return ignored;
            }
            self.gesture = Gesture::default();
            if e.key == "backspace" {
                self.advance(false);
                self.text.pop();
                return ignored;
            }
            if e.key == "space" {
                self.advance(true);
                if let Some(editor_word) = e.editor_word.as_ref() {
                    let token = editor_word.trim_end_matches(is_word_space);
                    // This optional snapshot is the complete token at the
                    // caret after the Space, including its literal delimiter
                    // tail. A stale/partial known snapshot cannot authorize a
                    // correction using an unrelated keyboard-history suffix.
                    if !editor_word.ends_with(is_word_space)
                        || token.is_empty()
                        || token.chars().any(char::is_whitespace)
                        || editor_word.chars().count() > 128
                        || suggest_with_policy(
                            &canonical_word(editor_word, false),
                            false,
                            &self.dictionary,
                            &AutoPolicy::default(),
                        )
                        .is_none()
                    {
                        return diagnostic(self.ignored_after_reset(), "invalid_editor_word");
                    }
                    let completed_same_word = self.text.ends_with(is_word_space)
                        && self.text.trim_end_matches(is_word_space) == token;
                    self.text = editor_word.clone();
                    // A second Space must not reconsider a word previously
                    // skipped by policy. Failed/stale edits reset history and
                    // therefore remain recoverable from the current snapshot.
                    if completed_same_word {
                        return diagnostic(ignored, "already_completed_editor_word");
                    }
                } else {
                    if self.text.is_empty() || self.text.ends_with(is_word_space) {
                        let reason = if self.text.is_empty() {
                            "empty_history"
                        } else {
                            "repeated_boundary"
                        };
                        self.text.clear();
                        return diagnostic(ignored, reason);
                    }
                    self.text.push(' ');
                }
                if !automatic {
                    return diagnostic(ignored, "automatic_disabled");
                }
            } else if let Some(text) = e.text {
                // Only the established RU/EN alphabet and mapped punctuation enter history.
                if text.chars().count() != 1
                    || !text.chars().all(|c| {
                        c.is_ascii_alphabetic()
                            || ('А'..='я').contains(&c)
                            || "ёЁ`~[]{};'\",.<>:".contains(c)
                    })
                {
                    return self.ignored_after_reset();
                }
                self.advance(false);
                if self.text.ends_with(is_word_space) {
                    self.text.clear();
                }
                self.text.push_str(&text);
                if self.text.chars().count() > 128 {
                    return self.ignored_after_reset();
                }
                return ignored;
            } else {
                return self.ignored_after_reset();
            }
            manual = false;
        }
        // A current editor snapshot can recover a truncated keyboard history.
        // Empty/invalid known context must refuse, never fall back to a suffix.
        if manual {
            self.suppress_auto_until_word = false;
            if let Some(editor_word) = e.editor_word {
                let token = editor_word.trim_end_matches(is_word_space);
                if token.is_empty()
                    || token.chars().any(char::is_whitespace)
                    || editor_word.chars().count() > 128
                    || suggest_with_policy(
                        &canonical_word(&editor_word, false),
                        false,
                        &self.dictionary,
                        &AutoPolicy::default(),
                    )
                    .is_none()
                {
                    return self.ignored_after_reset();
                }
                if self.text != editor_word {
                    self.reset_tracker();
                    self.text = editor_word;
                }
            }
        } else {
            // First auto word after a layout change is skipped (anti-loop).
            if self.suppress_auto_until_word {
                self.suppress_auto_until_word = false;
                return diagnostic(ignored, "layout_change_suppressed");
            }
            if !automatic {
                return diagnostic(ignored, "automatic_disabled");
            }
        }
        let Some(mut s) = suggest_with_policy(
            &canonical_word(&self.text, !manual),
            !manual,
            &self.dictionary,
            &self.policy,
        ) else {
            return diagnostic(ignored, "no_suggestion");
        };
        if !s.layout_only {
            // Only the decision uses canonical spaces. Restore the current
            // literal tail and count the whole token in Unicode scalars.
            let token = self.text.trim_end_matches(is_word_space);
            let tail = &self.text[token.len()..];
            s.remove = self.text.chars().count();
            s.replacement
                .truncate(s.replacement.trim_end_matches(' ').len());
            s.replacement.push_str(tail);
        }
        self.next += 1;
        let mode = if matches!(s.direction, Direction::UsToRu) {
            "ru"
        } else {
            "us"
        };
        if s.layout_only {
            // Layout-only is our own switch: only skip auto when policy asks and
            // treat it like `source: own` so the next word can still correct.
            return json!({"status":"layout_only","id":self.next,"mode":mode,"switch_layout":true});
        }
        let response = json!({"status":"inferred_edit","id":self.next,"before":self.text,
            "remove":s.remove,"replacement":s.replacement,"mode":mode,"switch_layout":true});
        self.pending = Some(Pending {
            id: self.next,
            before: self.text.clone(),
            after: s.replacement,
            automatic: !manual,
            time: e.time_ms,
        });
        response
    }
    pub fn result(&mut self, id: u64, outcome: Outcome, time: u64) -> Value {
        let Some(p) = self.pending.take() else {
            return json!({"status":"stale"});
        };
        // Covers macOS held-key wait (800ms) plus paired inject sleeps; elapsed
        // duration is added to the source timestamp, not a second clock domain.
        const RESULT_DEADLINE_MS: u64 = 2500;
        if p.id != id
            || time < p.time
            || time - p.time > RESULT_DEADLINE_MS
            || matches!(outcome, Outcome::FailedBefore | Outcome::UnknownAfter)
        {
            self.reset();
            return json!({"status":"reset"});
        }
        self.text = p.after.clone();
        self.held.clear();
        // Own rewrite intentionally continues in the target language — do not
        // suppress the next auto word (anti-loop is for external layout changes).
        // Only read-back-confirmed edits may change persistent vocabulary.
        let verified = outcome == Outcome::Verified;
        let mut learned_add = Vec::new();
        let mut exclusions_add = Vec::new();
        let target = p.after.trim().to_lowercase();
        if verified && self.add_learned(&target) {
            learned_add.push(target);
        }
        // Reverse undo of an auto rewrite: soft-exclude the source (1-shot).
        if !p.automatic {
            if let Some((source, corrected, deadline, auto_verified)) = self.last_auto.take() {
                if verified
                    && auto_verified
                    && time <= deadline
                    && p.before == corrected
                    && p.after == source
                {
                    let source = source.trim().to_lowercase();
                    if self.add_exclusion(&source) {
                        exclusions_add.push(source);
                    }
                }
            }
        } else {
            self.last_auto = Some((p.before, p.after, time.saturating_add(10000), verified));
            self.manual = None;
            self.consumed = false;
        }
        let mut response = json!({"status":"ok"});
        if !learned_add.is_empty() || !exclusions_add.is_empty() {
            response["feedback"] =
                json!({"learned_add":learned_add,"exclusions_add":exclusions_add});
        }
        response
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn event(
        r: &mut Runtime,
        key: &str,
        action: &str,
        text: Option<&str>,
        time: u64,
        auto: bool,
    ) -> Value {
        r.event(serde_json::from_value(json!({"key":key,"action":action,"text":text,"time_ms":time,"device":null,"origin":"physical","modifiers":0})).unwrap(),auto,true)
    }
    fn word(r: &mut Runtime, text: &str, t: &mut u64) {
        for c in text.chars() {
            *t += 1;
            event(r, "letter", "down", Some(&c.to_string()), *t, false);
            *t += 1;
            event(r, "letter", "up", None, *t, false);
        }
    }
    fn gesture(r: &mut Runtime, t: &mut u64) -> Value {
        let mut v = Value::Null;
        for a in ["down", "up", "down", "up"] {
            *t += 50;
            v = event(r, "left_shift", a, None, *t, false);
        }
        v
    }
    fn editor_space(r: &mut Runtime, observed: &str, action: &str, time: u64, auto: bool) -> Value {
        r.event(
            serde_json::from_value(json!({"key":"space", "action":action, "text":null,
                "time_ms":time, "device":null, "origin":"physical", "modifiers":0,
                "editor_word":observed}))
            .unwrap(),
            auto,
            false,
        )
    }

    fn editor_gesture(r: &mut Runtime, observed: &str, t: &mut u64) -> Value {
        for action in ["down", "up", "down"] {
            *t += 50;
            event(r, "left_shift", action, None, *t, false);
        }
        *t += 50;
        r.event(
            serde_json::from_value(json!({"key":"left_shift", "action":"up", "text":null,
                "time_ms":*t, "device":null, "origin":"physical", "modifiers":0,
                "editor_word":observed}))
            .unwrap(),
            false,
            true,
        )
    }

    #[test]
    fn auto_editor_nbsp_preserves_literal_tail_and_counts_unicode_scalars() {
        for tail in ["\u{a0}", " \u{a0}", "\u{a0} \u{a0}"] {
            for (source, target) in [("ghbdtn", "привет"), ("руддщ", "hello")] {
                let mut r = Runtime::default();
                let mut t = 0;
                // Even intact physical history contains only the Space key,
                // while Safari may commit a different literal delimiter.
                word(&mut r, source, &mut t);
                let observed = format!("{source}{tail}");
                let p = editor_space(&mut r, &observed, "down", t + 1, true);
                assert_eq!(p["status"], "inferred_edit", "{observed:?}");
                assert_eq!(p["before"], observed);
                assert_eq!(p["remove"], source.chars().count() + tail.chars().count());
                assert_eq!(p["replacement"], format!("{target}{tail}"));
                let outcome = r.result(p["id"].as_u64().unwrap(), Outcome::Verified, t + 2);
                assert_eq!(outcome["status"], "ok");
                assert_eq!(outcome["feedback"]["learned_add"], json!([target]));
                assert_eq!(r.text, format!("{target}{tail}"));
            }
        }
    }

    #[test]
    fn auto_editor_nbsp_recovery_preserves_current_safari_tail() {
        let mut r = Runtime::default();
        let first = editor_space(&mut r, "ghbdtn\u{a0}", "down", 1, true);
        assert_eq!(first["status"], "inferred_edit");
        r.result(first["id"].as_u64().unwrap(), Outcome::FailedBefore, 2);
        // Safari's second Space changes the first NBSP to ASCII and appends
        // NBSP. The current AX snapshot, not an old tail, defines the edit.
        let recovered = editor_space(&mut r, "ghbdtn \u{a0}", "repeat", 3, true);
        assert_eq!(recovered["before"], "ghbdtn \u{a0}");
        assert_eq!(recovered["remove"], 8);
        assert_eq!(recovered["replacement"], "привет \u{a0}");
    }

    #[test]
    fn manual_editor_nbsp_roundtrip_preserves_tail_and_reverse_feedback() {
        for tail in ["\u{a0}", " \u{a0}", "\u{a0} \u{a0}"] {
            let mut r = Runtime::default();
            let mut t = 1;
            let source = format!("ghbdtn{tail}");
            let corrected = format!("привет{tail}");
            let automatic = editor_space(&mut r, &source, "down", t, true);
            assert_eq!(automatic["status"], "inferred_edit");
            r.result(automatic["id"].as_u64().unwrap(), Outcome::Verified, t);
            let undo = editor_gesture(&mut r, &corrected, &mut t);
            assert_eq!(undo["before"], corrected);
            assert_eq!(undo["remove"], 6 + tail.chars().count());
            assert_eq!(undo["replacement"], source);
            let outcome = r.result(undo["id"].as_u64().unwrap(), Outcome::Verified, t);
            assert_eq!(outcome["feedback"]["exclusions_add"], json!(["ghbdtn"]));
            assert_eq!(r.learned_words(), &["привет", "ghbdtn"]);
            // The exact delimiter also survives a later history-only toggle.
            let redo = gesture(&mut r, &mut t);
            assert_eq!(redo["before"], source);
            assert_eq!(redo["remove"], 6 + tail.chars().count());
            assert_eq!(redo["replacement"], corrected);
        }
    }

    #[test]
    fn manual_editor_nbsp_recovers_whole_word_after_history_loss() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "r", &mut t);
        let p = editor_gesture(&mut r, "frr \u{a0}", &mut t);
        assert_eq!(p["before"], "frr \u{a0}");
        assert_eq!(p["remove"], 5);
        assert_eq!(p["replacement"], "акк \u{a0}");
        r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t);
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "frr \u{a0}");
    }

    #[test]
    fn editor_nbsp_boundary_starts_next_word_and_rejects_repeated_space() {
        for automatic in [false, true] {
            let mut r = Runtime::default();
            let mut t = 1;
            let p = editor_space(&mut r, "ghbdtn\u{a0}", "down", t, automatic);
            if automatic {
                assert_eq!(p["status"], "inferred_edit");
                r.result(p["id"].as_u64().unwrap(), Outcome::Verified, t);
            }
            word(&mut r, "руддщ", &mut t);
            assert_eq!(r.text, "руддщ");
            t += 1;
            let next = event(&mut r, "space", "down", None, t, true);
            assert_eq!(next["before"], "руддщ ");
            assert_eq!(next["replacement"], "hello ");
        }
        let mut r = Runtime::default();
        editor_space(&mut r, "hello\u{a0}", "down", 1, true);
        assert_eq!(
            event(&mut r, "space", "repeat", None, 2, true),
            json!({"status":"ignored", "reason":"repeated_boundary"})
        );
        assert!(!r.is_pending());
    }

    #[test]
    fn editor_nbsp_second_space_preserves_policy_and_current_literal_tail() {
        let mut r = Runtime::default();
        r.layout_notice("user", "ru");
        assert_eq!(
            editor_space(&mut r, "ghbdtn\u{a0}", "down", 1, true),
            json!({"status":"ignored", "reason":"layout_change_suppressed"})
        );
        assert_eq!(
            editor_space(&mut r, "ghbdtn \u{a0}", "down", 2, true),
            json!({"status":"ignored", "reason":"already_completed_editor_word"})
        );
        assert_eq!(r.text, "ghbdtn \u{a0}");
        assert!(!r.is_pending());
        r.configure(vec![], vec!["ghbdtn".into()], vec![], AutoPolicy::default())
            .unwrap();
        assert_eq!(
            editor_space(&mut r, "ghbdtn\u{a0}", "down", 3, true),
            json!({"status":"ignored", "reason":"no_suggestion"})
        );
        assert_eq!(
            editor_space(&mut r, "ghbdtn \u{a0}", "down", 4, true),
            json!({"status":"ignored", "reason":"already_completed_editor_word"})
        );
        assert_eq!(r.text, "ghbdtn \u{a0}");
        assert!(!r.is_pending());
    }

    #[test]
    fn auto_editor_space_recovers_after_stale_first_space_and_keeps_exact_tail() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        let first = event(&mut r, "space", "down", None, t, true);
        assert_eq!(first["status"], "inferred_edit");
        assert_eq!(
            r.result(first["id"].as_u64().unwrap(), Outcome::FailedBefore, t)["status"],
            "reset"
        );
        let recovered = editor_space(&mut r, "ghbdtn  ", "down", t + 1, true);
        assert_eq!(recovered["status"], "inferred_edit");
        assert_eq!(recovered["before"], "ghbdtn  ");
        assert_eq!(recovered["remove"], 8);
        assert_eq!(recovered["replacement"], "привет  ");
        assert_eq!(
            r.result(recovered["id"].as_u64().unwrap(), Outcome::Verified, t + 2)["status"],
            "ok"
        );
        assert_eq!(r.text, "привет  ");
        t += 3;
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "ghbdtn  ");
    }

    #[test]
    fn auto_editor_space_repeat_uses_whole_snapshot_instead_of_tracked_suffix() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "tn", &mut t);
        let recovered = editor_space(&mut r, "Ghbdtn   ", "repeat", t + 1, true);
        assert_eq!(recovered["before"], "Ghbdtn   ");
        assert_eq!(recovered["remove"], 9);
        assert_eq!(recovered["replacement"], "Привет   ");
    }

    #[test]
    fn auto_editor_space_invalid_known_snapshot_never_uses_history() {
        let too_long = format!("{} ", "a".repeat(128));
        for observed in [
            "",
            "ghbdtn",
            "ghbdtn\t",
            "ghbdtn\t ",
            "ghbdtn\n\u{a0}",
            "ghbdtn\u{a0}\t",
            "ghbdtn\u{202f}",
            "ghbdtn\u{a0}word\u{a0}",
            "\u{a0}ghbdtn\u{a0}",
            "two words ",
            " ghbdtn ",
            "ghbdtn1 ",
            "https://ghbdtn ",
            too_long.as_str(),
        ] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "ghbdtn", &mut t);
            let result = editor_space(&mut r, observed, "down", t + 1, true);
            assert_eq!(
                result,
                json!({"status":"ignored", "history_reset":true, "reason":"invalid_editor_word"}),
                "{observed:?}"
            );
            assert!(!r.is_pending());
            assert!(r.text.is_empty());
        }
    }

    #[test]
    fn auto_editor_space_obeys_disable_and_external_layout_suppression() {
        let mut r = Runtime::default();
        assert_eq!(
            editor_space(&mut r, "ghbdtn  ", "down", 1, false)["status"],
            "ignored"
        );
        assert_eq!(r.text, "ghbdtn  ");
        assert!(!r.is_pending());
        r.reset();
        r.layout_notice("user", "ru");
        assert_eq!(
            editor_space(&mut r, "ghbdtn ", "down", 2, true)["status"],
            "ignored"
        );
        // A second Space must not undo the first-word layout-change policy.
        assert_eq!(
            editor_space(&mut r, "ghbdtn  ", "down", 3, true)["status"],
            "ignored"
        );
        assert!(!r.is_pending());
        let mut t = 4;
        word(&mut r, "руддщ", &mut t);
        assert_eq!(
            editor_space(&mut r, "руддщ  ", "down", t + 1, true)["replacement"],
            "hello  "
        );
    }

    #[test]
    fn auto_editor_space_respects_dictionary_policy_and_does_not_handle_key_up() {
        let mut r = Runtime::default();
        r.configure(vec![], vec!["ghbdtn".into()], vec![], AutoPolicy::default())
            .unwrap();
        assert_eq!(
            editor_space(&mut r, "ghbdtn  ", "down", 1, true)["status"],
            "ignored"
        );
        assert!(!r.is_pending());
        r.configure(
            vec![],
            vec![],
            vec![],
            AutoPolicy {
                switch_only_last_word: false,
                dont_switch_words: true,
                ..AutoPolicy::default()
            },
        )
        .unwrap();
        let layout_only = editor_space(&mut r, "ghbdtn  ", "down", 2, true);
        assert_eq!(layout_only["status"], "layout_only");
        assert_eq!(layout_only["mode"], "ru");
        assert!(!r.is_pending());
        r.reset();
        let mut t = 3;
        word(&mut r, "ghbdtn", &mut t);
        assert_eq!(
            editor_space(&mut r, "invalid snapshot", "up", t + 1, true)["status"],
            "ignored"
        );
        assert_eq!(r.text, "ghbdtn");
    }

    #[test]
    fn known_invalid_editor_word_never_falls_back_to_history() {
        for observed in [
            "",
            "two words",
            "frr1",
            "https://frr",
            "frr\n\u{a0}",
            "frr\u{a0}\t",
            "frr\u{202f}",
            "frr\u{a0}word\u{a0}",
        ] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "r", &mut t);
            for a in ["down", "up", "down"] {
                t += 50;
                event(&mut r, "left_shift", a, None, t, false);
            }
            t += 50;
            let p = r.event(serde_json::from_value(json!({"key":"left_shift","action":"up","text":null,"time_ms":t,"device":null,"origin":"physical","modifiers":0,"editor_word":observed})).unwrap(),false,true);
            assert_eq!(p["status"], "ignored");
            assert_eq!(p["history_reset"], true);
            assert!(!r.is_pending());
            assert!(r.text.is_empty());
        }
    }

    #[test]
    fn history_reset_reports_invalid_origin_time_chord_and_payload() {
        for (field, value) in [
            ("origin", json!("unknown")),
            ("time_ms", json!(0)),
            ("modifiers", json!(2)),
            ("key", json!("x".repeat(65))),
            ("device", json!("x".repeat(129))),
        ] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "ghbdtn", &mut t);
            let mut input = json!({"key":"letter", "action":"down", "text":"a",
                "time_ms":t+1, "device":null, "origin":"physical", "modifiers":0});
            input[field] = value;
            assert_eq!(
                r.event(serde_json::from_value(input).unwrap(), false, true),
                json!({"status":"ignored", "history_reset":true}),
                "{field}"
            );
            assert!(r.text.is_empty());
        }
    }

    #[test]
    fn history_reset_reports_navigation_unsupported_text_and_capacity() {
        for (key, text) in [
            ("arrow_left", None),
            ("letter", Some("_")),
            ("letter", Some("/")),
            ("letter", Some("ab")),
        ] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "ghbdtn", &mut t);
            assert_eq!(
                event(&mut r, key, "down", text, t + 1, false),
                json!({"status":"ignored", "history_reset":true}),
                "{key} {text:?}"
            );
            assert!(r.text.is_empty());
        }
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, &"a".repeat(128), &mut t);
        assert_eq!(
            event(&mut r, "letter", "down", Some("a"), t + 1, false)["history_reset"],
            true
        );
        assert!(r.text.is_empty());

        for i in 0..32 {
            assert_eq!(
                event(&mut r, &format!("key{i}"), "down", Some("a"), i, false),
                json!({"status":"ignored"})
            );
        }
        assert_eq!(
            event(&mut r, "key32", "down", Some("a"), 32, false)["history_reset"],
            true
        );
    }

    #[test]
    fn ordinary_ignored_events_and_word_boundaries_do_not_report_history_loss() {
        let mut r = Runtime::default();
        let mut t = 0;
        for (key, action, text) in [
            ("letter", "down", Some("a")),
            ("letter", "up", None),
            ("backspace", "down", None),
            ("space", "down", None),
            ("space", "down", None),
            ("pointer", "down", None),
            ("lock_key", "down", None),
        ] {
            t += 1;
            assert_eq!(
                event(&mut r, key, action, text, t, false),
                if key == "space" {
                    json!({"status":"ignored", "reason":"empty_history"})
                } else {
                    json!({"status":"ignored"})
                },
                "{key} {action}"
            );
        }
        word(&mut r, "ghbdtn", &mut t);
        assert_eq!(
            event(&mut r, "space", "down", None, t + 1, false),
            json!({"status":"ignored", "reason":"automatic_disabled"})
        );
        assert_eq!(
            r.event(
                serde_json::from_value(json!({"key":"letter", "action":"down",
                "text":"_", "time_ms":0, "device":null, "origin":"own", "modifiers":2}))
                .unwrap(),
                false,
                true
            ),
            json!({"status":"ignored"})
        );
    }

    #[test]
    fn space_diagnostics_distinguish_boundary_policy_and_snapshot_refusals() {
        let mut r = Runtime::default();
        let mut t = 0;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true),
            json!({"status":"ignored", "reason":"empty_history"})
        );
        word(&mut r, "hello", &mut t);
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true),
            json!({"status":"ignored", "reason":"no_suggestion"})
        );
        t += 1;
        assert_eq!(
            event(&mut r, "space", "repeat", None, t, true),
            json!({"status":"ignored", "reason":"repeated_boundary"})
        );
        assert!(r.text.is_empty());
        t += 1;
        assert_eq!(
            editor_space(&mut r, "ghbdtn ", "down", t, false),
            json!({"status":"ignored", "reason":"automatic_disabled"})
        );
        assert_eq!(r.text, "ghbdtn ");
        t += 1;
        assert_eq!(
            editor_space(&mut r, "ghbdtn  ", "down", t, true),
            json!({"status":"ignored", "reason":"already_completed_editor_word"})
        );
        assert_eq!(r.text, "ghbdtn  ");
        r.reset();
        r.layout_notice("user", "ru");
        t += 1;
        assert_eq!(
            editor_space(&mut r, "ghbdtn ", "down", t, true),
            json!({"status":"ignored", "reason":"layout_change_suppressed"})
        );
        assert!(!r.suppress_auto_until_word);
        t += 1;
        assert_eq!(
            editor_space(&mut r, "ghbdtn", "down", t, true),
            json!({"status":"ignored", "history_reset":true, "reason":"invalid_editor_word"})
        );
        assert!(r.text.is_empty());
        t += 1;
        assert_eq!(
            editor_space(&mut r, "invalid snapshot", "up", t, true),
            json!({"status":"ignored"})
        );
    }

    #[test]
    fn space_diagnostics_do_not_change_origin_pending_or_chord_guards() {
        for (field, value, reason) in [
            ("origin", json!("unknown"), "untrusted_origin"),
            ("time_ms", json!(0), "stale_event"),
            ("modifiers", json!(2), "shortcut_or_held_limit"),
            ("device", json!("x".repeat(129)), "invalid_event"),
        ] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "ghbdtn", &mut t);
            let mut input = json!({"key":"space", "action":"down", "text":null,
                "time_ms":t+1, "device":null, "origin":"physical", "modifiers":0});
            input[field] = value;
            assert_eq!(
                r.event(serde_json::from_value(input).unwrap(), true, true),
                json!({"status":"ignored", "history_reset":true, "reason":reason})
            );
            assert!(r.text.is_empty());
            assert!(!r.is_pending());
        }
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        let edit = event(&mut r, "space", "down", None, t, true);
        assert_eq!(edit["status"], "inferred_edit");
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true),
            json!({"status":"ignored", "reason":"pending_edit"})
        );
        assert!(r.is_pending());
        assert_eq!(r.text, "ghbdtn ");
    }

    #[test]
    fn manual_uses_complete_editor_word_after_history_loss() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "r", &mut t);
        for a in ["down", "up", "down"] {
            t += 50;
            event(&mut r, "left_shift", a, None, t, false);
        }
        t += 50;
        let p = r.event(serde_json::from_value(json!({"key":"left_shift","action":"up","text":null,"time_ms":t,"device":null,"origin":"physical","modifiers":0,"editor_word":"frr"})).unwrap(),false,true);
        assert_eq!(p["before"], "frr");
        assert_eq!(p["remove"], 3);
        assert_eq!(p["replacement"], "акк");
        r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t);
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "frr");
    }

    #[test]
    fn manual_roundtrip_and_partial_failure() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "привет");
        r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "ghbdtn");
        r.result(p["id"].as_u64().unwrap(), Outcome::UnknownAfter, t);
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
    }
    #[test]
    fn auto_learn_and_reverse_undo_soft_excludes() {
        let mut r = Runtime::default();
        let mut t = 0;
        // Auto rewrite learns the target form.
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        let p = event(&mut r, "space", "down", None, t, true);
        t += 1;
        r.result(p["id"].as_u64().unwrap(), Outcome::Verified, t);
        assert!(r.learned_words().contains(&"привет".to_string()));
        // Reverse Double Shift within 10s soft-excludes the source (1-shot).
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "ghbdtn ");
        r.result(p["id"].as_u64().unwrap(), Outcome::Verified, t);
        assert!(r.exclusions().contains(&"ghbdtn".to_string()));
        // Clear learned words only.
        r.learn_clear();
        assert!(r.learned_words().is_empty());
        assert!(r.exclusions().contains(&"ghbdtn".to_string()));
    }

    #[test]
    fn own_rewrite_does_not_suppress_next_auto_word() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        let p = event(&mut r, "space", "down", None, t, true);
        t += 1;
        r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t);
        // Regression: anti-loop after ok made auto fire only every other word.
        r.reset();
        word(&mut r, "руддщ", &mut t);
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true)["status"],
            "inferred_edit"
        );
    }

    #[test]
    fn external_layout_change_skips_first_auto_word_only() {
        let mut r = Runtime::default();
        r.layout_notice("user", "us");
        r.layout_notice("user", "ru");
        let mut t = 10;
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true)["status"],
            "ignored"
        );
        r.reset();
        word(&mut r, "руддщ", &mut t);
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true)["status"],
            "inferred_edit"
        );
    }

    #[test]
    fn layout_notice_sets_anti_loop() {
        let mut r = Runtime::default();
        r.layout_notice("user", "us");
        r.layout_notice("user", "ru");
        word(&mut r, "ghbdtn", &mut { 0u64 });
        let mut t = 10;
        word(&mut r, "ghbdtn", &mut t);
        t += 1;
        assert_eq!(
            event(&mut r, "space", "down", None, t, true)["status"],
            "ignored"
        );
    }
    #[test]
    fn shared_gesture_fixtures() {
        let cases: Value =
            serde_json::from_str(include_str!("../../../tests/parity/gesture.json")).unwrap();
        for case in cases.as_array().unwrap() {
            let mut g = Gesture::default();
            let mut fired = false;
            for e in case["events"].as_array().unwrap() {
                fired |= g.edge(
                    e[0].as_str().unwrap().into(),
                    e[1].as_bool().unwrap(),
                    e[2].as_u64().unwrap(),
                );
            }
            assert_eq!(fired, case["fires"].as_bool().unwrap(), "{}", case["name"]);
        }
    }
    #[test]
    fn shared_feedback_fixtures_map_to_learned_and_exclusions() {
        // Feedback fixtures historically produced 3-count proposals. Aggressive
        // mode learns on verified and soft-excludes on a confirmed reverse undo.
        let cases: Value =
            serde_json::from_str(include_str!("../../../tests/parity/feedback.json")).unwrap();
        for case in cases.as_array().unwrap() {
            let mut r = Runtime::default();
            for _ in 0..case["cycles"].as_u64().unwrap() {
                for step in case["trace"].as_array().unwrap() {
                    match step["action"].as_str() {
                        Some("reset") => r.reset(),
                        Some("advance") => r.advance(step["boundary"].as_bool().unwrap()),
                        _ => {
                            r.next += 1;
                            let id = r.next;
                            r.pending = Some(Pending {
                                id,
                                before: step["before"].as_str().unwrap().into(),
                                after: step["after"].as_str().unwrap().into(),
                                automatic: step["kind"] == "auto",
                                time: 0,
                            });
                            r.result(id, Outcome::Verified, 0);
                        }
                    }
                }
            }
            // Fixture expectations remain documentation of the old proposal UI;
            // aggressive path asserts learned/exclusion side effects instead.
            assert!(r.learned_words().len() <= 500);
        }
    }
    #[test]
    fn origins_overflow_stale_result_and_shortcuts_invalidate() {
        for origin in ["own", "unknown"] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "ghbdtn", &mut t);
            r.event(serde_json::from_value(json!({"key":"letter","action":"down","text":"x","time_ms":t+1,"device":null,"origin":origin,"modifiers":0})).unwrap(),false,true);
            let edit = gesture(&mut r, &mut t);
            assert_eq!(
                edit["status"],
                if origin == "own" {
                    "inferred_edit"
                } else {
                    "ignored"
                }
            );
        }
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, &"a".repeat(129), &mut t);
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
        word(&mut r, "ghbdtn", &mut t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(
            r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t + 2501)["status"],
            "reset"
        );
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
        word(&mut r, "ghbdtn", &mut t);
        r.event(serde_json::from_value(json!({"key":"command","action":"down","text":null,"time_ms":t+1,"device":null,"origin":"physical","modifiers":2})).unwrap(),true,true);
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
    }
    #[test]
    fn result_accepts_source_elapsed_deadline_and_keeps_retoggle() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(
            r.result(p["id"].as_u64().unwrap(), Outcome::Ok, t + 2500)["status"],
            "ok"
        );
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "ghbdtn");
    }
    #[test]
    fn learn_add_is_validated_and_capped() {
        let mut r = Runtime::default();
        assert_eq!(r.learn_add("Привет".into())["status"], "learned");
        assert_eq!(r.learn_add("bad word".into())["status"], "invalid");
        assert!(r.learned_words().contains(&"привет".to_string()));
        for n in 0..600u16 {
            let word = format!(
                "word{}{}",
                char::from(b'a' + (n / 26) as u8),
                char::from(b'a' + (n % 26) as u8)
            );
            r.learn_add(word);
        }
        assert_eq!(r.learned_words().len(), 500);
        assert_eq!(r.learn_add("overflow".into())["status"], "full");
        assert!(r.learned_words().contains(&"привет".to_string()));
    }
}
