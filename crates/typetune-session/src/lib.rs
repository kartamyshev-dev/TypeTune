//! Read-only Linux session diagnostics, independent of the physical input loop.
//! API advertisement is evidence, never a grant of text-editing capabilities.
pub mod bridge;
use serde::Serialize;
use std::future::Future;
use std::time::{Duration, Instant};
use typetune_core::session::{Blocker, Capability, ContextSnapshot, TextCapabilities};
use zbus::{zvariant::OwnedValue, Connection};

const PROBE_TIMEOUT: Duration = Duration::from_millis(750);
const DESKTOP: &str = "org.freedesktop.portal.Desktop";
const DESKTOP_PATH: &str = "/org/freedesktop/portal/desktop";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionHint {
    Wayland,
    X11,
    Unknown,
}
impl SessionHint {
    pub fn from_environment_value(value: Option<&str>) -> Self {
        match value {
            Some("wayland") => Self::Wayland,
            Some("x11") => Self::X11,
            _ => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProbeFailure {
    Timeout,
    PermissionDenied,
    Unavailable,
    InvalidReply,
    Transport,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "status", content = "value", rename_all = "snake_case")]
pub enum Probe<T> {
    Observed(T),
    Failed(ProbeFailure),
}

fn failure(error: &zbus::Error) -> ProbeFailure {
    match error {
        zbus::Error::MethodError(name, _, _) => match name.as_str() {
            "org.freedesktop.DBus.Error.AccessDenied" | "org.freedesktop.DBus.Error.AuthFailed" => {
                ProbeFailure::PermissionDenied
            }
            "org.freedesktop.DBus.Error.ServiceUnknown"
            | "org.freedesktop.DBus.Error.NameHasNoOwner"
            | "org.freedesktop.DBus.Error.UnknownMethod"
            | "org.freedesktop.DBus.Error.UnknownInterface"
            | "org.freedesktop.DBus.Error.UnknownProperty"
            | "org.freedesktop.DBus.Error.UnknownObject" => ProbeFailure::Unavailable,
            _ => ProbeFailure::Transport,
        },
        zbus::Error::Variant(_) | zbus::Error::InvalidReply => ProbeFailure::InvalidReply,
        _ => ProbeFailure::Transport,
    }
}

async fn bounded<T>(future: impl Future<Output = zbus::Result<T>>) -> Probe<T> {
    match tokio::time::timeout(PROBE_TIMEOUT, future).await {
        Ok(Ok(value)) => Probe::Observed(value),
        Ok(Err(error)) => Probe::Failed(failure(&error)),
        Err(_) => Probe::Failed(ProbeFailure::Timeout),
    }
}

async fn property(
    connection: &Connection,
    destination: &str,
    path: &str,
    interface: &str,
    name: &str,
) -> zbus::Result<OwnedValue> {
    connection
        .call_method(
            Some(destination),
            path,
            Some("org.freedesktop.DBus.Properties"),
            "Get",
            &(interface, name),
        )
        .await?
        .body()
}

async fn portal_version(connection: &Connection, interface: &str) -> Probe<u32> {
    bounded(async {
        let value = property(connection, DESKTOP, DESKTOP_PATH, interface, "version").await?;
        Ok(u32::try_from(value)?)
    })
    .await
}

#[derive(Debug, Serialize)]
pub struct PortalEvidence {
    pub remote_desktop_version: Probe<u32>,
    pub input_capture_version: Probe<u32>,
    pub global_shortcuts_version: Probe<u32>,
    /// No CreateSession/Start calls, consent dialogs or input/clipboard access.
    pub permission_requested: bool,
}

#[derive(Debug, Serialize)]
pub struct SessionReport {
    pub schema_version: u32,
    /// Environment is a routing hint, not a verified application backend.
    pub session_hint: SessionHint,
    pub xwayland_display_hint: bool,
    pub session_bus: Probe<bool>,
    pub gnome_shell_version: Probe<String>,
    /// GetActive describes the screen shield; false alone does not establish
    /// active-session ownership or safe context for text replacement.
    pub gnome_screen_shield_active: Probe<bool>,
    pub portals: PortalEvidence,
    pub gnome_bridge: Probe<bridge::Observation>,
    pub context: ContextSnapshot,
    pub text_capabilities: TextCapabilities,
    pub replacement_blockers: Vec<Blocker>,
    pub elapsed_ms: u128,
}

fn unsupported_capabilities() -> TextCapabilities {
    let missing = |reason: &str| Capability::Unavailable(reason.into());
    TextCapabilities {
        observe_committed_text: missing("No accepted committed-text observer"),
        read_layout: missing(
            "No live compositor keymap/group adapter; local XKB defaults are not evidence",
        ),
        read_focus: missing(
            "No accepted focused-field adapter; XWayland cannot stand in for native Wayland",
        ),
        detect_sensitive_field: missing("No accepted field-sensitivity adapter"),
        replace_range: missing("No accepted range replacement backend"),
        inject_unicode: missing(
            "No accepted Unicode backend; portal advertisement is not permission or delivery",
        ),
    }
}

impl SessionReport {
    fn empty(session_hint: SessionHint, display: bool, now: Instant) -> Self {
        let context = ContextSnapshot::unknown(0, now);
        let text_capabilities = unsupported_capabilities();
        let replacement_blockers =
            context.replacement_blockers(&text_capabilities, 0, now, Duration::from_secs(2));
        Self {
            schema_version: 1,
            gnome_bridge: Probe::Failed(ProbeFailure::Unavailable),
            session_hint,
            xwayland_display_hint: session_hint == SessionHint::Wayland && display,
            session_bus: Probe::Failed(ProbeFailure::Unavailable),
            gnome_shell_version: Probe::Failed(ProbeFailure::Unavailable),
            gnome_screen_shield_active: Probe::Failed(ProbeFailure::Unavailable),
            portals: PortalEvidence {
                remote_desktop_version: Probe::Failed(ProbeFailure::Unavailable),
                input_capture_version: Probe::Failed(ProbeFailure::Unavailable),
                global_shortcuts_version: Probe::Failed(ProbeFailure::Unavailable),
                permission_requested: false,
            },
            context,
            text_capabilities,
            replacement_blockers,
            elapsed_ms: 0,
        }
    }
}

/// One fresh snapshot per invocation. Nothing is cached after disconnect;
/// failures never reuse a prior unlocked state or layout. At most two bounded
/// rounds: connection, then concurrent metadata requests (750 ms each).
pub async fn probe() -> SessionReport {
    let hint =
        SessionHint::from_environment_value(std::env::var("XDG_SESSION_TYPE").ok().as_deref());
    let display = std::env::var("DISPLAY").is_ok_and(|value| !value.is_empty());
    let start = Instant::now();
    let mut report = SessionReport::empty(hint, display, start);
    match bounded(Connection::session()).await {
        Probe::Observed(connection) => {
            report.session_bus = Probe::Observed(true);
            let shell = bounded(async {
                let value = property(
                    &connection,
                    "org.gnome.Shell",
                    "/org/gnome/Shell",
                    "org.gnome.Shell",
                    "ShellVersion",
                )
                .await?;
                let version = String::try_from(value)?;
                // Report versions only, not arbitrary service strings.
                if version.len() > 64
                    || !version
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || ".-+_".contains(c))
                {
                    return Err(zbus::Error::InvalidReply);
                }
                Ok(version)
            });
            let shield = bounded(async {
                connection
                    .call_method(
                        Some("org.gnome.ScreenSaver"),
                        "/org/gnome/ScreenSaver",
                        Some("org.gnome.ScreenSaver"),
                        "GetActive",
                        &(),
                    )
                    .await?
                    .body::<bool>()
            });
            let (shell, shield, remote, capture, shortcuts, bridge) = tokio::join!(
                shell,
                shield,
                portal_version(&connection, "org.freedesktop.portal.RemoteDesktop"),
                portal_version(&connection, "org.freedesktop.portal.InputCapture"),
                portal_version(&connection, "org.freedesktop.portal.GlobalShortcuts"),
                bridge::read(&connection)
            );
            if let Probe::Observed(observation) = &bridge {
                let snapshot = &observation.snapshot;
                if !snapshot.source_id.is_empty() {
                    report.text_capabilities.read_layout = Capability::Limited(
                        "GNOME input source only; full keymap/modifiers and composition are not known".into());
                }
                report.text_capabilities.read_focus = Capability::Limited(
                    "GNOME window identity only; focused field is unknown".into(),
                );
            }
            report.gnome_bridge = bridge;
            report.gnome_shell_version = shell;
            report.gnome_screen_shield_active = shield;
            report.portals.remote_desktop_version = remote;
            report.portals.input_capture_version = capture;
            report.portals.global_shortcuts_version = shortcuts;
        }
        Probe::Failed(error) => report.session_bus = Probe::Failed(error),
    }
    report.elapsed_ms = start.elapsed().as_millis();
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use typetune_core::session::Knowledge;
    #[test]
    fn display_and_portal_advertisement_do_not_grant_native_text_access() {
        let mut report = SessionReport::empty(SessionHint::Wayland, true, Instant::now());
        report.portals.remote_desktop_version = Probe::Observed(2);
        report.gnome_screen_shield_active = Probe::Observed(false);
        assert!(report.xwayland_display_hint);
        assert_eq!(report.context.layout, Knowledge::Unknown);
        assert_eq!(report.context.unlocked, Knowledge::Unknown);
        assert!(report
            .replacement_blockers
            .contains(&Blocker::UnicodeUnavailable));
        assert!(report.replacement_blockers.contains(&Blocker::FocusUnknown));
    }
    #[test]
    fn backend_hints_stay_separate() {
        assert_eq!(
            SessionHint::from_environment_value(Some("wayland")),
            SessionHint::Wayland
        );
        assert_eq!(
            SessionHint::from_environment_value(Some("x11")),
            SessionHint::X11
        );
        assert_eq!(
            SessionHint::from_environment_value(None),
            SessionHint::Unknown
        );
        assert!(
            !SessionReport::empty(SessionHint::X11, true, Instant::now()).xwayland_display_hint
        );
    }
    #[tokio::test(start_paused = true)]
    async fn stalled_probe_expires_without_reusing_state() {
        let result: Probe<bool> = bounded(std::future::pending()).await;
        assert_eq!(result, Probe::Failed(ProbeFailure::Timeout));
    }
    #[tokio::test]
    async fn access_denied_stays_a_failure() {
        let error = zbus::Error::MethodError(
            "org.freedesktop.DBus.Error.AccessDenied"
                .try_into()
                .unwrap(),
            None,
            zbus::Message::method(
                None::<&str>,
                Some("org.test.Service"),
                "/org/test",
                Some("org.test.Service"),
                "Read",
                &(),
            )
            .unwrap()
            .into(),
        );
        let result: Probe<bool> = bounded(async { Err(error) }).await;
        assert_eq!(result, Probe::Failed(ProbeFailure::PermissionDenied));
    }
}
