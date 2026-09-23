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
    use evdev::{AbsoluteAxisCode, KeyCode, RelativeAxisCode};

    let supported = match device.supported_keys() {
        Some(keys) => keys,
        None => return false,
    };

    if name_contains(device, "mouse")
        || name_contains(device, "touchpad")
        || name_contains(device, "trackpoint")
        || name_contains(device, "g305")
        || name_contains(device, "g502")
        || name_contains(device, "g pro")
        || name_contains(device, "typetune")
    {
        return false;
    }

    if device.supported_relative_axes().is_some_and(|axes| {
        axes.contains(RelativeAxisCode::REL_X) || axes.contains(RelativeAxisCode::REL_Y)
    }) {
        return false;
    }

    if device.supported_absolute_axes().is_some_and(|axes| {
        axes.contains(AbsoluteAxisCode::ABS_X) || axes.contains(AbsoluteAxisCode::ABS_Y)
    }) {
        return false;
    }

    if supported.contains(KeyCode::BTN_LEFT)
        || supported.contains(KeyCode::BTN_RIGHT)
        || supported.contains(KeyCode::BTN_TOOL_MOUSE)
    {
        return false;
    }

    supported.contains(KeyCode::KEY_A)
        && supported.contains(KeyCode::KEY_Z)
        && supported.contains(KeyCode::KEY_0)
        && supported.contains(KeyCode::KEY_9)
        && supported.contains(KeyCode::KEY_SPACE)
        && supported.contains(KeyCode::KEY_ENTER)
        && supported.contains(KeyCode::KEY_BACKSPACE)
        && supported.contains(KeyCode::KEY_LEFTSHIFT)
}

fn name_contains(device: &Device, pattern: &str) -> bool {
    device
        .name()
        .map(|n| n.to_lowercase().contains(pattern))
        .unwrap_or(false)
}
