# FrequencyWords data attribution

Copyright / attribution: Hermit Dave and FrequencyWords contributors.
Source: [FrequencyWords](https://github.com/hermitdave/FrequencyWords/tree/525f9b560de45753a5ea01069454e72e9aa541c6),
2018 lists derived from [OPUS OpenSubtitles2018](https://opus.nlpl.eu/OpenSubtitles2018.php).
Revision: `525f9b560de45753a5ea01069454e72e9aa541c6`.

The two `*_50k.txt` files are unmodified upstream content licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
See the included [license](LICENSE.html), [upstream statement](upstream-README.md)
and [SHA-256 manifest](manifest.json). No endorsement is implied.
TypeTune's MIT code license does not replace this data license.

TypeTune derives immutable sorted tables at build time (`../../build.rs`):
retain lowercase ASCII English / Cyrillic Russian letters including ё, length
1–32; preserve original frequency rank; reject duplicates or malformed counts.
The derived tables remain CC BY-SA 4.0. They are embedded in the engine library.
The preview installer distributes this whole directory, including the source
lists and license, alongside the library.

All retained top-50k entries protect valid source words. Only upstream top-20k
entries of length 4–32 may be automatic targets (plus the existing pilot words).
Three-letter targets require upstream top-1000; two-letter targets require
upstream top-100. One-letter words are excluded from automatic correction.
Rank is a conservative initial cutoff, not a calibrated confidence probability.
Subtitle data includes names, slang and errors; it is not a spelling authority
or a complete morphological dictionary. No automatic ё/е folding is applied.

Reproduce and verify from the repository root:

```sh
python3 scripts/verify-frequency-data.py --download
python3 scripts/verify-frequency-data.py
cargo test -p typetune-engine --offline
```

Normal builds and typing never fetch data from the network. Missing or malformed
vendored data fails the build; there is no runtime external dictionary loader yet.
