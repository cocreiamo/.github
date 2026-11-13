#!/usr/bin/env bash
# The shared pr-rules check (shared/scripts/pr-rules-test proves each rule), and the reusable pr-rules.yml runs exactly that script:
# embedded byte for byte, on every edit of the title, reported as `pr-rules / check`.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
shared/scripts/pr-rules-test
wf=.github/workflows/pr-rules.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -e '(.on | keys | join(",")) == "workflow_call"' "$wf" >/dev/null || fail "$wf must be reusable only (the trigger belongs to the caller)"
yq -e '(.jobs | keys | join(",")) == "check"' "$wf" >/dev/null || fail "$wf must have the one job check: a caller job pr-rules reports pr-rules / check"
yq -N '.jobs.check.steps[] | select(.name == "pr rules") | .env.SCRIPT' "$wf" >"$tmp/embedded"
[ "$(cat shared/scripts/pr-rules)" = "$(cat "$tmp/embedded")" ] || fail "the script embedded in $wf differs from shared/scripts/pr-rules: run tools/embed-scripts.sh"
yq -e '(.jobs.check.permissions | keys | join(",")) == "contents" and .jobs.check.permissions.contents == "read" and (.jobs.check."timeout-minutes" <= 5)' "$wf" >/dev/null \
  || fail "the job needs contents: read only and a short timeout"
yq -e '[.jobs.check.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}( |$)")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
yq -e '.jobs.check.steps[] | select(has("uses")) | .with | ((."fetch-depth" == 0) and (."persist-credentials" == false) and (.ref | test("pull_request.head.sha")))' "$wf" >/dev/null \
  || fail "the checkout needs the whole history of the head, without credentials"
yq -e '.jobs.check.steps[] | select(.name == "pr rules") | ((.env.PR_TITLE == "${{ github.event.pull_request.title }}") and (.run | test("PR_TITLE")))' "$wf" >/dev/null \
  || fail "the title must reach the script through the environment, never interpolated into the script"
grep -q 'types: \[opened, edited, synchronize, reopened\]' "$wf" || fail "$wf must document the caller trigger with edited: a renamed title is checked again"
echo "pr-rules workflow ok"
