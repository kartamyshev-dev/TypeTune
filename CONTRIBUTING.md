# Contributing

Thanks for your interest in TypeTune.

## Workflow

1. Fork and create a feature branch from `main`.
2. Keep changes focused; include tests for behaviour changes.
3. Run the checks for the platform you touch (see below).
4. Open a pull request with a clear description of user-visible behaviour.

## Checks

**Linux (CI toolchain 1.98.1):**

```sh
cargo fmt --all -- --check
cargo clippy --workspace --locked -- -D warnings
cargo test --workspace --all-targets --locked
/usr/bin/python3 -m unittest discover -s integrations/app -p 'test_*.py'
/usr/bin/python3 -m unittest discover -s integrations/compat -p 'test_*.py'
/usr/bin/python3 -m unittest discover -s tests/packaging -p 'test_*.py'
```

**macOS (CI toolchain 1.89.0):**

```sh
bash scripts/test-macos.sh
bash scripts/build-macos.sh
```

Green CI is not the same as native keyboard acceptance. Manual cases live in [docs/testing.md](docs/testing.md).

## Style

- Prefer small, reviewable commits with messages that explain *why*.
- Do not put typed user text, clipboard contents, or secrets in logs, fixtures, or commit messages.
- Public docs and README stay free of third-party product comparisons.

## Releases

- Version tags use `vMAJOR.MINOR.PATCH` (for example `v0.1.0`).
- Tag builds publish Linux and macOS artifacts only after all platform jobs succeed.
- Do not move or rewrite a published tag; ship a new version instead.
- Update `CHANGELOG.md` and `docs/releases/<version>.md` in the same change as the release.

## Security

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
