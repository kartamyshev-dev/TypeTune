//! Reconnect only explicit symbolic selections (usually /dev/input/by-id).
//! Raw eventN numbers can be reassigned to another device, so are startup-only.
use crate::EvdevSource;
use std::path::Path;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub fn reconnectable(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_symlink())
        && std::fs::canonicalize(path).is_ok()
}

pub fn watch_selected_paths(source: Arc<EvdevSource>, paths: Vec<String>) -> JoinHandle<()> {
    thread::spawn(move || {
        let stop = source.stop_token();
        while !stop.load(Ordering::SeqCst) {
            for path in &paths {
                if reconnectable(Path::new(path)) {
                    // Duplicate active paths are ignored by the serial source.
                    // A rejected non-neutral attach is retried on the next pass.
                    if let Err(error) = source.add_device(path, "selected reconnect") {
                        tracing::warn!("Reconnect queue: {error}");
                    }
                }
            }
            thread::sleep(Duration::from_millis(250));
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_explicit_existing_symlink_can_reconnect() {
        let root = std::env::temp_dir().join(format!("typetune-hotplug-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let target = root.join("node");
        std::fs::write(&target, "").unwrap();
        let link = root.join("selected");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert!(!reconnectable(&target));
        assert!(reconnectable(&link));
        std::fs::remove_file(&target).unwrap();
        assert!(!reconnectable(&link));
        std::fs::remove_dir_all(root).unwrap();
    }
}
