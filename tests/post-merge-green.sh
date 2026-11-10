#!/usr/bin/env bash
# post-merge-green.yml: when main is green again, the revert PRs the revert workflow opened for an earlier red commit are closed (auto-merge off, a comment naming the green commit) and never merge.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-green.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -N '.jobs.close.steps[] | select(.name == "close the reverts") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'close the reverts' with env SCRIPT"
yq -e '.on.workflow_call.inputs."app-id".required and .on.workflow_call.secrets."app-private-key".required' "$wf" >/dev/null \
  || fail "the workflow must require the input app-id and the secret app-private-key"
yq -e '[.jobs.close.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
python3 -I tests/post_merge_green_test.py "$tmp/script.py"
echo "post-merge-green ok"
