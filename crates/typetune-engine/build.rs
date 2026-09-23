// Prepare sorted immutable lookup tables at build time, never in the input path.
use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
};

fn valid_word(word: &str, lang: &str) -> bool {
    let n = word.chars().count();
    (1..=32).contains(&n)
        && word.chars().all(|c| match lang {
            "en" => c.is_ascii_lowercase(),
            _ => ('а'..='я').contains(&c) || c == 'ё',
        })
}

fn load_frequency(path: &Path, lang: &str) -> BTreeMap<String, usize> {
    let input = fs::read_to_string(path).expect("missing/invalid frequency dictionary");
    let mut words = BTreeMap::new();
    let mut previous = u64::MAX;
    for (i, line) in input.lines().enumerate() {
        let (word, count) = line.rsplit_once(' ').expect("invalid frequency row");
        let count: u64 = count.parse().expect("invalid frequency count");
        assert!(count > 0 && count <= previous, "frequency order changed");
        previous = count;
        if !valid_word(word, lang) {
            continue;
        }
        assert!(
            words.insert(word.to_string(), i + 1).is_none(),
            "duplicate frequency word"
        );
    }
    assert_eq!(input.lines().count(), 50_000, "incomplete dictionary");
    words
}

fn load_leeds(path: &Path) -> BTreeMap<String, usize> {
    let input = fs::read_to_string(path).expect("missing/invalid leeds list");
    let mut words = BTreeMap::new();
    for (i, line) in input.lines().enumerate() {
        let word = line.trim();
        if word.is_empty() || !valid_word(word, "ru") {
            continue;
        }
        assert!(
            words.insert(word.to_string(), i + 1).is_none(),
            "duplicate leeds word"
        );
    }
    assert_eq!(input.lines().count(), 50_000, "incomplete leeds list");
    words
}

fn load_tech(path: &Path, lang: &str) -> Vec<String> {
    let input = fs::read_to_string(path).expect("missing tech vocabulary");
    let mut out = Vec::new();
    for line in input.lines() {
        let word = line.trim();
        if word.is_empty() || word.starts_with('#') {
            continue;
        }
        assert!(valid_word(word, lang), "invalid tech word: {word}");
        assert!(
            !out.iter().any(|w: &String| w == word),
            "duplicate tech word"
        );
        out.push(word.to_string());
    }
    assert!(!out.is_empty(), "empty tech vocabulary");
    out
}

fn tech_boost_rank(word: &str) -> usize {
    // Comfortably under the matcher thresholds (2→100, 3→1000, 4+→20000)
    // without changing those thresholds.
    match word.chars().count() {
        1 => 50,
        2 => 50,
        3 => 100,
        _ => 100,
    }
}

fn apply_min(words: &mut BTreeMap<String, usize>, word: &str, rank: usize) {
    match words.get_mut(word) {
        Some(existing) if rank < *existing => *existing = rank,
        Some(_) => {}
        None => {
            words.insert(word.to_string(), rank);
        }
    }
}

/// Conservative English regular plurals from frequent lemmas.
/// Exactly one form per lemma (review 2026-09-22, P0): never both `s` and `es`.
///
/// - lemma already ending in `s` (upstream plurals like `cats`, sibilant
///   singulars like `bus`/`class`) → no generation;
/// - `x`/`z`/`ch`/`sh` → only `es` (`boxes`, never `boxs`);
/// - consonant + `y` → only `ies` (`stories`, never `storys`/`flys`);
/// - final `e` and `-o` → only `s` (`horses`/`photos`, never `horsees`);
/// - `f`/`fe` → skipped (irregular `leaves`/`knives`);
/// - everything else → only `s` (`cats`, never `cates`).
fn add_en_plural_forms(words: &mut BTreeMap<String, usize>, lemma: &str, lemma_rank: usize) {
    if lemma_rank > 15_000 || lemma.is_empty() || !lemma.chars().all(|c| c.is_ascii_lowercase()) {
        return;
    }
    if lemma.ends_with('s') {
        return;
    }
    if lemma.ends_with('f') || lemma.ends_with("fe") {
        return;
    }
    let form = if lemma.ends_with('y')
        && lemma.len() > 1
        && !matches!(
            lemma.as_bytes()[lemma.len() - 2],
            b'a' | b'e' | b'i' | b'o' | b'u'
        ) {
        format!("{}ies", &lemma[..lemma.len() - 1])
    } else if lemma.ends_with('x')
        || lemma.ends_with('z')
        || lemma.ends_with("ch")
        || lemma.ends_with("sh")
    {
        format!("{lemma}es")
    } else {
        format!("{lemma}s")
    };
    if valid_word(&form, "en") {
        apply_min(words, &form, lemma_rank + 500);
    }
}

fn main() {
    let mut output = String::from(
        "// Derived tables: FrequencyWords CC-BY-SA-4.0; Leeds CC-BY-2.5;\n\
         // tech vocab MIT. See data/frequency/README.md and data/tech/README.md.\n",
    );
    for lang in ["en", "ru"] {
        let path = format!("data/frequency/{lang}_50k.txt");
        println!("cargo:rerun-if-changed={path}");
        let mut words = load_frequency(Path::new(&path), lang);

        if lang == "ru" {
            let leeds_path = "data/frequency/leeds_ru_50k.txt";
            println!("cargo:rerun-if-changed={leeds_path}");
            let leeds = load_leeds(Path::new(leeds_path));
            // ADR-010: map Leeds positions onto the shared N = 50 000 score
            // base before min-merge (identity while leeds_total == 50 000).
            let leeds_total = 50_000usize;
            for (word, rank) in leeds {
                let scaled = rank
                    .checked_mul(50_000)
                    .expect("leeds rank overflow")
                    .div_ceil(leeds_total);
                apply_min(&mut words, &word, scaled);
            }
        }

        let tech_path = format!("data/tech/{lang}.txt");
        println!("cargo:rerun-if-changed={tech_path}");
        for word in load_tech(Path::new(&tech_path), lang) {
            apply_min(&mut words, &word, tech_boost_rank(&word));
        }

        if lang == "en" {
            let lemmas: Vec<(String, usize)> = words
                .iter()
                .filter(|(w, r)| **r <= 5_000 && w.chars().count() >= 3)
                .map(|(w, r)| (w.clone(), *r))
                .collect();
            for (lemma, rank) in lemmas {
                add_en_plural_forms(&mut words, &lemma, rank);
            }
        }

        output.push_str(&format!(
            "static {}: &[(&str, usize)] = &[\n",
            lang.to_uppercase()
        ));
        // BTreeMap iterates sorted by word — required for rank() binary search.
        for (word, rank) in &words {
            output.push_str(&format!("({word:?},{rank}),\n"));
        }
        output.push_str("];\n");
    }
    fs::write(
        PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("lexicons.rs"),
        output,
    )
    .unwrap();
}
