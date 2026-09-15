//! Real GTK buffer and caret acceptance with synthetic committed text. Run only
//! in the disposable compositor via native_stand.py --text-stand.
use gtk::{glib, prelude::*};
use std::{
    cell::Cell,
    rc::Rc,
    time::{Duration, Instant},
};
use typetune_engine::{execute, Origin, Outcome, Plan, RangeEditor, Rejection, StaticSnippet};
use typetune_gtk::ControlledField;

#[track_caller]
fn wait_for(mut condition: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while !condition() {
        assert!(Instant::now() < deadline, "fixture UI condition timed out");
        while glib::MainContext::default().pending() {
            glib::MainContext::default().iteration(false);
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}
fn reset(field: &ControlledField, text: &str) {
    let b = field.view().buffer();
    b.set_text(text);
    b.place_cursor(&b.end_iter());
    field.record_modifiers(Some(true));
    field.view().grab_focus();
    wait_for(|| field.snapshot().unwrap().focused == Some(true));
}
fn prepare(field: &ControlledField, snippet: &StaticSnippet) -> Plan {
    snippet
        .prepare(
            field.snapshot().unwrap(),
            Origin::CommittedUser,
            Instant::now(),
            Duration::from_secs(1),
        )
        .unwrap()
        .expect("fixture must match")
}
fn main() {
    assert!(
        std::env::var_os("TYPETUNE_NESTED_STAND").is_some(),
        "requires private native stand"
    );
    gtk::init().unwrap();
    let window = gtk::Window::builder()
        .title("TypeTune controlled text fixture")
        .default_width(500)
        .default_height(300)
        .build();
    let mut field = ControlledField::new(&window, 1);
    let second = gtk::TextView::new();
    let layout = gtk::Box::new(gtk::Orientation::Vertical, 4);
    layout.append(field.view());
    layout.append(&second);
    window.set_child(Some(&layout));
    field.view().set_vexpand(true);
    second.set_vexpand(true);
    window.present();
    wait_for(|| window.is_active());

    let snippet = StaticSnippet::new(":hi", "Привет, WORLD! 👋\ne\u{301}").unwrap();
    reset(&field, "до ");
    // Normal text reaches the actual buffer before detector/executor run.
    field.view().buffer().insert_at_cursor(":hi ");
    assert_eq!(field.snapshot().unwrap().text, "до :hi ");
    let p = prepare(&field, &snippet);
    assert_eq!(execute(&mut field, p, Instant::now), Outcome::Completed);
    let after = field.snapshot().unwrap();
    assert_eq!(after.text, "до Привет, WORLD! 👋\ne\u{301} ");
    assert_eq!(after.caret, after.text.chars().count());
    assert_eq!(after.anchor, after.caret);
    println!("PASS TEXT-01: committed trigger visible first; RU/EN/case/emoji/combining/newline, exact caret");

    reset(&field, "до :hi хвост");
    let b = field.view().buffer();
    b.place_cursor(&b.iter_at_offset(7));
    let p = prepare(&field, &snippet);
    assert_eq!(execute(&mut field, p, Instant::now), Outcome::Completed);
    assert_eq!(
        field.snapshot().unwrap().text,
        "до Привет, WORLD! 👋\ne\u{301} хвост"
    );
    println!("PASS TEXT-02: surrounding text and one delimiter preserved");

    reset(&field, ":hi ");
    let p = prepare(&field, &snippet);
    second.grab_focus();
    wait_for(|| !field.view().has_focus());
    assert_eq!(
        execute(&mut field, p, Instant::now),
        Outcome::FailedBeforeEdit(Rejection::Changed)
    );
    assert_eq!(field.snapshot().unwrap().text, ":hi ");
    println!("PASS TEXT-03: field focus changes before edit; source intact");

    reset(&field, ":hi ");
    let p = prepare(&field, &snippet);
    let b = field.view().buffer();
    b.select_range(&b.start_iter(), &b.end_iter());
    assert_eq!(
        execute(&mut field, p, Instant::now),
        Outcome::FailedBeforeEdit(Rejection::Changed)
    );
    assert_eq!(field.snapshot().unwrap().text, ":hi ");
    reset(&field, ":hi ");
    field
        .view()
        .emit_by_name::<()>("preedit-changed", &[&"synthetic preedit"]);
    assert!(matches!(
        snippet.prepare(
            field.snapshot().unwrap(),
            Origin::CommittedUser,
            Instant::now(),
            Duration::from_secs(1)
        ),
        Err(Rejection::Context)
    ));
    field.view().emit_by_name::<()>("preedit-changed", &[&""]);
    field.record_modifiers(None);
    assert!(snippet
        .prepare(
            field.snapshot().unwrap(),
            Origin::CommittedUser,
            Instant::now(),
            Duration::from_secs(1)
        )
        .is_err());
    assert_eq!(field.snapshot().unwrap().text, ":hi ");
    println!("PASS TEXT-04: selection, preedit signal and unknown modifiers refuse without edit");

    reset(&field, ":hi ");
    field.view().set_editable(false);
    assert!(matches!(
        snippet.prepare(
            field.snapshot().unwrap(),
            Origin::CommittedUser,
            Instant::now(),
            Duration::from_secs(1)
        ),
        Err(Rejection::Unsupported)
    ));
    assert_eq!(field.snapshot().unwrap().text, ":hi ");
    field.view().set_editable(true);
    reset(&field, ":hi ");
    let p = prepare(&field, &snippet);
    field.view().buffer().insert_at_cursor("x");
    assert_eq!(
        execute(&mut field, p, Instant::now),
        Outcome::FailedBeforeEdit(Rejection::Changed)
    );
    assert_eq!(field.snapshot().unwrap().text, ":hi x");
    println!("PASS TEXT-05: unavailable range output and intervening input refuse");

    reset(&field, "left :hi ");
    let p = prepare(&field, &snippet);
    let fired = Rc::new(Cell::new(false));
    let f = fired.clone();
    let b = field.view().buffer();
    let hook = b.connect_changed(move |buffer| {
        let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), true);
        if text == "left " && !f.replace(true) {
            buffer.insert_at_cursor("external");
        }
    });
    assert_eq!(
        execute(&mut field, p, Instant::now),
        Outcome::IndeterminateAfterEdit
    );
    assert!(fired.get());
    assert!(!field.applying());
    assert_eq!(field.snapshot().unwrap().text, "left external");
    assert_eq!(field.snapshot().unwrap().caret, 13);
    b.disconnect(hook);
    println!(
        "PASS TEXT-06: reentrant edit after deletion stops insertion; no retry, caret verified"
    );
    reset(&field, ":hi ");
    field.view().set_input_purpose(gtk::InputPurpose::Password);
    assert!(matches!(field.snapshot(), Err(Rejection::Context)));
    let b = field.view().buffer();
    assert_eq!(b.text(&b.start_iter(), &b.end_iter(), true), ":hi ");
    field.view().set_input_purpose(gtk::InputPurpose::FreeForm);
    println!("PASS TEXT-08: sensitive input purpose refuses snapshot before reading text");
    // Programmatic button activation exercises the same callback as the demo;
    // pointer delivery is a separate native case, not implied by emit_clicked.
    let result = Rc::new(Cell::new(None));
    let r = result.clone();
    let button = field.correction_button(
        "US → RU",
        typetune_engine::Direction::UsToRu,
        move |outcome| r.set(Some(outcome)),
    );
    layout.append(&button);
    reset(&field, "до GhBdTn  хвост");
    let b = field.view().buffer();
    b.place_cursor(&b.iter_at_offset(11));
    button.emit_clicked();
    assert_eq!(result.get(), Some(Outcome::Completed));
    let corrected = field.snapshot().unwrap();
    assert_eq!(corrected.text, "до ПрИвЕт  хвост");
    assert_eq!(corrected.caret, 11);
    assert_eq!(corrected.anchor, 11);
    println!("PASS MANUAL-01: GTK button callback, mixed case, spaces, surrounding text and caret");
    reset(&field, "ghbdtn");
    second.grab_focus();
    wait_for(|| !field.view().has_focus());
    button.emit_clicked();
    assert!(matches!(result.get(), Some(Outcome::FailedBeforeEdit(_))));
    assert_eq!(field.snapshot().unwrap().text, "ghbdtn");
    println!("PASS MANUAL-02: button callback refuses other-field focus, source intact");
    reset(&field, "");
    let completions = Rc::new(Cell::new(0));
    let c = completions.clone();
    field
        .install_snippet(snippet, move |result| {
            assert_eq!(result, Outcome::Completed);
            c.set(c.get() + 1);
        })
        .unwrap();
    let ready = std::path::PathBuf::from(std::env::var_os("TYPETUNE_NESTED_STAND").unwrap())
        .join("text-ready");
    std::fs::write(ready, b"ready").unwrap();
    wait_for(|| completions.get() == 1);
    let typed = field.snapshot().unwrap();
    assert_eq!(typed.text, "Привет, WORLD! 👋\ne\u{301} ");
    assert_eq!(typed.caret, typed.text.chars().count());
    assert_eq!(typed.anchor, typed.caret);
    assert_eq!(completions.get(), 1);
    println!("PASS TEXT-07: compositor keyboard -> GTK commit -> automatic static snippet; Unicode/caret read back");
    let base = std::path::PathBuf::from(std::env::var_os("TYPETUNE_NESTED_STAND").unwrap());
    let motion = gtk::EventControllerMotion::new();
    let coordinates = base.join("pointer-position");
    let write_position = move |x, y| {
        let temp = coordinates.with_extension("tmp");
        std::fs::write(&temp, format!("{x} {y}")).unwrap();
        std::fs::rename(temp, &coordinates).unwrap();
    };
    let enter_position = write_position.clone();
    motion.connect_enter(move |_, x, y| enter_position(x, y));
    motion.connect_motion(move |_, x, y| write_position(x, y));
    window.add_controller(motion);
    window.fullscreen();
    wait_for(|| window.is_fullscreen() && window.width() == 800);
    let reverse_result = Rc::new(Cell::new(None));
    let r = reverse_result.clone();
    let reverse = field.correction_button(
        "RU → US",
        typetune_engine::Direction::RuToUs,
        move |outcome| r.set(Some(outcome)),
    );
    layout.append(&reverse);
    wait_for(|| reverse.width() > 0);
    for (index, widget, source, expected, output) in [
        (0, &button, "ghbdtn ", "привет ", &result),
        (1, &reverse, "руддщ ", "hello ", &reverse_result),
    ] {
        reset(&field, source);
        output.set(None);
        let point = widget
            .compute_point(
                &window,
                &gtk::graphene::Point::new(
                    widget.width() as f32 / 2.0,
                    widget.height() as f32 / 2.0,
                ),
            )
            .unwrap();
        std::fs::write(
            base.join(format!("pointer-{index}")),
            format!("{} {}", point.x(), point.y()),
        )
        .unwrap();
        wait_for(|| output.get().is_some());
        assert_eq!(output.get(), Some(Outcome::Completed));
        let after = field.snapshot().unwrap();
        assert_eq!(after.text, expected);
        assert_eq!(after.caret, expected.chars().count());
        assert_eq!(after.anchor, after.caret);
        assert!(field.view().has_focus());
    }
    println!("PASS LOCAL-01: real pointer clicks in both directions, focus/text/caret verified");
    let outcomes = Rc::new(std::cell::RefCell::new(Vec::new()));
    let o = outcomes.clone();
    field
        .install_correction_shortcuts(move |outcome| o.borrow_mut().push(outcome))
        .unwrap();
    for index in 0..6 {
        reset(&field, if index == 1 { "руддщ " } else { "ghbdtn " });
        outcomes.borrow_mut().clear();
        std::fs::write(base.join(format!("shortcut-{index}")), b"ready").unwrap();
        wait_for(|| base.join(format!("held-{index}")).exists());
        assert!(outcomes.borrow().is_empty());
        assert_eq!(
            field.snapshot().unwrap().text,
            if index == 1 { "руддщ " } else { "ghbdtn " }
        );
        if index == 3 {
            field.view().buffer().insert_at_cursor("x");
        }
        if index == 5 {
            second.grab_focus();
            wait_for(|| !field.view().has_focus());
            field.view().grab_focus();
            wait_for(|| field.view().has_focus());
        }
        std::fs::write(base.join(format!("release-{index}")), b"ready").unwrap();
        wait_for(|| !outcomes.borrow().is_empty());
        let expected = match index {
            0 => "привет ",
            1 => "hello ",
            2 => "ghbdtn ",
            3 => "ghbdtn x",
            _ => "ghbdtn ",
        };
        let after = field.snapshot().unwrap();
        assert_eq!(after.text, expected);
        assert_eq!(after.caret, expected.chars().count());
        assert_eq!(after.anchor, after.caret);
        assert_eq!(outcomes.borrow().len(), 1);
        if index < 2 {
            assert_eq!(outcomes.borrow()[0], Outcome::Completed);
        } else {
            assert!(matches!(outcomes.borrow()[0], Outcome::FailedBeforeEdit(_)));
        }
    }
    println!("PASS LOCAL-02: F8/F9 release executes once; no edit while held");
    println!("PASS LOCAL-03: Shift+F8 and intervening input refuse, exact text/caret");
    println!("PASS LOCAL-04: expired hold and focus round trip refuse, source/caret intact");
    window.close();
    println!("GTK TEXT STAND PASS (cooperating field, synthetic commits)");
}
