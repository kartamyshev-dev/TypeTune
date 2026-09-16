// Prepare sorted immutable lookup tables at build time, never in the input path.
use std::{collections::BTreeMap, env, fs, path::PathBuf};
fn main() {
    let mut output = String::from(
        "// Derived FrequencyWords data: CC-BY-SA-4.0; see data/frequency/README.md.\n",
    );
    for lang in ["en", "ru"] {
        let path = format!("data/frequency/{lang}_50k.txt");
        println!("cargo:rerun-if-changed={path}");
        let input = fs::read_to_string(&path).expect("missing/invalid frequency dictionary");
        let mut words = BTreeMap::new();
        let mut previous = u64::MAX;
        for (i, line) in input.lines().enumerate() {
            let (word, count) = line.rsplit_once(' ').expect("invalid frequency row");
            let count: u64 = count.parse().expect("invalid frequency count");
            assert!(count > 0 && count <= previous, "frequency order changed");
            previous = count;
            if !(1..=32).contains(&word.chars().count())
                || !word.chars().all(|c| match lang {
                    "en" => c.is_ascii_lowercase(),
                    _ => ('а'..='я').contains(&c) || c == 'ё',
                })
            {
                continue;
            }
            assert!(
                words.insert(word, i + 1).is_none(),
                "duplicate frequency word"
            );
        }
        assert_eq!(input.lines().count(), 50_000, "incomplete dictionary");
        output.push_str(&format!(
            "static {}: &[(&str, usize)] = &[\n",
            lang.to_uppercase()
        ));
        for (word, rank) in words {
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
