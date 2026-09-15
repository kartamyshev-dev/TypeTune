//! Conservative context preflight. Passing this check is not authorization to
//! edit: an executor must still verify suffix, origin, modifiers and interleaving.
use serde::Serialize;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "state", content = "value", rename_all = "snake_case")]
pub enum Knowledge<T> {
    Known(T),
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "state", content = "reason", rename_all = "snake_case")]
pub enum Capability {
    Available,
    Limited(String),
    Unavailable(String),
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TextCapabilities {
    pub observe_committed_text: Capability,
    pub read_layout: Capability,
    pub read_focus: Capability,
    pub detect_sensitive_field: Capability,
    pub replace_range: Capability,
    pub inject_unicode: Capability,
}

impl Default for TextCapabilities {
    fn default() -> Self {
        Self {
            observe_committed_text: Capability::Unknown,
            read_layout: Capability::Unknown,
            read_focus: Capability::Unknown,
            detect_sensitive_field: Capability::Unknown,
            replace_range: Capability::Unknown,
            inject_unicode: Capability::Unknown,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ContextSnapshot {
    /// Backend generation: changes on focus/layout changes, loss or reconnect.
    pub epoch: u64,
    #[serde(skip)]
    pub captured_at: Instant,
    /// Opaque target identity; never an application title or text contents.
    pub target: Knowledge<u64>,
    pub unlocked: Knowledge<bool>,
    pub sensitive: Knowledge<bool>,
    pub selection_empty: Knowledge<bool>,
    pub composing: Knowledge<bool>,
    pub layout: Knowledge<String>,
}

impl ContextSnapshot {
    pub fn unknown(epoch: u64, now: Instant) -> Self {
        Self {
            epoch,
            captured_at: now,
            target: Knowledge::Unknown,
            unlocked: Knowledge::Unknown,
            sensitive: Knowledge::Unknown,
            selection_empty: Knowledge::Unknown,
            composing: Knowledge::Unknown,
            layout: Knowledge::Unknown,
        }
    }

    /// Strict keymap-inferred profile. Limited app exceptions need their own
    /// accepted policy; neither a manual shortcut nor a portal version grants it.
    pub fn replacement_blockers(
        &self,
        capabilities: &TextCapabilities,
        expected_epoch: u64,
        now: Instant,
        max_age: Duration,
    ) -> Vec<Blocker> {
        let mut reasons = Vec::new();
        if self.epoch != expected_epoch {
            reasons.push(Blocker::ContextChanged);
        }
        if !now
            .checked_duration_since(self.captured_at)
            .is_some_and(|age| age < max_age)
        {
            reasons.push(Blocker::StaleContext);
        }
        if self.target == Knowledge::Unknown || capabilities.read_focus != Capability::Available {
            reasons.push(Blocker::FocusUnknown);
        }
        if self.unlocked != Knowledge::Known(true) {
            reasons.push(Blocker::LockedOrUnknown);
        }
        if self.sensitive != Knowledge::Known(false) {
            reasons.push(Blocker::SensitiveOrUnknown);
        }
        if self.selection_empty != Knowledge::Known(true) {
            reasons.push(Blocker::SelectionPresentOrUnknown);
        }
        if self.composing != Knowledge::Known(false) {
            reasons.push(Blocker::CompositionActiveOrUnknown);
        }
        if !matches!(&self.layout, Knowledge::Known(id) if !id.is_empty())
            || capabilities.read_layout != Capability::Available
        {
            reasons.push(Blocker::LayoutUnknown);
        }
        if capabilities.inject_unicode != Capability::Available {
            reasons.push(Blocker::UnicodeUnavailable);
        }
        reasons
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Blocker {
    ContextChanged,
    StaleContext,
    FocusUnknown,
    LockedOrUnknown,
    SensitiveOrUnknown,
    SelectionPresentOrUnknown,
    CompositionActiveOrUnknown,
    LayoutUnknown,
    UnicodeUnavailable,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clock::{Clock, FakeClock};

    fn trusted(now: Instant) -> (ContextSnapshot, TextCapabilities) {
        let mut context = ContextSnapshot::unknown(4, now);
        context.target = Knowledge::Known(9);
        context.unlocked = Knowledge::Known(true);
        context.sensitive = Knowledge::Known(false);
        context.selection_empty = Knowledge::Known(true);
        context.composing = Knowledge::Known(false);
        context.layout = Knowledge::Known("test-keymap:group0".into());
        let capabilities = TextCapabilities {
            read_focus: Capability::Available,
            read_layout: Capability::Available,
            inject_unicode: Capability::Available,
            ..Default::default()
        };
        (context, capabilities)
    }
    fn blockers(c: &ContextSnapshot, caps: &TextCapabilities, now: Instant) -> Vec<Blocker> {
        c.replacement_blockers(caps, 4, now, Duration::from_millis(100))
    }
    #[test]
    fn each_unknown_context_guard_independently_refuses() {
        let now = Instant::now();
        let (c, caps) = trusted(now);
        assert!(blockers(&c, &caps, now).is_empty());
        let mut cases = Vec::new();
        let mut x = c.clone();
        x.target = Knowledge::Unknown;
        cases.push((x, Blocker::FocusUnknown));
        let mut x = c.clone();
        x.unlocked = Knowledge::Unknown;
        cases.push((x, Blocker::LockedOrUnknown));
        let mut x = c.clone();
        x.sensitive = Knowledge::Unknown;
        cases.push((x, Blocker::SensitiveOrUnknown));
        let mut x = c.clone();
        x.selection_empty = Knowledge::Unknown;
        cases.push((x, Blocker::SelectionPresentOrUnknown));
        let mut x = c.clone();
        x.composing = Knowledge::Unknown;
        cases.push((x, Blocker::CompositionActiveOrUnknown));
        let mut x = c;
        x.layout = Knowledge::Unknown;
        cases.push((x, Blocker::LayoutUnknown));
        for (context, reason) in cases {
            assert_eq!(blockers(&context, &caps, now), vec![reason]);
        }
    }
    #[test]
    fn lock_sensitive_selection_and_composition_refuse() {
        let now = Instant::now();
        let (mut c, caps) = trusted(now);
        c.unlocked = Knowledge::Known(false);
        c.sensitive = Knowledge::Known(true);
        c.selection_empty = Knowledge::Known(false);
        c.composing = Knowledge::Known(true);
        assert_eq!(
            blockers(&c, &caps, now),
            vec![
                Blocker::LockedOrUnknown,
                Blocker::SensitiveOrUnknown,
                Blocker::SelectionPresentOrUnknown,
                Blocker::CompositionActiveOrUnknown
            ]
        );
    }
    #[test]
    fn stale_future_and_changed_generation_refuse_with_fake_clock() {
        let clock = FakeClock::at_zero();
        let (mut c, caps) = trusted(clock.now());
        clock.advance(Duration::from_millis(100));
        assert_eq!(
            blockers(&c, &caps, clock.now()),
            vec![Blocker::StaleContext]
        );
        c.captured_at = clock.now() + Duration::from_millis(1);
        assert_eq!(
            blockers(&c, &caps, clock.now()),
            vec![Blocker::StaleContext]
        );
        c.captured_at = clock.now();
        c.epoch += 1;
        assert_eq!(
            blockers(&c, &caps, clock.now()),
            vec![Blocker::ContextChanged]
        );
    }
    #[test]
    fn limited_or_missing_unicode_is_not_permission_to_delete() {
        let now = Instant::now();
        let (c, mut caps) = trusted(now);
        for state in [
            Capability::Unknown,
            Capability::Limited("unverified portal".into()),
            Capability::Unavailable("no backend".into()),
        ] {
            caps.inject_unicode = state;
            assert_eq!(blockers(&c, &caps, now), vec![Blocker::UnicodeUnavailable]);
        }
    }
}
