#!/usr/bin/env bash
# Every check of this repository (a tests/*.sh test, a hook) has an entry in docs/fitness-functions/ and every entry validates against the schema of cocreiamo/deploy; the checker is proven on fixtures and on this tree with an entry removed and an entry broken.
set -euo pipefail
cd "$(dirname "$0")/.."
uv_run() { uv run --quiet --no-project --no-config --with pyyaml==6.0.3 "$@"; }
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/shared/scripts" uv_run python3 -m unittest tests/fitness_entries_test.py
check() { uv_run python3 -I shared/scripts/fitness_entries.py dotgithub "$PWD" "$@"; }
check
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r docs/fitness-functions "$tmp/missing"
rm "$tmp/missing/dotgithub_test_pr-title.sh.yaml"
if check --entries "$tmp/missing" > "$tmp/out" 2>&1; then echo "FAIL: a check without an entry must be refused" >&2; exit 1; fi
grep -qF 'tests/pr-title.sh is a check with no entry' "$tmp/out" || { echo "FAIL: the refusal must name the check" >&2; cat "$tmp/out" >&2; exit 1; }
cp -r docs/fitness-functions "$tmp/broken"
sed -i 's/^- pr-ci$/- weekly/' "$tmp/broken/dotgithub_test_pr-title.sh.yaml"
if check --entries "$tmp/broken" > "$tmp/out" 2>&1; then echo "FAIL: an entry outside the schema must be refused" >&2; exit 1; fi
grep -qF 'runs must be a list drawn from' "$tmp/out" || { echo "FAIL: the refusal must say why" >&2; cat "$tmp/out" >&2; exit 1; }
echo "every check has an entry and an invalid entry is refused"
