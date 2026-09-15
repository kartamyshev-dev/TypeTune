//! The current relay supports key frames only. Reject devices whose essential
//! input would otherwise disappear behind an exclusive grab.
use anyhow::{ensure, Result};

pub fn validate(
    types: impl IntoIterator<Item = u16>,
    keys: impl IntoIterator<Item = u16>,
) -> Result<()> {
    for kind in types {
        // MSC is scan metadata; LED and REP are device settings/feedback. Their
        // absence from output is an explicit limitation of the key-only profile.
        ensure!(
            matches!(kind, 0 | 1 | 4 | 17 | 20),
            "unsupported input event type {kind}; key-only relay cannot grab this device"
        );
    }
    let keys: Vec<_> = keys.into_iter().collect();
    ensure!(!keys.is_empty(), "device advertises no keys");
    ensure!(
        keys.iter().all(|code| *code > 0 && *code <= 0x2ff),
        "input key is unsupported by relay output"
    );
    Ok(())
}

pub fn check(file: &std::fs::File) -> Result<()> {
    // Query capabilities on the same open description; do not reopen a path
    // that could have been reassigned during hotplug.
    let device = evdev::Device::from_fd(file.try_clone()?.into())?;
    validate(
        device.supported_events().iter().map(|e| e.0),
        device
            .supported_keys()
            .into_iter()
            .flat_map(|keys| keys.iter().map(|key| key.0)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn composite_pointer_and_unknown_types_are_rejected() {
        assert!(validate([0, 1, 2], [30]).is_err());
        assert!(validate([0, 1, 3], [30]).is_err());
        assert!(validate([0, 1, 31], [30]).is_err());
    }
    #[test]
    fn invalid_or_absent_keys_are_rejected() {
        assert!(validate([0], []).is_err());
        assert!(validate([0, 1], [0x300]).is_err());
        assert!(validate([0, 1], [0]).is_err());
        assert!(validate([0, 1, 4, 17, 20], [1, 30, 274, 0x2ff]).is_ok());
    }
}
