mod bus;
mod settings;

use adw::prelude::*;
use adw::{Application, ApplicationWindow, HeaderBar, WindowTitle};
use settings::Settings;
use std::cell::{Cell, RefCell};
use std::rc::Rc;

fn main() {
    let app = Application::builder()
        .application_id("dev.kartamyshev.TypeTune")
        .build();
    app.connect_activate(build_ui);
    app.run();
}

struct Model {
    settings: Settings,
    status: bus::RuntimeStatus,
}

type Shared = Rc<RefCell<Model>>;

fn build_ui(app: &Application) {
    let model: Shared = Rc::new(RefCell::new(Model {
        settings: Settings::load(),
        status: bus::RuntimeStatus::default(),
    }));

    let header = HeaderBar::builder()
        .title_widget(&WindowTitle::new("TypeTune", "Linux preview"))
        .build();

    let content = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(18)
        .margin_bottom(18)
        .margin_start(24)
        .margin_end(24)
        .build();

    let title = gtk::Label::builder()
        .label("Получение состояния…")
        .css_classes(["title-2"])
        .halign(gtk::Align::Start)
        .build();
    let detail = gtk::Label::builder()
        .label("")
        .wrap(true)
        .halign(gtk::Align::Start)
        .xalign(0.0)
        .css_classes(["dim-label"])
        .build();
    content.append(&title);
    content.append(&detail);

    let actions = gtk::Box::builder().spacing(8).build();
    let pause = gtk::Button::builder().label("Пауза").build();
    let start = gtk::Button::builder()
        .label("Запустить")
        .css_classes(["suggested-action"])
        .build();
    let stop = gtk::Button::builder().label("Остановить").build();
    actions.append(&pause);
    actions.append(&start);
    actions.append(&stop);
    content.append(&actions);
    content.append(&gtk::Separator::new(gtk::Orientation::Horizontal));

    content.append(&section("Переключение"));
    let automatic = switch_row(&content, "Автопереключение (пробел)");
    let manual = switch_row(&content, "Ручное переключение (Double Shift)");
    let only_last = switch_row(&content, "Переключать только последнее слово");
    let dont_words = switch_row(&content, "Не переключать слова");
    let anti_loop = switch_row(&content, "Не исправлять после смены раскладки");
    let sound = switch_row(&content, "Звук переключения");
    let show_flag = switch_row(&content, "Показывать флаг раскладки");
    let autostart = switch_row(&content, "Автозапуск");

    content.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
    content.append(&section("Разрешения и состояние"));
    let doctor = gtk::Label::builder()
        .label("")
        .wrap(true)
        .halign(gtk::Align::Start)
        .xalign(0.0)
        .selectable(true)
        .build();
    content.append(&doctor);
    let refresh = gtk::Button::builder().label("Обновить состояние").build();
    content.append(&refresh);

    content.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
    content.append(
        &gtk::Label::builder()
            .label("Закрытие окна не останавливает TypeTune. Пауза действует в текущем сеансе. Слова и исключения — в TypeTune Preview.")
            .wrap(true)
            .halign(gtk::Align::Start)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );

    let scroll = gtk::ScrolledWindow::builder()
        .child(&content)
        .vexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .build();
    let toolbar = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .build();
    toolbar.append(&header);
    toolbar.append(&scroll);

    let window = ApplicationWindow::builder()
        .application(app)
        .title("TypeTune")
        .default_width(560)
        .default_height(760)
        .content(&toolbar)
        .build();

    let widgets = Widgets {
        title: title.clone(),
        detail: detail.clone(),
        doctor: doctor.clone(),
        pause: pause.clone(),
        start: start.clone(),
        stop: stop.clone(),
        automatic: automatic.clone(),
        manual: manual.clone(),
        only_last: only_last.clone(),
        dont_words: dont_words.clone(),
        anti_loop: anti_loop.clone(),
        sound: sound.clone(),
        show_flag: show_flag.clone(),
        autostart: autostart.clone(),
    };

    let rendering = Rc::new(Cell::new(false));
    spawn_refresh(model.clone(), widgets.clone(), rendering.clone());

    // Policy toggles: mutate settings, persist, keep mutex UI in sync.
    {
        let model = model.clone();
        let rendering = rendering.clone();
        automatic.connect_state_set(move |_, on| {
            if rendering.get() {
                return glib::Propagation::Proceed;
            }
            {
                let mut m = model.borrow_mut();
                m.settings.automatic = on;
                if let Err(error) = m.settings.save() {
                    eprintln!("TypeTune: {error}");
                }
            }
            glib::MainContext::default().spawn_local(async move {
                if let Err(error) = bus::set_automatic(on).await {
                    eprintln!("TypeTune: {error}");
                }
            });
            glib::Propagation::Proceed
        });
    }
    bind_switch(&manual, model.clone(), rendering.clone(), |m, on| {
        m.settings.manual_switching = on;
    });
    {
        let model = model.clone();
        let dont_words = dont_words.clone();
        let rendering = rendering.clone();
        only_last.connect_state_set(move |_, on| {
            if rendering.get() {
                return glib::Propagation::Proceed;
            }
            let sibling = {
                let mut m = model.borrow_mut();
                m.settings.toggling_switch_only_last_word(on);
                if let Err(error) = m.settings.save() {
                    eprintln!("TypeTune: {error}");
                }
                m.settings.dont_switch_words
            };
            if dont_words.is_active() != sibling {
                dont_words.set_active(sibling);
            }
            glib::Propagation::Proceed
        });
    }
    {
        let model = model.clone();
        let only_last = only_last.clone();
        let rendering = rendering.clone();
        dont_words.connect_state_set(move |_, on| {
            if rendering.get() {
                return glib::Propagation::Proceed;
            }
            let sibling = {
                let mut m = model.borrow_mut();
                m.settings.toggling_dont_switch_words(on);
                if let Err(error) = m.settings.save() {
                    eprintln!("TypeTune: {error}");
                }
                m.settings.switch_only_last_word
            };
            if only_last.is_active() != sibling {
                only_last.set_active(sibling);
            }
            glib::Propagation::Proceed
        });
    }
    bind_switch(&anti_loop, model.clone(), rendering.clone(), |m, on| {
        m.settings.dont_correct_after_layout_change = on;
    });
    bind_switch(&sound, model.clone(), rendering.clone(), |m, on| {
        m.settings.play_switching_sound = on;
    });
    bind_switch(&show_flag, model.clone(), rendering.clone(), |m, on| {
        m.settings.display_layout_flag = on;
    });
    bind_switch(&autostart, model.clone(), rendering.clone(), |m, on| {
        m.settings.autostart = on;
        if let Err(error) = settings::write_autostart(on) {
            eprintln!("TypeTune: {error}");
        }
    });

    pause.connect_clicked(|_| {
        glib::MainContext::default().spawn_local(async {
            let _ = bus::set_enabled(false).await;
        });
    });
    start.connect_clicked(|_| {
        let _ = std::process::Command::new("/usr/bin/typetune-preview")
            .arg("start")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    });
    stop.connect_clicked(|_| {
        glib::MainContext::default().spawn_local(async {
            let _ = bus::quit().await;
        });
    });

    {
        let model = model.clone();
        let widgets = widgets.clone();
        let rendering = rendering.clone();
        refresh.connect_clicked(move |_| {
            spawn_refresh(model.clone(), widgets.clone(), rendering.clone())
        });
    }

    window.present();
}

