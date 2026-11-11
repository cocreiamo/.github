#!/usr/bin/env bash
# post-merge-selftest.yml is the reusable dry run of the post-merge path (revert and green decisions, nothing written) with an alert
# when either is red: reusable only, every call pinned by commit, dry-run on, the alert reaches the founder, and the contract of the
# callers (inputs, secret, permissions) is the one the three callee workflows declare.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-selftest.yml
[ -f "$wf" ] || fail "$wf is missing"
yq -e '(.on | keys | join(",")) == "workflow_call"' "$wf" >/dev/null || fail "$wf must be reusable only (the schedule belongs to the caller)"
yq -e '.on.workflow_call.inputs.sha.type == "string" and (.on.workflow_call.inputs.sha.required != true)
  and .on.workflow_call.inputs.green.type == "boolean" and .on.workflow_call.inputs.green.default == true' "$wf" >/dev/null \
  || fail "$wf must declare the optional inputs sha (string) and green (boolean, default true)"
yq -e '.on.workflow_call.secrets."app-private-key".required == true' "$wf" >/dev/null || fail "$wf must require the secret app-private-key"
yq -e '.permissions == {}' "$wf" >/dev/null || fail "$wf must start from permissions: {}"
yq -e '.concurrency.group | test("github.repository")' "$wf" >/dev/null || fail "$wf must declare a concurrency group of its own that names the repository"
yq -e '.concurrency."cancel-in-progress" != true' "$wf" >/dev/null || fail "a self-test in progress must not be cancelled"
for job in dry-run dry-run-green dry-run-red; do
  yq -e ".jobs.\"$job\".uses | test(\"^cocreiamo/\\.github/\\.github/workflows/post-merge-(revert|green|alert)\\.yml@[0-9a-f]{40}( |\$)\")" "$wf" >/dev/null \
    || fail "job $job must call a post-merge workflow of cocreiamo/.github pinned by commit"
done
yq -e '(.jobs."dry-run".uses | test("post-merge-revert\\.yml")) and .jobs."dry-run".with."dry-run" == true and .jobs."dry-run".with."ignore-head-green" == true' "$wf" >/dev/null \
  || fail "dry-run must call post-merge-revert.yml with dry-run and ignore-head-green on"
yq -e '(.jobs."dry-run-green".uses | test("post-merge-green\.yml")) and .jobs."dry-run-green".with."dry-run" == true
  and (.jobs."dry-run-green".if | test("inputs.green"))' "$wf" >/dev/null || fail "dry-run-green must call post-merge-green.yml with dry-run on, only when green is true"
yq -e '(.jobs."dry-run-red".uses | test("post-merge-alert\.yml")) and (.jobs."dry-run-red".needs | join(",")) == "dry-run,dry-run-green"
  and (.jobs."dry-run-red".if | test("always\(\)") and test("failure"))
  and .jobs."dry-run-red".with."title-prefix" == "post-merge revert dry run red: " and .jobs."dry-run-red".with.label == "post-merge-dry-run-red"' "$wf" >/dev/null \
  || fail "dry-run-red must follow both dry runs, run always on a failure and open the labelled alert through post-merge-alert.yml"
for job in dry-run dry-run-green dry-run-red; do
  yq -e ".jobs.\"$job\".with.\"app-id\" | test(\"vars.CLAUDE_CODE_PR_APP_ID\")" "$wf" >/dev/null || fail "job $job must pass the App id of the caller"
  yq -e ".jobs.\"$job\".secrets.\"app-private-key\" | test(\"secrets.app-private-key\")" "$wf" >/dev/null || fail "job $job must pass the App key"
done
yq -e '.jobs."dry-run".permissions.actions == "write" and .jobs."dry-run".permissions.issues == "write"
  and .jobs."dry-run-green".permissions.actions == "read" and .jobs."dry-run-red".permissions.actions == "read" and .jobs."dry-run-red".permissions.issues == "write"' "$wf" >/dev/null \
  || fail "permissions: dry-run actions and issues write, dry-run-green actions read, dry-run-red actions read and issues write"
shared/scripts/workflow-pins-check.py
echo "post-merge-selftest ok"
