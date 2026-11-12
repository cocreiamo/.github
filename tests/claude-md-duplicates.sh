#!/usr/bin/env bash
# No rule longer than 120 characters is carried by two repository CLAUDE.md files outside the shared section (shared/scripts/claude-md-duplicates), proven by shared/scripts/claude-md-duplicates-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/claude-md-duplicates-test
