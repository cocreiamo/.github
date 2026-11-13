#!/usr/bin/env bash
# Every OpenVEX statement that silences a finding says why (shared/scripts/vex_lint.py), proven by shared/scripts/vex-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/vex-test
