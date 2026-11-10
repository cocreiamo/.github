#!/usr/bin/env bash
# renovate.yml is the reusable nightly Renovate of every repository: its inputs and secrets, the environment merge of extra-env (only
# RENOVATE_ keys, never one the workflow sets itself), the failure alert, and this repository's own caller (renovate-nightly.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/renovate.yml
caller=.github/workflows/renovate-nightly.yml
fail() { echo "FAIL: $*" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
yq -e '.on | has("workflow_call") and (has("schedule") | not)' "$wf" >/dev/null || fail "$wf must be reusable only (the schedule belongs to the caller)"
yq -e '.on.workflow_call.inputs.repositories.type == "string" and (.on.workflow_call.inputs.repositories.required != true)
  and .on.workflow_call.inputs."extra-env".type == "string" and (.on.workflow_call.inputs."extra-env".required != true)
  and .on.workflow_call.inputs.alert.type == "boolean" and .on.workflow_call.inputs.alert.default == true' "$wf" >/dev/null \
  || fail "$wf must declare the optional inputs repositories (string), extra-env (string) and alert (boolean, default true)"
yq -e '.on.workflow_call.secrets."app-private-key".required == true and (.on.workflow_call.secrets."extra-env-secret".required != true)' "$wf" >/dev/null \
  || fail "$wf must require the secret app-private-key and take an optional extra-env-secret"
yq -e '[.jobs[] | select(has("steps")) | .steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}( |$)")] | all' "$wf" >/dev/null || fail "every action of $wf must be pinned by commit"
yq -e '.jobs.alert.uses | test("^cocreiamo/\.github/\.github/workflows/post-merge-alert\.yml@[0-9a-f]{40}$")' "$wf" >/dev/null \
  || fail "the alert job must call post-merge-alert.yml of cocreiamo/.github at a commit (a local ./ in a reusable workflow resolves to the caller)"
yq -e '.jobs.alert.needs == ["renovate"] and .jobs.alert.permissions.actions == "read" and (.jobs.alert.if | test("inputs.alert") and test("failure"))' "$wf" >/dev/null \
  || fail "the alert job must follow renovate, need actions: read and run only for alert: true on a failure"
yq -e '(.jobs.renovate.steps[] | select(.uses == "renovate*") | .env.RENOVATE_ALLOWED_COMMANDS) | length > 0' "$wf" >/dev/null || fail "the Renovate step must keep RENOVATE_ALLOWED_COMMANDS"

script=$tmp/extra.py
yq -N '.jobs.renovate.steps[] | select(.name == "extra environment") | .env.SCRIPT' "$wf" > "$script"
[ -s "$script" ] && [ "$(cat "$script")" != null ] || fail "$wf has no step 'extra environment' with env SCRIPT"
run() { # <extra-env> <extra-env-secret>: rc and $tmp/github-env
  : > "$tmp/github-env"
  rc=0; EXTRA_ENV=$1 EXTRA_ENV_SECRET=$2 GITHUB_ENV=$tmp/github-env python3 -I "$script" > "$tmp/out" 2>&1 || rc=$?
}
run '' ''
[ "$rc" = 0 ] && [ ! -s "$tmp/github-env" ] || fail "empty extra environments must be accepted and write nothing"
run '{"RENOVATE_ALLOWED_UNSAFE_EXECUTIONS":"[\"bazelModDeps\"]"}' '{"RENOVATE_HOST_RULES":"line one\nline two"}'
[ "$rc" = 0 ] || { cat "$tmp/out" >&2; fail "a valid extra environment was refused"; }
grep -q '^RENOVATE_ALLOWED_UNSAFE_EXECUTIONS<<' "$tmp/github-env" && grep -qF '["bazelModDeps"]' "$tmp/github-env" || fail "extra-env is not written to GITHUB_ENV"
grep -q '^RENOVATE_HOST_RULES<<' "$tmp/github-env" && grep -qF 'line two' "$tmp/github-env" || fail "extra-env-secret is not written to GITHUB_ENV (multi-line values included)"
for bad in '{"PATH":"x"}' '{"renovate_x":"x"}' '{"RENOVATE_TOKEN":"x"}' '{"RENOVATE_ALLOWED_COMMANDS":"[]"}' '{"RENOVATE_REPOSITORIES":"o/r"}' '[1]' 'not json' '{"RENOVATE_X":1}'; do
  run "$bad" ''
  [ "$rc" != 0 ] || fail "extra-env $bad was accepted"
  run '' "$bad"
  [ "$rc" != 0 ] || fail "extra-env-secret $bad was accepted"
done
! grep -qF '"x"' "$tmp/out" || fail "a refusal must not echo values (extra-env-secret may hold a secret)"

yq -e '.on | has("schedule") and has("workflow_dispatch") and (has("workflow_call") | not)' "$caller" >/dev/null || fail "$caller must run on a schedule and on demand"
yq -e '.jobs.renovate.uses == "./.github/workflows/renovate.yml" and .jobs.renovate.permissions.contents == "read" and .jobs.renovate.permissions.actions == "read"
  and (.jobs.renovate.secrets."app-private-key" | test("CLAUDE_CODE_PR_APP_PRIVATE_KEY"))' "$caller" >/dev/null \
  || fail "$caller must call ./.github/workflows/renovate.yml with contents and actions read and the App key"
echo "renovate-reusable ok"
