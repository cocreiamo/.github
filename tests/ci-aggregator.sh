#!/usr/bin/env bash
# The workflow of the pull request checks has the job `ci`, the one required check of the repository: re-actors/alls-green
# pinned by commit, always() so it reports after a failed dependency, and every other job under it.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."

problems() {
  local f=$1 job missing=""
  yq -e '.jobs.ci' "$f" >/dev/null 2>&1 || { echo "no job ci"; return; }
  yq -N '.jobs.ci.steps[].uses // ""' "$f" | grep -Eq '^re-actors/alls-green@[0-9a-f]{40}$' || echo "ci does not run re-actors/alls-green pinned by commit"
  yq -N '.jobs.ci.if // ""' "$f" | grep -q 'always()' || echo "ci has no always(): a failed dependency would skip it"
  yq -N '.jobs.ci.steps[].with.jobs // ""' "$f" | grep -q 'toJSON(needs)' || echo "ci does not pass toJSON(needs)"
  for job in $(yq -N '.jobs | keys | .[]' "$f"); do
    [ "$job" = ci ] && continue
    yq -e ".jobs.ci.needs[] | select(. == \"$job\")" "$f" >/dev/null 2>&1 || missing="$missing $job"
  done
  [ -z "$missing" ] || echo "ci does not need:$missing"
}

yq -e '.jobs.check' .github/workflows/check.yml >/dev/null 2>&1 && fail "a job is still named check: the required check of the repository is ci"
out=$(problems .github/workflows/check.yml)
[ -z "$out" ] || fail "$out"

tmpdir
sed 's/^  ci:$/  gone:/' .github/workflows/check.yml > "$tmp/no-ci.yml"
[[ $(problems "$tmp/no-ci.yml") == *"no job ci"* ]] || fail "a workflow without ci was accepted"
yq '.jobs.ci.needs = ["title"]' .github/workflows/check.yml > "$tmp/missing.yml"
[[ $(problems "$tmp/missing.yml") == *"ci does not need: lint"* ]] || fail "a job outside ci was accepted"
yq '.jobs.ci.if = "github.event_name == '"'pull_request'"'"' .github/workflows/check.yml > "$tmp/no-always.yml"
[[ $(problems "$tmp/no-always.yml") == *"no always()"* ]] || fail "an aggregator without always() was accepted"
echo "ci-aggregator ok"
