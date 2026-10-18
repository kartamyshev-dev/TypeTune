#!/bin/sh
# Offline checks of Core and CLI that run on Linux and macOS (CI and locally).
# Not a native, GUI or Caramba-parity check.
set -eu
cd "$(dirname "$0")/.."
swift build --product layoutpilot-cli
cli=.build/debug/layoutpilot-cli
"$cli" selftest
python3 scripts/evaluate_corpus.py
python3 scripts/evaluate_corpus.py --corpus corpus/synthetic-v3.jsonl --manifest corpus/manifest-v3.json --report-prefix evaluation-v3
for fixtures in corpus/review-regressions.jsonl corpus/lexicon-regressions.jsonl corpus/context-regressions.jsonl; do
  "$cli" evaluate "$fixtures" > /dev/null
  echo "$fixtures: passed"
done
swift test
python3 scripts/test_audit_gates.py
# Evaluation reports are deterministic: a rerun must reproduce the committed files.
git diff --exit-code -- corpus/
