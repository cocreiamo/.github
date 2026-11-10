#!/usr/bin/env bash
# post-merge-retry.yml: a red first attempt is repeated once, never a second attempt, a green or cancelled run, or a dry run; a refused repeat fails the job.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-retry.yml
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$wf" ] || fail "$wf is missing"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
yq -N '.jobs.retry.steps[] | select(.name == "repeat the failed jobs") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'repeat the failed jobs' with env SCRIPT"
yq -e '.on.workflow_call.inputs."run-id".required and .jobs.retry.permissions.actions == "write"' "$wf" >/dev/null || fail "the workflow must require run-id and ask for actions: write"
python3 -I tests/post_merge_retry_test.py "$tmp/script.py"
echo "post-merge-retry ok"
