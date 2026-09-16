use super::*;
use typetune_core::clock::{Clock, FakeClock};
struct Editor {
    state: Snapshot,
    calls: usize,
    partial: bool,
}
impl RangeEditor for Editor {
    fn snapshot(&self) -> Result<Snapshot, Rejection> {
        Ok(self.state.clone())
    }
    fn apply(&mut self, plan: &Plan, now: &dyn Fn() -> Instant) -> ApplyResult {
        if plan.expired(now()) {
            return ApplyResult::Rejected(Rejection::Expired);
        }
        self.calls += 1;
        if self.state != *plan.before() {
            return ApplyResult::Rejected(Rejection::Changed);
        }
        let replacement = if self.partial { "" } else { plan.replacement() };
        self.state.text = replace_chars(&self.state.text, plan.range(), replacement).unwrap();
        self.state.caret = plan.range().start + replacement.chars().count();
        self.state.anchor = self.state.caret;
        self.state.revision += 1;
        if self.partial {
            ApplyResult::Indeterminate
        } else {
            ApplyResult::Applied
        }
    }
}
fn editor(text: &str) -> Editor {
    Editor {
        state: Snapshot {
            target: 1,
            epoch: 1,
            revision: 1,
            text: text.into(),
            caret: text.chars().count(),
            anchor: text.chars().count(),
            focused: Some(true),
            normal_field: Some(true),
            composing: Some(false),
            modifiers_clear: Some(true),
            unicode_range: Some(true),
        },
        calls: 0,
        partial: false,
    }
}
fn plan(e: &Editor, clock: &FakeClock) -> Plan {
    StaticSnippet::new(":hi", "Привет, WORLD! 👋\ne\u{301}")
        .unwrap()
        .prepare(
            e.state.clone(),
            Origin::CommittedUser,
            clock.now(),
            Duration::from_millis(100),
        )
        .unwrap()
        .unwrap()
}
#[test]
fn unicode_range_preserves_prefix_suffix_caret_and_one_delimiter() {
    let clock = FakeClock::at_zero();
    let mut e = editor("я :hi хвост");
    e.state.caret = 6;
    e.state.anchor = 6;
    let p = plan(&e, &clock);
    assert_eq!(execute(&mut e, p, || clock.now()), Outcome::Completed);
    assert_eq!(e.state.text, "я Привет, WORLD! 👋\ne\u{301} хвост");
    assert_eq!(
        e.state.caret,
        "я Привет, WORLD! 👋\ne\u{301} ".chars().count()
    );
    assert_eq!(e.state.anchor, e.state.caret);
    assert_eq!(e.calls, 1);
}
#[test]
fn every_guard_rejects_unknown_before_edit() {
    let snippet = StaticSnippet::new(":hi", "hello").unwrap();
    for field in 0..6 {
        let mut e = editor(":hi ");
        match field {
            0 => e.state.focused = None,
            1 => e.state.normal_field = None,
            2 => e.state.composing = None,
            3 => e.state.modifiers_clear = None,
            4 => e.state.unicode_range = None,
            _ => e.state.anchor = 0,
        }
        assert!(snippet
            .prepare(
                e.state.clone(),
                Origin::CommittedUser,
                Instant::now(),
                Duration::from_secs(1)
            )
            .is_err());
        assert_eq!(e.state.text, ":hi ");
        assert_eq!(e.calls, 0);
    }
}
#[test]
fn changed_target_revision_caret_selection_and_context_cancel() {
    let clock = FakeClock::at_zero();
    for field in 0..7 {
        let mut e = editor(":hi ");
        let p = plan(&e, &clock);
        match field {
            0 => e.state.target += 1,
            1 => e.state.epoch += 2,
            2 => e.state.revision += 1,
            3 => e.state.caret = 0,
            4 => e.state.anchor = 0,
            5 => e.state.composing = Some(true),
            _ => e.state.focused = Some(false),
        }
        let before = e.state.text.clone();
        assert_eq!(
            execute(&mut e, p, || clock.now()),
            Outcome::FailedBeforeEdit(Rejection::Changed)
        );
        assert_eq!(e.state.text, before);
        assert_eq!(e.calls, 0);
    }
}
#[test]
fn expiry_and_future_time_do_not_edit() {
    let clock = FakeClock::at_zero();
    let mut e = editor(":hi ");
    let p = plan(&e, &clock);
    clock.advance(Duration::from_millis(100));
    assert_eq!(
        execute(&mut e, p, || clock.now()),
        Outcome::FailedBeforeEdit(Rejection::Expired)
    );
    let p = plan(&e, &clock);
    assert_eq!(
        execute(&mut e, p, || clock.now() - Duration::from_millis(1)),
        Outcome::FailedBeforeEdit(Rejection::Expired)
    );
    assert_eq!(e.calls, 0);
}
#[test]
fn own_or_unknown_output_cannot_retrigger() {
    let snippet = StaticSnippet::new(":hi", ":hi").unwrap();
    let e = editor(":hi ");
    for origin in [Origin::OwnReplacement, Origin::Unknown] {
        assert!(matches!(
            snippet.prepare(
                e.state.clone(),
                origin,
                Instant::now(),
                Duration::from_secs(1)
            ),
            Err(Rejection::Origin)
        ));
    }
}
#[test]
fn space_and_word_boundary_only() {
    let snippet = StaticSnippet::new(":hi", "hello").unwrap();
    for text in ["abc:hi ", ":hi\n", ":hi\t", ":hi"] {
        assert!(snippet
            .prepare(
                editor(text).state,
                Origin::CommittedUser,
                Instant::now(),
                Duration::from_secs(1)
            )
            .unwrap()
            .is_none());
    }
}
#[test]
fn partial_edit_stops_without_retry() {
    let clock = FakeClock::at_zero();
    let mut e = editor("left :hi ");
    e.partial = true;
    let p = plan(&e, &clock);
    assert_eq!(
        execute(&mut e, p, || clock.now()),
        Outcome::IndeterminateAfterEdit
    );
    assert_eq!(e.state.text, "left ");
    assert_eq!(e.state.caret, 5);
    assert_eq!(e.calls, 1);
}
#[test]
fn oversized_or_nul_renderer_rejected_before_deletion() {
    assert!(matches!(
        StaticSnippet::new(":hi", &"x".repeat(4096)),
        Err(Rejection::Limit)
    ));
    assert!(matches!(
        StaticSnippet::new(":hi", "bad\0text"),
        Err(Rejection::InvalidSnippet)
    ));
    let mut e = editor(":hi ");
    e.state.text = "x".repeat(MAX_DOCUMENT_BYTES + 1);
    assert_eq!(e.state.check(), Err(Rejection::Limit));
    assert_eq!(e.calls, 0);
}

