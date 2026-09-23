# Auto-correction data

The engine combines original pilot fixtures with [pinned frequency lists](frequency/README.md)
and a curated [tech vocabulary](tech/README.md). Frequency + derived tables:
CC BY-SA 4.0 (FrequencyWords) and CC BY 2.5 (Leeds). Tech lists: MIT.

# Pilot auto-correction lexicons

Created 2026-09-16 for TypeTune from manually selected common words during this
implementation. No third-party dictionary or baseline `dict/` data was imported.
Distributed under the project's MIT license. These are small fixtures for the
pilot matcher, not frequency-ranked or corpus-validated dictionaries.

| File | Unique entries | SHA-256 |
|---|---:|---|
| en.txt | 149 | eae3e17246607f86df7bbc716c24c2ca0e0a7637052c7901bfea1c98f180060c |
| ru.txt | 150 | 9c1e243a2e6b75bcef30534b1afabda080b99547a7288dbd46330fa52eddcd51 |

Both lists are embedded at build time. Unit tests verify uniqueness, script and
length constraints. No external files or services are consulted while typing.

`auto-corpus.tsv` is an original, synthetic TypeTune test fixture (MIT).
It contains development and holdout labels chosen before the frequency matcher
was evaluated; this small corpus does not establish population-wide accuracy.

## Measurement baseline (plan 57)

`corpus-baseline.txt` records expected metrics for the corpus harness
(`tests::autocorrection_corpus_editor_and_inferred_agree`). Update it only
together with a deliberate data or matcher change, and record the delta in
`docs/evidence/`. Regenerate or edit rows with `scripts/build-corpus.py`
(`--generate` rewrites positives/negatives from curated word lists; always
re-run the Rust harness and `--check` afterwards).

Recorded slices:
- D1 (before merge): 428 positive / 492 negative; missed=53; false=0.
- D2 (Leeds + tech + EN plurals): missed=6; false=0. See `docs/evidence/57-baseline.txt`.
- D3/D4 (edge-punct, ё/е, score `ln(50000/rank)` + full yo/e ambiguity, ADR-010):
  **430 positive / 507 negative; all_missed=6; false=0** (dev 3/172, holdout 3/258).
  Current `corpus-baseline.txt` matches this D4 slice.
