//! Shared physical forwarding state for the daemon and the isolated stand.
//! No text processing, shell execution or GUI locks belong on this path.

use anyhow::{bail, Result};
use std::collections::BTreeMap;
use typetune_core::event::{DeviceId, EventOrigin, KeyAction, NativeCode, PhysicalKeyEvent};

#[derive(Default)]
pub struct Relay {
    held: BTreeMap<(u64, u16), PhysicalKeyEvent>,
    failed: bool,
}

impl Relay {
    pub fn forward_frame(
        &mut self,
        events: Vec<PhysicalKeyEvent>,
        output: &mut impl FnMut(&[PhysicalKeyEvent]) -> Result<()>,
    ) -> Result<()> {
        let mut frame = Vec::new();
        for event in events {
            self.forward(event, &mut |e| {
                frame.push(e.clone());
                Ok(())
            })?;
        }
        self.emit_frame(&frame, output)
    }

    fn emit_frame(
        &mut self,
        frame: &[PhysicalKeyEvent],
        output: &mut impl FnMut(&[PhysicalKeyEvent]) -> Result<()>,
    ) -> Result<()> {
        if self.failed {
            bail!("relay output failed");
        }
        if !frame.is_empty() {
            if let Err(error) = output(frame) {
                self.failed = true;
                return Err(error);
            }
        }
        Ok(())
    }

    pub fn disconnect_frame(
        &mut self,
        device: DeviceId,
        output: &mut impl FnMut(&[PhysicalKeyEvent]) -> Result<()>,
    ) -> Result<()> {
        let mut frame = Vec::new();
        self.disconnect(device, &mut |e| {
            frame.push(e.clone());
            Ok(())
        })?;
        self.emit_frame(&frame, output)
    }

    pub fn finish_frames(
        &mut self,
        output: &mut impl FnMut(&[PhysicalKeyEvent]) -> Result<()>,
    ) -> Result<()> {
        let mut frame = Vec::new();
        self.finish(&mut |e| {
            frame.push(e.clone());
            Ok(())
        })?;
        self.emit_frame(&frame, output)
    }

    pub fn forward(
        &mut self,
        event: PhysicalKeyEvent,
        output: &mut impl FnMut(&PhysicalKeyEvent) -> Result<()>,
    ) -> Result<()> {
        if self.failed {
            bail!("relay output failed; no further writes are allowed");
        }
        let code = match event.native_code {
            NativeCode::Evdev(code)
                if code.0 > 0 && code.0 <= 0x2ff && code.0 == event.physical_key.0 =>
            {
                code.0
            }
            _ => bail!("unsupported or inconsistent native keycode"),
        };
        let key = (event.device_id.0, code);
        let owned = self.held.contains_key(&key);
        let other_owner = self.held.keys().any(|k| k.1 == code && *k != key);
        let emit = match event.action {
            KeyAction::Down => !owned && !other_owner,
            KeyAction::Up => owned && !other_owner,
            KeyAction::Repeat => owned,
        };
        if emit {
            if let Err(error) = output(&event) {
                // A write may already have partially reached the kernel. Do not
                // retry it or send further synthetic edges to a failed output.
                self.failed = true;
                return Err(error);
            }
        }
        match event.action {
            KeyAction::Down => {
                self.held.insert(key, event);
            }
            KeyAction::Up => {
                self.held.remove(&key);
            }
            KeyAction::Repeat => {}
        }
        Ok(())
    }

    pub fn disconnect(
        &mut self,
        device: DeviceId,
        output: &mut impl FnMut(&PhysicalKeyEvent) -> Result<()>,
    ) -> Result<()> {
        let releases: Vec<_> = self
            .held
            .iter()
            .filter(|(key, _)| key.0 == device.0)
            .map(|(_, event)| event.clone())
            .collect();
        for mut event in releases {
            event.action = KeyAction::Up;
            event.origin = EventOrigin::Resync;
            event.source_time = std::time::Instant::now();
            event.observed_time = event.source_time;
            self.forward(event, output)?;
        }
        Ok(())
    }

