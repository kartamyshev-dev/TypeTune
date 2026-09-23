# FrequencyWords data attribution

## Primary frequency (both languages)

Copyright / attribution: Hermit Dave and FrequencyWords contributors.
Source: [FrequencyWords](https://github.com/hermitdave/FrequencyWords/tree/525f9b560de45753a5ea01069454e72e9aa541c6),
2018 lists derived from [OPUS OpenSubtitles2018](https://opus.nlpl.eu/OpenSubtitles2018.php).
Revision: `525f9b560de45753a5ea01069454e72e9aa541c6`.

The two `*_50k.txt` files are unmodified upstream content licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
See the included [license](LICENSE.html), [upstream statement](upstream-README.md)
and [SHA-256 manifest](manifest.json). No endorsement is implied.
TypeTune's MIT code license does not replace this data license.

## Secondary frequency (RU): Leeds Internet Corpus list

File: `leeds_ru_50k.txt` — 50 000 one-token lines, unmodified mirror of
`50000-russian-words-cyrillic-only.txt` from
[hingston/russian](https://github.com/hingston/russian) (upstream
[corpus.leeds.ac.uk/frqc/internet-ru.num](http://corpus.leeds.ac.uk/frqc/internet-ru.num)).
License: [CC BY 2.5](https://creativecommons.org/licenses/by/2.5/); corpus
editing/cleanup attribution: hingston — see `LICENSE-leeds.txt`.
SHA-256: `57fe4356417987c1d0221f32e20b5afeaf45fb7b6c318a9f8f55fb119b81c05f`.

## Derived tables (plan 57 D2)

Leeds ranks are scaled onto the shared `N = 50 000` score base before the
min-merge: `scaled = ceil(leeds_rank * 50000 / leeds_total)` where
`leeds_total` is the number of lines in `leeds_ru_50k.txt` (currently 50 000,
so the factor is 1; the formula keeps the scales aligned if the list length
changes). See ADR-010 in `docs/13-target-architecture.md`.

TypeTune derives immutable sorted tables at build time (`../../build.rs`):

1. Start from primary `*_50k.txt` ranks (line number).
2. RU: merge Leeds ranks with `min(existing, leeds)`.
3. Apply tech-vocabulary boosts from `../tech/{en,ru}.txt` (MIT) so curated
   forms sit under existing matcher thresholds without changing 100/1000/20000.
4. EN: exactly one regular plural per lemma with rank ≤ 5 000, at
   `lemma_rank + 500`. Lemmas ending in `s` are skipped (upstream plurals);
   `x`/`z`/`ch`/`sh` → `+es`; consonant+`y` → `y→ies`; final `e`/`-o` and
   other stems → `+s`; `f`/`fe` are skipped (irregular `leaves`/`knives`).
5. Filter: lowercase ASCII / Cyrillic+ё, length 1–32; reject duplicates.

Retained primary entries still protect valid source words (any merged rank).
Targets for length 4–32 need merged rank ≤ 20 000 (or pilot/tech under that);
length 3 ≤ 1 000; length 2 ≤ 100; length 1 excluded. Rank is a conservative
cutoff, not a calibrated confidence probability. Subtitle data includes names,
slang and errors; Leeds and tech lists are not a complete morphological
authority. No automatic ё/е folding is applied.

The derived tables embed primary CC BY-SA 4.0 and Leeds CC BY 2.5 content and
must keep attribution when redistributed (preview installer ships this directory).

Reproduce and verify from the repository root:

```sh
python3 scripts/verify-frequency-data.py --download
python3 scripts/verify-frequency-data.py
cargo test -p typetune-engine --offline
```

Normal builds and typing never fetch data from the network. Missing or malformed
vendored data fails the build; there is no runtime external dictionary loader yet.
