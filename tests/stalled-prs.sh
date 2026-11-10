#!/usr/bin/env bash
# shared/scripts/stalled_prs.py lists the pull requests that make no progress in one issue per repository (its unit tests), and the
# reusable stalled-prs.yml runs exactly that script: embedded byte for byte, optional workspace cleanup, failure alert.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/stalled-prs.yml
script=shared/scripts/stalled_prs.py
fail() { echo "FAIL: $*" >&2; exit 1; }
(cd shared/scripts && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest stalled_prs_test)
[ -f "$wf" ] || fail "$wf is missing"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
yq -e '(.on | keys | join(",")) == "workflow_call"' "$wf" >/dev/null || fail "$wf must be reusable only (the schedule belongs to the caller)"
yq -e '.on.workflow_call.inputs.cleanup.type == "boolean" and .on.workflow_call.inputs.cleanup.default == false
  and .on.workflow_call.inputs.alert.type == "boolean" and .on.workflow_call.inputs.alert.default == true' "$wf" >/dev/null \
  || fail "$wf must declare the optional inputs cleanup (boolean, default false) and alert (boolean, default true)"
yq -e '.on.workflow_call.secrets."app-private-key".required != true' "$wf" >/dev/null || fail "the app key is needed only for the alert: it must be optional"
yq -N '.jobs.stalled.steps[] | select(.name == "list the stalled pull requests") | .env.SCRIPT' "$wf" > "$tmp/embedded.py"
[ -s "$tmp/embedded.py" ] && [ "$(cat "$tmp/embedded.py")" != null ] || fail "$wf has no step 'list the stalled pull requests' with env SCRIPT"
diff -u "$script" "$tmp/embedded.py" >/dev/null || fail "the script embedded in $wf differs from $script: run tools/embed-scripts.sh"
yq -e '(.jobs.stalled.steps[] | select(.name == "empty the workspace") | .if) | test("inputs.cleanup")' "$wf" >/dev/null || fail "the workspace cleanup must run only when cleanup is true"
yq -e '[.jobs.stalled.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}( |$)")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
yq -e '.jobs.stalled.permissions.issues == "write" and .jobs.stalled.permissions."pull-requests" == "read" and .jobs.stalled.permissions.checks == "read"' "$wf" >/dev/null \
  || fail "the job needs issues: write, pull-requests: read and checks: read"
yq -e '.jobs.alert.uses | test("^cocreiamo/\.github/\.github/workflows/post-merge-alert\.yml@[0-9a-f]{40}$")' "$wf" >/dev/null || fail "the alert must call post-merge-alert.yml of cocreiamo/.github at a commit"
yq -e '(.jobs.alert.needs | join(",")) == "stalled" and .jobs.alert.permissions.actions == "read" and (.jobs.alert.if | test("inputs.alert"))' "$wf" >/dev/null \
  || fail "the alert job must follow stalled, need actions: read and honour the alert input"
echo "stalled-prs ok"
