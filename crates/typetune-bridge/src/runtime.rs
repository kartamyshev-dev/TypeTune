//! Pure, bounded compatibility state. An inferred edit never asserts editor truth.
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeSet;
use typetune_engine::{inferred::suggest_with_policy, AutoPolicy, Direction, UserDictionary};

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
/// Tri-state edit result (docs/60). Legacy host labels map via aliases.
#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    #[serde(alias = "verified", alias = "submitted")]
    Ok,
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
    last_auto: Option<(String, String, u64)>,
    manual: Option<(String, String)>,
    consumed: bool,
    words: Vec<String>,
    exclusions: Vec<String>,
    learned: Vec<String>,
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
    ) {
        self.words = words;
        self.exclusions = exclusions;
        self.learned = learned;
        self.policy = policy;
        self.reset();
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
        if !self.learned.contains(&word) {
            if self.learned.len() >= 500 {
                self.learned.remove(0);
            }
            self.learned.push(word);
        }
        json!({"status":"learned"})
    }
    pub fn learn_clear(&mut self) -> Value {
        self.learned.clear();
        json!({"status":"cleared"})
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
    pub fn event(&mut self, e: Event, automatic: bool, dictionary: &UserDictionary) -> Value {
        let ignored = json!({"status":"ignored"});
        if e.origin == Origin::Own {
            return ignored;
        }
        // Caps / Fn (layout switch, latch) must not invalidate keyboard history.
        if e.key == "lock_key" {
            return ignored;
        }
        if e.origin != Origin::Physical
            || e.key.len() > 64
            || e.device.as_ref().is_some_and(|v| v.len() > 128)
            || self.time.is_some_and(|t| e.time_ms < t)
        {
            self.reset();
            return ignored;
        }
        if self.pending.is_some() {
            self.reset();
            return json!({"status":"invalidated"});
        }
        self.time = Some(e.time_ms);
        let identity = format!("{}:{}", e.device.as_deref().unwrap_or("unknown"), e.key);
        if e.action == Action::Up {
            self.held.remove(&identity);
        } else if e.action == Action::Down {
            self.held.insert(identity.clone());
        }
        if self.held.len() > 32 || e.modifiers & !1 != 0 {
            self.reset();
            return ignored;
        }
        let manual;
        if e.key == "left_shift" || e.key == "right_shift" {
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
                if self.text.is_empty() || self.text.ends_with(' ') {
                    self.text.clear();
                    return ignored;
                }
                self.text.push(' ');
                if !automatic {
                    return ignored;
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
                    self.reset();
                    return ignored;
                }
                self.advance(false);
                if self.text.ends_with(' ') {
                    self.text.clear();
                }
                self.text.push_str(&text);
                if self.text.chars().count() > 128 {
                    self.reset();
                }
                return ignored;
            } else {
                self.reset();
                return ignored;
            }
            manual = false;
        }
        // A current editor snapshot can recover a truncated keyboard history.
        // Empty/invalid known context must refuse, never fall back to a suffix.
        if manual {
            self.suppress_auto_until_word = false;
            if let Some(editor_word) = e.editor_word {
                let token = editor_word.trim_end_matches(' ');
                if token.is_empty()
                    || token.chars().any(char::is_whitespace)
                    || editor_word.chars().count() > 128
                    || suggest_with_policy(&editor_word, false, dictionary, &AutoPolicy::default())
                        .is_none()
                {
                    self.reset();
                    return ignored;
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
                return ignored;
            }
            if !automatic {
                return ignored;
            }
        }
        let Some(s) = suggest_with_policy(&self.text, !manual, dictionary, &self.policy) else {
            return ignored;
        };
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
    pub fn result(
        &mut self,
        id: u64,
        outcome: Outcome,
        time: u64,
        dictionary: &UserDictionary,
    ) -> Value {
        let Some(p) = self.pending.take() else {
            return json!({"status":"stale"});
        };
        // Covers macOS held-key wait (800ms) plus paired inject sleeps; elapsed
        // duration is added to the source timestamp, not a second clock domain.
        const RESULT_DEADLINE_MS: u64 = 2500;
        if p.id != id
            || time < p.time
            || time - p.time > RESULT_DEADLINE_MS
            || outcome != Outcome::Ok
        {
            self.reset();
            return json!({"status":"reset"});
        }
        self.text = p.after.clone();
        self.held.clear();
        // Own rewrite intentionally continues in the target language — do not
        // suppress the next auto word (anti-loop is for external layout changes).
        // Auto-learn the target form after a successful rewrite.
        let target = p.after.trim().to_lowercase();
        if UserDictionary::new(vec![target.clone()], vec![]).is_ok()
            && !self.learned.contains(&target)
            && !self.words.contains(&target)
        {
            if self.learned.len() >= 500 {
                self.learned.remove(0);
            }
            self.learned.push(target.clone());
        }
        // Reverse undo of an auto rewrite: soft-exclude the source (1-shot).
        if !p.automatic {
            if let Some((source, corrected, deadline)) = self.last_auto.take() {
                if time <= deadline && p.before == corrected && p.after == source {
                    let source = source.trim().to_lowercase();
                    if UserDictionary::new(vec![], vec![source.clone()]).is_ok()
                        && !self.exclusions.contains(&source)
                    {
                        if self.exclusions.len() >= 500 {
                            self.exclusions.remove(0);
                        }
                        self.exclusions.push(source);
                    }
                }
            }
        } else {
            self.last_auto = Some((p.before, p.after, time + 10000));
            self.manual = None;
            self.consumed = false;
        }
        let _ = dictionary;
        json!({"status":"ok"})
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
        r.event(serde_json::from_value(json!({"key":key,"action":action,"text":text,"time_ms":time,"device":null,"origin":"physical","modifiers":0})).unwrap(),auto,&UserDictionary::default())
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
    #[test]
    fn known_invalid_editor_word_never_falls_back_to_history() {
        for observed in ["", "two words", "frr1", "https://frr"] {
            let mut r = Runtime::default();
            let mut t = 0;
            word(&mut r, "r", &mut t);
            for a in ["down", "up", "down"] {
                t += 50;
                event(&mut r, "left_shift", a, None, t, false);
            }
            t += 50;
            let p = r.event(serde_json::from_value(json!({"key":"left_shift","action":"up","text":null,"time_ms":t,"device":null,"origin":"physical","modifiers":0,"editor_word":observed})).unwrap(),false,&UserDictionary::default());
            assert_eq!(p["status"], "ignored");
            assert!(!r.is_pending());
            assert!(r.text.is_empty());
        }
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
        let p = r.event(serde_json::from_value(json!({"key":"left_shift","action":"up","text":null,"time_ms":t,"device":null,"origin":"physical","modifiers":0,"editor_word":"frr"})).unwrap(),false,&UserDictionary::default());
        assert_eq!(p["before"], "frr");
        assert_eq!(p["remove"], 3);
        assert_eq!(p["replacement"], "акк");
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Ok,
            t,
            &UserDictionary::default(),
        );
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "frr");
    }

    #[test]
    fn manual_roundtrip_and_partial_failure() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "привет");
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Ok,
            t,
            &UserDictionary::default(),
        );
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "ghbdtn");
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::UnknownAfter,
            t,
            &UserDictionary::default(),
        );
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
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Ok,
            t,
            &UserDictionary::default(),
        );
        assert!(r.learned_words().contains(&"привет".to_string()));
        // Reverse Double Shift within 10s soft-excludes the source (1-shot).
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "ghbdtn ");
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Ok,
            t,
            &UserDictionary::default(),
        );
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
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Ok,
            t,
            &UserDictionary::default(),
        );
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
        // mode auto-learns on ok and soft-excludes on one reverse undo instead.
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
                            r.result(id, Outcome::Ok, 0, &UserDictionary::default());
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
            r.event(serde_json::from_value(json!({"key":"letter","action":"down","text":"x","time_ms":t+1,"device":null,"origin":origin,"modifiers":0})).unwrap(),false,&UserDictionary::default());
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
            r.result(
                p["id"].as_u64().unwrap(),
                Outcome::Ok,
                t + 2501,
                &UserDictionary::default()
            )["status"],
            "reset"
        );
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
        word(&mut r, "ghbdtn", &mut t);
        r.event(serde_json::from_value(json!({"key":"command","action":"down","text":null,"time_ms":t+1,"device":null,"origin":"physical","modifiers":2})).unwrap(),true,&UserDictionary::default());
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
    }
    #[test]
    fn result_accepts_source_elapsed_deadline_and_keeps_retoggle() {
        let mut r = Runtime::default();
        let mut t = 0;
        word(&mut r, "ghbdtn", &mut t);
        let p = gesture(&mut r, &mut t);
        assert_eq!(
            r.result(
                p["id"].as_u64().unwrap(),
                Outcome::Ok,
                t + 2500,
                &UserDictionary::default()
            )["status"],
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
        for n in 0..600 {
            r.learn_add(format!("word{n}"));
        }
        assert!(r.learned_words().len() <= 500);
    }
}
