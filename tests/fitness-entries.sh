#!/usr/bin/env bash
# Every check of this repository (a tests/*.sh test, a hook) has an entry in docs/fitness-functions/ and every entry validates against the schema of cocreiamo/deploy; the checker is proven on fixtures and on this tree with an entry removed and an entry broken.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
uv_run() { uv run --quiet --no-project --no-config --with pyyaml==6.0.3 "$@"; }
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/shared/scripts:$PWD" uv_run python3 -P -m unittest tests/fitness_entries_test.py
check() { uv_run python3 -I shared/scripts/fitness_entries.py dotgithub "$PWD" "$@"; }
check
tmpdir
cp -r docs/fitness-functions "$tmp/missing"
rm "$tmp/missing/dotgithub_test_pr-title.sh.yaml"
if check --entries "$tmp/missing" > "$tmp/out" 2>&1; then fail "a check without an entry must be refused"; fi
grep -qF 'tests/pr-title.sh is a check with no entry' "$tmp/out" || { cat "$tmp/out" >&2; fail "the refusal must name the check"; }
cp -r docs/fitness-functions "$tmp/broken"
sed -i 's/^- pr-ci$/- weekly/' "$tmp/broken/dotgithub_test_pr-title.sh.yaml"
if check --entries "$tmp/broken" > "$tmp/out" 2>&1; then fail "an entry outside the schema must be refused"; fi
grep -qF 'runs must be a list drawn from' "$tmp/out" || { cat "$tmp/out" >&2; fail "the refusal must say why"; }
echo "every check has an entry and an invalid entry is refused"
