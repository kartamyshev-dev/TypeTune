# TypeTune tech vocabulary (MIT)

Curated RU/EN tech and UX word forms for layout autocorrection. These are
not frequency lists: a word is present because it is a valid correction
target that subtitle/web corpora often miss (inflected forms, product terms).

| File | Non-comment lines | License | SHA-256 |
|---|---:|---|---|
| `ru.txt` | 95 | MIT (TypeTune) | `f787a52142ed2fd53032dd94d82fba2cf993e9a492f3f6a4591c7e0e07e17a53` |
| `en.txt` | 129 | MIT (TypeTune) | `95789c10afea9da23d15fe9eab5aed915bfb7959ab3be3d5b294bfbc6348567a` |

Update SHA-256 after every edit: `sha256sum data/tech/ru.txt data/tech/en.txt`
(from `crates/typetune-engine/`).

Processing at build time (`crates/typetune-engine/build.rs`):
- strip comments/blank lines; require language-appropriate alphabet;
- length 1–32 after trim; reject duplicates;
- each word receives a strong rank boost (under existing matcher thresholds
  100/1000/20000) without changing those thresholds.

Runtime still does no network I/O; tables are embedded at compile time.
