//! Bounded in-process protocol for the Python frontend. No I/O,
//! callbacks, key mapping, or native editing here: the common engine owns plans.
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::{Duration, Instant};
use typetune_engine::{
    prepare_automatic_with_dictionary, prepare_manual, prepare_toggle, AutoPolicy, Direction,
    InFlight, Plan, Snapshot,
};
mod runtime;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct State {
    target: u64,
    epoch: u64,
    revision: u64,
    text: String,
    caret: usize,
    anchor: usize,
    focused: Option<bool>,
    normal_field: Option<bool>,
    composing: Option<bool>,
    modifiers_clear: Option<bool>,
    unicode_range: Option<bool>,
}
impl From<State> for Snapshot {
    fn from(s: State) -> Self {
        Self {
            target: s.target,
            epoch: s.epoch,
            revision: s.revision,
            text: s.text,
            caret: s.caret,
            anchor: s.anchor,
            focused: s.focused,
            normal_field: s.normal_field,
            composing: s.composing,
            modifiers_clear: s.modifiers_clear,
            unicode_range: s.unicode_range,
        }
    }
}
#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Protocol,
    KeyEvent {
        event: runtime::Event,
        automatic: bool,
        #[serde(default = "default_true")]
        manual: bool,
    },
    ResetContext,
    EditResult {
        id: u64,
        outcome: runtime::Outcome,
        time_ms: u64,
    },
    /// Host reports a TIS layout change (own or user) for anti-loop.
    LayoutNotice {
        source: String,
        layout: String,
    },
    LearnedAdd {
        word: String,
    },
    LearnedClear,
    Prepare {
        state: State,
        reverse: bool,
    },
    Smart {
        state: State,
        automatic: bool,
    },
    Authorize {
        state: State,
    },
    Observe {
        state: State,
    },
    Infer {
        text: String,
        automatic: bool,
    },
    Configure {
        words: Vec<String>,
        exclusions: Vec<String>,
        #[serde(default)]
        learned: Vec<String>,
        #[serde(default)]
        policy: PolicyDto,
    },
    /// Replace vocabulary without disturbing an edit or a Double Shift gesture.
    DictionaryUpdate {
        words: Vec<String>,
        exclusions: Vec<String>,
        #[serde(default)]
        learned: Vec<String>,
    },
    Cancel,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PolicyDto {
    #[serde(default = "default_true")]
    switch_only_last_word: bool,
    #[serde(default)]
    dont_switch_words: bool,
    #[serde(default = "default_true")]
    dont_correct_after_layout_change: bool,
}
impl Default for PolicyDto {
    fn default() -> Self {
        let policy = AutoPolicy::default();
        Self {
            switch_only_last_word: policy.switch_only_last_word,
            dont_switch_words: policy.dont_switch_words,
            dont_correct_after_layout_change: policy.dont_correct_after_layout_change,
        }
    }
}
fn default_true() -> bool {
    true
}
impl From<PolicyDto> for AutoPolicy {
    fn from(p: PolicyDto) -> Self {
        Self {
            switch_only_last_word: p.switch_only_last_word,
            dont_switch_words: p.dont_switch_words,
            dont_correct_after_layout_change: p.dont_correct_after_layout_change,
        }
    }
}
#[derive(Default)]
pub struct Bridge {
    runtime: runtime::Runtime,
    policy: AutoPolicy,
    plan: Option<Plan>,
    flight: Option<InFlight>,
    deadline: Option<Instant>,
}
impl Bridge {
    /// Learned words currently used by the runtime's effective dictionary.
    pub fn learned_words(&self) -> &[String] {
        self.runtime.learned_words()
    }
    /// Soft exclusions from reverse undo (never logged as typed text).
    pub fn soft_exclusions(&self) -> &[String] {
        self.runtime.exclusions()
    }
    fn cancel(&mut self) -> Value {
        self.runtime.reset();
        self.plan = None;
        self.deadline = None;
        json!({"status": if self.flight.take().is_some() { "indeterminate" } else { "rejected" }})
    }
    fn request(&mut self, bytes: &[u8], now: Instant) -> Value {
        let Ok(request) = serde_json::from_slice::<Request>(bytes) else {
            return self.cancel();
        };
        if self.deadline.is_some_and(|deadline| now >= deadline) {
            return self.cancel();
        }
        if self.runtime.is_pending()
            && matches!(
                request,
                Request::Prepare { .. } | Request::Smart { .. } | Request::Infer { .. }
            )
        {
            return self.cancel();
        }
        match request {
            Request::Protocol => {
                json!({"version":3,"profile":"lang-id-aggressive","max_response_bytes":32768})
            }
            Request::KeyEvent {
                event,
                automatic,
                manual,
            } => {
                if self.plan.is_some() || self.flight.is_some() {
                    return self.cancel();
                }
                self.runtime.event(event, automatic, manual)
            }
            Request::ResetContext => {
                self.runtime.reset();
                json!({"status":"reset"})
            }
            Request::EditResult {
                id,
                outcome,
                time_ms,
            } => self.runtime.result(id, outcome, time_ms),
            Request::LayoutNotice { source, layout } => {
                self.runtime.layout_notice(&source, &layout)
            }
            Request::LearnedAdd { word } => self.runtime.learn_add(word),
            Request::LearnedClear => self.runtime.learn_clear(),
            Request::Prepare { state, reverse } => {
                // Never replace an outstanding transaction with a new one.
                if self.plan.is_some() || self.flight.is_some() {
                    return self.cancel();
                }
                match prepare_manual(
                    state.into(),
                    if reverse {
                        Direction::RuToUs
                    } else {
                        Direction::UsToRu
                    },
                    now,
                    Duration::from_millis(500),
                ) {
                    Ok(plan) => {
                        self.plan = Some(plan);
                        self.deadline = Some(now + Duration::from_millis(500));
                        json!({"status":"ready"})
                    }
                    Err(reason) => json!({"status":"rejected", "reason":format!("{reason:?}")}),
                }
            }
            Request::Smart { state, automatic } => {
                if self.plan.is_some() || self.flight.is_some() {
                    return self.cancel();
                }
                let result = if automatic {
                    prepare_automatic_with_dictionary(
                        state.into(),
                        now,
                        Duration::from_millis(500),
                        self.runtime.dictionary(),
                    )
                } else {
                    prepare_toggle(state.into(), now, Duration::from_millis(500)).map(Some)
                };
                match result {
                    Ok(Some((plan, direction))) => {
                        self.plan = Some(plan);
                        self.deadline = Some(now + Duration::from_millis(500));
                        json!({"status":"ready", "mode":match direction {Direction::UsToRu=>"ru",Direction::RuToUs=>"us"}})
                    }
                    Ok(None) => json!({"status":"ignored"}),
                    Err(reason) => json!({"status":"rejected", "reason":format!("{reason:?}")}),
                }
            }
            Request::Authorize { state } => {
                let Some(plan) = self.plan.take() else {
                    return self.cancel();
                };
                match InFlight::begin(plan, &state.into(), now) {
                    Ok(edit) => {
                        let plan = edit.plan();
                        if plan.range().end != plan.before().caret {
                            return self.cancel();
                        }
                        let response = json!({"status":"edit", "offset":plan.range().start as i64 - plan.before().caret as i64,
                            "length":plan.range().len(), "replacement":plan.replacement()});
                        self.flight = Some(edit);
                        response
                    }
                    Err(reason) => {
                        self.deadline = None;
                        json!({"status":"rejected", "reason":format!("{reason:?}")})
                    }
                }
            }
            Request::Observe { state } => {
                let state = Snapshot::from(state);
                let Some(edit) = &self.flight else {
                    return self.cancel();
                };
                if edit.confirms(&state) {
                    self.flight.take().unwrap().finish(Some(&state));
                    self.deadline = None;
                    json!({"status":"completed"})
                } else if state.target != edit.plan().before().target
                    || state.epoch != edit.plan().before().epoch
                    || state.check().is_err()
                {
                    self.cancel()
                } else {
                    json!({"status":"pending"})
                }
            }
            Request::Infer { text, automatic } => {
                // Never claim committed text or create a range Plan for key history.
                if self.plan.is_some() || self.flight.is_some() {
                    return self.cancel();
                }
                match typetune_engine::inferred::suggest_with_policy(
                    &text,
                    automatic,
                    self.runtime.dictionary(),
                    &self.policy,
                ) {
                    Some(candidate) => json!({"status":"inferred", "remove": candidate.remove,
                        "replacement":candidate.replacement, "layout_only":candidate.layout_only,
                        "mode":match candidate.direction {
                            Direction::UsToRu=>"ru",Direction::RuToUs=>"us"}}),
                    None => json!({"status":"ignored"}),
                }
            }
            Request::Configure {
                words,
                exclusions,
                learned,
                policy,
            } => {
                if self.plan.is_some() || self.flight.is_some() || self.runtime.is_pending() {
                    return json!({"status":"busy"});
                }
                let policy = policy.into();
                match self.runtime.configure(words, exclusions, learned, policy) {
                    Ok(()) => {
                        self.policy = policy;
                        json!({"status":"configured"})
                    }
                    Err(_) => json!({"status":"invalid-dictionary"}),
                }
            }
            Request::DictionaryUpdate {
                words,
                exclusions,
                learned,
            } => match self.runtime.update_dictionary(words, exclusions, learned) {
                Ok(()) => json!({"status":"dictionary_updated"}),
                Err(_) => json!({"status":"invalid-dictionary"}),
            },
            Request::Cancel => self.cancel(),
        }
    }
}

