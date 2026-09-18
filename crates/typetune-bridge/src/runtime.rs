//! Pure, bounded compatibility state. An inferred edit never asserts editor truth.
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{BTreeSet, VecDeque};
use typetune_engine::{inferred::suggest_with_dictionary, Direction, UserDictionary};

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
#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Verified,
    Submitted,
    Rejected,
    Indeterminate,
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
struct Proposal {
    id: u64,
    source: String,
    word: String,
    kind: &'static str,
    count: u8,
    dismissed: bool,
}
#[derive(Default)]
pub struct Runtime {
    text: String,
    held: BTreeSet<String>,
    time: Option<u64>,
    gesture: Gesture,
    pending: Option<Pending>,
    next: u64,
    proposals: VecDeque<Proposal>,
    dismissed: BTreeSet<(String, String, &'static str)>,
    last_auto: Option<(String, String, u64)>,
    manual: Option<(String, String)>,
    consumed: bool,
    receipt: Option<(u64, u8)>,
    words: Vec<String>,
    exclusions: Vec<String>,
}
impl Runtime {
    pub fn is_pending(&self) -> bool {
        self.pending.is_some()
    }
    pub fn configure(&mut self, words: Vec<String>, exclusions: Vec<String>) {
        self.words = words;
        self.exclusions = exclusions;
        self.reset();
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
        self.receipt = None;
    }
    fn advance(&mut self, boundary: bool) {
        let pending = self.manual.take();
        self.reset_tracker();
        if let Some((source, word)) = pending {
            if boundary && !word.ends_with(' ') {
                self.record(&source, &word, "word");
            }
        }
    }
    fn record(&mut self, source: &str, word: &str, kind: &'static str) -> Option<(u64, u8)> {
        let source = source.trim().to_lowercase();
        let word = word.trim().to_lowercase();
        if source == word
            || UserDictionary::new(vec![word.clone()], vec![]).is_err()
            || self.dismissed.len() >= 64
            || self
                .dismissed
                .contains(&(source.clone(), word.clone(), kind))
        {
            return None;
        }
        if !self
            .proposals
            .iter()
            .any(|p| p.source == source && p.word == word && p.kind == kind)
        {
            if self.proposals.len() >= 64 {
                self.proposals.pop_front();
            }
            self.next += 1;
            self.proposals.push_back(Proposal {
                id: self.next,
                source: source.clone(),
                word: word.clone(),
                kind,
                count: 0,
                dismissed: false,
            });
        }
        let p = self
            .proposals
            .iter_mut()
            .find(|p| p.source == source && p.word == word && p.kind == kind)?;
        if p.dismissed || p.count >= 3 {
            return None;
        }
        p.count += 1;
        Some((p.id, p.count))
    }
    pub fn suggestions(&self, _: &UserDictionary) -> Value {
        json!({"status":"suggestions","items":self.proposals.iter().filter(|p| p.count==3 && !p.dismissed && !self.exclusions.contains(&p.word) && (p.kind=="exclusion" || (!self.words.contains(&p.word) && !self.exclusions.contains(&p.source)))).map(|p|json!({"id":p.id,"word":p.word,"kind":p.kind})).collect::<Vec<_>>()})
    }
    pub fn dismiss(&mut self, id: u64) -> Value {
        if let Some(p) = self
            .proposals
            .iter_mut()
            .find(|p| p.id == id && p.count == 3 && !p.dismissed)
        {
            p.dismissed = true;
            self.dismissed
                .insert((p.source.clone(), p.word.clone(), p.kind));
            json!({"status":"dismissed"})
        } else {
            json!({"status":"stale"})
        }
    }
    pub fn event(&mut self, e: Event, automatic: bool, dictionary: &UserDictionary) -> Value {
        let ignored = json!({"status":"ignored"});
        if e.origin == Origin::Own {
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
            if let Some(editor_word) = e.editor_word {
                let token = editor_word.trim_end_matches(' ');
                if token.is_empty()
                    || token.chars().any(char::is_whitespace)
                    || editor_word.chars().count() > 128
                    || suggest_with_dictionary(&editor_word, false, dictionary).is_none()
                {
                    self.reset();
                    return ignored;
                }
                if self.text != editor_word {
                    self.reset_tracker();
                    self.text = editor_word;
                }
            }
        }
        let Some(s) = suggest_with_dictionary(&self.text, !manual, dictionary) else {
            return ignored;
        };
        self.next += 1;
        let response = json!({"status":"inferred_edit","id":self.next,"before":self.text,"remove":s.remove,"replacement":s.replacement,"mode":if matches!(s.direction,Direction::UsToRu) {"ru"}else{"us"}});
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
            || (outcome != Outcome::Verified && outcome != Outcome::Submitted)
        {
            self.reset();
            return json!({"status":"reset"});
        }
        self.text = p.after.clone();
        self.held.clear();
        let previous = self.last_auto.take();
        if p.automatic {
            self.manual = None;
            self.consumed = false;
            self.receipt = None;
            self.last_auto = Some((p.before, p.after, time + 10000));
        } else if let Some((source, corrected, deadline)) = previous {
            self.consumed = true;
            if time <= deadline && p.before == corrected && p.after == source {
                self.record(&source, &corrected, "exclusion");
            }
        } else if self.manual.is_some() {
            if let Some((id, count)) = self.receipt.take() {
                if let Some(item) = self
                    .proposals
                    .iter_mut()
                    .find(|p| p.id == id && p.count == count && !p.dismissed)
                {
                    item.count -= 1;
                }
            }
            self.manual = None;
            self.consumed = true;
        } else if !self.consumed {
            let target = p.after.trim().to_lowercase();
            let input = format!("{} ", p.before.trim_end());
            let mut words = self.words.clone();
            words.push(target);
            let learn = suggest_with_dictionary(&input, true, dictionary).is_none()
                && UserDictionary::new(words, self.exclusions.clone())
                    .ok()
                    .and_then(|d| suggest_with_dictionary(&input, true, &d))
                    .is_some_and(|s| s.replacement == format!("{} ", p.after.trim_end()));
            if learn {
                self.manual = Some((p.before.clone(), p.after.clone()));
                if p.before.ends_with(' ') {
                    self.receipt = self.record(&p.before, &p.after, "word");
                }
            }
        }
        json!({"status":if outcome==Outcome::Verified {"verified"} else {"submitted"}})
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
            Outcome::Verified,
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
            Outcome::Submitted,
            t,
            &UserDictionary::default(),
        );
        let p = gesture(&mut r, &mut t);
        assert_eq!(p["replacement"], "ghbdtn");
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Indeterminate,
            t,
            &UserDictionary::default(),
        );
        assert_eq!(gesture(&mut r, &mut t)["status"], "ignored");
    }
    #[test]
    fn three_undos_and_three_learned_occurrences() {
        let mut r = Runtime::default();
        let mut t = 0;
        for _ in 0..3 {
            r.reset();
            word(&mut r, "ghbdtn", &mut t);
            t += 1;
            let p = event(&mut r, "space", "down", None, t, true);
            t += 1; // result before next physical event
            r.result(
                p["id"].as_u64().unwrap(),
                Outcome::Submitted,
                t,
                &UserDictionary::default(),
            );
            event(&mut r, "space", "up", None, t, false);
            let p = gesture(&mut r, &mut t);
            r.result(
                p["id"].as_u64().unwrap(),
                Outcome::Submitted,
                t,
                &UserDictionary::default(),
            );
        }
        assert_eq!(
            r.suggestions(&UserDictionary::default())["items"][0]["kind"],
            "exclusion"
        );
        let mut r = Runtime::default();
        for _ in 0..3 {
            r.reset();
            word(&mut r, "пшерги", &mut t);
            t += 1;
            event(&mut r, "space", "down", None, t, false);
            t += 1;
            event(&mut r, "space", "up", None, t, false);
            let p = gesture(&mut r, &mut t);
            r.result(
                p["id"].as_u64().unwrap(),
                Outcome::Submitted,
                t,
                &UserDictionary::default(),
            );
        }
        assert_eq!(
            r.suggestions(&UserDictionary::default())["items"][0]["word"],
            "github"
        );
        let p = gesture(&mut r, &mut t);
        r.result(
            p["id"].as_u64().unwrap(),
            Outcome::Submitted,
            t,
            &UserDictionary::default(),
        );
        assert_eq!(
            r.suggestions(&UserDictionary::default())["items"],
            json!([])
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
    fn shared_feedback_fixtures() {
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
                            r.result(id, Outcome::Submitted, 0, &UserDictionary::default());
                        }
                    }
                }
            }
            let actual = r.suggestions(&UserDictionary::default())["items"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| json!([p["kind"], p["word"]]))
                .collect::<Vec<_>>();
            assert_eq!(json!(actual), case["expected"], "{}", case["name"]);
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
                Outcome::Verified,
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
                Outcome::Verified,
                t + 2500,
                &UserDictionary::default()
            )["status"],
            "verified"
        );
        assert_eq!(gesture(&mut r, &mut t)["replacement"], "ghbdtn");
    }
    #[test]
    fn dismiss_survives_eviction_and_clock_or_context_never_teaches() {
        let mut r = Runtime::default();
        for _ in 0..3 {
            r.record("ghbdtn", "привет", "exclusion");
        }
        let id = r.proposals[0].id;
        r.dismiss(id);
        for n in 0..100 {
            r.record(&format!("word{n}"), "слово", "word");
        }
        assert!(r.record("ghbdtn", "привет", "exclusion").is_none());
        assert_eq!(r.proposals.len(), 64);
        assert_eq!(r.dismiss(id)["status"], "stale");
    }
}
