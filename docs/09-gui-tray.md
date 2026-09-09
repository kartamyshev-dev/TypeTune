# 09 — Графический интерфейс и системный трей

## Цель
Иконка в системном трее с контекстным меню + GTK4 окно настроек.

## Архитектура

```
typetune (daemon)
  ├── Pipeline (evdev → stages → uinput)
  ├── TrayIcon (ksni → D-Bus StatusNotifierItem)
  └── IPC Server (zbus → unix socket)

typetune-gui (запускается по запросу из трее)
  ├── GTK4 + libadwaita окно настроек
  └── IPC Client (zbus → подключение к daemon)
```

Демон и GUI — отдельные процессы, общаются через D-Bus (или unix socket через zbus).

---

## Шаг 9.1: typetune-tray — иконка в трее

### Cargo.toml
```toml
[package]
name = "typetune-tray"
version.workspace = true
edition.workspace = true

[dependencies]
typetune-core = { path = "../typetune-core" }
typetune-config = { path = "../typetune-config" }
ksni = "0.2"
tracing = "0.1"
```

### src/lib.rs — StatusNotifierItem

```rust
use ksni::{MenuItem, StatusNotifierItem, TrayMethods};
use std::sync::{Arc, Mutex};

pub struct TypeTuneTray {
    config: Arc<Mutex<typetune_config::Config>>,
    enabled: Arc<Mutex<bool>>,
}

impl StatusNotifierItem for TypeTuneTray {
    fn id(&self) -> String { "typetune".into() }
    fn title(&self) -> String { "TypeTune".into() }
    fn icon_name(&self) -> String {
        if *self.enabled.lock().unwrap() {
            "typetune-active".into()
        } else {
            "typetune-disabled".into()
        }
    }
    fn icon_theme_path(&self) -> String {
        "/usr/share/typetune/icons".into()
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let enabled = *self.enabled.lock().unwrap();
        vec![
            MenuItem::Standard {
                label: if enabled { "TypeTune: Включён" } else { "TypeTune: Выключен" }.into(),
                ..Default::default()
            },
            MenuItem::Separator,
            MenuItem::Standard {
                label: "Настройки...".into(),
                activate: Box::new(|_| {
                    // Запустить typetune-gui
                    std::process::Command::new("typetune-gui").spawn().ok();
                }),
                ..Default::default()
            },
            MenuItem::Standard {
                label: if enabled { "Отключить" } else { "Включить" }.into(),
                activate: Box::new(|tray| {
                    let mut e = tray.enabled.lock().unwrap();
                    *e = !*e;
                    // Уведомить daemon через IPC
                }),
                ..Default::default()
            },
            MenuItem::Separator,
            MenuItem::Standard {
                label: "Статистика".into(),
                activate: Box::new(|_| {
                    // Показать popup со статистикой
                }),
                ..Default::default()
            },
            MenuItem::Standard {
                label: "Выход".into(),
                activate: Box::new(|_| {
                    // Отправить SIGTERM демону
                    std::process::Command::new("typetune")
                        .arg("stop")
                        .spawn()
                        .ok();
                }),
                ..Default::default()
            },
        ]
    }
}

pub async fn run_tray(
    config: Arc<Mutex<typetune_config::Config>>,
    enabled: Arc<Mutex<bool>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let tray = TypeTuneTray { config, enabled };
    let service = TrayMethods::spawn(tray).await?;
    // Держать сервис живым
    futures::future::pending::<()>().await;
    Ok(())
}
```

### Иконки

```
resources/icons/hicolor/
├── 16x16/status/typetune-active.png
├── 16x16/status/typetune-disabled.png
├── 24x24/status/typetune-active.png
├── 24x24/status/typetune-disabled.png
├── scalable/typetune-active.svg
└── scalable/typetune-disabled.svg
```

Установка:
```bash
sudo cp -r resources/icons /usr/share/typetune/icons
```

---

## Шаг 9.2: IPC между daemon и GUI/tray

### Протокол через zbus (D-Bus)

Интерфейс `org.typetune.Daemon`:

