#!/usr/bin/env bash
# This repository cleans its worktrees with the shared wt:gc and wt:list (shared/scripts), through its own mise tasks,
# and the shared test proves them: a merged clean worktree is removed; a dirty one, one with an open PR and one a
# process uses are kept.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
export MISE_TRUSTED_CONFIG_PATHS="$PWD"
for t in wt:gc:wt-gc wt:list:wt-list; do
  task="${t%:*}" script="${t##*:}"
  mise tasks info "$task" 2>/dev/null | grep -qF "shared/scripts/$script" || fail "task $task does not run shared/scripts/$script"
done
WT_GC="$PWD/shared/scripts/wt-gc" WT_LIST="$PWD/shared/scripts/wt-list" shared/scripts/worktrees-test
