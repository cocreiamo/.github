#!/usr/bin/env bash
# post-merge-retry.yml: a red first attempt is repeated once, never a second attempt, a green or cancelled run, or a dry run; a refused repeat fails the job,
# and with alert: true the failure raises «main is red: retry failed» (the job every caller wrote by hand).
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-retry.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -N '.jobs.retry.steps[] | select(.name == "repeat the failed jobs") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'repeat the failed jobs' with env SCRIPT"
yq -e '.on.workflow_call.inputs."run-id".required and .jobs.retry.permissions.actions == "write"' "$wf" >/dev/null || fail "the workflow must require run-id and ask for actions: write"
yq -e '.on.workflow_call.inputs.alert.type == "boolean" and .on.workflow_call.inputs.alert.default == false and .on.workflow_call.secrets."app-private-key".required != true' "$wf" >/dev/null \
  || fail "the workflow must declare the optional input alert (boolean, default false, so a caller without the App key keeps working) and an optional app-private-key"
yq -e '.jobs.alert.uses | test("^cocreiamo/\.github/\.github/workflows/post-merge-alert\.yml@[0-9a-f]{40}$")' "$wf" >/dev/null || fail "the alert must call post-merge-alert.yml of cocreiamo/.github at a commit"
yq -e '(.jobs.alert.needs | join(",")) == "retry" and .jobs.alert.permissions.actions == "read" and (.jobs.alert.if | test("inputs.alert")) and (.jobs.alert.if | test("failure"))' "$wf" >/dev/null \
  || fail "the alert job must follow retry, need actions: read, honour the alert input and run only on a failure"
python3 -I tests/post_merge_retry_test.py "$tmp/script.py"
echo "post-merge-retry ok"
