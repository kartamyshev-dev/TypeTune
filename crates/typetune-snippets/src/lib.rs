use typetune_core::event::{InputEvent, KeyState};
use typetune_core::pipeline::PipelineStage;

pub struct Snippet {
    pub trigger: String,
    pub replacement: String,
    pub word_boundary: bool,
}

pub struct SnippetExpander {
    buffer: Vec<char>,
    max_buffer_size: usize,
    snippets: Vec<Snippet>,
}

impl SnippetExpander {
    pub fn new(snippets: Vec<Snippet>) -> Self {
        Self {
            buffer: Vec::new(),
            max_buffer_size: 256,
            snippets,
        }
    }

    pub fn from_config(config: &typetune_config::SnippetsConfig) -> Self {
        let snippets = config
            .entries
            .iter()
            .map(|(trigger, replacement)| Snippet {
                trigger: format!("{}{}", config.trigger_prefix, trigger),
                replacement: replacement.clone(),
                word_boundary: true,
            })
            .collect();
        Self::new(snippets)
    }

    fn is_boundary(buffer: &[char], trigger_len: usize) -> bool {
        if trigger_len >= buffer.len() {
            return true;
        }
        let prev_char = buffer[buffer.len() - trigger_len - 1];
        prev_char == ' '
            || prev_char == '\t'
            || prev_char == '\n'
            || prev_char == '('
            || prev_char == '['
            || prev_char == '{'
            || prev_char == ','
            || prev_char == '.'
            || prev_char == ':'
    }

    fn expand_variables(template: &str) -> String {
        let mut result = template.to_string();

        if result.contains("{{date}}") {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let days = now.as_secs() / 86400;
            let year = 1970 + (days / 365);
            let day_of_year = days % 365;
            let month = (day_of_year / 30) + 1;
            let day = (day_of_year % 30) + 1;
            result = result.replace("{{date}}", &format!("{:04}-{:02}-{:02}", year, month, day));
        }

        if result.contains("{{time}}") {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let secs = now.as_secs() % 86400;
            let hours = secs / 3600;
            let minutes = (secs % 3600) / 60;
            let seconds = secs % 60;
            result = result.replace(
                "{{time}}",
                &format!("{:02}:{:02}:{:02}", hours, minutes, seconds),
            );
        }

        while let Some(start) = result.find("{{shell:") {
            if let Some(end) = result[start..].find("}}") {
                let cmd = &result[start + 8..start + end];
                let output = std::process::Command::new("sh")
                    .args(["-c", cmd])
                    .output()
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                    .unwrap_or_default();
                result = format!(
                    "{}{}{}",
                    &result[..start],
                    output,
                    &result[start + end + 2..]
                );
            } else {
                break;
            }
        }

        result
    }

    fn text_to_events(text: &str) -> Vec<InputEvent> {
        let mut events = Vec::new();
        for ch in text.chars() {
            if let Some(kc) = char_to_keycode(ch) {
                events.push(InputEvent::new(kc, KeyState::Pressed));
                events.push(InputEvent::new(kc, KeyState::Released));
            }
        }
        events
    }
}

impl PipelineStage for SnippetExpander {
    fn name(&self) -> &str {
        "snippet-expander"
    }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        let ch = match event.character {
            Some(c) => c,
            None => return vec![event],
        };

        self.buffer.push(ch);

        for snippet in &self.snippets {
            let trigger_len = snippet.trigger.chars().count();
            if self.buffer.len() >= trigger_len {
                let tail: String = self.buffer[self.buffer.len() - trigger_len..]
                    .iter()
                    .collect();
                if tail == snippet.trigger
                    && (!snippet.word_boundary || Self::is_boundary(&self.buffer, trigger_len))
                {
                    let expanded = Self::expand_variables(&snippet.replacement);
                    for _ in 0..trigger_len {
                        self.buffer.pop();
                    }
                    let mut events = Vec::new();
                    for _ in 0..trigger_len {
                        events.push(InputEvent::new(14, KeyState::Pressed));
                        events.push(InputEvent::new(14, KeyState::Released));
                    }
                    events.extend(Self::text_to_events(&expanded));
                    return events;
                }
            }
        }

        if self.buffer.len() > self.max_buffer_size {
            self.buffer.remove(0);
        }

        vec![event]
    }
}

fn char_to_keycode(ch: char) -> Option<u32> {
    match ch {
        'q' | 'Q' => Some(16),
        'w' | 'W' => Some(17),
        'e' | 'E' => Some(18),
        'r' | 'R' => Some(19),
        't' | 'T' => Some(20),
        'y' | 'Y' => Some(21),
        'u' | 'U' => Some(22),
        'i' | 'I' => Some(23),
        'o' | 'O' => Some(24),
        'p' | 'P' => Some(25),
        'a' | 'A' => Some(30),
        's' | 'S' => Some(31),
        'd' | 'D' => Some(32),
        'f' | 'F' => Some(33),
        'g' | 'G' => Some(34),
        'h' | 'H' => Some(35),
        'j' | 'J' => Some(36),
        'k' | 'K' => Some(37),
        'l' | 'L' => Some(38),
        'z' | 'Z' => Some(44),
        'x' | 'X' => Some(45),
        'c' | 'C' => Some(46),
        'v' | 'V' => Some(47),
        'b' | 'B' => Some(48),
        'n' | 'N' => Some(49),
        'm' | 'M' => Some(50),
        '0' => Some(11),
        '1' => Some(2),
        '2' => Some(3),
        '3' => Some(4),
        '4' => Some(5),
        '5' => Some(6),
        '6' => Some(7),
        '7' => Some(8),
        '8' => Some(9),
        '9' => Some(10),
        ' ' => Some(57),
        '\n' => Some(28),
        '\t' => Some(15),
        '-' => Some(12),
        '=' => Some(13),
        '[' => Some(26),
        ']' => Some(27),
        ';' => Some(39),
        '\'' => Some(40),
        '`' => Some(41),
        '\\' => Some(43),
        ',' => Some(51),
        '.' => Some(52),
        '/' => Some(53),
        _ => None,
    }
}
