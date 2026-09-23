use adw::prelude::*;
use adw::{Application, ApplicationWindow, HeaderBar};
use zbus::dbus_proxy;

#[dbus_proxy(
    interface = "org.typetune.Daemon",
    default_service = "org.typetune.Daemon",
    default_path = "/org/typetune/Daemon"
)]
trait Daemon {
    fn get_status(&self) -> zbus::Result<(bool, Vec<String>)>;
    fn set_enabled(&self, enabled: bool) -> zbus::Result<()>;
    fn get_stats(&self) -> zbus::Result<(u64, u64)>;
    fn reload_config(&self) -> zbus::Result<()>;
}

fn main() {
    tracing_subscriber::fmt::init();

    let app = Application::builder()
        .application_id("dev.kartamyshev.typetune")
        .build();

    app.connect_activate(|app| {
        build_ui(app);
    });

    app.run();
}

fn check_daemon_status() -> String {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        match zbus::Connection::session().await {
            Ok(conn) => match DaemonProxy::new(&conn).await {
                Ok(proxy) => match proxy.get_status().await {
                    Ok((enabled, features)) => {
                        let state = if enabled { "running" } else { "disabled" };
                        format!(
                            "Daemon: {} | Features: {}",
                            state,
                            if features.is_empty() {
                                "none".to_string()
                            } else {
                                features.join(", ")
                            }
                        )
                    }
                    Err(e) => format!("Daemon not responding: {}", e),
                },
                Err(e) => format!("Cannot connect: {}", e),
            },
            Err(e) => format!("D-Bus error: {}", e),
        }
    })
}

fn build_ui(app: &Application) {
    let config = typetune_config::load(&typetune_config::config_path()).unwrap_or_else(|e| {
        tracing::warn!("Failed to load config: {}", e);
        panic!("Cannot load config")
    });

    let header = HeaderBar::builder()
        .title_widget(&adw::WindowTitle::new("TypeTune", "Settings"))
        .build();

    let content = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(12)
        .margin_bottom(12)
        .margin_start(12)
        .margin_end(12)
        .build();

    let status_text = check_daemon_status();
    let status_label = gtk::Label::new(Some(&status_text));
    content.append(&status_label);

    let general_label = gtk::Label::builder()
        .label("General")
        .css_classes(["title-2"])
        .halign(gtk::Align::Start)
        .build();
    content.append(&general_label);

    let log_level_label =
        gtk::Label::new(Some(&format!("Log level: {}", config.general.log_level)));
    content.append(&log_level_label);

    let corrector_label = gtk::Label::builder()
        .label("Layout Corrector")
        .css_classes(["title-2"])
        .halign(gtk::Align::Start)
        .build();
    content.append(&corrector_label);

    let corrector_switch = gtk::CheckButton::builder()
        .label("Auto layout correction")
        .active(config.corrector.enabled)
        .build();
    content.append(&corrector_switch);

    let min_word_label = gtk::Label::new(Some(&format!(
        "Min word length: {}",
        config.corrector.min_word_length
    )));
    content.append(&min_word_label);

    let double_shift_switch = gtk::CheckButton::builder()
        .label("Double-Shift manually corrects last word")
        .active(config.corrector.double_shift_corrects)
        .build();
    content.append(&double_shift_switch);

    let chatter_label = gtk::Label::builder()
        .label("Anti-Chatter")
        .css_classes(["title-2"])
        .halign(gtk::Align::Start)
        .build();
    content.append(&chatter_label);

    let chatter_switch = gtk::CheckButton::builder()
        .label("Key chatter filtering")
        .active(config.chatter.enabled)
        .build();
    content.append(&chatter_switch);

    let debounce_label = gtk::Label::new(Some(&format!(
        "Debounce window: {}ms",
        config.chatter.debounce_ms
    )));
    content.append(&debounce_label);

    let snippets_label = gtk::Label::builder()
        .label("Snippets")
        .css_classes(["title-2"])
        .halign(gtk::Align::Start)
        .build();
    content.append(&snippets_label);

    let snippets_switch = gtk::CheckButton::builder()
        .label("Text snippets")
        .active(config.snippets.enabled)
        .build();
    content.append(&snippets_switch);

    let btn_box = gtk::Box::builder()
        .orientation(gtk::Orientation::Horizontal)
        .spacing(8)
        .halign(gtk::Align::End)
        .margin_top(12)
        .build();

    let save_btn = gtk::Button::builder()
        .label("Save")
        .css_classes(["suggested-action"])
        .build();

    let config_path = typetune_config::config_path();
    let config_path_clone = config_path.clone();
    save_btn.connect_clicked(move |_| {
        let mut cfg = config.clone();
        cfg.corrector.enabled = corrector_switch.is_active();
        cfg.chatter.enabled = chatter_switch.is_active();
        cfg.snippets.enabled = snippets_switch.is_active();
        cfg.corrector.double_shift_corrects = double_shift_switch.is_active();

        match toml::to_string_pretty(&cfg) {
            Ok(toml_str) => {
                if let Err(e) = std::fs::write(&config_path_clone, &toml_str) {
                    tracing::error!("Failed to save config: {}", e);
                } else {
                    tracing::info!("Config saved");
                    let rt = tokio::runtime::Runtime::new().unwrap();
                    rt.block_on(async {
                        if let Ok(conn) = zbus::Connection::session().await {
                            if let Ok(proxy) = DaemonProxy::new(&conn).await {
                                let _ = proxy.reload_config().await;
                            }
                        }
                    });
                }
            }
            Err(e) => tracing::error!("Failed to serialize config: {}", e),
        }
    });
    btn_box.append(&save_btn);

    let reload_btn = gtk::Button::builder().label("Reload daemon").build();
    reload_btn.connect_clicked(|_| {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Ok(conn) = zbus::Connection::session().await {
                if let Ok(proxy) = DaemonProxy::new(&conn).await {
                    let _ = proxy.reload_config().await;
                }
            }
        });
    });
    btn_box.append(&reload_btn);

    content.append(&btn_box);

    let scroll = gtk::ScrolledWindow::builder()
        .child(&content)
        .vexpand(true)
        .build();

    let toolbar_view = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .build();
    toolbar_view.append(&header);
    toolbar_view.append(&scroll);

    let window = ApplicationWindow::builder()
        .application(app)
        .title("TypeTune")
        .default_width(600)
        .default_height(700)
        .content(&toolbar_view)
        .build();

    window.present();
}
