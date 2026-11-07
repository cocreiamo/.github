#!/usr/bin/env bash
# pr:wait is the shared pr-wait.sh (a task of this repository too), its test and the check that no bare gh watch exists.
set -euo pipefail
cd "$(dirname "$0")/.."
export MISE_TRUSTED_CONFIG_PATHS="$PWD"
mise tasks info pr:wait 2>/dev/null | grep -qF "shared/scripts/pr-wait.sh" || { echo "FAIL: task pr:wait does not run shared/scripts/pr-wait.sh" >&2; exit 1; }
shared/scripts/pr-wait-test
shared/scripts/gh-watch-interval.sh
