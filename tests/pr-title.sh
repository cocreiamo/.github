#!/usr/bin/env bash
# The title check must keep the agreed Conventional Commit types (`test` included) and refuse any other.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
f=.github/workflows/pr-title.yml
types=$(yq -N '.jobs.check.steps[0].with.types' "$f" | grep . | sort | paste -sd' ')
want="build chore ci docs feat fix perf refactor revert style test"
[[ $types == "$want" ]] || fail "allowed types are '$types', want '$want'"
[[ $(yq -N '.jobs.check.steps[0].with.requireScope' "$f") == false ]] || fail "scope must stay optional"
yq -e '.jobs.check.steps[0].uses | test("^amannn/action-semantic-pull-request@[0-9a-f]{40} ?")' "$f" >/dev/null \
  || fail "the action must be pinned by commit"
allowed() { [[ " $types " == *" ${1%%[:(!]*} "* ]]; }
allowed "test: pin the failing case first" || fail "a test: title must be accepted (the test-first commit rule)"
allowed "fix(scope): x" || fail "fix(scope): must be accepted"
allowed "wibble: x" && fail "an unknown type must be refused"
echo "pr-title ok"
