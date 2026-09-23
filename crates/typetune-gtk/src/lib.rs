//! Adapter for a newly created, cooperating plain GtkTextView. Not accessibility
//! automation of other applications. Snapshot strings are bounded and never logged.
use gtk::{glib, prelude::*};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use typetune_engine::{
    replace_chars, ApplyResult, Plan, RangeEditor, Rejection, Snapshot, MAX_DOCUMENT_BYTES,
};

struct State {
    epoch: Cell<u64>,
    revision: Cell<u64>,
    composing: Cell<bool>,
    modifiers_clear: Cell<Option<bool>>,
    applying: Cell<bool>,
    pending_space: Cell<bool>,
    snippet_installed: Cell<bool>,
    shortcuts_installed: Cell<bool>,
}
fn bump(cell: &Cell<u64>) {
    cell.set(
        cell.get()
            .checked_add(1)
            .expect("field generation exhausted"),
    );
}

pub struct ControlledField {
    view: gtk::TextView,
    window: gtk::Window,
    state: Rc<State>,
    target: u64,
}
impl ControlledField {
    /// target must uniquely identify this field within the owning runtime.
    pub fn new(window: &gtk::Window, target: u64) -> Self {
        assert_ne!(target, 0);
        let view = gtk::TextView::new();
        let state = Rc::new(State {
            epoch: Cell::new(1),
            revision: Cell::new(1),
            composing: Cell::new(false),
            modifiers_clear: Cell::new(None),
            applying: Cell::new(false),
            pending_space: Cell::new(false),
            snippet_installed: Cell::new(false),
            shortcuts_installed: Cell::new(false),
        });
        let s = state.clone();
        view.buffer().connect_changed(move |_| bump(&s.revision));
        let s = state.clone();
        view.buffer().connect_mark_set(move |_, _, mark| {
            if !s.applying.get()
                && matches!(mark.name().as_deref(), Some("insert" | "selection_bound"))
            {
                bump(&s.epoch);
            }
        });
        let s = state.clone();
        view.connect_has_focus_notify(move |_| {
            s.pending_space.set(false);
            bump(&s.epoch);
        });
        let s = state.clone();
        window.connect_is_active_notify(move |_| {
            s.pending_space.set(false);
            bump(&s.epoch);
        });
        let s = state.clone();
        view.connect_preedit_changed(move |_, text| {
            s.pending_space.set(false);
            s.composing.set(!text.is_empty());
            bump(&s.epoch);
        });
        let keys = gtk::EventControllerKey::new();
        let s = state.clone();
        keys.connect_key_pressed(move |controller, key, _, mods| {
            s.pending_space.set(
                key == gtk::gdk::Key::space
                    && mods.is_empty()
                    && controller.current_event().is_some(),
            );
            s.modifiers_clear.set(Some(mods.is_empty()));
            glib::Propagation::Proceed
        });
        let s = state.clone();
        keys.connect_key_released(move |_, _, _, mods| {
            s.pending_space.set(false);
            s.modifiers_clear.set(Some(mods.is_empty()));
        });
        keys.set_propagation_phase(gtk::PropagationPhase::Capture);
        view.add_controller(keys);
        Self {
            view,
            window: window.clone(),
            state,
            target,
        }
    }
    /// Install one static rule in this owned widget. Observe the committed buffer
    /// at end-user-action, only after an actual Space key event; own replacement,
    /// paste actions and arbitrary programmatic edits do not arm this observer.
    pub fn install_snippet(
        &self,
        snippet: typetune_engine::StaticSnippet,
        on_result: impl Fn(typetune_engine::Outcome) + 'static,
    ) -> Result<(), Rejection> {
        if self.state.snippet_installed.replace(true) {
            return Err(Rejection::InvalidSnippet);
        }
        let view = self.view.downgrade();
        let window = self.window.downgrade();
        let state = self.state.clone();
        let target = self.target;
        self.view.buffer().connect_end_user_action(move |_| {
            if state.applying.get() || !state.pending_space.replace(false) {
                return;
            }
            let (Some(view), Some(window)) = (view.upgrade(), window.upgrade()) else {
                return;
            };
            let mut field = ControlledField {
                view,
                window,
                state: state.clone(),
                target,
            };
            let result = field.snapshot().and_then(|snapshot| {
                snippet.prepare(
                    snapshot,
                    typetune_engine::Origin::CommittedUser,
                    std::time::Instant::now(),
                    std::time::Duration::from_millis(100),
                )
            });
            match result {
                Ok(Some(plan)) => on_result(typetune_engine::execute(
                    &mut field,
                    plan,
                    std::time::Instant::now,
                )),
                Err(reason) => on_result(typetune_engine::Outcome::FailedBeforeEdit(reason)),
                Ok(None) => {}
            }
        });
        Ok(())
    }
    /// Local F8 (US→RU) / F9 (RU→US), executed once on release. The plan
    /// captures the press-time context; repeats never refresh it or its deadline.
    pub fn install_correction_shortcuts(
        &self,
        on_result: impl Fn(typetune_engine::Outcome) + 'static,
    ) -> Result<(), Rejection> {
        if self.state.shortcuts_installed.replace(true) {
            return Err(Rejection::Unsupported);
        }
        let pending = Rc::new(RefCell::new(
            None::<(gtk::gdk::Key, Result<Plan, Rejection>)>,
        ));
        let held = Rc::new(Cell::new(0u8));
        let pressed = held.clone();
        let keys = gtk::EventControllerKey::new();
        keys.set_propagation_phase(gtk::PropagationPhase::Capture);
        let view = self.view.downgrade();
        let window = self.window.downgrade();
        let state = self.state.clone();
        let target = self.target;
        let p = pending.clone();
        keys.connect_key_pressed(move |controller, key, _, mods| {
            use gtk::gdk::Key;
            let direction = match key {
                Key::F8 => typetune_engine::Direction::UsToRu,
                Key::F9 => typetune_engine::Direction::RuToUs,
                _ => {
                    p.borrow_mut().take();
                    return glib::Propagation::Proceed;
                }
            };
            let bit = if key == Key::F8 { 1 } else { 2 };
            let previous = pressed.replace(pressed.get() | bit);
            if previous != 0 {
                if previous & bit == 0 {
                    p.borrow_mut().take();
                }
                return glib::Propagation::Stop;
            }
            p.borrow_mut().take();
            let (Some(view), Some(window)) = (view.upgrade(), window.upgrade()) else {
                return glib::Propagation::Proceed;
            };
            state.modifiers_clear.set(Some(mods.is_empty()));
            let field = ControlledField {
                view,
                window,
                state: state.clone(),
                target,
            };
            let plan = if controller.current_event().is_none() {
                Err(Rejection::Origin)
            } else {
                field.snapshot().and_then(|s| {
                    typetune_engine::prepare_manual(
                        s,
                        direction,
                        std::time::Instant::now(),
                        std::time::Duration::from_secs(1),
                    )
                })
            };
            *p.borrow_mut() = Some((key, plan));
            glib::Propagation::Stop
        });
        let view = self.view.downgrade();
        let window = self.window.downgrade();
        let state = self.state.clone();
        keys.connect_key_released(move |controller, key, _, mods| {
            let bit = match key {
                gtk::gdk::Key::F8 => 1,
                gtk::gdk::Key::F9 => 2,
                _ => 0,
            };
            held.set(held.get() & !bit);
            let Some((armed, plan)) = pending.borrow_mut().take() else {
                return;
            };
            if key != armed {
                return;
            }
            let (Some(view), Some(window)) = (view.upgrade(), window.upgrade()) else {
                return;
            };
            state.modifiers_clear.set(Some(mods.is_empty()));
            let mut field = ControlledField {
                view,
                window,
                state: state.clone(),
                target,
            };
            let outcome = if controller.current_event().is_none() || !mods.is_empty() {
                typetune_engine::Outcome::FailedBeforeEdit(Rejection::Context)
            } else {
                match plan {
                    Ok(plan) => typetune_engine::execute(&mut field, plan, std::time::Instant::now),
                    Err(reason) => typetune_engine::Outcome::FailedBeforeEdit(reason),
                }
            };
            on_result(outcome);
        });
        self.view.add_controller(keys);
        Ok(())
    }
    /// A local explicit command. The button preserves text focus on pointer
    /// clicks; keyboard activation with focus elsewhere fails the normal guard.
    pub fn correction_button(
        &self,
        label: &str,
        direction: typetune_engine::Direction,
        on_result: impl Fn(typetune_engine::Outcome) + 'static,
    ) -> gtk::Button {
        let button = gtk::Button::with_label(label);
        button.set_focus_on_click(false);
        let events = gtk::EventControllerLegacy::new();
        events.set_propagation_phase(gtk::PropagationPhase::Capture);
        let state = self.state.clone();
        events.connect_event(move |_, event| {
            let mut mods = event.modifier_state();
            mods.remove(
                gtk::gdk::ModifierType::BUTTON1_MASK
                    | gtk::gdk::ModifierType::BUTTON2_MASK
                    | gtk::gdk::ModifierType::BUTTON3_MASK
                    | gtk::gdk::ModifierType::BUTTON4_MASK
                    | gtk::gdk::ModifierType::BUTTON5_MASK,
            );
            state.modifiers_clear.set(Some(mods.is_empty()));
            bump(&state.epoch);
            glib::Propagation::Proceed
        });
        button.add_controller(events);
        let view = self.view.downgrade();
        let window = self.window.downgrade();
        let state = self.state.clone();
        let target = self.target;
        button.connect_clicked(move |_| {
            let (Some(view), Some(window)) = (view.upgrade(), window.upgrade()) else {
                return;
            };
            let mut field = ControlledField {
                view,
                window,
                state: state.clone(),
                target,
            };
            let plan = field.snapshot().and_then(|snapshot| {
                typetune_engine::prepare_manual(
                    snapshot,
                    direction,
                    std::time::Instant::now(),
                    std::time::Duration::from_millis(100),
                )
            });
            let outcome = match plan {
                Ok(plan) => typetune_engine::execute(&mut field, plan, std::time::Instant::now),
                Err(reason) => typetune_engine::Outcome::FailedBeforeEdit(reason),
            };
            on_result(outcome);
        });
        button
    }
    pub fn view(&self) -> &gtk::TextView {
        &self.view
    }
    pub fn applying(&self) -> bool {
        self.state.applying.get()
    }
    /// The cooperating host may supply a verified modifier snapshot with a
    /// committed input transaction; None invalidates it. No guessed default.
    pub fn record_modifiers(&self, clear: Option<bool>) {
        self.state.modifiers_clear.set(clear);
        bump(&self.state.epoch);
    }
}

