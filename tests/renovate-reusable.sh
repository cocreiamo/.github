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
  and .on.workflow_call.inputs."extra-allowed-commands".type == "string" and (.on.workflow_call.inputs."extra-allowed-commands".required != true)
  and .on.workflow_call.inputs.alert.type == "boolean" and .on.workflow_call.inputs.alert.default == true' "$wf" >/dev/null \
  || fail "$wf must declare the optional inputs repositories (string), extra-env (string), extra-allowed-commands (string) and alert (boolean, default true)"
yq -e '.on.workflow_call.secrets."app-private-key".required == true and (.on.workflow_call.secrets."extra-env-secret".required != true)' "$wf" >/dev/null \
  || fail "$wf must require the secret app-private-key and take an optional extra-env-secret"
yq -e '[.jobs[] | select(has("steps")) | .steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}( |$)")] | all' "$wf" >/dev/null || fail "every action of $wf must be pinned by commit"
yq -e '.jobs.alert.uses | test("^cocreiamo/\.github/\.github/workflows/post-merge-alert\.yml@[0-9a-f]{40}$")' "$wf" >/dev/null \
  || fail "the alert job must call post-merge-alert.yml of cocreiamo/.github at a commit (a local ./ in a reusable workflow resolves to the caller)"
yq -e '(.jobs.alert.needs | join(",")) == "renovate" and .jobs.alert.permissions.actions == "read" and .jobs.alert.permissions.issues == "write" and (.jobs.alert.if | test("inputs.alert")) and (.jobs.alert.if | test("failure"))' "$wf" >/dev/null \
  || fail "the alert job must follow renovate, need actions: read and issues: write and run only for alert: true on a failure"
yq -e '[.jobs.renovate.steps[] | select(has("uses") and (.uses | test("renovatebot/github-action"))) | .env | has("RENOVATE_ALLOWED_COMMANDS")] | any | not' "$wf" >/dev/null \
  || fail "the Renovate step must not set RENOVATE_ALLOWED_COMMANDS itself: the step that merges the callers' extra commands writes it"

script=$tmp/extra.py
yq -N '.jobs.renovate.steps[] | select(.name == "extra environment") | .env.SCRIPT' "$wf" > "$script"
[ -s "$script" ] && [ "$(cat "$script")" != null ] || fail "$wf has no step 'extra environment' with env SCRIPT"
base=$(yq -N '.jobs.renovate.steps[] | select(.name == "extra environment") | .env.BASE_COMMAND' "$wf")
case $base in '^bash -c '*) ;; *) fail "the extra environment step must carry the sync command as env BASE_COMMAND" ;; esac
run() { # <extra-env> <extra-env-secret> [<extra-allowed-commands>]: rc and $tmp/github-env
  : > "$tmp/github-env"
  rc=0; EXTRA_ENV=$1 EXTRA_ENV_SECRET=$2 EXTRA_COMMANDS=${3:-} BASE_COMMAND=$base GITHUB_ENV=$tmp/github-env python3 -I "$script" > "$tmp/out" 2>&1 || rc=$?
}
allowed() { # prints the JSON array written as RENOVATE_ALLOWED_COMMANDS
  python3 -I -c 'import re,sys; m=re.search(r"^RENOVATE_ALLOWED_COMMANDS<<(\S+)\n(.*?)\n\1$", open(sys.argv[1]).read(), re.S|re.M); print(m.group(2) if m else "")' "$tmp/github-env"
}
run '' ''
[ "$rc" = 0 ] || fail "empty extra environments must be accepted"
[ "$(allowed | jq -c .)" = "$(jq -cn --arg b "$base" '[$b]')" ] || fail "with no extra command the only allowed command is the sync of the founder section"
[ "$(grep -cE '^RENOVATE_[A-Z_]+<<' "$tmp/github-env")" = 1 ] || fail "empty extra environments write nothing but the allowed commands"
run '' '' '["^bash mise-tasks/vendor/upstream$"]'
[ "$rc" = 0 ] || { cat "$tmp/out" >&2; fail "an anchored extra command was refused"; }
[ "$(allowed | jq -c .)" = "$(jq -cn --arg b "$base" '[$b, "^bash mise-tasks/vendor/upstream$"]')" ] || fail "the extra command must follow the sync command in RENOVATE_ALLOWED_COMMANDS"
for bad in '^bash x' 'bash x$' '^.*$' '^(bash|rm) .*$' '["^bash x$", 1]' '"^bash x$"' 'not json' '["^[$"]'; do
  run '' '' "$bad"
  [ "$rc" != 0 ] || fail "extra-allowed-commands $bad was accepted"
done
run '{"RENOVATE_ALLOWED_UNSAFE_EXECUTIONS":"[\"bazelModDeps\"]"}' '{"RENOVATE_HOST_RULES":"line one\nline two"}'
[ "$rc" = 0 ] || { cat "$tmp/out" >&2; fail "a valid extra environment was refused"; }
{ grep -q '^RENOVATE_ALLOWED_UNSAFE_EXECUTIONS<<' "$tmp/github-env" && grep -qF '["bazelModDeps"]' "$tmp/github-env"; } || fail "extra-env is not written to GITHUB_ENV"
{ grep -q '^RENOVATE_HOST_RULES<<' "$tmp/github-env" && grep -qF 'line two' "$tmp/github-env"; } || fail "extra-env-secret is not written to GITHUB_ENV (multi-line values included)"
for bad in '{"PATH":"x"}' '{"renovate_x":"x"}' '{"RENOVATE_TOKEN":"x"}' '{"RENOVATE_ALLOWED_COMMANDS":"[]"}' '{"RENOVATE_REPOSITORIES":"o/r"}' '[1]' 'not json' '{"RENOVATE_X":1}'; do
  run "$bad" ''
  [ "$rc" != 0 ] || fail "extra-env $bad was accepted"
  run '' "$bad"
  [ "$rc" != 0 ] || fail "extra-env-secret $bad was accepted"
done
! grep -qF '"x"' "$tmp/out" || fail "a refusal must not echo values (extra-env-secret may hold a secret)"

yq -e '(.on | keys | join(",")) == "schedule,workflow_dispatch"' "$caller" >/dev/null || fail "$caller must run on a schedule and on demand"
yq -e '.jobs.renovate.uses == "./.github/workflows/renovate.yml" and .jobs.renovate.permissions.contents == "read" and .jobs.renovate.permissions.actions == "read" and .jobs.renovate.permissions.issues == "write"
  and (.jobs.renovate.secrets."app-private-key" | test("CLAUDE_CODE_PR_APP_PRIVATE_KEY"))' "$caller" >/dev/null \
  || fail "$caller must call ./.github/workflows/renovate.yml with contents and actions read and the App key"
echo "renovate-reusable ok"
