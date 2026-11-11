#!/usr/bin/env bash
# A public repository never runs on the self-hosted runners: every job reachable from a trigger other than workflow_call, directly or through a local reusable call, runs on a GitHub-hosted label or on the guarded form that is hosted when the repository is public; proven red on fixtures of each way to break it.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
tmpdir
check() { tests/public_runners.py "$1"; }

refuse() { # name, expected text, then file bodies as name=body
  local name=$1 want=$2 got
  shift 2
  mkdir -p "$tmp/$name"
  local kv
  for kv in "$@"; do printf '%s\n' "${kv#*=}" > "$tmp/$name/${kv%%=*}"; done
  if got=$(check "$tmp/$name" 2>&1); then fail "case '$name' was not refused"; fi
  [[ $got == *"$want"* ]] || fail "case '$name': expected '$want', got: $got"
}
job() { printf 'jobs:\n  j:\n    runs-on: %s\n    steps:\n      - run: true\n' "$1"; }
guard="\${{ fromJSON(github.repository_visibility == 'public' && '\"ubuntu-24.04\"' || '[\"self-hosted\",\"cocreiamo-ci\"]') }}"

for trigger in push pull_request pull_request_target schedule workflow_dispatch merge_group workflow_run; do
  refuse "self-hosted-$trigger" 'runs on' "a.yml=$(printf 'on:\n  %s:\n' "$trigger")
$(job '[self-hosted, cocreiamo-ci]')"
done
refuse mixed-triggers 'runs on' "a.yml=$(printf 'on: [push, workflow_call]\n')
$(job '[self-hosted, cocreiamo-ci]')"
refuse local-reusable 'reached from a.yml' \
  "a.yml=$(printf 'on: push\njobs:\n  c:\n    uses: ./.github/workflows/b.yml\n')" \
  "b.yml=$(printf 'on: workflow_call\n')
$(job '[self-hosted, cocreiamo-ci]')"
refuse guard-private-branch-hosted 'runs on' "a.yml=$(printf 'on: push\n')
$(job "\${{ fromJSON(github.repository_visibility == 'private' && '\"ubuntu-24.04\"' || '[\"self-hosted\"]') }}")"
refuse guard-public-branch-self-hosted 'runs on' "a.yml=$(printf 'on: push\n')
$(job "\${{ fromJSON(github.repository_visibility == 'public' && '[\"self-hosted\"]' || '\"ubuntu-24.04\"') }}")"
refuse label-in-vars 'runs on' "a.yml=$(printf 'on: push\n')
$(job '${{ vars.RUNNER }}')"

mkdir -p "$tmp/ok"
printf 'on: [push, pull_request]\n%s\n' "$(job ubuntu-24.04)" > "$tmp/ok/a.yml"
printf 'on: push\n%s\n' "$(job "$guard")" > "$tmp/ok/g.yml"
printf 'on: workflow_call\n%s\n' "$(job '[self-hosted, cocreiamo-ci]')" > "$tmp/ok/r.yml"
check "$tmp/ok" || fail "hosted, guarded and workflow_call-only jobs were refused"
check .github/workflows
echo "public-runners ok"
