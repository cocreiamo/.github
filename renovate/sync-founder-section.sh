#!/usr/bin/env bash
# Rewrites the section «## Working with the founder» of ./CLAUDE.md to the canonical text embedded in
# shared-rules.yml (SHARED_RULES_FILE, or fetched at the commit given as $1 with RENOVATE_TOKEN: a caller's token
# cannot read this repository's files, but it can read the workflow). Run by Renovate as a postUpgradeTask when a
# repository bumps its pin of shared-rules.yml, so the bump PR is complete.
set -euo pipefail
heading='## Working with the founder'
if [ -n "${SHARED_RULES_FILE:-}" ]; then
  workflow=$(cat "$SHARED_RULES_FILE")
else
  workflow=$(curl -fsSL -H "Authorization: Bearer $RENOVATE_TOKEN" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/cocreiamo/.github/contents/.github/workflows/shared-rules.yml?ref=${1:?commit}")
fi
canonical=$(awk '
  f && /^[[:space:]]*$/ { print ""; next }
  f { match($0, /^ */); if (RLENGTH < ind) exit; print substr($0, ind + 1); next }
  /^ +CANONICAL: \|-$/ { f = 1; match($0, /^ */); ind = RLENGTH + 2 }
' <<<"$workflow")
[ "${canonical%%$'\n'*}" = "$heading" ] || { echo "no canonical section in shared-rules.yml" >&2; exit 1; }
grep -qx "$heading" CLAUDE.md || { echo "CLAUDE.md has no '$heading' section" >&2; exit 1; }
tmp=$(mktemp)
awk -v h="$heading" -v canonical="$canonical" '
  $0 == h { print canonical; skip = 1; next }
  skip && /^## / { skip = 0; print ""; print; next }
  !skip { print }
' CLAUDE.md > "$tmp"
cat "$tmp" > CLAUDE.md
rm -f "$tmp"
