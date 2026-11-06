#!/usr/bin/env bash
# The title check must keep the agreed Conventional Commit types (`test` included) and refuse any other.
set -euo pipefail
cd "$(dirname "$0")/.."
f=.github/workflows/pr-title.yml
types=$(yq -N '.jobs.check.steps[0].with.types' "$f" | grep . | sort | paste -sd' ')
want="build chore ci docs feat fix perf refactor revert style test"
[[ $types == "$want" ]] || { echo "FAIL: allowed types are '$types', want '$want'" >&2; exit 1; }
[[ $(yq -N '.jobs.check.steps[0].with.requireScope' "$f") == false ]] || { echo "FAIL: scope must stay optional" >&2; exit 1; }
yq -e '.jobs.check.steps[0].uses | test("^amannn/action-semantic-pull-request@[0-9a-f]{40} ?")' "$f" >/dev/null \
  || { echo "FAIL: the action must be pinned by commit" >&2; exit 1; }
allowed() { [[ " $types " == *" ${1%%[:(!]*} "* ]]; }
allowed "test: pin the failing case first" || { echo "FAIL: a test: title must be accepted (the test-first commit rule)" >&2; exit 1; }
allowed "fix(scope): x" || { echo "FAIL: fix(scope): must be accepted" >&2; exit 1; }
allowed "wibble: x" && { echo "FAIL: an unknown type must be refused" >&2; exit 1; }
echo "pr-title ok"
