//! GNOME 50 read-only bridge. Window focus is NOT text-field focus; an input
//! source identifier is NOT a complete keymap/modifier/composition snapshot.
use crate::{bounded, Probe, ProbeFailure};
use serde::{Deserialize, Serialize};
use zbus::Connection;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WindowBackend {
    Wayland,
    X11,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub protocol: u32,
    pub instance: String,
    pub generation: u64,
    pub source_generation: u64,
    pub source_type: String,
    pub source_id: String,
    pub xkb_id: String,
    pub window: u64,
    pub window_backend: WindowBackend,
    pub locked: bool,
    pub shield_active: bool,
    pub overview: bool,
    pub user_session: bool,
    pub external_source: bool,
}

impl Snapshot {
    pub fn parse(json: &str) -> Result<Self, ProbeFailure> {
        if json.len() > 4096 {
            return Err(ProbeFailure::InvalidReply);
        }
        let s: Self = serde_json::from_str(json).map_err(|_| ProbeFailure::InvalidReply)?;
        let uuid = s.instance.len() == 36
            && s.instance.bytes().enumerate().all(|(i, c)| {
                if [8, 13, 18, 23].contains(&i) {
                    c == b'-'
                } else {
                    c.is_ascii_hexdigit()
                }
            });
        let safe_number = |n| n > 0 && n <= 9_007_199_254_740_991;
        let clean = |value: &str| {
            value.len() <= 128
                && value
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"_+.:@/-".contains(&c))
        };
        let empty_source =
            s.source_type.is_empty() && s.source_id.is_empty() && s.xkb_id.is_empty();
        let valid_source = empty_source
            || (matches!(s.source_type.as_str(), "xkb" | "ibus")
                && !s.source_id.is_empty()
                && !s.xkb_id.is_empty());
        let restricted = s.locked || s.shield_active || s.overview || !s.user_session;
        if s.protocol != 1
            || !uuid
            || !safe_number(s.generation)
            || !safe_number(s.source_generation)
            || s.source_generation > s.generation
            || s.window > 9_007_199_254_740_991
            || ![&s.source_type, &s.source_id, &s.xkb_id]
                .into_iter()
                .all(|v| clean(v))
            || !valid_source
            || (restricted && (s.window != 0 || !empty_source))
            || (s.external_source && !empty_source)
            || (s.window == 0 && s.window_backend != WindowBackend::Unknown)
        {
            return Err(ProbeFailure::InvalidReply);
        }
        Ok(s)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Observation {
    /// Unique owner + instance scopes all window and generation identifiers.
    pub owner: String,
    pub snapshot: Snapshot,
}

pub async fn read(connection: &Connection) -> Probe<Observation> {
    bounded(async {
        let owner: String = connection
            .call_method(
                Some("org.freedesktop.DBus"),
                "/org/freedesktop/DBus",
                Some("org.freedesktop.DBus"),
                "GetNameOwner",
                &("org.gnome.Shell",),
            )
            .await?
            .body()?;
        // Pin to the resolved owner: never follow a replacement mid-request.
        let json: String = connection
            .call_method(
                Some(owner.as_str()),
                "/org/typetune/Session1",
                Some("org.typetune.Session1"),
                "GetSnapshot",
                &(),
            )
            .await?
            .body()?;
        let current_owner: String = connection
            .call_method(
                Some("org.freedesktop.DBus"),
                "/org/freedesktop/DBus",
                Some("org.freedesktop.DBus"),
                "GetNameOwner",
                &("org.gnome.Shell",),
            )
            .await?
            .body()?;
        if current_owner != owner {
            return Err(zbus::Error::InvalidReply);
        }
        let snapshot = Snapshot::parse(&json).map_err(|_| zbus::Error::InvalidReply)?;
        Ok(Observation { owner, snapshot })
    })
    .await
}

/// Consumer-side continuity tracking. Failures discard the snapshot immediately.
/// Consumers must additionally bound age and subscribe to Changed or poll before
/// using metadata. This type never authorizes edits or retains text history.
#[derive(Default)]
pub struct Tracker {
    pub epoch: u64,
    last: Option<Observation>,
}
impl Tracker {
    pub fn update(&mut self, result: Probe<Observation>) -> Probe<Observation> {
        let mut result = result;
        if let (Some(last), Probe::Observed(next)) = (&self.last, &result) {
            if last.owner == next.owner && last.snapshot.instance == next.snapshot.instance {
                let old = &last.snapshot;
                let new = &next.snapshot;
                if new.generation < old.generation
                    || new.source_generation < old.source_generation
                    || (new.generation == old.generation && new != old)
                {
                    result = Probe::Failed(ProbeFailure::InvalidReply);
                }
            }
        }
        let next = match &result {
            Probe::Observed(value) => Some(value.clone()),
            _ => None,
        };
        if next != self.last {
            self.epoch = self.epoch.checked_add(1).expect("session epoch exhausted");
        }
        self.last = next;
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample() -> Snapshot {
        Snapshot {
            protocol: 1,
            instance: "11111111-1111-4111-8111-111111111111".into(),
            generation: 1,
            source_generation: 1,
            source_type: "xkb".into(),
            source_id: "us".into(),
            xkb_id: "us".into(),
            window: 1,
            window_backend: WindowBackend::Wayland,
            locked: false,
            shield_active: false,
            overview: false,
            user_session: true,
            external_source: false,
        }
    }
    fn observed(snapshot: Snapshot) -> Probe<Observation> {
        Probe::Observed(Observation {
            owner: ":1.5".into(),
            snapshot,
        })
    }
    #[test]
    fn strict_protocol_rejects_unknown_version_fields_and_oversized_data() {
        let good = serde_json::to_string(&sample()).unwrap();
        assert!(Snapshot::parse(&good).is_ok());
        let mut s = sample();
        s.protocol = 2;
        assert!(Snapshot::parse(&serde_json::to_string(&s).unwrap()).is_err());
        assert!(Snapshot::parse(
            &good.replace("\"protocol\":1", "\"protocol\":1,\"text\":\"secret\"")
        )
        .is_err());
        assert!(Snapshot::parse(&" ".repeat(4097)).is_err());
    }
    #[test]
    fn locked_or_external_snapshot_cannot_leak_source() {
        for field in ["locked", "shield_active", "overview", "external_source"] {
            let mut value = serde_json::to_value(sample()).unwrap();
            value[field] = true.into();
            assert!(Snapshot::parse(&value.to_string()).is_err());
        }
        let mut s = sample();
        s.locked = true;
        s.window = 0;
        s.window_backend = WindowBackend::Unknown;
        s.source_type.clear();
        s.source_id.clear();
        s.xkb_id.clear();
        assert!(Snapshot::parse(&serde_json::to_string(&s).unwrap()).is_ok());
    }
    #[test]
    fn generation_and_instance_invalidate_even_if_window_returns() {
        let mut t = Tracker::default();
        t.update(observed(sample()));
        let first = t.epoch;
        let mut next = sample();
        next.generation = 3;
        t.update(observed(next.clone()));
        assert!(t.epoch > first);
        let before = t.epoch;
        next.instance = "22222222-2222-4222-8222-222222222222".into();
        next.generation = 1;
        assert!(matches!(t.update(observed(next)), Probe::Observed(_)));
        assert!(t.epoch > before);
    }
    #[test]
    fn loss_and_inconsistent_replies_discard_previous_metadata() {
        let mut t = Tracker::default();
        t.update(observed(sample()));
        let mut inconsistent = sample();
        inconsistent.window = 2;
        assert_eq!(
            t.update(observed(inconsistent)),
            Probe::Failed(ProbeFailure::InvalidReply)
        );
        assert!(t.last.is_none());
        t.update(observed(sample()));
        let before = t.epoch;
        t.update(Probe::Failed(ProbeFailure::Timeout));
        assert!(t.last.is_none());
        assert!(t.epoch > before);
    }
}