#[derive(Clone)]
struct Widgets {
    title: gtk::Label,
    detail: gtk::Label,
    doctor: gtk::Label,
    pause: gtk::Button,
    start: gtk::Button,
    stop: gtk::Button,
    automatic: gtk::Switch,
    manual: gtk::Switch,
    only_last: gtk::Switch,
    dont_words: gtk::Switch,
    anti_loop: gtk::Switch,
    sound: gtk::Switch,
    show_flag: gtk::Switch,
    autostart: gtk::Switch,
}

fn spawn_refresh(model: Shared, widgets: Widgets, rendering: Rc<Cell<bool>>) {
    glib::MainContext::default().spawn_local(async move {
        let status = bus::fetch_status().await;
        {
            let mut m = model.borrow_mut();
            m.status = status;
        }
        // set_active during render emits state-set; handlers must not re-enter.
        rendering.set(true);
        {
            let m = model.borrow();
            render(&m, &widgets);
        }
        rendering.set(false);
    });
}

fn section(label: &str) -> gtk::Label {
    gtk::Label::builder()
        .label(label)
        .css_classes(["title-3"])
        .halign(gtk::Align::Start)
        .build()
}

fn switch_row(parent: &gtk::Box, label: &str) -> gtk::Switch {
    let sw = gtk::Switch::builder().valign(gtk::Align::Center).build();
    let text = gtk::Label::builder()
        .label(label)
        .hexpand(true)
        .halign(gtk::Align::Start)
        .xalign(0.0)
        .wrap(true)
        .build();
    let row = gtk::Box::builder().spacing(16).build();
    row.append(&text);
    row.append(&sw);
    parent.append(&row);
    sw
}

