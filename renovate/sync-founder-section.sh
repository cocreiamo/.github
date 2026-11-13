#!/usr/bin/env bash
# Brings a repository in line with the pinned shared-rules.yml (SHARED_RULES_FILE, or fetched at the commit given as $1
# with RENOVATE_TOKEN: a caller's token cannot read this repository's files, but it can read the workflow): rewrites the
# section «## Working with the founder» of ./CLAUDE.md to the canonical text, and overwrites each script and config that
# ./.github/shared-scripts and ./.github/shared-configs declare with the canonical copy from the embedded bundles. Run by Renovate as a postUpgradeTask
# when a repository bumps its pin of shared-rules.yml, so the bump PR is complete. The name is the one in every caller's
# allowedCommands.
set -euo pipefail
heading='## Working with the founder'
if [ -n "${SHARED_RULES_FILE:-}" ]; then
  workflow=$(cat "$SHARED_RULES_FILE")
else
  workflow=$(curl -fsSL -H "Authorization: Bearer $RENOVATE_TOKEN" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/cocreiamo/.github/contents/.github/workflows/shared-rules.yml?ref=${1:?commit}")
fi
block() {
  awk -v key="$1" '
    f && /^[[:space:]]*$/ { print ""; next }
    f { match($0, /^ */); if (RLENGTH < ind) exit; print substr($0, ind + 1); next }
    $0 ~ "^ +" key ": \\|-$" { f = 1; match($0, /^ */); ind = RLENGTH + 2 }
  ' <<<"$workflow"
}
# chunks <name>: the bundle spread over the block scalars <name>_1, <name>_2, ... (one env value is capped by the kernel)
chunks() {
  local k=1
  while grep -qE "^ +$1_$k: \|-$" <<<"$workflow"; do
    block "$1_$k"
    k=$((k + 1))
  done
}
canonical=$(block CANONICAL)
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

canon=$(mktemp -d); trap 'rm -rf "$canon"' EXIT
# vendor <manifest> <bundle key> <name regex>: overwrites each file the manifest declares with the canonical copy from the bundle
vendor() {
  local manifest=$1 key=$2 re=$3 name path _
  [ -f "$manifest" ] || return 0
  mkdir -p "$canon/$key"
  chunks "$key" | base64 -d | tar -xzf - -C "$canon/$key"
  while read -r name path _; do
    case ${name:-} in ''|'#'*) continue ;; esac
    [[ $name =~ $re ]] && [ -f "$canon/$key/$name" ] && [ -n "${path:-}" ] || { echo "$manifest: bad line: $name ${path:-}" >&2; exit 1; }
    case $name in /*|..|../*|*/..|*/../*) echo "$manifest: $name leaves the bundle" >&2; exit 1 ;; esac
    case $path in /*|..|../*|*/..|*/../*) echo "$manifest: $path leaves the repository" >&2; exit 1 ;; esac
    mkdir -p "$(dirname "$path")"
    cat "$canon/$key/$name" > "$path"
    if [ -x "$canon/$key/$name" ]; then chmod 755 "$path"; else chmod 644 "$path"; fi
  done < "$manifest"
}
vendor .github/shared-scripts SCRIPTS_BUNDLE '^[A-Za-z0-9._-]+$'
vendor .github/shared-configs CONFIGS_BUNDLE '^[A-Za-z0-9._/-]+$'
