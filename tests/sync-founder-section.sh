#!/usr/bin/env bash
# renovate/sync-founder-section.sh rewrites the founder section of a CLAUDE.md to the canonical text embedded in a
# shared-rules.yml, wherever the section sits, leaves the rest alone, and the result passes the shared-rules check.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
sync=renovate/sync-founder-section.sh
canonical=shared/working-with-the-founder.md
step='.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section")'
check=$(yq -N "$step | .run" "$wf")
embedded=$(yq -N "$step | .env.CANONICAL" "$wf")
tmpdir
passes() { (cd "$1" && CANONICAL="$embedded" bash -c "$check") >/dev/null 2>&1; }
sync() { (cd "$1" && SHARED_RULES_FILE="$OLDPWD/$wf" bash "$OLDPWD/$sync") >/dev/null; }
old() { sed -e 's/Answer first/Answer second/' -e '$ a\- an extra old bullet' "$canonical"; }

mkdir "$tmp/middle"
{ printf '# Repo\n\nIntro.\n\n## Layout\n\nx\n\n'; old; printf '\n\n\n## Never\n\n- y\n'; } > "$tmp/middle/CLAUDE.md"
passes "$tmp/middle" && fail "the fixture should start diverged"
sync "$tmp/middle"
passes "$tmp/middle" || fail "not canonical after the sync (section in the middle)"
grep -q '^## Layout$' "$tmp/middle/CLAUDE.md" && grep -q '^- y$' "$tmp/middle/CLAUDE.md" && grep -q '^Intro\.$' "$tmp/middle/CLAUDE.md" \
  || fail "the sync touched the rest of the file"

mkdir "$tmp/end"
{ printf '# Repo\n\n'; old; } > "$tmp/end/CLAUDE.md"
sync "$tmp/end"
passes "$tmp/end" || fail "not canonical after the sync (section at the end)"

cp "$tmp/middle/CLAUDE.md" "$tmp/before"
sync "$tmp/middle"
cmp -s "$tmp/before" "$tmp/middle/CLAUDE.md" || fail "the sync is not idempotent"

mkdir "$tmp/none"; printf '# Repo\n\n## Layout\n\nx\n' > "$tmp/none/CLAUDE.md"
if sync "$tmp/none"; then fail "the sync accepted a CLAUDE.md without the section"; fi

scripts_check=$(yq -N '.jobs.check.steps[] | select(.name == "vendored scripts equal the canonical ones") | .run' "$wf")
bundle=$(yq -N '.jobs.check.steps[] | select(.name == "vendored scripts equal the canonical ones") | .env.SCRIPTS_BUNDLE' "$wf")
scripts_pass() { (cd "$1" && SCRIPTS_BUNDLE="$bundle" bash -c "$scripts_check") >/dev/null 2>&1; }
mkdir -p "$tmp/vendored/.github" "$tmp/vendored/tasks"
{ printf '# Repo\n\n'; old; } > "$tmp/vendored/CLAUDE.md"
printf 'wt-gc tasks/gc\nwt-list tasks/deep/list\n' > "$tmp/vendored/.github/shared-scripts"
echo "# stale" > "$tmp/vendored/tasks/gc"; chmod 644 "$tmp/vendored/tasks/gc"
scripts_pass "$tmp/vendored" && fail "the vendored fixture should start diverged"
sync "$tmp/vendored"
scripts_pass "$tmp/vendored" || fail "the vendored scripts are not canonical after the sync"
passes "$tmp/vendored" || fail "the founder section is not canonical after the sync"
printf 'no-such-script tasks/gc\n' > "$tmp/vendored/.github/shared-scripts"
if sync "$tmp/vendored"; then fail "the sync accepted a manifest naming a non-canonical script"; fi
printf 'wt-gc ../escape\n' > "$tmp/vendored/.github/shared-scripts"
if sync "$tmp/vendored"; then fail "the sync wrote outside the repository"; fi
echo "sync-founder-section ok"
