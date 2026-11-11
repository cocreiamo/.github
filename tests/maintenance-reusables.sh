#!/usr/bin/env bash
# The reusable maintenance workflows every repository calls: dirty-prs.yml (labels the PRs a merge to main left in conflict),
# auto-merge-rearm.yml (arms auto-merge again after a reopen) and eol.yml (the nightly end-of-life issue). Each is reusable only, has
# its own concurrency group naming the repository, a timeout on every job, actions pinned by commit and the least permissions; the
# embedded scripts are the canonical ones byte for byte, and what each does is proven on a stub API.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
tmpdir
dir=.github/workflows

common() { # <workflow> <job>...: the rules every reusable maintenance workflow keeps
  local wf=$dir/$1 job
  shift
  [ -f "$wf" ] || fail "$wf is missing"
  yq -e '(.on | keys | join(",")) == "workflow_call"' "$wf" >/dev/null || fail "$wf must be reusable only (the trigger belongs to the caller)"
  yq -e '(.permissions | length) == 0' "$wf" >/dev/null || fail "$wf must start from permissions: {}"
  yq -e '(.concurrency.group | test("github.repository")) and .concurrency."cancel-in-progress" != true' "$wf" >/dev/null \
    || fail "$wf must declare its own concurrency group naming the repository, never cancelling a run in progress"
  for job in "$@"; do
    yq -e ".jobs.\"$job\".\"runs-on\" | join(\",\") == \"self-hosted,cocreiamo-ci\"" "$wf" >/dev/null || fail "$wf job $job must run on [self-hosted, cocreiamo-ci]"
    yq -e ".jobs.\"$job\".\"timeout-minutes\" > 0 and .jobs.\"$job\".\"timeout-minutes\" <= 10" "$wf" >/dev/null || fail "$wf job $job needs a short timeout-minutes"
    yq -e "[.jobs.\"$job\".steps[] | select(has(\"uses\")) | .uses | test(\"@[0-9a-f]{40}( |\$)\")] | all" "$wf" >/dev/null || fail "every action of $wf must be pinned by commit"
    yq -e ".jobs.\"$job\" | has(\"permissions\")" "$wf" >/dev/null || fail "$wf job $job must declare its permissions"
  done
}

embedded() { # <workflow> <job> <step name> <file>: the embedded SCRIPT equals the canonical file
  yq -N ".jobs.\"$2\".steps[] | select(.name == \"$3\") | .env.SCRIPT" "$dir/$1" > "$tmp/embedded"
  [ -s "$tmp/embedded" ] && [ "$(cat "$tmp/embedded")" != null ] || fail "$1 has no step '$3' with env SCRIPT"
  [ "$(cat "$4")" = "$(cat "$tmp/embedded")" ] || fail "the script embedded in $1 differs from $4: run tools/embed-scripts.sh"
}

# dirty-prs
common dirty-prs.yml mark
wf=$dir/dirty-prs.yml
yq -e '.jobs.mark.permissions."pull-requests" == "write" and .jobs.mark.permissions.issues == "write" and (.jobs.mark.permissions | has("contents") | not)' "$wf" >/dev/null \
  || fail "dirty-prs.yml needs pull-requests and issues write and no contents (the script is embedded, nothing is checked out)"
yq -e '[.jobs.mark.steps[] | has("uses")] | any | not' "$wf" >/dev/null || fail "dirty-prs.yml checks out and uses nothing: the script is embedded"
embedded dirty-prs.yml mark "label and comment the pull requests in conflict" shared/scripts/mark_conflicts.py
(cd shared/scripts && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest mark_conflicts_test)
printf '%s\n' "$(cat shared/scripts/mark_conflicts.py)" > "$tmp/mark_conflicts.py"
(cd shared/scripts && MARK_CONFLICTS_SCRIPT=$tmp/mark_conflicts.py PYTHONDONTWRITEBYTECODE=1 python3 -m unittest mark_conflicts_test)

# auto-merge-rearm
common auto-merge-rearm.yml arm
wf=$dir/auto-merge-rearm.yml
yq -e '.jobs.arm.permissions | length == 0' "$wf" >/dev/null || fail "auto-merge-rearm.yml's job holds no token permission: the App token acts"
yq -e '(.jobs.arm.if | test("!github.event.pull_request.draft")) and (.jobs.arm.if | test("head.repo.full_name == github.repository"))' "$wf" >/dev/null \
  || fail "auto-merge-rearm.yml must skip drafts and PRs from forks"
yq -e '[.jobs.arm.steps[] | select(has("uses")) | .uses | test("actions/checkout")] | any | not' "$wf" >/dev/null || fail "auto-merge-rearm.yml runs with secrets: it must check out no code of the PR"
yq -e '[.jobs.arm.steps[] | select(has("run")) | .run | test("\bgh\b")] | any | not' "$wf" >/dev/null || fail "auto-merge-rearm.yml must not call gh: the runners have none and its token must be the App's"
yq -e '.jobs.arm.steps[] | select(.id == "token") | .with | (."permission-contents" == "write" and ."permission-pull-requests" == "write")' "$wf" >/dev/null \
  || fail "the App token of auto-merge-rearm.yml needs contents and pull-requests write, nothing more"
