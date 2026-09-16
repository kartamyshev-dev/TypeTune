# Auto-correction data

The engine now combines these original pilot fixtures with [pinned frequency lists](frequency/README.md). The frequency data and derived tables have a separate CC BY-SA 4.0 license.

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