fn bind_switch<F>(sw: &gtk::Switch, model: Shared, rendering: Rc<Cell<bool>>, mutate: F)
where
    F: Fn(&mut Model, bool) + 'static,
{
    sw.connect_state_set(move |_, on| {
        if rendering.get() {
            return glib::Propagation::Proceed;
        }
        {
            let mut m = model.borrow_mut();
            mutate(&mut m, on);
            if let Err(error) = m.settings.save() {
                eprintln!("TypeTune: {error}");
            }
        }
        glib::Propagation::Proceed
    });
}

fn set_switch(sw: &gtk::Switch, active: bool) {
    if sw.is_active() != active {
        sw.set_active(active);
    }
}

fn render(model: &Model, w: &Widgets) {
    let status = &model.status;
    let flag = match status.flag.as_str() {
        "us" => "🇺🇸",
        "ru" => "🇷🇺",
        _ => "?",
    };
    let head = if !status.helper_ok {
        "Нужны разрешения…"
    } else if !status.enabled {
        "На паузе"
    } else if status.available {
        "Работает"
    } else {
        "Ожидает подходящее поле"
    };
    w.title.set_label(&format!("{flag}  {head}"));

    let mut lines = vec!["Режим совместимости".to_string()];
    if status.helper_ok && status.devices == 0 {
        lines.push("Нет доступа к /dev/input — откройте «Настроить доступ».".into());
    }
    if !status.words_error.is_empty() {
        lines.push(status.words_error.clone());
    }
    if !status.applications_error.is_empty() {
        lines.push(status.applications_error.clone());
    }
    if status.automatic && status.automatic_blocked == "excluded-application" {
        lines.push("Автокоррекция выключена для этого приложения. Double Shift доступен.".into());
    }
    w.detail.set_label(&lines.join("\n"));

    w.pause.set_sensitive(status.helper_ok && status.enabled);
    w.start.set_sensitive(!status.helper_ok || !status.enabled);
    w.stop.set_sensitive(status.helper_ok);

    let s = &model.settings;
    set_switch(&w.automatic, s.automatic);
    set_switch(&w.manual, s.manual_switching);
    set_switch(&w.only_last, s.switch_only_last_word);
    set_switch(&w.dont_words, s.dont_switch_words);
    set_switch(&w.anti_loop, s.dont_correct_after_layout_change);
    set_switch(&w.sound, s.play_switching_sound);
    set_switch(&w.show_flag, s.display_layout_flag);
    set_switch(&w.autostart, s.autostart);

    let mut report = Vec::new();
    for (name, ok, note) in bus::local_doctor() {
        report.push(format!("{} — {}", name, if ok { "OK" } else { "внимание" }));
        report.push(format!("    {note}"));
    }
    report.push(format!(
        "GNOME Session1 — {}",
        if status.session_ok {
            "доступен"
        } else {
            "не отвечает (перелогин после установки?)"
        }
    ));
    report.push(format!(
        "Compat runtime — {}",
        if status.helper_ok {
            "доступен"
        } else {
            "не запущен"
        }
    ));
    if status.helper_ok {
        report.push(format!("Последний результат — {}", status.last_result));
        report.push(format!("Устройств — {}", status.devices));
    }
    w.doctor.set_label(&report.join("\n"));
}