#[test]
fn successful_api_call_without_expected_content_is_indeterminate() {
    struct Lying(Editor);
    impl RangeEditor for Lying {
        fn snapshot(&self) -> Result<Snapshot, Rejection> {
            self.0.snapshot()
        }
        fn apply(&mut self, plan: &Plan, now: &dyn Fn() -> Instant) -> ApplyResult {
            self.0.apply(plan, now);
            ApplyResult::Applied
        }
    }
    let clock = FakeClock::at_zero();
    let mut e = editor(":hi ");
    let p = plan(&e, &clock);
    e.partial = true;
    let mut backend = Lying(e);
    assert_eq!(
        execute(&mut backend, p, || clock.now()),
        Outcome::IndeterminateAfterEdit
    );
    assert_eq!(backend.0.state.text, "");
    assert_eq!(backend.0.state.caret, 0);
    assert_eq!(backend.0.calls, 1);
}

#[test]
fn manual_mapping_case_delimiters_and_surroundings() {
    let clock = FakeClock::at_zero();
    for (source, expected, direction) in [
        ("ghbdtn", "привет", Direction::UsToRu),
        ("GhBdTn  ", "ПрИвЕт  ", Direction::UsToRu),
        ("GHBDTN", "ПРИВЕТ", Direction::UsToRu),
        ("руддщ ", "hello ", Direction::RuToUs),
        ("ЁХЪЖЭБЮ", "~{}:\"<>", Direction::RuToUs),
        ("`[];' ,.", "`[];' бю", Direction::UsToRu),
    ] {
        let mut e = editor(&format!("до {source} хвост"));
        e.state.caret = 3 + source.chars().count();
        e.state.anchor = e.state.caret;
        let p = prepare_manual(
            e.state.clone(),
            direction,
            clock.now(),
            Duration::from_secs(1),
        )
        .unwrap();
        assert_eq!(execute(&mut e, p, || clock.now()), Outcome::Completed);
        assert_eq!(e.state.text, format!("до {expected} хвост"));
        assert_eq!(e.state.caret, 3 + expected.chars().count());
        assert_eq!(e.state.anchor, e.state.caret);
    }
}
#[test]
fn manual_refuses_unsupported_tokens_and_partial_words() {
    for text in [
        "", "   ", "ghbdtn\n", "ghbdtn\t", "abcЯ", "abc123", "x@y", "a/b", "é", "🙂",
    ] {
        let e = editor(text);
        assert!(prepare_manual(
            e.state,
            Direction::UsToRu,
            Instant::now(),
            Duration::from_secs(1)
        )
        .is_err());
    }
    let mut e = editor("ghbdtn");
    e.state.caret = 3;
    e.state.anchor = 3;
    assert!(prepare_manual(
        e.state,
        Direction::UsToRu,
        Instant::now(),
        Duration::from_secs(1)
    )
    .is_err());
}
#[test]
fn manual_stale_expired_and_partial_use_same_executor() {
    let clock = FakeClock::at_zero();
    for mode in 0..4 {
        let mut e = editor("ghbdtn ");
        let p = prepare_manual(
            e.state.clone(),
            Direction::UsToRu,
            clock.now(),
            Duration::from_millis(100),
        )
        .unwrap();
        match mode {
            0 => e.state.focused = Some(false),
            1 => e.state.anchor = 0,
            2 => clock.advance(Duration::from_millis(100)),
            _ => e.partial = true,
        }
        let result = execute(&mut e, p, || clock.now());
        if mode == 3 {
            assert_eq!(result, Outcome::IndeterminateAfterEdit);
            assert_eq!(e.calls, 1);
            assert_eq!(e.state.text, "");
            assert_eq!(e.state.caret, 0);
        } else {
            assert!(matches!(result, Outcome::FailedBeforeEdit(_)));
            assert_eq!(e.calls, 0);
            assert_eq!(e.state.text, "ghbdtn ");
        }
    }
}

