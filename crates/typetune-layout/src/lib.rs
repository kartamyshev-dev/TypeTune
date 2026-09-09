use xkbcommon::xkb;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LayoutId {
    English,
    Russian,
}

pub struct LayoutManager {
    _context: xkb::Context,
    _keymap: xkb::Keymap,
    state: xkb::State,
}

impl Default for LayoutManager {
    fn default() -> Self {
        Self::new()
    }
}

impl LayoutManager {
    pub fn new() -> Self {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap = xkb::Keymap::new_from_names(&context, "evdev", "pc105", "us,ru", "", None, 0)
            .expect("Failed to create keymap");
        let state = xkb::State::new(&keymap);
        Self {
            _context: context,
            _keymap: keymap,
            state,
        }
    }

    pub fn keycode_to_char(&mut self, keycode: u32) -> Option<char> {
        let utf8 = self.state.key_get_utf8((keycode + 8).into());
        if utf8.is_empty() {
            None
        } else {
            utf8.chars().next()
        }
    }

    pub fn update_key(&mut self, keycode: u32, direction: xkb::KeyDirection) {
        self.state.update_key((keycode + 8).into(), direction);
    }

    pub fn current_layout(&self) -> LayoutId {
        if self
            .state
            .layout_name_is_active("ru", xkb::STATE_LAYOUT_EFFECTIVE)
        {
            LayoutId::Russian
        } else {
            LayoutId::English
        }
    }
}
