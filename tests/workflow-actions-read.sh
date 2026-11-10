#!/usr/bin/env bash
# A reusable workflow that calls the Actions API (runs, jobs, logs) must declare actions: read on the job that does it: the
# App token has no Actions permission, so the call needs the run's own token, and that token only has what the job declares.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."

scan() {
  local dir="$1" f bad=0
  for f in "$dir"/*.yml; do
    yq -e '.on | has("workflow_call")' "$f" >/dev/null 2>&1 || continue
    local jobs
    jobs=$(yq -N '.jobs | keys | .[]' "$f")
    for j in $jobs; do
      if yq -N ".jobs.\"$j\"" "$f" | grep -qE '/actions/(runs|jobs|workflows)'; then
        yq -e ".jobs.\"$j\".permissions.actions == \"read\" or .jobs.\"$j\".permissions.actions == \"write\"" "$f" >/dev/null 2>&1 \
          || { echo "refused: $f job $j calls the Actions API without actions: read" >&2; bad=1; }
      fi
    done
  done
  return $bad
}

scan .github/workflows || fail "a reusable workflow calls the Actions API without declaring actions: read"

tmpdir
cat > "$tmp/bad.yml" <<'Y'
on:
  workflow_call: {}
jobs:
  j:
    runs-on: x
    permissions: {}
    steps:
      - run: curl "$API/repos/o/r/actions/runs/1"
Y
if scan "$tmp" 2>/dev/null; then fail "a reusable workflow that reads the runs without actions: read was accepted"; fi
sed -i 's/permissions: {}/permissions: {actions: read}/' "$tmp/bad.yml"
scan "$tmp" || fail "a reusable workflow that declares actions: read was refused"
echo "workflow-actions-read ok"
