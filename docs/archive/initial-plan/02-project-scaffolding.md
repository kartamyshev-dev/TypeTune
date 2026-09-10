# 02 — Scaffolding проекта

## Цель
Создать Cargo workspace, CI, лицензию, базовую структуру.

## Шаг 2.1: Инициализация workspace

```bash
cd /home/kartamyshev/Git/TypeTune/typetune
```

### Cargo.toml (workspace root)
```toml
[workspace]
resolver = "2"
members = [
    "crates/typetune-core",
    "crates/typetune-input",
    "crates/typetune-inject",
    "crates/typetune-layout",
    "crates/typetune-corrector",
    "crates/typetune-chatter",
    "crates/typetune-snippets",
    "crates/typetune-config",
    "crates/typetune-cli",
]

[workspace.package]
version = "0.1.0"
edition = "2021"
license = "MIT"
repository = "https://github.com/kartamyshev-dev/TypeTune"
authors = ["Kartamyshev"]
description = "Keyboard daemon: layout correction, anti-chatter, snippets"
```

## Шаг 2.2: Создание crates

```bash
mkdir -p crates/{typetune-core,typetune-input,typetune-inject,typetune-layout,typetune-corrector,typetune-chatter,typetune-snippets,typetune-config,typetune-cli}/src
```

### typetune-core/Cargo.toml
```toml
[package]
name = "typetune-core"
version.workspace = true
edition.workspace = true

[dependencies]
tracing = "0.1"
```

### typetune-core/src/lib.rs
```rust
pub mod event;
pub mod pipeline;
```

### typetune-core/src/event.rs
```rust
use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Pressed,
    Released,
}

#[derive(Debug, Clone)]
pub struct InputEvent {
    pub keycode: u32,
    pub state: KeyState,
    pub timestamp: Instant,
    pub character: Option<char>,
}

impl InputEvent {
    pub fn new(keycode: u32, state: KeyState) -> Self {
        Self {
            keycode,
            state,
            timestamp: Instant::now(),
            character: None,
        }
    }

    pub fn with_character(mut self, ch: char) -> Self {
        self.character = Some(ch);
        self
    }
}
```

### typetune-core/src/pipeline.rs
```rust
use crate::event::InputEvent;

pub trait PipelineStage {
    fn name(&self) -> &str;
    fn process(&mut self, event: InputEvent) -> Vec<InputEvent>;
    fn reset(&mut self) {}
}

pub struct Pipeline {
    stages: Vec<Box<dyn PipelineStage>>,
}

impl Pipeline {
    pub fn new() -> Self {
        Self { stages: Vec::new() }
    }

    pub fn add_stage(&mut self, stage: Box<dyn PipelineStage>) {
        tracing::info!("Pipeline: добавлен этап '{}'", stage.name());
        self.stages.push(stage);
    }

    pub fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        let mut events = vec![event];
        for stage in &mut self.stages {
            let mut next = Vec::new();
            for e in events.drain(..) {
                next.extend(stage.process(e));
            }
            events = next;
        }
        events
    }
}

impl Default for Pipeline {
    fn default() -> Self {
        Self::new()
    }
}
```

## Шаг 2.3: .gitignore

```gitignore
/target
**/*.rs.bk
*.swp
*.swo
*~
.idea/
.vscode/
```

## Шаг 2.4: LICENSE (MIT)

```text
MIT License

Copyright (c) 2026 Kartamyshev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Шаг 2.5: GitHub Actions CI

### .github/workflows/ci.yml
```yaml
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
      - name: Install system deps
        run: sudo apt-get install -y libevdev-dev libudev-dev libxkbcommon-dev libxkbcommon-x11-dev
      - name: Check
        run: cargo check --workspace
      - name: Clippy
        run: cargo clippy --workspace -- -D warnings
      - name: Fmt
        run: cargo fmt --all -- --check
```

## Шаг 2.6: README.md

Обновить placeholder README полноценным описанием проекта.

## Проверочный лист
- [ ] `cargo check --workspace` проходит без ошибок
- [ ] `cargo clippy --workspace` без предупреждений
- [ ] `cargo fmt --check` без отклонений
- [ ] CI зелёный на GitHub
