#!/usr/bin/env bash
# Writes shared/scripts into .github/workflows/shared-rules.yml as the base64 of a gzipped tar (a caller's token cannot
# read this private repository's files, so the workflow carries the scripts it compares against), and
# shared/scripts/stalled_prs.py into .github/workflows/stalled-prs.yml (the reusable workflow runs it from there).
# tests/shared-scripts.sh and tests/stalled-prs.sh fail until this has been run after a change to shared/scripts.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT

# embed <workflow> <regex of the block scalar's key line> <text>: replaces the lines under the key with <text>
embed() {
  EMBED_TEXT=$3 awk -v key="$2" '
    skip && (/^[[:space:]]*$/ || match($0, /^ */) && RLENGTH >= ind) { next }
    { skip = 0 }
    { print }
    $0 ~ key {
      match($0, /^ */); ind = RLENGTH + 2
      n = split(ENVIRON["EMBED_TEXT"], lines, "\n")
      for (i = 1; i <= n; i++) print (lines[i] == "" ? "" : sprintf("%*s", ind, "")) lines[i]
      skip = 1
    }
  ' "$1" > "$tmp"
  cat "$tmp" > "$1"
}

bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts . | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +SCRIPTS_BUNDLE: \\|-$' "$bundle"
embed .github/workflows/stalled-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/stalled_prs.py)"
