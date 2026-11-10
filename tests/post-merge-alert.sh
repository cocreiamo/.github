#!/usr/bin/env bash
# post-merge-alert.yml: a red job on main that must not be reverted (a publish) opens one issue per failing job, or
# comments on the one already open, with the run link and the failing lines; nothing here ever reverts.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/post-merge-alert.yml
[ -f "$wf" ] || fail "$wf is missing"
tmpdir
yq -N '.jobs.alert.steps[] | select(.name == "alert") | .env.SCRIPT' "$wf" > "$tmp/script.py"
[ -s "$tmp/script.py" ] && [ "$(cat "$tmp/script.py")" != null ] || fail "$wf has no step 'alert' with env SCRIPT"
yq -e '.on.workflow_call.inputs.failed.required and .on.workflow_call.inputs."app-id".required and .on.workflow_call.secrets."app-private-key".required' "$wf" >/dev/null \
  || fail "the workflow must require the inputs failed and app-id and the secret app-private-key"
yq -e '[.jobs.alert.steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$wf" >/dev/null || fail "every action must be pinned by commit"
yq -e '(.jobs.alert.permissions | keys | join(",")) == "actions" and .jobs.alert.permissions.actions == "read"' "$wf" >/dev/null || fail "the job needs exactly actions: read"
if grep -q 'revertPullRequest' "$wf"; then fail "an alert-only workflow never reverts"; fi
drill=.github/workflows/alert-drill.yml
[ -f "$drill" ] || fail "$drill is missing"
verify=.github/workflows/alert-drill-verify.yml
[ -f "$verify" ] || fail "$verify is missing"
yq -e '(.on | keys | join(",")) == "schedule,workflow_dispatch" and (.on.schedule | length) == 1 and (.on.schedule[0].cron | test("^[0-9]+ [0-9]+ [0-9]+ \* \*$"))' "$drill" >/dev/null \
  || fail "the drill must run on its own every month (schedule with a monthly cron) and stay dispatchable"
yq -e '[.jobs[] | select(has("steps")) | .steps[] | select(has("uses")) | .uses | test("@[0-9a-f]{40}$")] | all' "$drill" "$verify" >/dev/null || fail "every action of the drill must be pinned by commit"
yq -e '.jobs."alert-created".with."title-prefix" == "drill: " and .jobs."alert-created".with.label == "drill" and .jobs."alert-commented".with."title-prefix" == "drill: " and .jobs."alert-commented".with.label == "drill"' "$drill" >/dev/null || fail "the drill must not use the title or the label of a red main"
yq -e '(.jobs."alert-created".needs | contains(["drill-fail"])) and (.jobs."alert-commented".needs | contains(["verify-created"])) and (.jobs."verify-commented".needs | contains(["alert-commented"]))' "$drill" >/dev/null || fail "the drill must run created, verify, commented, verify in sequence in one run"
yq -e '.jobs."drill-red".uses | test("post-merge-alert.yml$")' "$drill" >/dev/null || fail "a red scheduled drill must reach the founder through post-merge-alert.yml"
yq -e '(.jobs."drill-red".with | has("title-prefix") | not) and (.jobs."drill-red".if | test("schedule.*failure"))' "$drill" >/dev/null || fail "the red-drill alert keeps the default main is red prefix and runs on a failed scheduled drill"
yq -e '.jobs."drill-fail"."continue-on-error" == true' "$drill" >/dev/null || fail "the drill run must end green: its deliberate failure is continue-on-error"
drill_cleans() {
  yq -e '(.jobs."clean-stale".steps[] | select(.name == "clean") | .env.SCRIPT | length) > 0
    and (.jobs."alert-created".needs | contains(["clean-stale"]))
    and (.jobs."clean-stale"."if" | (test("schedule") and test("commented")))
    and (.jobs."clean-stale".steps[0].with."permission-issues" == "write")' "$1" >/dev/null 2>&1
}
drill_cleans "$drill" || fail "the drill must close the open drill issues of an earlier run before it starts (job clean-stale, before alert-created, not in expect=commented)"
yq '.jobs."alert-created".needs = ["drill-fail"] | del(.jobs."clean-stale")' "$drill" > "$tmp/no-clean.yml"
if drill_cleans "$tmp/no-clean.yml"; then fail "a drill with no stale-issue cleanup must be refused"; fi
yq -N '.jobs."clean-stale".steps[] | select(.name == "clean") | .env.SCRIPT' "$drill" > "$tmp/clean.py"
python3 -I tests/alert_drill_clean_test.py "$tmp/clean.py"
python3 -I tests/post_merge_alert_test.py "$tmp/script.py"
echo "post-merge-alert ok"
