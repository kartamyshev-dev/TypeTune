use evdev::Device;
use std::fs;

pub fn discover_keyboards(exclude_names: &[String]) -> Vec<(String, String)> {
    let mut keyboards = Vec::new();

    let entries = match fs::read_dir("/dev/input") {
        Ok(e) => e,
        Err(_) => return keyboards,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let path_str = path.to_string_lossy().to_string();

        if !path_str.starts_with("/dev/input/event") {
            continue;
        }

        let device = match Device::open(&path) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let name = device.name().unwrap_or("unknown").to_string();

        if exclude_names.iter().any(|n| n.eq_ignore_ascii_case(&name)) {
            continue;
        }

        if is_keyboard(&device) {
            tracing::info!("Found keyboard: {} at {}", name, path_str);
            keyboards.push((path_str, name));
        }
    }

    keyboards
}

fn is_keyboard(device: &Device) -> bool {
    use evdev::KeyCode;

    let supported = match device.supported_keys() {
        Some(keys) => keys,
        None => return false,
    };

    let has_letters = supported.contains(KeyCode::KEY_A)
        && supported.contains(KeyCode::KEY_Z)
        && supported.contains(KeyCode::KEY_SPACE);

    let is_mouse = name_contains(device, "mouse")
        || name_contains(device, "touchpad")
        || name_contains(device, "trackpoint");

    has_letters && !is_mouse
}

fn name_contains(device: &Device, pattern: &str) -> bool {
    device
        .name()
        .map(|n| n.to_lowercase().contains(pattern))
        .unwrap_or(false)
}
