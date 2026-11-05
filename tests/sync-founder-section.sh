#!/usr/bin/env bash
# renovate/sync-founder-section.sh rewrites the founder section of a CLAUDE.md to the canonical text embedded in a
# shared-rules.yml, wherever the section sits, leaves the rest alone, and the result passes the shared-rules check.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
sync=renovate/sync-founder-section.sh
canonical=shared/working-with-the-founder.md
step='.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section")'
check=$(yq -N "$step | .run" "$wf")
embedded=$(yq -N "$step | .env.CANONICAL" "$wf")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
passes() { (cd "$1" && CANONICAL="$embedded" bash -c "$check") >/dev/null 2>&1; }
sync() { (cd "$1" && SHARED_RULES_FILE="$OLDPWD/$wf" bash "$OLDPWD/$sync") >/dev/null; }
old() { sed -e 's/Answer first/Answer second/' -e '$ a\- an extra old bullet' "$canonical"; }

mkdir "$tmp/middle"
{ printf '# Repo\n\nIntro.\n\n## Layout\n\nx\n\n'; old; printf '\n\n\n## Never\n\n- y\n'; } > "$tmp/middle/CLAUDE.md"
passes "$tmp/middle" && { echo "FAIL: the fixture should start diverged" >&2; exit 1; }
sync "$tmp/middle"
passes "$tmp/middle" || { echo "FAIL: not canonical after the sync (section in the middle)" >&2; exit 1; }
grep -q '^## Layout$' "$tmp/middle/CLAUDE.md" && grep -q '^- y$' "$tmp/middle/CLAUDE.md" && grep -q '^Intro\.$' "$tmp/middle/CLAUDE.md" \
  || { echo "FAIL: the sync touched the rest of the file" >&2; exit 1; }

mkdir "$tmp/end"
{ printf '# Repo\n\n'; old; } > "$tmp/end/CLAUDE.md"
sync "$tmp/end"
passes "$tmp/end" || { echo "FAIL: not canonical after the sync (section at the end)" >&2; exit 1; }

cp "$tmp/middle/CLAUDE.md" "$tmp/before"
sync "$tmp/middle"
cmp -s "$tmp/before" "$tmp/middle/CLAUDE.md" || { echo "FAIL: the sync is not idempotent" >&2; exit 1; }

mkdir "$tmp/none"; printf '# Repo\n\n## Layout\n\nx\n' > "$tmp/none/CLAUDE.md"
if sync "$tmp/none"; then echo "FAIL: the sync accepted a CLAUDE.md without the section" >&2; exit 1; fi
echo "sync-founder-section ok"
