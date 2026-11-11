#!/usr/bin/env bash
# hooks/check-conflict-markers on a throwaway repository: a file with git's conflict markers is refused, a clean file and a lone ======= line pass.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
check="$repo/hooks/check-conflict-markers"
tmpdir
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git_env_clear

git init -q -b main "$tmp/r"
cd "$tmp/r"

expect() {
  local want="$1" name="$2" rc=0
  [ -x "$check" ] || { echo "conflict-markers: $check is missing" >&2; exit 1; }
  "$check" "$tmp/r" > "$tmp/out" 2>&1 || rc=$?
  if { [ "$want" = ok ] && [ "$rc" != 0 ]; } || { [ "$want" = refuse ] && [ "$rc" = 0 ]; }; then
    echo "conflict-markers: $name: expected $want, got exit $rc" >&2
    cat "$tmp/out" >&2
    exit 1
  fi
  echo "ok   $name"
}

# Built at run time: a literal marker at the start of a line here would trip the check on this repository.
printf 'one\ntwo\n' > clean.txt
printf 'Title\n%s\nbody\n' '=======' > heading.md
git add -A
expect ok "clean file and a lone ======= line"

printf 'one\n%s ours\ntwo\n%s\nthree\n%s theirs\n' '<<<<<<<' '=======' '>>>>>>>' > conflicted.txt
expect refuse "conflict markers in an untracked file"
grep -q 'conflicted.txt' "$tmp/out" || { echo "conflict-markers: the file is not named" >&2; cat "$tmp/out" >&2; exit 1; }
git add conflicted.txt
expect refuse "conflict markers in a tracked file"
