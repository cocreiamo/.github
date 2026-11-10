#!/usr/bin/env bash
# The organization's default pull request template exists and asks the four things every PR answers: what, why, the test proven red, how the class is closed.
set -euo pipefail
cd "$(dirname "$0")/.."
f=.github/PULL_REQUEST_TEMPLATE.md
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$f" ] || fail "$f is missing: the repositories of the organization without a template of their own get none"
for heading in "What" "Why" "Test proven red" "How the class is closed"; do
  grep -qx "## $heading" "$f" || fail "$f has no '## $heading' section"
done
[ "$(wc -l < "$f")" -le 25 ] || fail "$f must stay short (25 lines)"
echo "pr-template ok"
