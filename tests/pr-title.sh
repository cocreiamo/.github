#!/usr/bin/env bash
# Runs the title check of .github/workflows/pr-title.yml on accepted and refused titles.
set -euo pipefail
cd "$(dirname "$0")/.."
script=$(yq -N '.jobs.check.steps[0].run' .github/workflows/pr-title.yml)
check() { TITLE="$1" bash -c "$script" >/dev/null 2>&1; }
for t in "fix: kc reaches the API over SSH" "feat(ci): reusable PR title check" "docs: the founder section" "refactor!: one render helper"; do
  check "$t" || { echo "FAIL: refused a good title: $t" >&2; exit 1; }
done
for t in "test: kc reaches the API over SSH" "test(ci): x y z" "Update README" "fix:no space" "feat: " "WIP"; do
  if check "$t"; then echo "FAIL: accepted a bad title: $t" >&2; exit 1; fi
done
echo "pr-title ok"
