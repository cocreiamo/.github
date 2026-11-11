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

steps='.jobs.renovate.steps[]'
for n in 1 2; do
  yq -e "[$steps | select(has(\"uses\") and (.uses | test(\"renovatebot/github-action\"))) | .env.RENOVATE_LOG_FILE] | any_c(. == \"/tmp/renovate-$n.log\")" "$wf" >/dev/null \
    || fail "attempt $n of Renovate must write its JSON log to /tmp/renovate-$n.log (the runner temp folder): the result of the run is read from it"
done
yq -e "[$steps | select(has(\"uses\") and (.uses | test(\"renovatebot/github-action\"))) | .env.RENOVATE_LOG_FILE_LEVEL] | all_c(. == \"info\")" "$wf" >/dev/null \
  || fail "every Renovate attempt must set RENOVATE_LOG_FILE_LEVEL to info"
yq -e '[.jobs.renovate.steps[] | select(has("uses") and (.uses | test("renovatebot/github-action"))) ] | length == 2' "$wf" >/dev/null \
  || fail "$wf must run Renovate twice at most: the second attempt is the retry after repository-changed"
yq -e '[.jobs.renovate.steps[] | select(.name == "renovate retry") | .if] | all_c(test("steps[.]classify[.]outputs[.]status == .retry."))' "$wf" >/dev/null \
  || fail "the second Renovate attempt must run only when the first ended repository-changed"
yq -e '.jobs.renovate.steps[-1].name == "renovate result" and (.jobs.renovate.steps[-1].if | test("always"))' "$wf" >/dev/null \
  || fail "the last step of the renovate job must be 'renovate result' and run always: a Renovate run that did not finish must turn the job red"
yq -N '.jobs.renovate.steps[] | select(.name == "renovate result") | .env.SCRIPT' "$wf" > "$tmp/result.py"
[ -s "$tmp/result.py" ] && [ "$(cat "$tmp/result.py")" != null ] || fail "$wf has no step 'renovate result' with env SCRIPT"
yq -N '.jobs.renovate.steps[] | select(.id == "classify") | .env.SCRIPT' "$wf" > "$tmp/classify.py"
[ -s "$tmp/classify.py" ] && [ "$(cat "$tmp/classify.py")" != null ] || fail "$wf has no step 'classify' with env SCRIPT"
log() { # <file> <result> <exitCode>: a Renovate JSON log whose repository finished like that
  printf '%s\n' '{"level":30,"msg":"Renovate started"}' '{"level":40,"msg":"Cannot access vulnerability alerts."}' > "$1"
  printf '{"level":30,"repository":"o/r","cloned":true,"result":"%s","status":"onboarded","enabled":true,"onboarded":true,"exitCode":%s,"msg":"Repository finished"}\n' "$2" "$3" >> "$1"
}
classify() { # <log...>: the status the classify step writes
  : > "$tmp/out-status"
  rc=0; RENOVATE_LOGS="$*" GITHUB_OUTPUT=$tmp/out-status python3 -I "$tmp/classify.py" > "$tmp/out" 2>&1 || rc=$?
  sed -n 's/^status=//p' "$tmp/out-status"
}
final() { rc=0; RENOVATE_LOGS="$*" python3 -I "$tmp/result.py" > "$tmp/out" 2>&1 || rc=$?; }
log "$tmp/ok.log" done 0
log "$tmp/changed.log" repository-changed 6
log "$tmp/bad.log" external-host-error 1
printf '%s\n' '{"level":30,"msg":"Renovate started"}' > "$tmp/crash.log"
[ "$(classify "$tmp/ok.log")" = ok ] || fail "a finished repository (exitCode 0) must classify as ok"
[ "$(classify "$tmp/changed.log")" = retry ] || fail "repository-changed must classify as retry"
[ "$(classify "$tmp/bad.log")" = fail ] || fail "any other non-zero result must classify as fail"
[ "$(classify "$tmp/crash.log")" = fail ] || fail "a log without «Repository finished» must classify as fail"
[ "$(classify "$tmp/missing.log")" = fail ] || fail "a missing log must classify as fail"
final "$tmp/ok.log"; [ "$rc" = 0 ] || fail "a finished repository must pass the final check"
final "$tmp/changed.log"; [ "$rc" != 0 ] || fail "repository-changed on the only attempt must turn the run red (it went green on 2026-11-11 with the Go security bump missed)"
final "$tmp/changed.log" "$tmp/ok.log"; [ "$rc" = 0 ] || fail "a retry that finished must make the run green"
final "$tmp/changed.log" "$tmp/changed.log"; [ "$rc" != 0 ] || fail "repository-changed twice must turn the run red"
final "$tmp/ok.log" "$tmp/bad.log"; [ "$rc" != 0 ] || fail "the last attempt decides: a failed retry must turn the run red"
final "$tmp/crash.log"; [ "$rc" != 0 ] || fail "a log without «Repository finished» must turn the run red"
final "$tmp/missing.log"; [ "$rc" != 0 ] || fail "a missing log must turn the run red"

yq -e '(.on | keys | join(",")) == "schedule,workflow_dispatch"' "$caller" >/dev/null || fail "$caller must run on a schedule and on demand"
yq -e '.jobs.renovate.uses == "./.github/workflows/renovate.yml" and .jobs.renovate.permissions.contents == "read" and .jobs.renovate.permissions.actions == "read" and .jobs.renovate.permissions.issues == "write"
  and (.jobs.renovate.secrets."app-private-key" | test("CLAUDE_CODE_PR_APP_PRIVATE_KEY"))' "$caller" >/dev/null \
  || fail "$caller must call ./.github/workflows/renovate.yml with contents and actions read and the App key"
echo "renovate-reusable ok"