#[test]
fn manual_after_spaces_immediately_before_following_word() {
    let clock = FakeClock::at_zero();
    let mut e = editor("до GhBdTn  хвост");
    e.state.caret = 11;
    e.state.anchor = 11;
    let p = prepare_manual(
        e.state.clone(),
        Direction::UsToRu,
        clock.now(),
        Duration::from_secs(1),
    )
    .unwrap();
    assert_eq!(execute(&mut e, p, || clock.now()), Outcome::Completed);
    assert_eq!(e.state.text, "до ПрИвЕт  хвост");
    assert_eq!(e.state.caret, 11);
}

#[test]
fn external_editor_without_composition_evidence_refuses_manual_correction() {
    let mut e = editor("до ghbdtn хвост");
    e.state.caret = 9;
    e.state.anchor = 9;
    e.state.composing = None; // AT-SPI Text/EditableText does not prove inactive IME.
    let before = e.state.clone();
    assert!(matches!(
        prepare_manual(
            e.state.clone(),
            Direction::UsToRu,
            Instant::now(),
            Duration::from_secs(1)
        ),
        Err(Rejection::Context)
    ));
    assert!(e.state == before);
    assert_eq!(e.calls, 0);
}

#[test]
fn autocorrection_corpus_editor_and_inferred_agree() {
    let clock = FakeClock::at_zero();
    let mut missed = 0;
    let mut false_changes = 0;
    let mut positive = 0;
    let mut negative = 0;
    for row in include_str!("../data/auto-corpus.tsv")
        .lines()
        .filter(|r| !r.starts_with('#'))
    {
        let cols: Vec<_> = row.split('\t').collect();
        let before = format!("{} ", cols[2]);
        let expected = format!("{} ", cols[3]);
        let mut e = editor(&format!("prefix {before}"));
        if let Some((plan, _)) =
            prepare_automatic(e.state.clone(), clock.now(), Duration::from_secs(1)).unwrap()
        {
            assert_eq!(execute(&mut e, plan, || clock.now()), Outcome::Completed);
        }
        let inferred = inferred::suggest(&before, true)
            .map(|s| s.replacement)
            .unwrap_or(before);
        assert_eq!(e.state.text, format!("prefix {inferred}"));
        assert_eq!(e.state.caret, e.state.text.chars().count());
        assert_eq!(e.state.anchor, e.state.caret);
        if cols[1] == "positive" {
            let deferred = [
                "клавиатуры",
                "настройками",
                "исправления",
                "сохранение",
                "переключения",
                "keyboards",
            ]
            .contains(&cols[3]);
            assert_eq!(
                inferred,
                if deferred {
                    format!("{} ", cols[2])
                } else {
                    expected.clone()
                },
                "{}",
                cols[3]
            );
            positive += 1;
            if inferred != expected {
                missed += 1;
                eprintln!("MISS {} {}", cols[0], cols[3]);
            }
        } else {
            negative += 1;
            if inferred != expected {
                false_changes += 1;
                eprintln!("FALSE {}", cols[2]);
            }
        }
    }
    eprintln!(
        "AUTO-CORPUS positive={positive} missed={missed} negative={negative} false={false_changes}"
    );
    assert_eq!(false_changes, 0);
    // Frozen policy rollout: do not widen the rank cutoff to fit holdout misses.
    assert_eq!(missed, 6);
}

