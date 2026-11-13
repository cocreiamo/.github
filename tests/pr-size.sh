#!/usr/bin/env bash
# The PR size gate (shared/scripts/pr-size): over the budget refused without the founder's label, a platform/* branch warned, generated and vendored files not counted, proven by shared/scripts/pr-size-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/pr-size-test
