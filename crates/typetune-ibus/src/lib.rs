//! Bounded in-process protocol for the experimental GI IBus adapter. No I/O,
//! callbacks, key mapping, or native editing here: the common engine owns plans.
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::{Duration, Instant};
use typetune_engine::{
    prepare_automatic_with_dictionary, prepare_manual, prepare_toggle, Direction, InFlight, Plan,
    Snapshot,
};

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
    },
    Cancel,
}
#[derive(Default)]
pub struct Bridge {
    dictionary: typetune_engine::UserDictionary,
    plan: Option<Plan>,
    flight: Option<InFlight>,
    deadline: Option<Instant>,
}
impl Bridge {
    fn cancel(&mut self) -> Value {
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
        match request {
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
                        &self.dictionary,
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
                match typetune_engine::inferred::suggest_with_dictionary(
                    &text,
                    automatic,
                    &self.dictionary,
                ) {
                    Some(candidate) => json!({"status":"inferred", "remove": candidate.remove,
                        "replacement":candidate.replacement, "mode":match candidate.direction {
                            Direction::UsToRu=>"ru",Direction::RuToUs=>"us"}}),
                    None => json!({"status":"ignored"}),
                }
            }
            Request::Configure { words, exclusions } => {
                if self.plan.is_some() || self.flight.is_some() {
                    return json!({"status":"busy"});
                }
                match typetune_engine::UserDictionary::new(words, exclusions) {
                    Ok(dictionary) => {
                        self.dictionary = dictionary;
                        json!({"status":"configured"})
                    }
                    Err(_) => json!({"status":"invalid-dictionary"}),
                }
            }
            Request::Cancel => self.cancel(),
        }
    }
}

#[no_mangle]
pub extern "C" fn typetune_ibus_new() -> *mut Bridge {
    Box::into_raw(Box::default())
}
/// # Safety
/// `handle` is an exclusively owned live result of typetune_ibus_new, freed once.
#[no_mangle]
pub unsafe extern "C" fn typetune_ibus_free(handle: *mut Bridge) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}
/// Returns response length, or zero for invalid buffers (transaction cancelled).
/// Buffer capacity is fixed by the ABI, preventing a state-changing retry on size.
/// # Safety
/// Handle is live and exclusively borrowed; input references `len` readable bytes;
/// output references at least 32768 writable bytes, disjoint from input and handle.
#[no_mangle]
pub unsafe extern "C" fn typetune_ibus_call(
    handle: *mut Bridge,
    input: *const u8,
    len: usize,
    output: *mut u8,
) -> usize {
    if handle.is_null() {
        return 0;
    }
    let bridge = &mut *handle;
    if input.is_null() || output.is_null() || len > 131072 {
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
}
