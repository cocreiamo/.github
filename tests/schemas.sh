#!/usr/bin/env bash
# tools/schemas validates the workflows, the issue forms and their config, and the Renovate configs against the schemas
# check-jsonschema vendors (SchemaStore, offline): green on this repository, red on each broken copy.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
tmpdir
[ -x tools/schemas ] || fail "tools/schemas is missing"
grep -qx 'tools/schemas' mise-tasks/ci/lint || fail "ci:lint does not run tools/schemas"
tools/schemas >"$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "this repository does not pass its schemas"; }
copy() {
  rm -rf "$tmp/r"
  mkdir -p "$tmp/r"
  cp -r .github default.json renovate.json renovate "$tmp/r/"
}
refused() {
  if tools/schemas "$tmp/r" >/dev/null 2>&1; then fail "tools/schemas accepted $1"; fi
}
copy
printf 'name: x\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    stepz: []\n' >"$tmp/r/.github/workflows/bad.yml"
refused "a workflow job with an unknown key"
copy
printf 'name: x\ndescription: y\nbody:\n  - type: nonsense\n' >"$tmp/r/.github/ISSUE_TEMPLATE/bad.yml"
refused "an issue form with an unknown field type"
copy
printf 'blank_issues_enabled: maybe\n' >"$tmp/r/.github/ISSUE_TEMPLATE/config.yml"
refused "an issue config with a non-boolean blank_issues_enabled"
copy
jq '.prHourlyLimit = "many"' default.json >"$tmp/r/default.json"
refused "a Renovate preset with a string where a number goes"
echo "schemas ok"