struct Action {
    buffer: gtk::TextBuffer,
    state: Rc<State>,
}
impl Drop for Action {
    fn drop(&mut self) {
        self.buffer.end_user_action();
        self.state.applying.set(false);
    }
}
impl RangeEditor for ControlledField {
    fn snapshot(&self) -> Result<Snapshot, Rejection> {
        if self.view.input_purpose() != gtk::InputPurpose::FreeForm {
            return Err(Rejection::Context);
        }
        let b = self.view.buffer();
        if b.char_count() as usize > MAX_DOCUMENT_BYTES {
            return Err(Rejection::Limit);
        }
        let (start, end) = b.bounds();
        let text = b.text(&start, &end, true).to_string();
        if text.len() > MAX_DOCUMENT_BYTES {
            return Err(Rejection::Limit);
        }
        let caret = b.iter_at_mark(&b.get_insert()).offset() as usize;
        let anchor = b.iter_at_mark(&b.selection_bound()).offset() as usize;
        Ok(Snapshot {
            target: self.target,
            epoch: self.state.epoch.get(),
            revision: self.state.revision.get(),
            text,
            caret,
            anchor,
            focused: Some(self.view.has_focus() && self.window.is_active()),
            normal_field: Some(self.view.input_purpose() == gtk::InputPurpose::FreeForm),
            composing: Some(self.state.composing.get()),
            modifiers_clear: self.state.modifiers_clear.get(),
            unicode_range: Some(self.view.is_editable() && b.tag_table().size() == 0),
        })
    }
    fn apply(&mut self, plan: &Plan, now: &dyn Fn() -> std::time::Instant) -> ApplyResult {
        if self.state.applying.get() || self.snapshot().ok().as_ref() != Some(plan.before()) {
            return ApplyResult::Rejected(Rejection::Changed);
        }
        if let Err(reason) = plan.before().check() {
            return ApplyResult::Rejected(reason);
        }
        let b = self.view.buffer();
        let deleted = match replace_chars(&plan.before().text, plan.range(), "") {
            Ok(value) => value,
            Err(reason) => return ApplyResult::Rejected(reason),
        };
        self.state.applying.set(true);
        b.begin_user_action();
        let _action = Action {
            buffer: b.clone(),
            state: self.state.clone(),
        };
        // begin-user-action is a signal and may invoke cooperating application callbacks.
        if self.snapshot().ok().as_ref() != Some(plan.before()) {
            return ApplyResult::Rejected(Rejection::Changed);
        }
        if plan.expired(now()) {
            return ApplyResult::Rejected(Rejection::Expired);
        }
        let range = plan.range();
        b.delete(
            &mut b.iter_at_offset(range.start as i32),
            &mut b.iter_at_offset(range.end as i32),
        );
        // GTK delete/insert emit synchronous callbacks; grouping is not a transaction.
        // Stop after deletion if any callback changed content, focus or context.
        let after_delete = match self.snapshot() {
            Ok(s) => s,
            Err(_) => return ApplyResult::Indeterminate,
        };
        if after_delete.check().is_err()
            || after_delete.text != deleted
            || after_delete.caret != range.start
            || after_delete.epoch != plan.before().epoch
            || after_delete.revision != plan.before().revision + 1
        {
            return ApplyResult::Indeterminate;
        }
        if plan.expired(now()) {
            return ApplyResult::Indeterminate;
        }
        b.insert(
            &mut b.iter_at_offset(range.start as i32),
            plan.replacement(),
        );
        let after = match self.snapshot() {
            Ok(s) => s,
            Err(_) => return ApplyResult::Indeterminate,
        };
        if after.revision != plan.before().revision + 2 || after.epoch != plan.before().epoch {
            return ApplyResult::Indeterminate;
        }
        // The executor verifies final content, caret, selection and context after
        // end-user-action callbacks. No retry or guessed rollback on uncertainty.
        ApplyResult::Applied
    }
}
