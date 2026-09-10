# 07 — Text Snippets

## Цель
Разворачивание триггеров в текст/команды.

## Шаг 7.1: Rolling Matcher

Алгоритм: буфер последних N символов, проверка на совпадение с триггерами.

```rust
pub struct SnippetExpander {
    buffer: Vec<char>,
    max_buffer_size: usize,
    snippets: Vec<Snippet>,
}

pub struct Snippet {
    pub trigger: String,
    pub replacement: String,
    pub word_boundary: bool,
}
```

### Алгоритм обработки:
```
on_key(char c):
    buffer.push(c)

    for snippet in snippets:
        if buffer.ends_with(snippet.trigger.chars()):
            if !snippet.word_boundary || is_boundary(buffer, trigger_len):
                backspaces = trigger_len
                expanded = expand_variables(snippet.replacement)
                return [BACKSPACE * backspaces] + string_to_events(expanded)

    if buffer.len() > max_buffer_size:
        buffer.remove(0)

    return [event]
```

## Шаг 7.2: Динамические переменные

```rust
fn expand_variables(template: &str) -> String {
    let mut result = template.to_string();

    // {{date}} → 2026-09-10
    if result.contains("{{date}}") {
        result = result.replace("{{date}}", &chrono::Local::now().format("%Y-%m-%d").to_string());
    }

    // {{time}} → 14:30:00
    if result.contains("{{time}}") {
        result = result.replace("{{time}}", &chrono::Local::now().format("%H:%M:%S").to_string());
    }

    // {{shell:command}} → вывод команды
    while let Some(start) = result.find("{{shell:") {
        if let Some(end) = result[start..].find("}}") {
            let cmd = &result[start+8..start+end];
            let output = std::process::Command::new("sh")
                .args(["-c", cmd])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();
            result = format!("{}{}{}", &result[..start], output, &result[start+end+2..]);
        } else { break; }
    }

    result
}
```

## Шаг 7.3: Word boundary detection

```rust
fn is_boundary(buffer: &[char], trigger_len: usize) -> bool {
    if trigger_len >= buffer.len() {
        return true;
    }
    let prev_char = buffer[buffer.len() - trigger_len - 1];
    prev_char == ' ' || prev_char == '\t' || prev_char == '\n'
        || prev_char == '(' || prev_char == '[' || prev_char == '{'
        || prev_char == ',' || prev_char == '.' || prev_char == ':'
}
```

## Шаг 7.4: Конфигурация

```toml
[snippets]
enabled = true
trigger_prefix = ":"
word_separators = [" ", "\t", "\n"]

[snippets.entries]
date = "{{date}}"
time = "{{time}}"
myip = "{{shell:curl -s ifconfig.me}}"
docker = "docker run -it --rm -v $(pwd):/app -w /app"
glog = "git log --oneline --graph --decorate -20"
```

## Шаг 7.5: PipelineStage

```rust
impl PipelineStage for SnippetExpander {
    fn name(&self) -> &str { "snippet-expander" }

    fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        if let Some(ch) = event.character {
            self.buffer.push(ch);

            // Проверить каждый сниппет
            for snippet in &self.snippets {
                let trigger_len = snippet.trigger.chars().count();
                if self.buffer.len() >= trigger_len {
                    let tail: String = self.buffer[self.buffer.len()-trigger_len..].iter().collect();
                    if tail == snippet.trigger {
                        if !snippet.word_boundary || is_boundary(&self.buffer, trigger_len) {
                            let expanded = expand_variables(&snippet.replacement);
                            // Удалить триггер из буфера
                            for _ in 0..trigger_len { self.buffer.pop(); }
                            return self.text_to_events(&expanded);
                        }
                    }
                }
            }

            if self.buffer.len() > self.max_buffer_size {
                self.buffer.remove(0);
            }
        }

        vec![event]
    }
}
```

## Проверочный лист
- [ ] `:date` + пробел → текущая дата
- [ ] `:myip` + пробел → вывод curl
- [ ] Сниппеты не срабатывают внутри слова
- [ ] Длинные триггеры работают корректно
