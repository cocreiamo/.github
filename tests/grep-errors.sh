#!/usr/bin/env bash
# A check that greps for a forbidden pattern must fail when grep itself fails (exit 2, or an argument list too long): `grep ... || true` and `xargs grep` read that error as "no match" and the
# check passes on a tree it never read. Proven two ways: each shared pattern-scanning script is red on a tree larger than ARG_MAX whose last-sorted file holds the forbidden form (and green when
# it does not), and tools/grep-errors-check refuses the unsafe forms in this repository's scripts (a fixture of each; the real tree is clean).
# shellcheck disable=SC2016,SC1091,SC2154 # fixture bodies are single-quoted on purpose; the library is a sibling file and sets $tmp
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/shared/scripts/testlib.sh"
tmpdir
git_env_clear

arg_max="$(getconf ARG_MAX)"
comp="$(printf 'd%.0s' $(seq 1 250))"
deep="$(printf '%s/' "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp" "$comp")"
pad="$(printf 'p%.0s' $(seq 1 100))"
n=$((arg_max / 3000 + 100))

# tree <dir> <prefix>: more path bytes than ARG_MAX under <dir>/<prefix>, and <prefix>zzz-last.sh, sorted after every other file
tree() {
  rm -rf "$1" && mkdir -p "$1/$2$deep"
  seq 1 "$n" | sed "s|^|$2$deep$pad|" | (cd "$1" && xargs touch)
}
# expect <red|green> <label> <dir> <command...>: the command runs in <dir>
expect() {
  local want=$1 label=$2 dir=$3 rc=0
  shift 3
  (cd "$dir" && "$@") >"$tmp/out" 2>&1 || rc=$?
  if [ "$want" = red ] && [ "$rc" -eq 0 ]; then fail "$label: accepted the forbidden form: $(head -c 300 "$tmp/out")"; fi
  if [ "$want" = green ] && [ "$rc" -ne 0 ]; then fail "$label: refused a clean tree: $(head -c 300 "$tmp/out")"; fi
  return 0
}
# scan_case <label> <prefix> <forbidden body> <clean body> <prepare function> <command...>: red on a small tree and on a tree over ARG_MAX whose last file has
# the form, green on a tree over ARG_MAX without it
scan_case() {
  local label=$1 prefix=$2 bad=$3 clean=$4 prepare=$5 d
  shift 5
  d="$tmp/case-$label"
  rm -rf "$d" && mkdir -p "$d/$prefix"
  printf '%s\n' "$bad" >"$d/${prefix}zzz-last.sh"
  "$prepare" "$d"
  expect red "$label (small tree)" "$d" "$@"
  tree "$d" "$prefix"
  printf '%s\n' "$bad" >"$d/${prefix}zzz-last.sh"
  "$prepare" "$d"
  expect red "$label (tree over ARG_MAX)" "$d" "$@"
  printf '%s\n' "$clean" >"$d/${prefix}zzz-last.sh"
  "$prepare" "$d"
  expect green "$label (clean tree over ARG_MAX)" "$d" "$@"
}
plain() { :; }
as_repo() {
  [ -e "$1/.git" ] || git_repo "$1"
  git -C "$1" add -A
}
as_docker_repo() {
  mkdir -p "$1/mise-tasks/test" "$1/tests/ci-docker/bad" "$1/tests/ci-docker/good"
  cp "$repo/shared/scripts/docker-mounts" "$1/mise-tasks/test/docker-mounts"
  printf 'docker run -v /tmp/x:/t img\n' >"$1/tests/ci-docker/bad/b"
  printf 'docker run -v cache:/c img\n' >"$1/tests/ci-docker/good/g"
  as_repo "$1"
}

mkdir -p "$tmp/s"
cp "$repo/shared/scripts/gh-watch-interval.sh" "$repo/shared/scripts/mktemp-trap-check" "$repo/shared/scripts/git-env-cleared" "$tmp/s/"
watch="$(printf 'gh pr checks 1 --%s' watch)"
scan_case gh-watch-interval '' "$watch" 'echo clean' as_repo "$tmp/s/gh-watch-interval.sh"
scan_case docker-mounts tests/ 'docker run -v /tmp/x:/t img' 'echo clean' as_docker_repo bash mise-tasks/test/docker-mounts
scan_case git-env-cleared '' "$(printf '#!/usr/bin/env bash\ngit %s -q d' init)" '#!/usr/bin/env bash' plain "$tmp/s/git-env-cleared" .
scan_case mktemp-trap-check '' "$(printf '#!/usr/bin/env bash\ntmp=$(%s -d)' mktemp)" '#!/usr/bin/env bash' plain "$tmp/s/mktemp-trap-check" .

check="$repo/tools/grep-errors-check"
[ -x "$check" ] || fail "tools/grep-errors-check is missing"
refused() { # refused <name> <line>
  rm -rf "$tmp/f" && mkdir -p "$tmp/f/shared/scripts"
  printf '%s\n' "$2" >"$tmp/f/shared/scripts/x"
  if "$check" "$tmp/f" >"$tmp/o" 2>&1; then fail "$1 was accepted"; fi
  grep -qF 'shared/scripts/x' "$tmp/o" || fail "the refusal of $1 does not name the file"
}
accepted() {
  rm -rf "$tmp/f" && mkdir -p "$tmp/f/shared/scripts"
  printf '%s\n' "$2" >"$tmp/f/shared/scripts/x"
  "$check" "$tmp/f" >"$tmp/o" 2>&1 || fail "$1 was refused: $(cat "$tmp/o")"
}
refused "grep over a file list with || true" '{ grep -nHE -e "$p" -- "${files[@]}" || true; }'
refused "grep with errors silenced and || true" 'grep -nE "$p" "$f" 2>/dev/null | sed x || true'
refused "grep with || :" 'x="$(grep -E "$p" "$f" || :)"'
refused "xargs grep" 'printf x | xargs grep -n foo'
refused "xargs -0 -r grep" 'git ls-files -z | xargs -0 -r grep -l foo'
refused "git grep with || true" 'git grep -l foo || true'
refused "grep -c with || true" 'count() { grep -c "$1" "$tmp/log" || true; }'
accepted "grep exit 1 as no match" 'hits="$(grep -E "$p" "$f")" || [ $? -eq 1 ]'
accepted "git grep" 'git grep -nIE foo -- . || [ $? -eq 1 ]'
accepted "a comment" '# grep foo "$f" || true'
accepted "a here-string" 'grep -q x <<<"$(check || true)"'
accepted "another command with || true" 'rm -f "$x" || true'
"$check" "$repo" >"$tmp/o" 2>&1 || fail "a script of this repository has the unsafe form: $(cat "$tmp/o")"
echo "grep errors fail the check"
