#!/usr/bin/env bash
# Every agent that waits for a PR shares one user token of 5000 REST requests an hour: `gh pr checks --watch` polls every
# 10 s and `gh run watch` every 3 s, so a few agents waiting at once exhaust it and nobody can read a check state. A wait
# is `mise run pr:wait` (shared/scripts/pr-wait.sh, vendored in every repository: interval of at least 60 s, sleeps through a rate limit); a bare gh watch
# anywhere else in the tracked files must carry --interval of at least 60.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

watches='gh +pr +checks.*(--watch|[[:space:]]-w([[:space:]]|$))|gh +run +watch'
slow='--interval[ =]+([6-9][0-9]|[1-9][0-9]{2,})([^0-9]|$)'

# grep_files <grep options and pattern>: greps the NUL-separated paths on stdin in as many grep runs as the argument limit needs. No match is success; a grep that
# fails (exit 2: an unreadable file, a bad pattern) fails this command, so an error is never read as a clean tree.
grep_files() {
  # shellcheck disable=SC2016 # the script is bash -c's, expanded there
  xargs -0 -r -- bash -c 'grep "$@"; rc=$?; [ "$rc" -le 1 ] || exit 255' grep-files "$@" --
}
offenders() { # offenders: reads NUL-separated paths, prints the lines that watch without a slow enough interval
  local hits
  hits="$(grep_files -nHIE -e "$watches")" || return 1
  grep -vE -e "$slow" <<<"$hits" || [ $? -eq 1 ]
}

printf '%s\n' 'gh pr checks --required --watch' > "$tmp/bare"
printf '%s\n' 'gh pr checks 7 -w --interval 10' > "$tmp/short"
printf '%s\n' 'gh run watch 123' > "$tmp/run"
printf '%s\n' 'gh run watch 123 --interval 59' > "$tmp/fast"
printf '%s\n' 'gh pr checks --required --watch --interval 60' > "$tmp/ok60"
printf '%s\n' 'gh run watch 123 --interval=120 --exit-status' > "$tmp/ok120"
printf '%s\n' 'gh pr checks 7 --required' > "$tmp/nowatch"
for bad in bare short run fast; do
  [ -n "$(printf '%s\0' "$tmp/$bad" | offenders)" ] || { echo "FAIL: the check accepts '$(cat "$tmp/$bad")'" >&2; exit 1; }
done
for good in ok60 ok120 nowatch; do
  [ -z "$(printf '%s\0' "$tmp/$good" | offenders)" ] || { echo "FAIL: the check refuses '$(cat "$tmp/$good")'" >&2; exit 1; }
done

cd "$repo"
shared_paths() { # the vendored copies of the shared scripts, which carry the bare watch on purpose
  [ -f .github/shared-scripts ] || return 0
  awk '$1 == "gh-watch-interval.sh" || $1 == "pr-wait-test" || $1 == "pr-wait.sh" || $1 == "claude-pre-bash" || $1 == "claude-pre-bash-test" { print $2 }' .github/shared-scripts
}
declare -A skip=()
for f in shared/scripts/gh-watch-interval.sh shared/scripts/pr-wait-test shared/scripts/pr-wait.sh shared/scripts/claude-pre-bash shared/scripts/claude-pre-bash-test; do skip["$f"]=1; done
while IFS= read -r p; do skip["$p"]=1; done < <(shared_paths)
scan() { # the tracked and untracked files that exist, without the vendored copies
  local f
  while IFS= read -r -d '' f; do
    [ -z "${skip[$f]:-}" ] && [ -f "$f" ] && printf '%s\0' "$f"
  done < <(git -c core.quotePath=false ls-files -z --cached --others --exclude-standard)
  return 0
}
found="$(scan | offenders)"
if [ -n "$found" ]; then
  echo "FAIL: a gh watch without --interval of at least 60 (use mise run pr:wait):" >&2
  echo "$found" >&2
  exit 1
fi
echo "no tracked file watches with gh at less than 60 s"
