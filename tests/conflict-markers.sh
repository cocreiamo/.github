#!/usr/bin/env bash
# shared/scripts/conflict-markers (the pre-commit hook hooks/check-conflict-markers runs it; the other repositories vendor it) on a throwaway
# repository: a file with git's conflict markers is refused, a clean file and a lone ======= line pass, a directory of
# .github/conflict-markers-allowlist with a reason is skipped and an allowlist line without a reason is refused.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
check="$repo/shared/scripts/conflict-markers"
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

mkdir -p vendor/up .github
printf 'a\n%s x\n' '<<<<<<<' > vendor/up/patch.rej
git rm -q --cached conflicted.txt
rm conflicted.txt
printf 'vendor/up/ upstream rejects kept byte for byte\n' > .github/conflict-markers-allowlist
expect ok "a directory of the allowlist"
printf 'vendor/up/\n' > .github/conflict-markers-allowlist
expect refuse "an allowlist line without a reason"
grep -q 'no reason' "$tmp/out" || { echo "conflict-markers: the refusal does not say the reason is missing" >&2; cat "$tmp/out" >&2; exit 1; }
