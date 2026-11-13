#!/usr/bin/env bash
# Writes shared/scripts and shared/config into .github/workflows/shared-rules.yml (and the founder section, as the text the check holds CLAUDE.md to) as the base64 of a gzipped tar (a caller's token cannot
# read this private repository's files, so the workflow carries the scripts it compares against), and
# shared/scripts/stalled_prs.py into .github/workflows/stalled-prs.yml and shared/scripts/mark_conflicts.py into .github/workflows/dirty-prs.yml
# (the reusable workflows run them from there).
# tests/shared-scripts.sh, tests/shared-configs.sh and tests/stalled-prs.sh and tests/maintenance-reusables.sh fail until this has been run after a change to shared/scripts or shared/config.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp); trap 'rm -f "$tmp" "$tmp.text" "$tmp".chunk.*' EXIT

# embed <workflow> <regex of the block scalar's key line> <text>: replaces the lines under the key with <text>
embed() {
  printf '%s\n' "$3" > "$tmp.text"
  awk -v key="$2" -v text="$tmp.text" '
    skip && (/^[[:space:]]*$/ || match($0, /^ */) && RLENGTH >= ind) { next }
    { skip = 0 }
    { print }
    $0 ~ key {
      match($0, /^ */); ind = RLENGTH + 2
      while ((getline line < text) > 0) print (line == "" ? "" : sprintf("%*s", ind, "")) line
      close(text)
      skip = 1
    }
  ' "$1" > "$tmp"
  cat "$tmp" > "$1"
}

# embed_chunks <workflow> <name> <text>: spreads <text> over the block scalars <name>_1, <name>_2, ... (one environment variable is
# capped at 131072 bytes by the kernel, and a bundle inside a run script makes actionlint's shellcheck pass crawl); fails when the
# keys the workflow declares cannot hold it, unused keys are left empty.
embed_chunks() {
  local wf=$1 name=$2 keys chunks k
  keys=$(grep -cE "^ +${name}_[0-9]+: \|-$" "$wf" || true)
  printf '%s\n' "$3" | split -l "$CHUNK_LINES" -d -a 2 - "$tmp.chunk."
  chunks=$(find "$(dirname "$tmp")" -maxdepth 1 -name "${tmp##*/}.chunk.*" | wc -l)
  if [ "$chunks" -gt "$keys" ]; then
    rm -f "$tmp".chunk.*
    echo "embed-scripts: $name needs $chunks keys of $CHUNK_LINES lines, $wf declares $keys: add ${name}_$((keys + 1)) beside the others" >&2
    exit 1
  fi
  for k in $(seq 1 "$keys"); do
    f=$(printf '%s.chunk.%02d' "$tmp" $((k - 1)))
    if [ -f "$f" ]; then embed "$wf" "^ +${name}_${k}: \\|-$" "$(cat "$f")"; else embed "$wf" "^ +${name}_${k}: \\|-$" ""; fi
  done
  rm -f "$tmp".chunk.*
}
CHUNK_LINES=1150

bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts . | gzip -n -9 | base64 -w76)
embed_chunks .github/workflows/shared-rules.yml SCRIPTS_BUNDLE "$bundle"
check_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts commit-identity unattributed_commits.py | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +CHECK_BUNDLE: \\|-$' "$check_bundle"
pins_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pins-consistent | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +PINS_BUNDLE: \\|-$' "$pins_bundle"
rules_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pr-size comment-hygiene claude-md-duplicates claude-md-paragraphs | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +RULES_BUNDLE: \\|-$' "$rules_bundle"
config_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/config . | gzip -n -9 | base64 -w76)
embed_chunks .github/workflows/shared-rules.yml CONFIGS_BUNDLE "$config_bundle"
embed .github/workflows/shared-rules.yml '^ +CANONICAL: \\|-$' "$(cat shared/working-with-the-founder.md)"
embed .github/workflows/stalled-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/stalled_prs.py)"
embed .github/workflows/dirty-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/mark_conflicts.py)"