```xml
<node>
  <interface name="org.typetune.Daemon">
    <method name="GetStatus">
      <arg name="enabled" type="b" direction="out"/>
      <arg name="active_features" type="as" direction="out"/>
    </method>
    <method name="SetEnabled">
      <arg name="enabled" type="b" direction="in"/>
    </method>
    <method name="GetStats">
      <arg name="total_events" type="t" direction="out"/>
      <arg name="suppressed" type="t" direction="out"/>
    </method>
    <method name="ReloadConfig"/>
    <signal name="ConfigChanged"/>
  </interface>
</node>
```

### typetune-ipc crate (опционально, или внутри daemon)

```rust
use zbus::{connection, interface};

struct DaemonInterface {
    enabled: Arc<Mutex<bool>>,
    stats: Arc<Mutex<ChatterStats>>,
}

#[interface(name = "org.typetune.Daemon")]
impl DaemonInterface {
    async fn get_status(&self) -> (bool, Vec<String>) {
        let e = *self.enabled.lock().unwrap();
        (e, vec!["layout-corrector".into(), "anti-chatter".into()])
    }

    async fn set_enabled(&self, enabled: bool) {
        *self.enabled.lock().unwrap() = enabled;
    }

    async fn get_stats(&self) -> (u64, u64) {
        let s = self.stats.lock().unwrap();
        (s.total_events, s.suppressed_events)
    }

    async fn reload_config(&self) {
        // SIGHUP
    }
}
```

---

## Шаг 9.3: typetune-gui — GTK4 окно настроек

### Cargo.toml
```toml
[package]
name = "typetune-gui"
version.workspace = true
edition.workspace = true

[[bin]]
name = "typetune-gui"
path = "src/main.rs"

[dependencies]
typetune-config = { path = "../typetune-config" }
gtk = { version = "0.9", package = "gtk4" }
adw = { version = "0.7", package = "libadwaita" }
zbus = "4"
serde = { version = "1", features = ["derive"] }
toml = "0.8"
tracing = "0.1"
tracing-subscriber = "0.3"
```

### src/main.rs — Структура окна

