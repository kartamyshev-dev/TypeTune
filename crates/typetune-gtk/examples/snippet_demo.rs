//! Interactive cooperating editor; it only edits its own newly created field.
use gtk::prelude::*;
use typetune_engine::{Direction, Outcome, StaticSnippet};
use typetune_gtk::ControlledField;
fn main() {
    let app = gtk::Application::builder()
        .application_id("org.typetune.ControlledDemo")
        .build();
    app.connect_activate(|app| {
        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("TypeTune — тестовое текстовое поле")
            .default_width(640)
            .default_height(400)
            .build();
        let field = ControlledField::new(window.upcast_ref(), 1);
        let layout = gtk::Box::new(gtk::Orientation::Vertical, 12);
        layout.set_margin_top(16);
        layout.set_margin_bottom(16);
        layout.set_margin_start(16);
        layout.set_margin_end(16);
        layout.append(&gtk::Label::new(Some(
            "Введите :hi и пробел. Замена работает только в этом поле.",
        )));
        field.view().set_vexpand(true);
        layout.append(field.view());
        let status = gtk::Label::new(None);
        layout.append(&status);
        let shortcut_status = status.clone();
        field
            .install_correction_shortcuts(move |outcome| {
                shortcut_status.set_text(match outcome {
                    Outcome::Completed => "Слово исправлено",
                    Outcome::FailedBeforeEdit(_) => "Команда отменена; текст не изменён",
                    Outcome::IndeterminateAfterEdit => "Замена прервана; проверьте текст",
                });
            })
            .unwrap();
        let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        for (label, direction) in [
            ("Исправить US → RU", Direction::UsToRu),
            ("Исправить RU → US", Direction::RuToUs),
        ] {
            let status = status.clone();
            buttons.append(&field.correction_button(label, direction, move |result| {
                status.set_text(match result {
                    Outcome::Completed => "Слово исправлено",
                    Outcome::FailedBeforeEdit(_) => {
                        "Нет подходящего слова или контекста. Текст не изменён."
                    }
                    Outcome::IndeterminateAfterEdit => {
                        "Замена прервана. Проверьте текст; повтор не выполнялся."
                    }
                });
            }));
        }
        layout.append(&buttons);
        layout.append(&gtk::Label::new(Some(
            "F8: US → RU; F9: RU → US. Отпустите клавишу без Shift/Ctrl/Alt.",
        )));
        field
            .install_snippet(
                StaticSnippet::new(":hi", "Привет, World! 👋\nХорошего дня.").unwrap(),
                move |result| {
                    status.set_text(match result {
                        Outcome::Completed => "Сниппет вставлен",
                        Outcome::FailedBeforeEdit(_) => "Замена отменена до изменения",
                        Outcome::IndeterminateAfterEdit => {
                            "Замена прервана. Проверьте текст; повтор не выполнялся."
                        }
                    });
                },
            )
            .unwrap();
        window.set_child(Some(&layout));
        window.present();
        field.view().grab_focus();
    });
    app.run();
}
