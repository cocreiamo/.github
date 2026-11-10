#!/usr/bin/env bash
# merge-queue.yml: with the ruleset requiring up-to-date branches, the oldest PR that has auto-merge on and green required checks
# but is behind main is brought up to date, one at a time; a PR in flight, a red, draft, conflicting or auto-merge-less PR never is.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/merge-queue.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -N '.jobs.queue.steps[] | select(.name == "update the oldest ready branch") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'update the oldest ready branch' with env SCRIPT"
yq -e '.on.workflow_call.inputs."app-id".required and .on.workflow_call.secrets."app-private-key".required' "$wf" >/dev/null \
  || fail "the workflow must require the input app-id and the secret app-private-key"
yq -e '[.jobs.queue.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
python3 -I tests/merge_queue_test.py "$tmp/script.py"
echo "merge-queue ok"
