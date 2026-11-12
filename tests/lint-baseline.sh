#!/usr/bin/env bash
# The shared lint baseline (shared/scripts/lint-baseline: shellcheck, shfmt, ruff, yamllint, prettier, gitleaks on tracked files) refuses each bad case, skips vendored copies and fixtures, and runs one part at a time (shared/scripts/lint-baseline-test); the founder section carries the one-formatter rule.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/lint-baseline-test
grep -qF -- '- One formatter per file type, never two: prettier for YAML, Markdown, JSON and JS, shfmt for shell, ruff format for Python' shared/working-with-the-founder.md ||
  { echo "FAIL: the founder section does not carry the formatter rule lint-baseline enforces" >&2; exit 1; }