#[test]
fn short_frequent_words_preserve_editor_state_and_inferred_parity() {
    let clock = FakeClock::at_zero();
    for (input, expected) in [
        ("rfr ", "как "),
        ("Rfr ", "Как "),
        ("RFR ", "КАК "),
        ("xnj ", "что "),
        ("ult ", "где "),
        ("rnj ", "кто "),
        ("'nj ", "это "),
        ("еру ", "the "),
        ("cat ", "cat "),
        ("yet ", "yet "),
        ("как ", "как "),
        ("the ", "the "),
        ("нет ", "нет "),
        ("да ", "да "),
        ("lf ", "lf "),
        ("z ", "z "),
        ("сфе ", "сфе "),
        ("rFr ", "rFr "),
        ("rfr", "rfr"),
        ("rfr  ", "rfr  "),
        ("rfr42 ", "rfr42 "),
        ("rfr_ ", "rfr_ "),
        ("https://rfr ", "https://rfr "),
        ("/rfr ", "/rfr "),
        ("a@rfr ", "a@rfr "),
        ("foo::rfr ", "foo::rfr "),
    ] {
        let mut e = editor(&format!("prefix {input}suffix"));
        e.state.caret = "prefix ".chars().count() + input.chars().count();
        e.state.anchor = e.state.caret;
        if let Some((plan, _)) =
            prepare_automatic(e.state.clone(), clock.now(), Duration::from_secs(1)).unwrap()
        {
            assert_eq!(execute(&mut e, plan, || clock.now()), Outcome::Completed);
        }
        assert_eq!(e.state.text, format!("prefix {expected}suffix"), "{input}");
        assert_eq!(
            e.state.caret,
            "prefix ".chars().count() + expected.chars().count()
        );
        assert_eq!(e.state.anchor, e.state.caret);
        assert_eq!(
            inferred::suggest(input, true)
                .map(|s| s.replacement)
                .unwrap_or(input.into()),
            expected
        );
    }
}

