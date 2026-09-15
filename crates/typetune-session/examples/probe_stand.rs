//! Run on a private bus only (see docs/24-session-capability-checkpoint.md).
//! Synthetic service fixtures, not GNOME native acceptance.
use std::sync::{
    atomic::{AtomicU8, Ordering},
    Arc,
};
use typetune_core::session::{Blocker, Knowledge};
use typetune_session::{Probe, ProbeFailure};

struct Shell;
#[zbus::dbus_interface(name = "org.gnome.Shell")]
impl Shell {
    #[dbus_interface(property)]
    fn shell_version(&self) -> &str {
        "50.1-test"
    }
}
struct Shield(Arc<AtomicU8>);
#[zbus::dbus_interface(name = "org.gnome.ScreenSaver")]
impl Shield {
    async fn get_active(&self) -> zbus::fdo::Result<bool> {
        match self.0.load(Ordering::SeqCst) {
            1 => Err(zbus::fdo::Error::AccessDenied("synthetic denial".into())),
            2 => {
                tokio::time::sleep(std::time::Duration::from_secs(10)).await;
                Ok(false)
            }
            _ => Ok(false),
        }
    }
}
struct Portal;
#[zbus::dbus_interface(name = "org.freedesktop.portal.RemoteDesktop")]
impl Portal {
    #[dbus_interface(property, name = "version")]
    fn version(&self) -> u32 {
        2
    }
}
struct Bridge(Arc<AtomicU8>);
#[zbus::dbus_interface(name = "org.typetune.Session1")]
impl Bridge {
    async fn get_snapshot(
        &self,
        #[zbus(connection)] connection: &zbus::Connection,
    ) -> zbus::fdo::Result<String> {
        if self.0.load(Ordering::SeqCst) == 1 {
            return Ok("{}".into());
        }
        if self.0.load(Ordering::SeqCst) == 2 {
            connection
                .release_name("org.gnome.Shell")
                .await
                .map_err(|_| zbus::fdo::Error::Failed("fixture release".into()))?;
        }
        Ok(
            serde_json::json!({"protocol":1,"instance":"11111111-1111-4111-8111-111111111111",
            "generation":1,"source_generation":1,"source_type":"xkb","source_id":"us","xkb_id":"us",
            "window":1,"window_backend":"wayland","locked":false,"shield_active":false,
            "overview":false,"user_session":true,"external_source":false})
            .to_string(),
        )
    }
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    assert_eq!(
        std::env::var("TYPETUNE_PRIVATE_SESSION_STAND").as_deref(),
        Ok("1"),
        "requires an isolated dbus-run-session; do not use the desktop bus"
    );
    let mode = Arc::new(AtomicU8::new(0));
    let bridge_mode = Arc::new(AtomicU8::new(0));
    let fixture = zbus::ConnectionBuilder::session()?
        .name("org.gnome.Shell")?
        .name("org.gnome.ScreenSaver")?
        .name("org.freedesktop.portal.Desktop")?
        .serve_at("/org/gnome/Shell", Shell)?
        .serve_at("/org/typetune/Session1", Bridge(bridge_mode.clone()))?
        .serve_at("/org/gnome/ScreenSaver", Shield(mode.clone()))?
        .serve_at("/org/freedesktop/portal/desktop", Portal)?
        .build()
        .await?;
    let report = typetune_session::probe().await;
    assert_eq!(
        report.gnome_shell_version,
        Probe::Observed("50.1-test".into())
    );
    assert_eq!(report.portals.remote_desktop_version, Probe::Observed(2));
    assert_eq!(report.gnome_screen_shield_active, Probe::Observed(false));
    assert_eq!(report.context.layout, Knowledge::Unknown);
    assert!(report
        .replacement_blockers
        .contains(&Blocker::UnicodeUnavailable));
    assert!(matches!(
        report.portals.input_capture_version,
        Probe::Failed(_)
    ));
    println!("PASS SES-BUS-01: typed replies, missing interface, no permission inferred");
    mode.store(1, Ordering::SeqCst);
    let report = typetune_session::probe().await;
    assert_eq!(
        report.gnome_screen_shield_active,
        Probe::Failed(ProbeFailure::PermissionDenied)
    );
    assert_eq!(report.context.unlocked, Knowledge::Unknown);
    println!("PASS SES-BUS-02: access denied, no last-known unlocked fallback");
    mode.store(2, Ordering::SeqCst);
    let report = typetune_session::probe().await;
    assert_eq!(
        report.gnome_screen_shield_active,
        Probe::Failed(ProbeFailure::Timeout)
    );
    assert!(report.elapsed_ms < 2000);
    println!("PASS SES-BUS-03: stalled method bounded, context unknown");
    assert!(matches!(
        typetune_session::bridge::read(&fixture).await,
        Probe::Observed(_)
    ));
    bridge_mode.store(1, Ordering::SeqCst);
    assert_eq!(
        typetune_session::bridge::read(&fixture).await,
        Probe::Failed(ProbeFailure::InvalidReply)
    );
    println!("PASS BRIDGE-BUS-01: valid protocol read, malformed reply rejected");
    bridge_mode.store(2, Ordering::SeqCst);
    assert!(matches!(
        typetune_session::bridge::read(&fixture).await,
        Probe::Failed(_)
    ));
    println!("PASS BRIDGE-BUS-02: owner lost during GetSnapshot, old-owner reply rejected");
    // Name release gives deterministic disappearance without polling/sleeps.
    fixture.release_name("org.gnome.Shell").await?;
    let report = typetune_session::probe().await;
    assert_eq!(
        report.gnome_shell_version,
        Probe::Failed(ProbeFailure::Unavailable)
    );
    assert_eq!(report.context.target, Knowledge::Unknown);
    println!("PASS SES-BUS-04: service disappears, no stale identity");
    println!("SESSION PROBE STAND PASS (synthetic private D-Bus)");
    Ok(())
}
