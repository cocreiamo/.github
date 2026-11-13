#!/usr/bin/env bash
# One hook manager in every repository, the pre-commit framework with the shared hooks (shared/scripts/hooks-check): proven by shared/scripts/hooks-check-test, the worktree-safe install by shared/scripts/hooks-install-test, then run on this repository's config.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/hooks-check-test
shared/scripts/hooks-install-test
[ "$(yq -N -p toml '.hooks.postinstall' mise.toml)" = shared/scripts/hooks-install ] || { echo "FAIL: the mise postinstall must be shared/scripts/hooks-install (it never touches core.hooksPath, which every worktree shares)" >&2; exit 1; }
HOOKS_CHECK_CONFIG_ONLY=1 shared/scripts/hooks-check