#[test]
fn two_letter_words_preserve_context_and_reject_ambiguous_input() {
    let clock = FakeClock::at_zero();
    for (input, expected) in [
        (",s ", "бы "),
        ("<s ", "Бы "),
        ("<S ", "БЫ "),
        ("yt ", "не "),
        ("jy ", "он "),
        ("ещ ", "to "),
        ("шт ", "in "),
        ("ye ", "ye "),
        ("lf ", "lf "),
        ("vs ", "vs "),
        ("бы ", "бы "),
        ("to ", "to "),
        ("in ", "in "),
        ("да ", "да "),
        ("z ", "z "),
        (",s", ",s"),
        (",s  ", ",s  "),
        (",s42 ", ",s42 "),
        ("/,s ", "/,s "),
        ("https://,s ", "https://,s "),
        ("a@,s ", "a@,s "),
        (",s_ ", ",s_ "),
    ] {
        let mut e = editor(&format!("prefix {input}suffix"));
        e.state.caret = 7 + input.chars().count();
        e.state.anchor = e.state.caret;
        if let Some((plan, direction)) =
            prepare_automatic(e.state.clone(), clock.now(), Duration::from_secs(1)).unwrap()
        {
            assert!(matches!(
                (direction, expected),
                (Direction::RuToUs, "to " | "in ")
                    | (Direction::UsToRu, "бы " | "Бы " | "БЫ " | "не " | "он ")
            ));
            assert_eq!(execute(&mut e, plan, || clock.now()), Outcome::Completed);
        }
        assert_eq!(e.state.text, format!("prefix {expected}suffix"), "{input}");
        assert_eq!(e.state.caret, 7 + expected.chars().count());
        assert_eq!(e.state.anchor, e.state.caret);
        assert_eq!(
            inferred::suggest(input, true)
                .map(|s| s.replacement)
                .unwrap_or(input.into()),
            expected,
            "{input}"
        );
    }
    for (focused, composing, anchor) in [
        (None, Some(false), 3),
        (Some(true), None, 3),
        (Some(true), Some(false), 0),
    ] {
        let mut e = editor(",s ");
        e.state.focused = focused;
        e.state.composing = composing;
        e.state.anchor = anchor;
        let before = e.state.clone();
        assert!(prepare_automatic(before.clone(), clock.now(), Duration::from_secs(1)).is_err());
        assert!(e.state == before);
        assert_eq!(e.calls, 0);
    }
}

#[test]
fn user_words_and_exclusions_apply_to_both_profiles_without_changing_manual() {
    let clock = FakeClock::at_zero();
    let custom = UserDictionary::new(vec!["Клавиатуры".into()], vec![]).unwrap();
    let excluded = UserDictionary::new(vec![], vec!["Привет".into()]).unwrap();
    let protected = UserDictionary::new(vec!["ghbdtn".into()], vec![]).unwrap();
    for (dictionary, input, expected) in [
        (&custom, "rkfdbfnehs ", "клавиатуры "),
        (&custom, "клавиатуры ", "клавиатуры "),
        (&excluded, "ghbdtn ", "ghbdtn "),
        (&protected, "ghbdtn ", "ghbdtn "),
    ] {
        let mut e = editor(&format!("prefix {input}suffix"));
        e.state.caret = 7 + input.chars().count();
        e.state.anchor = e.state.caret;
        if let Some((plan, _)) = prepare_automatic_with_dictionary(
            e.state.clone(),
            clock.now(),
            Duration::from_secs(1),
            dictionary,
        )
        .unwrap()
        {
            assert_eq!(execute(&mut e, plan, || clock.now()), Outcome::Completed);
        }
        assert_eq!(e.state.text, format!("prefix {expected}suffix"));
        assert_eq!(e.state.caret, 7 + expected.chars().count());
        assert_eq!(e.state.anchor, e.state.caret);
        assert_eq!(
            inferred::suggest_with_dictionary(input, true, dictionary)
                .map(|s| s.replacement)
                .unwrap_or(input.into()),
            expected
        );
    }
    assert!(inferred::suggest("rkfdbfnehs ", true).is_none());
    assert_eq!(
        inferred::suggest_with_dictionary("ghbdtn ", false, &excluded)
            .unwrap()
            .replacement,
        "привет "
    );
    assert!(UserDictionary::new(vec!["привеt".into()], vec![]).is_err());
    assert!(UserDictionary::new(vec![], vec!["x".into()]).is_err());
    assert!(UserDictionary::new(vec!["hello".into(); 501], vec![]).is_err());
}
