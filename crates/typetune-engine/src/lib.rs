//! Committed-text/range profile for cooperating editors. No keycode injection,
//! layout inference, clipboard, shell, network or global keyboard hooks.
mod automatic;
mod user_dictionary;
pub use user_dictionary::UserDictionary;
pub mod inferred;
mod manual;
pub use automatic::{prepare_automatic, prepare_automatic_with_dictionary, prepare_toggle};
pub use manual::{prepare_manual, Direction};

use std::ops::Range;
use std::time::{Duration, Instant};

pub const MAX_DOCUMENT_BYTES: usize = 16 * 1024;
pub const MAX_REPLACEMENT_BYTES: usize = 4096;

#[derive(Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub target: u64,
    pub epoch: u64,
    pub revision: u64,
    pub text: String,
    /// Unicode scalar offsets, matching GtkTextBuffer offsets, NOT byte offsets
    /// or a count of Backspace presses.
    pub caret: usize,
    pub anchor: usize,
    pub focused: Option<bool>,
    pub normal_field: Option<bool>,
    pub composing: Option<bool>,
    pub modifiers_clear: Option<bool>,
    pub unicode_range: Option<bool>,
}
impl Snapshot {
    pub fn check(&self) -> Result<(), Rejection> {
        if self.text.len() > MAX_DOCUMENT_BYTES {
            return Err(Rejection::Limit);
        }
        if self.target == 0
            || self.focused != Some(true)
            || self.normal_field != Some(true)
            || self.composing != Some(false)
            || self.modifiers_clear != Some(true)
        {
            return Err(Rejection::Context);
        }
        if self.unicode_range != Some(true) {
            return Err(Rejection::Unsupported);
        }
        if self.caret != self.anchor {
            return Err(Rejection::Selection);
        }
        if self.caret > self.text.chars().count() {
            return Err(Rejection::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    CommittedUser,
    OwnReplacement,
    Unknown,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rejection {
    Context,
    Selection,
    Unsupported,
    InvalidRange,
    Limit,
    Changed,
    Expired,
    Origin,
    InvalidSnippet,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    Completed,
    FailedBeforeEdit(Rejection),
    IndeterminateAfterEdit,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApplyResult {
    Applied,
    Rejected(Rejection),
    Indeterminate,
}

/// Snapshot must be fresh; apply must recheck expected state immediately before
/// its first mutation. An indeterminate result must never trigger an automatic retry.
pub trait RangeEditor {
    fn snapshot(&self) -> Result<Snapshot, Rejection>;
    fn apply(&mut self, plan: &Plan, now: &dyn Fn() -> Instant) -> ApplyResult;
}

/// Move-only transaction. No Debug/Serialize implementation: content stays in RAM.
pub struct Plan {
    before: Snapshot,
    range: Range<usize>,
    replacement: String,
    after_text: String,
    after_caret: usize,
    created: Instant,
    ttl: Duration,
}
impl Plan {
    pub fn expired(&self, now: Instant) -> bool {
        !now.checked_duration_since(self.created)
            .is_some_and(|age| age < self.ttl)
    }
    pub fn before(&self) -> &Snapshot {
        &self.before
    }
    pub fn range(&self) -> Range<usize> {
        self.range.clone()
    }
    pub fn replacement(&self) -> &str {
        &self.replacement
    }
}

pub struct StaticSnippet {
    suffix: String,
    replacement: String,
}
impl StaticSnippet {
    pub fn new(trigger: &str, replacement: &str) -> Result<Self, Rejection> {
        if !trigger.starts_with(':')
            || trigger.chars().count() < 2
            || trigger.chars().count() > 64
            || trigger.chars().any(|c| c.is_whitespace() || c == '\0')
            || replacement.contains('\0')
        {
            return Err(Rejection::InvalidSnippet);
        }
        if replacement.len() + 1 > MAX_REPLACEMENT_BYTES {
            return Err(Rejection::Limit);
        }
        Ok(Self {
            suffix: format!("{trigger} "),
            replacement: format!("{replacement} "),
        })
    }

    /// The delimiter Space is already in the application. Enter/Tab and own
    /// output never create a plan. No separate shadow history in this range profile.
    pub fn prepare(
        &self,
        snapshot: Snapshot,
        origin: Origin,
        now: Instant,
        ttl: Duration,
    ) -> Result<Option<Plan>, Rejection> {
        if origin != Origin::CommittedUser {
            return Err(Rejection::Origin);
        }
        snapshot.check()?;
        let end_byte =
            byte_offset(&snapshot.text, snapshot.caret).ok_or(Rejection::InvalidRange)?;
        let prefix = &snapshot.text[..end_byte];
        let Some(before_trigger) = prefix.strip_suffix(&self.suffix) else {
            return Ok(None);
        };
        if before_trigger
            .chars()
            .next_back()
            .is_some_and(|c| !c.is_whitespace())
        {
            return Ok(None);
        }
        let range = before_trigger.chars().count()..snapshot.caret;
        let after_text = replace_chars(&snapshot.text, range.clone(), &self.replacement)?;
        let after_caret = range.start + self.replacement.chars().count();
        Ok(Some(Plan {
            before: snapshot,
            range,
            replacement: self.replacement.clone(),
            after_text,
            after_caret,
            created: now,
            ttl,
        }))
    }
}

pub fn byte_offset(text: &str, scalar: usize) -> Option<usize> {
    text.char_indices()
        .map(|(i, _)| i)
        .chain(std::iter::once(text.len()))
        .nth(scalar)
}
pub fn replace_chars(
    text: &str,
    range: Range<usize>,
    replacement: &str,
) -> Result<String, Rejection> {
    if range.start > range.end {
        return Err(Rejection::InvalidRange);
    }
    let start = byte_offset(text, range.start).ok_or(Rejection::InvalidRange)?;
    let end = byte_offset(text, range.end).ok_or(Rejection::InvalidRange)?;
    if text.len() - (end - start) + replacement.len() > MAX_DOCUMENT_BYTES {
        return Err(Rejection::Limit);
    }
    Ok(format!("{}{}{}", &text[..start], replacement, &text[end..]))
}

/// An edit authorized against a fresh snapshot. Async backends retain this value
/// until readback or timeout; dropping it never authorizes a retry.
pub struct InFlight {
    plan: Plan,
}
impl InFlight {
    pub fn begin(plan: Plan, current: &Snapshot, now: Instant) -> Result<Self, Rejection> {
        if plan.expired(now) {
            return Err(Rejection::Expired);
        }
        if *current != plan.before || current.check().is_err() {
            return Err(Rejection::Changed);
        }
        Ok(Self { plan })
    }
    pub fn plan(&self) -> &Plan {
        &self.plan
    }
    pub fn confirms(&self, after: &Snapshot) -> bool {
        after.check().is_ok()
            && after.target == self.plan.before.target
            && after.epoch == self.plan.before.epoch
            && after.revision > self.plan.before.revision
            && after.text == self.plan.after_text
            && after.caret == self.plan.after_caret
            && after.anchor == self.plan.after_caret
    }
    pub fn finish(self, after: Option<&Snapshot>) -> Outcome {
        if after.is_some_and(|s| self.confirms(s)) {
            Outcome::Completed
        } else {
            Outcome::IndeterminateAfterEdit
        }
    }
}

pub fn execute(editor: &mut impl RangeEditor, plan: Plan, now: impl Fn() -> Instant) -> Outcome {
    // Preserve expiration precedence even when snapshot acquisition fails.
    if plan.expired(now()) {
        return Outcome::FailedBeforeEdit(Rejection::Expired);
    }
    let current = match editor.snapshot() {
        Ok(s) => s,
        Err(_) => return Outcome::FailedBeforeEdit(Rejection::Changed),
    };
    let edit = match InFlight::begin(plan, &current, now()) {
        Ok(edit) => edit,
        Err(reason) => return Outcome::FailedBeforeEdit(reason),
    };
    match editor.apply(edit.plan(), &now) {
        ApplyResult::Rejected(reason) => Outcome::FailedBeforeEdit(reason),
        ApplyResult::Indeterminate => edit.finish(None),
        ApplyResult::Applied => edit.finish(editor.snapshot().ok().as_ref()),
    }
}

#[cfg(test)]
mod tests;
