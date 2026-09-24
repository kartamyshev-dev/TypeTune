#![cfg(target_os = "linux")]
use std::process::Command;

#[test]
fn session_doctor_survives_missing_config_and_bus_without_fallback() {
    let output = Command::new(env!("CARGO_BIN_EXE_typetune"))
        .args([
            "--config",
            "/nonexistent/typetune-doctor/config.toml",
            "doctor",
            "--session",
        ])
        .env(
            "DBUS_SESSION_BUS_ADDRESS",
            "unix:path=/nonexistent/typetune-doctor/bus",
        )
        .env("XDG_SESSION_TYPE", "wayland")
        .env("DISPLAY", ":0")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["session_hint"], "wayland");
    assert_eq!(report["xwayland_display_hint"], true);
    assert_eq!(report["session_bus"]["status"], "failed");
    assert_eq!(report["context"]["layout"]["state"], "unknown");
    assert_eq!(report["context"]["target"]["state"], "unknown");
    assert_eq!(report["portals"]["permission_requested"], false);
    assert!(report["replacement_blockers"]
        .as_array()
        .unwrap()
        .iter()
        .any(|v| v == "unicode_unavailable"));
    // macOS --doctor parity keys stay present even with a dead bus.
    assert!(report["os"].as_str().unwrap().len() > 0);
    assert!(report["protocol"].is_null());
    assert_eq!(report["input_source"], "");
    assert!(report["permissions"].get("dev_input").is_some());
    assert!(report["permissions"].get("uinput").is_some());
    assert!(report["autostart"].is_boolean());
}

#[test]
fn invalid_configuration_does_not_block_diagnostics() {
    let path = std::env::temp_dir().join(format!("typetune-doctor-{}.toml", std::process::id()));
    std::fs::write(&path, "this is not toml [").unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_typetune"))
        .arg("--config")
        .arg(&path)
        .args(["doctor", "--session"])
        .env(
            "DBUS_SESSION_BUS_ADDRESS",
            "unix:path=/nonexistent/typetune-doctor/bus",
        )
        .output();
    std::fs::remove_file(path).unwrap();
    let output = result.unwrap();
    assert!(output.status.success());
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema_version"], 1);
}
