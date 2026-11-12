#!/usr/bin/env bash
# One hook manager in every repository, the pre-commit framework with the shared hooks (shared/scripts/hooks-check): proven by shared/scripts/hooks-check-test, then run on this repository's config.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/hooks-check-test
HOOKS_CHECK_CONFIG_ONLY=1 shared/scripts/hooks-check
