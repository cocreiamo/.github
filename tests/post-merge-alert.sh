#!/usr/bin/env bash
# post-merge-alert.yml: a red job on main that must not be reverted (a publish) opens one issue per failing job, or
# comments on the one already open, with the run link and the failing lines; nothing here ever reverts.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-alert.yml
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$wf" ] || fail "$wf is missing"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
yq -N '.jobs.alert.steps[] | select(.name == "alert") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'alert' with env SCRIPT"
yq -e '.on.workflow_call.inputs.failed.required and .on.workflow_call.inputs."app-id".required and .on.workflow_call.secrets."app-private-key".required' "$wf" >/dev/null \
  || fail "the workflow must require the inputs failed and app-id and the secret app-private-key"
yq -e '[.jobs.alert.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
yq -e '(.jobs.alert.permissions | keys | join(",")) == "actions" and .jobs.alert.permissions.actions == "read"' "$wf" >/dev/null || fail "the job needs exactly actions: read"
if grep -q 'revertPullRequest' "$wf"; then fail "an alert-only workflow never reverts"; fi
drill=.github/workflows/alert-drill.yml
[ -f "$drill" ] || fail "$drill is missing"
yq -e '(.on | keys | join(",")) == "workflow_dispatch"' "$drill" >/dev/null || fail "the drill runs on workflow_dispatch only"
yq -e '[.jobs[] | select(has("steps")) | .steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$drill" >/dev/null || fail "every action of the drill must be pinned by commit"
yq -e '.jobs.alert.with."title-prefix" == "drill: " and .jobs.alert.with.label == "drill"' "$drill" >/dev/null || fail "the drill must not use the title or the label of a red main"
python3 -I tests/post_merge_alert_test.py "$tmp/script.py"
echo "post-merge-alert ok"
