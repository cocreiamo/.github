#!/usr/bin/env bash
#MISE description="Wait for a PR's required checks (or --run <id>) at 60 s polls, through a GitHub rate limit: mise run pr:wait [<pr>|--run <id>]"
# Every agent shares one user token of 5000 REST requests an hour: gh's own defaults (10 s for pr checks, 3 s for run watch)
# exhaust it with a few waits at once. Exit 0 the PR is merged (a required check that has not reported yet makes gh exit 0 early, so green alone is not enough), 1 a check failed or the PR closed, 75 still pending after PR_WAIT_BUDGET seconds (540):
# repeat the same command in the foreground. A rate-limit answer is slept through until the reset gh api rate_limit reports.
set -euo pipefail

budget="${PR_WAIT_BUDGET:-540}"
interval="${PR_WAIT_INTERVAL:-60}"
[[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 60 ] || interval=60
deadline=$(( $(date +%s) + budget ))

if [ "${1:-}" = --run ]; then
  [ -n "${2:-}" ] || { echo "refused: usage is pr:wait [<pr>|--run <id>]" >&2; exit 2; }
  cmd=(gh run watch "$2" --exit-status --interval "$interval")
else
  cmd=(gh pr checks "$@" --required --watch --fail-fast --interval "$interval")
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
while :; do
  left=$(( deadline - $(date +%s) ))
  [ "$left" -gt 0 ] || exit 75
  set +e
  timeout "$left" "${cmd[@]}" 2>&1 | tee "$out"
  rc="${PIPESTATUS[0]}"
  set -e
  [ "$rc" != 124 ] || exit 75
  if [ "$rc" = 0 ] && [ "${cmd[1]}" = pr ]; then
    state="$(gh pr view "$@" --json state --jq .state 2>/dev/null || echo OPEN)"
    [ "$state" != MERGED ] || exit 0
    [ "$state" != CLOSED ] || { echo "the PR is closed, not merged" >&2; exit 1; }
    sleep "$interval"
    continue
  fi
  if [ "$rc" = 0 ] || ! grep -qiE 'rate limit|HTTP 429' "$out"; then
    exit "$rc"
  fi
  now="$(date +%s)"
  reset="$(gh api rate_limit --jq '[.resources[] | select(.remaining == 0) | .reset] | max // .resources.core.reset' 2>/dev/null || echo 0)"
  pause=$(( reset - now + 5 ))
  [ "$pause" -ge 5 ] && [ "$pause" -le 3700 ] || pause=60
  if [ $(( now + pause )) -ge "$deadline" ]; then
    sleep "$(( deadline - now > 0 ? deadline - now : 1 ))"
    exit 75
  fi
  echo "GitHub rate limit: waiting ${pause}s for the reset" >&2
  sleep "$pause"
done
