#!/usr/bin/env bash
# The shared lint baseline (shared/scripts/lint-baseline: shellcheck, shfmt, ruff, yamllint, gitleaks on tracked files) refuses each bad case, skips vendored copies and fixtures, and runs one part at a time (shared/scripts/lint-baseline-test).
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/lint-baseline-test