yq -N '.jobs.arm.steps[] | select(has("run")) | .env.SCRIPT' "$wf" > "$tmp/arm.py"
python3 -I tests/auto_merge_rearm_test.py "$tmp/arm.py"

# eol
common eol.yml eol
wf=$dir/eol.yml
yq -e '.on.workflow_call.inputs.task.type == "string" and .on.workflow_call.inputs.task.default == "check:eol"
  and .on.workflow_call.inputs.cleanup.type == "boolean" and .on.workflow_call.inputs.cleanup.default == false' "$wf" >/dev/null \
  || fail "eol.yml must declare the optional inputs task (string, default check:eol) and cleanup (boolean, default false)"
yq -e '.jobs.eol.permissions.contents == "read" and .jobs.eol.permissions.issues == "write"' "$wf" >/dev/null || fail "eol.yml needs contents read and issues write"
yq -e '(.jobs.eol.steps[] | select(.name == "empty the workspace") | .if) | test("inputs.cleanup")' "$wf" >/dev/null || fail "the workspace cleanup must run only when cleanup is true"
yq -e '.jobs.eol.steps[] | select(has("uses")) | .with."persist-credentials" == false' "$wf" >/dev/null || fail "the checkout must not persist credentials"

yq -N '.jobs.eol.steps[] | select(.name == "pinned versions that are end of life or reach it within 60 days") | .run' "$wf" > "$tmp/check.sh"
yq -N '.jobs.eol.steps[] | select(.name == "open, update or close the end-of-life issue") | .run' "$wf" > "$tmp/issue.sh"
yq -N '.jobs.eol.steps[] | select(.name == "a failed check that is not a finding fails the run") | .run' "$wf" > "$tmp/notfinding.sh"
for f in check issue notfinding; do [ -s "$tmp/$f.sh" ] && [ "$(cat "$tmp/$f.sh")" != null ] || fail "eol.yml lost the step of $f.sh"; done
yq -e '(.jobs.eol.steps[] | select(.name == "a failed check that is not a finding fails the run") | .if) | test("steps.eol.outputs.status != .0.")' "$wf" >/dev/null || fail "a failed check must reach the last step"

mkdir "$tmp/work" "$tmp/mise-bin"
stub_bin gh 'echo "gh $*" >> "$FAKE_GH_LOG"; case "$1 $2" in "issue list") printf "%s" "${OPEN_ISSUE:-}" ;; esac'
export FAKE_GH_LOG=$tmp/gh.log GITHUB_OUTPUT=$tmp/output
issue() { # <open issue number or empty> <FAIL line or empty>: runs the issue step
  : > "$FAKE_GH_LOG"
  printf '%s' "$2" > "$tmp/work/eol.err"
  (cd "$tmp/work" && OPEN_ISSUE=$1 bash -e "$tmp/issue.sh")
}
issue '' 'FAIL python 3.9 ends 2025-10-31'
grep -q '^gh label create eol' "$FAKE_GH_LOG" && grep -q '^gh issue create --title Pinned versions near end of life --label eol --body-file body.md' "$FAKE_GH_LOG" \
  || { cat "$FAKE_GH_LOG" >&2; fail "a finding with no open issue must create the labelled issue"; }
grep -qF 'FAIL python 3.9' "$tmp/work/body.md" || fail "the issue body must carry the finding"
issue 12 'FAIL python 3.9 ends 2025-10-31'
grep -q '^gh issue edit 12 --body-file body.md' "$FAKE_GH_LOG" && ! grep -q 'issue create' "$FAKE_GH_LOG" || fail "a finding with an open issue must update it, never duplicate"
issue 12 ''
grep -q '^gh issue close 12 --comment' "$FAKE_GH_LOG" || fail "no finding with an open issue must close it"
issue '' ''
! grep -qE 'issue (create|edit|close)' "$FAKE_GH_LOG" || fail "no finding and no issue must write nothing"
printf 'FAIL x\n' > "$tmp/work/eol.err"
(cd "$tmp/work" && bash -e "$tmp/notfinding.sh") || fail "a failed check whose stderr is a finding is not a run failure"
printf 'Traceback: no network\n' > "$tmp/work/eol.err"
if (cd "$tmp/work" && bash -e "$tmp/notfinding.sh") > /dev/null 2>&1; then fail "a failed check that is not a finding must fail the run"; fi
stub_bin mise 'echo "mise $*" >> "$FAKE_GH_LOG"; echo "FAIL from task" >&2; exit 1'
(cd "$tmp/work" && EOL_TASK=check:eol GITHUB_OUTPUT=$tmp/output bash -e "$tmp/check.sh") || fail "a failing task must be recorded, not fail the step"
grep -qF 'status=1' "$tmp/output" || fail "the status of the task must reach the output"
grep -qF 'mise run check:eol' "$FAKE_GH_LOG" || fail "the check must run the task named by the input"
grep -qF 'FAIL from task' "$tmp/work/eol.err" || fail "the findings are on stderr, kept in eol.err"
echo "maintenance reusables ok"