#[no_mangle]
pub extern "C" fn typetune_bridge_new() -> *mut Bridge {
    Box::into_raw(Box::default())
}
/// # Safety
/// `handle` is an exclusively owned live result of typetune_bridge_new, freed once.
#[no_mangle]
pub unsafe extern "C" fn typetune_bridge_free(handle: *mut Bridge) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}
/// Returns response length, or zero for invalid buffers (transaction cancelled).
/// Buffer capacity is fixed by the ABI, preventing a state-changing retry on size.
/// Input `len` must be ≤ 524288 bytes (512 KiB); output must have ≥ 32768 bytes.
/// # Safety
/// Handle is live and exclusively borrowed; input references `len` readable bytes;
/// output references at least 32768 writable bytes, disjoint from input and handle.
#[no_mangle]
pub unsafe extern "C" fn typetune_bridge_call(
    handle: *mut Bridge,
    input: *const u8,
    len: usize,
    output: *mut u8,
) -> usize {
    if handle.is_null() {
        return 0;
    }
    let bridge = &mut *handle;
    if input.is_null() || output.is_null() || len > 524288 {
        bridge.cancel();
        return 0;
    }
    let result = bridge.request(std::slice::from_raw_parts(input, len), Instant::now());
    let bytes = serde_json::to_vec(&result).expect("JSON value serialization");
    if bytes.len() > 32768 {
        bridge.cancel();
        return 0;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
    bytes.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state(text: &str, revision: u64) -> Value {
        json!({"target":1,"epoch":1,"revision":revision,"text":text,"caret":text.chars().count(),"anchor":text.chars().count(),
            "focused":true,"normal_field":true,"composing":false,"modifiers_clear":true,"unicode_range":true})
    }
    fn call(b: &mut Bridge, value: Value, now: Instant) -> Value {
        b.request(&serde_json::to_vec(&value).unwrap(), now)
    }
    fn key(
        b: &mut Bridge,
        time: &mut u64,
        key: &str,
        action: &str,
        text: Option<&str>,
        manual: Option<bool>,
    ) -> Value {
        *time += 1;
        let mut request = json!({"op":"key_event","automatic":true,"event":{
            "key":key,"action":action,"text":text,"time_ms":*time,
            "device":null,"origin":"physical","modifiers":0
        }});
        if let Some(manual) = manual {
            request["manual"] = json!(manual);
        }
        call(b, request, Instant::now())
    }
    fn type_word(b: &mut Bridge, time: &mut u64, word: &str) {
        for letter in word.chars() {
            key(b, time, "letter", "down", Some(&letter.to_string()), None);
            key(b, time, "letter", "up", None, None);
        }
    }
    fn double_shift(b: &mut Bridge, time: &mut u64, manual: Option<bool>) -> Value {
        for action in ["down", "up", "down"] {
            key(b, time, "left_shift", action, None, manual);
        }
        key(b, time, "left_shift", "up", None, manual)
    }
    fn result(b: &mut Bridge, edit: &Value, outcome: &str, time: u64) -> Value {
        call(
            b,
            json!({"op":"edit_result","id":edit["id"],"outcome":outcome,"time_ms":time}),
            Instant::now(),
        )
    }
    fn infer(b: &mut Bridge, word: &str) -> Value {
        call(
            b,
            json!({"op":"infer","text":word,"automatic":true}),
            Instant::now(),
        )
    }
    fn authorize(b: &mut Bridge, now: Instant) -> Value {
        assert_eq!(
            call(
                b,
                json!({"op":"prepare","state":state("ghbdtn",1),"reverse":false}),
                now
            )["status"],
            "ready"
        );
        call(b, json!({"op":"authorize","state":state("ghbdtn",1)}), now)
    }
    #[test]
    fn asynchronous_delete_then_unicode_readback() {
        let mut b = Bridge::default();
        let now = Instant::now();
        let edit = authorize(&mut b, now);
        assert_eq!(
            edit,
            json!({"status":"edit","offset":-6,"length":6,"replacement":"привет"})
        );
        assert_eq!(
            call(&mut b, json!({"op":"observe","state":state("",2)}), now)["status"],
            "pending"
        );
        assert_eq!(
            call(
                &mut b,
                json!({"op":"observe","state":state("привет",3)}),
                now
            )["status"],
            "completed"
        );
        assert_eq!(
            call(
                &mut b,
                json!({"op":"authorize","state":state("ghbdtn",1)}),
                now
            )["status"],
            "rejected"
        );
    }
    #[test]
    fn partial_timeout_is_indeterminate_and_never_retried() {
        let mut b = Bridge::default();
        let now = Instant::now();
        authorize(&mut b, now);
        assert_eq!(
            call(
                &mut b,
                json!({"op":"observe","state":state("",2)}),
                now + Duration::from_millis(500)
            )["status"],
            "indeterminate"
        );
        assert_eq!(
            call(
                &mut b,
                json!({"op":"authorize","state":state("ghbdtn",1)}),
                now
            )["status"],
            "rejected"
        );
    }
    #[test]
    fn stale_focus_selection_unknown_and_expiry_refuse_before_edit() {
        let now = Instant::now();
        for field in [
            "target",
            "epoch",
            "anchor",
            "normal_field",
            "composing",
            "revision",
            "expiry",
        ] {
            let mut b = Bridge::default();
            call(
                &mut b,
                json!({"op":"prepare","state":state("ghbdtn",1),"reverse":false}),
                now,
            );
            let mut s = state("ghbdtn", 1);
            match field {
                "target" | "epoch" | "revision" => s[field] = json!(2),
                "anchor" => s[field] = json!(0),
                "expiry" => {}
                _ => s[field] = Value::Null,
            }
            let later = if field == "expiry" {
                now + Duration::from_millis(500)
            } else {
                now
            };
            assert_eq!(
                call(&mut b, json!({"op":"authorize","state":s}), later)["status"],
                "rejected"
            );
        }
    }
    #[test]
    fn focus_loss_and_bad_protocol_after_edit_are_indeterminate() {
        let now = Instant::now();
        let mut b = Bridge::default();
        authorize(&mut b, now);
        let mut s = state("привет", 2);
        s["epoch"] = json!(2);
        assert_eq!(
            call(&mut b, json!({"op":"observe","state":s}), now)["status"],
            "indeterminate"
        );
        authorize(&mut b, now);
        assert_eq!(b.request(b"{}", now)["status"], "indeterminate");
    }

    #[test]
    fn input_len_boundary_is_524288_inclusive() {
        unsafe {
            let handle = typetune_bridge_new();
            let mut output = vec![0u8; 32768];
            // len == 524288 passes the ABI gate; invalid JSON → cancelled response.
            let at_limit = vec![b' '; 524288];
            let n = typetune_bridge_call(
                handle,
                at_limit.as_ptr(),
                at_limit.len(),
                output.as_mut_ptr(),
            );
            assert!(n > 0, "len==524288 must be accepted at the gate");
            // len == 524289 → immediate cancel with zero length.
            let over = vec![b'x'; 524289];
            let n2 = typetune_bridge_call(handle, over.as_ptr(), over.len(), output.as_mut_ptr());
            assert_eq!(n2, 0, "len==524289 must be refused");
            typetune_bridge_free(handle);
        }
    }

    #[test]
    fn dictionary_configuration_is_validated_and_never_replaces_pending_edit() {
        let now = Instant::now();
        let mut bridge = Bridge::default();
        let custom = json!({"op":"configure","words":["клавиатуры"],"exclusions":["привет"]});
        assert_eq!(
            call(&mut bridge, custom.clone(), now)["status"],
            "configured"
        );
        assert_eq!(
            call(
                &mut bridge,
                json!({"op":"infer","text":"rkfdbfnehs ","automatic":true}),
                now
            )["replacement"],
            "клавиатуры "
        );
        assert_eq!(
            call(
                &mut bridge,
                json!({"op":"configure","words":["bad word"],"exclusions":[]}),
                now
            )["status"],
            "invalid-dictionary"
        );
        assert_eq!(
            call(
                &mut bridge,
                json!({"op":"infer","text":"ghbdtn ","automatic":true}),
                now
            )["status"],
            "ignored"
        );
        assert_eq!(
            call(
                &mut bridge,
                json!({"op":"smart","state":state("rkfdbfnehs ",1),"automatic":true}),
                now
            )["status"],
            "ready"
        );
        assert_eq!(call(&mut bridge, custom, now)["status"], "busy");
        assert_eq!(
            call(
                &mut bridge,
                json!({"op":"authorize","state":state("rkfdbfnehs ",1)}),
                now
            )["replacement"],
            "клавиатуры "
        );
    }

    #[test]
    fn infer_respects_configured_policy() {
        let now = Instant::now();
        let mut b = Bridge::default();
        assert_eq!(
            call(
                &mut b,
                json!({"op":"configure","words":[],"exclusions":[],
                    "policy":{"switch_only_last_word":true,"dont_switch_words":true,
                        "dont_correct_after_layout_change":true}}),
                now
            )["status"],
            "configured"
        );
        let result = call(
            &mut b,
            json!({"op":"infer","text":"ghbdtn ","automatic":true}),
            now,
        );
        assert_eq!(result["status"], "inferred");
        assert_eq!(result["layout_only"], true);
        assert_eq!(result["remove"], 0);
        // Manual Double Shift still rewrites text under dont_switch_words.
        let manual = call(
            &mut b,
            json!({"op":"infer","text":"ghbdtn","automatic":false}),
            now,
        );
        assert_eq!(manual["status"], "inferred");
        assert_eq!(manual["layout_only"], false);
    }

    #[test]
    fn confirmed_feedback_changes_next_decision_without_breaking_retoggle() {
        let mut b = Bridge::default();
        let mut time = 0;
        type_word(&mut b, &mut time, "ghbdtn");
        let edit = key(&mut b, &mut time, "space", "down", None, None);
        assert_eq!(edit["replacement"], "привет ");
        let ack = result(&mut b, &edit, "verified", time);
        assert_eq!(ack["status"], "ok");
        assert_eq!(ack["feedback"]["learned_add"], json!(["привет"]));

        // Host persists the delta and synchronizes its canonical dictionary.
        // Neither that operation nor learning may clear last_auto or history.
        assert_eq!(
            call(
                &mut b,
                json!({"op":"dictionary_update","words":[],
                "learned":["привет"],"exclusions":[]}),
                Instant::now()
            )["status"],
            "dictionary_updated"
        );
        let undo = double_shift(&mut b, &mut time, None);
        assert_eq!(undo["replacement"], "ghbdtn ");
        let ack = result(&mut b, &undo, "verified", time);
        assert_eq!(ack["feedback"]["exclusions_add"], json!(["ghbdtn"]));

        // An immediate third gesture remains a normal manual rewrite.
        let again = double_shift(&mut b, &mut time, None);
        assert_eq!(again["replacement"], "привет ");
        assert_eq!(
            result(&mut b, &again, "verified", time),
            json!({"status":"ok"})
        );
        // Prove the exclusion itself is effective, not just learned source
        // protection that could otherwise conceal a stale exclusions dictionary.
        assert_eq!(
            call(&mut b, json!({"op":"learned_clear"}), Instant::now())["status"],
            "cleared"
        );
        type_word(&mut b, &mut time, "ghbdtn");
        assert_eq!(
            key(&mut b, &mut time, "space", "down", None, None)["status"],
            "ignored"
        );
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "ignored");
    }

    #[test]
    fn submitted_and_legacy_ok_preserve_history_without_durable_learning() {
        for outcome in ["submitted", "ok"] {
            let mut b = Bridge::default();
            let mut time = 0;
            type_word(&mut b, &mut time, "ghbdtn");
            let edit = key(&mut b, &mut time, "space", "down", None, None);
            assert_eq!(result(&mut b, &edit, outcome, time), json!({"status":"ok"}));
            assert!(b.learned_words().is_empty());
            let undo = double_shift(&mut b, &mut time, None);
            assert_eq!(undo["replacement"], "ghbdtn ");
            // Even a verified undo cannot turn an unverified auto into exclusion.
            let ack = result(&mut b, &undo, "verified", time);
            assert_eq!(ack["feedback"]["exclusions_add"], json!([]));
            assert!(b.soft_exclusions().is_empty());
        }
    }

    #[test]
    fn unsuccessful_results_and_unverified_undo_never_add_feedback() {
        for outcome in [
            "failed_before",
            "unknown_after",
            "rejected",
            "indeterminate",
        ] {
            let mut b = Bridge::default();
            let mut time = 0;
            type_word(&mut b, &mut time, "ghbdtn");
            let edit = key(&mut b, &mut time, "space", "down", None, None);
            assert_eq!(
                result(&mut b, &edit, outcome, time),
                json!({"status":"reset"})
            );
            assert!(b.learned_words().is_empty());
            assert!(b.soft_exclusions().is_empty());
        }
        let mut b = Bridge::default();
        let mut time = 0;
        type_word(&mut b, &mut time, "ghbdtn");
        let edit = key(&mut b, &mut time, "space", "down", None, None);
        result(&mut b, &edit, "verified", time);
        let undo = double_shift(&mut b, &mut time, None);
        assert_eq!(
            result(&mut b, &undo, "submitted", time),
            json!({"status":"ok"})
        );
        assert!(b.soft_exclusions().is_empty());
        assert_eq!(b.learned_words(), ["привет"]);
    }

    #[test]
    fn vocabulary_updates_are_atomic_and_preserve_pending_edits_and_gestures() {
        let mut b = Bridge::default();
        let mut time = 0;
        type_word(&mut b, &mut time, "ghbdtn");
        for action in ["down", "up", "down"] {
            key(&mut b, &mut time, "left_shift", action, None, None);
        }
        let update = json!({"op":"dictionary_update","words":[],"exclusions":["hello"]});
        assert_eq!(
            call(&mut b, update.clone(), Instant::now())["status"],
            "dictionary_updated"
        );
        let edit = key(&mut b, &mut time, "left_shift", "up", None, None);
        assert_eq!(edit["replacement"], "привет");
        assert_eq!(
            call(&mut b, update, Instant::now())["status"],
            "dictionary_updated"
        );
        assert_eq!(
            call(
                &mut b,
                json!({"op":"dictionary_update","words":["bad word"],
            "exclusions":[],"learned":[]}),
                Instant::now()
            )["status"],
            "invalid-dictionary"
        );
        assert_eq!(result(&mut b, &edit, "verified", time)["status"], "ok");
        assert_eq!(b.soft_exclusions(), ["hello"]);
        assert_eq!(
            double_shift(&mut b, &mut time, None)["replacement"],
            "ghbdtn"
        );
    }

    #[test]
    fn learned_add_clear_and_dictionary_clear_change_effective_dictionary() {
        let mut b = Bridge::default();
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "inferred");
        assert_eq!(
            call(
                &mut b,
                json!({"op":"learned_add","word":"ghbdtn"}),
                Instant::now()
            )["status"],
            "learned"
        );
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "ignored");
        assert_eq!(
            call(&mut b, json!({"op":"learned_clear"}), Instant::now())["status"],
            "cleared"
        );
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "inferred");
        assert_eq!(
            call(
                &mut b,
                json!({"op":"dictionary_update","words":[],"exclusions":["ghbdtn"]}),
                Instant::now()
            )["status"],
            "dictionary_updated"
        );
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "ignored");
        assert_eq!(
            call(
                &mut b,
                json!({"op":"dictionary_update","words":[],"exclusions":[]}),
                Instant::now()
            )["status"],
            "dictionary_updated"
        );
        assert_eq!(infer(&mut b, "ghbdtn ")["status"], "inferred");
    }

    #[test]
    fn manual_gate_preserves_word_and_old_requests_default_to_enabled() {
        let mut b = Bridge::default();
        let mut time = 0;
        type_word(&mut b, &mut time, "ghbdtn");
        assert_eq!(
            double_shift(&mut b, &mut time, Some(false))["status"],
            "ignored"
        );
        assert_eq!(
            double_shift(&mut b, &mut time, None)["replacement"],
            "привет"
        );
        let mut b = Bridge::default();
        type_word(&mut b, &mut time, "ghbdtn");
        double_shift(&mut b, &mut time, Some(false));
        assert_eq!(
            key(&mut b, &mut time, "space", "down", None, Some(false))["replacement"],
            "привет "
        );
    }

    #[test]
    fn missing_policy_and_empty_policy_have_the_same_defaults() {
        for policy in [None, Some(json!({}))] {
            let mut b = Bridge::default();
            let mut request = json!({"op":"configure","words":[],"exclusions":[]});
            if let Some(policy) = policy {
                request["policy"] = policy;
            }
            assert_eq!(
                call(&mut b, request, Instant::now())["status"],
                "configured"
            );
            assert_eq!(b.policy, AutoPolicy::default());
            call(
                &mut b,
                json!({"op":"layout_notice","source":"user","layout":"ru"}),
                Instant::now(),
            );
            let mut time = 0;
            type_word(&mut b, &mut time, "ghbdtn");
            assert_eq!(
                key(&mut b, &mut time, "space", "down", None, None)["status"],
                "ignored"
            );
            type_word(&mut b, &mut time, "ghbdtn");
            assert_eq!(
                key(&mut b, &mut time, "space", "down", None, None)["status"],
                "inferred_edit"
            );
        }
    }
}