    pub fn finish(
        &mut self,
        output: &mut impl FnMut(&PhysicalKeyEvent) -> Result<()>,
    ) -> Result<()> {
        if self.failed {
            bail!("relay output failed; destroy output to release remaining holds");
        }
        while let Some(&(device, _)) = self.held.keys().next() {
            self.disconnect(DeviceId(device), output)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::convert_ev_key_event;

    fn event(device: u64, code: u16, value: i32) -> PhysicalKeyEvent {
        convert_ev_key_event(DeviceId(device), 17, code, value, std::time::Instant::now()).unwrap()
    }

    #[test]
    fn in03_frame_boundaries_survive_filtering_and_finish() {
        let mut relay = Relay::default();
        let mut frames = Vec::new();
        let mut output = |frame: &[PhysicalKeyEvent]| {
            frames.push(
                frame
                    .iter()
                    .map(|e| (e.physical_key.0, e.action))
                    .collect::<Vec<_>>(),
            );
            Ok(())
        };
        relay
            .forward_frame(vec![event(1, 29, 1), event(1, 30, 1)], &mut output)
            .unwrap();
        // Duplicate ownership of Ctrl adds no output edge, but the new key
        // remains in the second source frame instead of joining the first.
        relay
            .forward_frame(vec![event(2, 29, 1), event(2, 31, 1)], &mut output)
            .unwrap();
        relay.finish_frames(&mut output).unwrap();
        assert_eq!(frames[0], [(29, KeyAction::Down), (30, KeyAction::Down)]);
        assert_eq!(frames[1], [(31, KeyAction::Down)]);
        assert_eq!(
            frames[2],
            [
                (30, KeyAction::Up),
                (29, KeyAction::Up),
                (31, KeyAction::Up)
            ]
        );
        assert!(relay.held.is_empty());
    }

    #[test]
    fn in09_frame_write_failure_prevents_cleanup_writes() {
        let mut relay = Relay::default();
        let mut writes = 0;
        let mut output = |_: &[PhysicalKeyEvent]| {
            writes += 1;
            bail!("partial frame write")
        };
        assert!(relay
            .forward_frame(vec![event(1, 29, 1), event(1, 30, 1)], &mut output)
            .is_err());
        assert!(relay.finish_frames(&mut output).is_err());
        assert_eq!(writes, 1);
    }

    #[test]
    fn in02_preserves_repeat_identity_and_metadata() {
        let mut relay = Relay::default();
        let mut events = Vec::new();
        for value in [1, 2, 2, 0] {
            let e = event(3, 274, value);
            let time = e.source_time;
            relay
                .forward(e, &mut |e| {
                    assert_eq!(e.device_id, DeviceId(3));
                    assert_eq!(e.source_time, time);
                    assert_eq!(e.sequence, 17);
                    assert_eq!(e.origin, EventOrigin::Physical);
                    events.push(e.action);
                    Ok(())
                })
                .unwrap();
        }
        assert_eq!(
            events,
            [
                KeyAction::Down,
                KeyAction::Repeat,
                KeyAction::Repeat,
                KeyAction::Up
            ]
        );
        assert!(relay.held.is_empty());
    }

    #[test]
    fn in05_shared_key_stays_down_until_last_device_releases() {
        let mut relay = Relay::default();
        let mut actions = Vec::new();
        let mut output = |e: &PhysicalKeyEvent| {
            actions.push(e.action);
            Ok(())
        };
        relay.forward(event(1, 42, 1), &mut output).unwrap();
        relay.forward(event(2, 42, 1), &mut output).unwrap();
        relay.disconnect(DeviceId(1), &mut output).unwrap();
        assert!(relay.held.contains_key(&(2, 42)));
        relay.forward(event(2, 42, 2), &mut output).unwrap();
        relay.forward(event(2, 42, 0), &mut output).unwrap();
        assert_eq!(actions, [KeyAction::Down, KeyAction::Repeat, KeyAction::Up]);
        assert!(relay.held.is_empty());
    }

    #[test]
    fn in06_disconnect_and_stop_release_only_owned_keys() {
        let mut relay = Relay::default();
        let mut held = std::collections::BTreeSet::new();
        let mut output = |e: &PhysicalKeyEvent| {
            match e.action {
                KeyAction::Down => assert!(held.insert(e.physical_key.0)),
                KeyAction::Up => assert!(held.remove(&e.physical_key.0)),
                KeyAction::Repeat => assert!(held.contains(&e.physical_key.0)),
            }
            Ok(())
        };
        relay.forward(event(1, 30, 1), &mut output).unwrap();
        relay.forward(event(2, 31, 1), &mut output).unwrap();
        relay.disconnect(DeviceId(1), &mut output).unwrap();
        relay.forward(event(1, 30, 0), &mut output).unwrap(); // orphan ignored
        relay.finish(&mut output).unwrap();
        assert!(held.is_empty());
        assert!(relay.held.is_empty());
    }

    #[test]
    fn in09_output_failure_is_terminal_even_if_a_partial_write_occurred() {
        let mut relay = Relay::default();
        let mut calls = 0;
        let mut output = |_: &PhysicalKeyEvent| {
            calls += 1;
            bail!("injected output failure")
        };
        assert!(relay.forward(event(1, 30, 1), &mut output).is_err());
        assert!(relay.forward(event(1, 30, 0), &mut output).is_err());
        assert!(relay.finish(&mut output).is_err());
        assert_eq!(calls, 1);
    }
}
