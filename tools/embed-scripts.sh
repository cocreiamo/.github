#!/usr/bin/env bash
# Writes shared/scripts into .github/workflows/shared-rules.yml as the base64 of a gzipped tar (a caller's token cannot
# read this private repository's files, so the workflow carries the scripts it compares against). tests/shared-scripts.sh
# fails until this has been run after a change to shared/scripts.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts . | gzip -n -9 | base64 -w76)
awk -v bundle="$bundle" '
  skip && (/^[[:space:]]*$/ || match($0, /^ */) && RLENGTH >= ind) { next }
  { skip = 0 }
  { print }
  /^ +SCRIPTS_BUNDLE: \|-$/ {
    match($0, /^ */); ind = RLENGTH + 2
    n = split(bundle, lines, "\n")
    for (i = 1; i <= n; i++) printf "%*s%s\n", ind, "", lines[i]
    skip = 1
  }
' "$wf" > "$tmp"
cat "$tmp" > "$wf"