```rust
use adw::prelude::*;
use adw::{Application, ApplicationWindow, HeaderBar};
use gtk::prelude::*;

fn main() {
    let app = Application::builder()
        .application_id("dev.kartamyshev.typetune")
        .build();

    app.activate(|app| {
        build_ui(app);
    });

    app.run();
}

fn build_ui(app: &Application) {
    // Загрузить конфиг
    let config = typetune_config::load(&typetune_config::config_path()).unwrap();

    // Header bar
    let header = HeaderBar::builder()
        .title_widget(&adw::WindowTitle::new("TypeTune", "Настройки"))
        .build();

    // === Страница: Общие ===
    let general_group = adw::PreferencesGroup::builder()
        .title("Общие")
        .build();

    // Переключатель "Включён"
    let enabled_row = adw::SwitchRow::builder()
        .title("Включён")
        .subtitle("Активировать обработку клавиатуры")
        .active(config.general.enabled)
        .build();

    // Уровень логирования
    let log_level_row = adw::ComboRow::builder()
        .title("Уровень логирования")
        .model(&gtk::StringList::new(&["trace", "debug", "info", "warn", "error"]))
        .build();

    general_group.add(&enabled_row);
    general_group.add(&log_level_row);

    // === Страница: Корректор раскладки ===
    let corrector_group = adw::PreferencesGroup::builder()
        .title("Корректор раскладки")
        .build();

    let corrector_switch = adw::SwitchRow::builder()
        .title("Автокоррекция раскладки")
        .subtitle("ghbdtn → привет")
        .active(config.corrector.enabled)
        .build();

    let min_word_spin = adw::SpinRow::builder()
        .title("Минимальная длина слова")
        .subtitle("Слова короче не исправляются")
        .adjustment(&gtk::Adjustment::new(
            config.corrector.min_word_length as f64,
            1.0, 10.0, 1.0, 0.0, 0.0
        ))
        .build();

    // Исключения (список приложений)
    let exclude_list = gtk::ListBox::builder()
        .css_classes(["boxed-list"])
        .build();
    for class in &config.corrector.exclude_classes {
        let row = adw::ActionRow::builder().title(class.as_str()).build();
        exclude_list.append(&row);
    }

    corrector_group.add(&corrector_switch);
    corrector_group.add(&min_word_spin);
    corrector_group.add(&exclude_list);

    // === Страница: Антидребезг ===
    let chatter_group = adw::PreferencesGroup::builder()
        .title("Антидребезг")
        .build();

    let chatter_switch = adw::SwitchRow::builder()
        .title("Фильтрация дребезга")
        .active(config.chatter.enabled)
        .build();

    let debounce_spin = adw::SpinRow::builder()
        .title("Окно подавления (мс)")
        .adjustment(&gtk::Adjustment::new(
            config.chatter.debounce_ms as f64,
            10.0, 200.0, 5.0, 0.0, 0.0
        ))
        .build();

    chatter_group.add(&chatter_switch);
    chatter_group.add(&debounce_spin);

    // === Страница: Сниппеты ===
    let snippets_group = adw::PreferencesGroup::builder()
        .title("Сниппеты")
        .build();

    let snippets_switch = adw::SwitchRow::builder()
        .title("Текстовые сниппеты")
        .active(config.snippets.enabled)
        .build();

    // Таблица сниппетов (trigger → replacement)
    let snippets_list = gtk::ListBox::builder()
        .css_classes(["boxed-list"])
        .build();
    for (trigger, replacement) in &config.snippets.entries {
        let row = adw::ActionRow::builder()
            .title(trigger.as_str())
            .subtitle(replacement.as_str())
            .build();
        snippets_list.append(&row);
    }

    snippets_group.add(&snippets_switch);
    snippets_group.add(&snippets_list);

    // === Сборка layout ===
    let content = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(12).margin_bottom(12)
        .margin_start(12).margin_end(12)
        .build();

    content.append(&general_group);
    content.append(&corrector_group);
    content.append(&chatter_group);
    content.append(&snippets_group);

    let scroll = gtk::ScrolledWindow::builder()
        .child(&content)
        .vexpand(true)
        .build();

    let toolbar_view = adw::ToolbarView::new();
    toolbar_view.add_top_bar(&header);
    toolbar_view.set_content(Some(&scroll));

    let window = ApplicationWindow::builder()
        .application(app)
        .title("TypeTune")
        .default_width(600)
        .default_height(700)
        .content(&toolbar_view)
        .build();

    window.present();
}
```

---

## Шаг 9.4: Интеграция в daemon

В `typetune-cli/src/main.rs` daemon mode запускает tray в отдельном потоке:

```rust
fn daemon_mode(config: Config) {
    // ... pipeline setup ...

    let config_arc = Arc::new(Mutex::new(config));
    let enabled = Arc::new(Mutex::new(true));

    // Запуск tray в отдельном tokio task
    let tray_config = config_arc.clone();
    let tray_enabled = enabled.clone();
    tokio::spawn(async move {
        if let Err(e) = run_tray(tray_config, tray_enabled).await {
            tracing::error!("Tray error: {}", e);
        }
    });

    // Event loop
    source.run(Box::new(move |event| {
        if *enabled.lock().unwrap() {
            let events = pipeline.process(event);
            for e in events { vkb.emit(&e).ok(); }
        }
    }));
}
```

---

## Шаг 9.5: Десктоп-файл

### typetune.desktop
```desktop
[Desktop Entry]
Name=TypeTune
Comment=Keyboard daemon with layout correction, anti-chatter and snippets
Exec=typetune-gui
Icon=typetune
Terminal=false
Type=Application
Categories=Utility;Settings;
Keywords=keyboard;layout;chatter;snippets;
```

Установка:
```bash
sudo cp typetune.desktop /usr/share/applications/
```

---

## Проверочный лист
- [ ] Иконка TypeTune видна в системном трее
- [ ] Контекстное меню: Включить/Выключить, Настройки, Выход
- [ ] Клик "Настройки" открывает GTK4 окно
- [ ] Окно показывает текущие настройки из конфига
- [ ] Переключатели работают (corrector, chatter, snippets)
- [ ] Изменения применяются без перезапуска демона
- [ ] D-Bus IPC работает между daemon и GUI
- [ ] Десктоп-файл работает (запуск из app grid)
