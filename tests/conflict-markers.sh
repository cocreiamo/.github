#!/usr/bin/env bash
# The shared conflict-markers check (the pre-commit hook hooks/check-conflict-markers runs it), proven by shared/scripts/conflict-markers-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/conflict-markers-test
