#!/usr/bin/env bash
# post-merge-revert.yml: the decision (which commit to revert, when to only alert, when to skip) and the whole flow
# against a fake `gh`, including that a dry run changes nothing.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-revert.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -N '.jobs.revert.steps[] | select(.name == "decide and act") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'decide and act' with env SCRIPT"
yq -e '.on.workflow_call.inputs.failed.required and .on.workflow_call.inputs."app-id".required and .on.workflow_call.secrets."app-private-key".required' "$wf" >/dev/null \
  || fail "the workflow must require the inputs failed and app-id and the secret app-private-key"
yq -e '[.jobs.revert.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
yq -e '.jobs.revert.permissions.issues == "write"' "$wf" >/dev/null || fail "the job needs issues: write for the fallback token"
yq -e '(.jobs.revert.steps[] | select(.id == "token") | ."continue-on-error") == true' "$wf" >/dev/null || fail "a dead App key must not end the job silently: the token step is continue-on-error"
yq -e '(.jobs.revert.steps[] | select(.name == "decide and act") | .if) | test("steps.token.outcome")' "$wf" >/dev/null || fail "the decision runs only with an App token"
yq -e '.jobs.revert.steps[] | select(.name == "alert without the App") | ((.if | test("steps.token.outcome")) and (.env.GH_TOKEN | test("github.token")) and (.env.SCRIPT | test("App token")))' "$wf" >/dev/null || fail "when the App token fails, a fallback step raises the main-red issue with the run own github.token"
yq -N '.jobs.revert.steps[] | select(.name == "alert without the App") | .env.SCRIPT' "$wf" > "$tmp/fallback.py"
python3 -I tests/post_merge_revert_test.py "$tmp/script.py"
python3 -I tests/post_merge_fallback_test.py "$tmp/fallback.py"
echo "post-merge-revert ok"
