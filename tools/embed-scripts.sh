#!/usr/bin/env bash
# Writes shared/scripts and shared/config into .github/workflows/shared-rules.yml (and the founder section, as the text the check holds CLAUDE.md to) as the base64 of a gzipped tar (a caller's token cannot
# read this private repository's files, so the workflow carries the scripts it compares against), and
# shared/scripts/stalled_prs.py into .github/workflows/stalled-prs.yml and shared/scripts/mark_conflicts.py into .github/workflows/dirty-prs.yml
# (the reusable workflows run them from there).
# tests/shared-scripts.sh, tests/shared-configs.sh and tests/stalled-prs.sh and tests/maintenance-reusables.sh fail until this has been run after a change to shared/scripts or shared/config.
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
check_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts commit-identity unattributed_commits.py | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +CHECK_BUNDLE: \\|-$' "$check_bundle"
pins_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pins-consistent | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +PINS_BUNDLE: \\|-$' "$pins_bundle"
rules_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pr-size comment-hygiene | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +RULES_BUNDLE: \\|-$' "$rules_bundle"
config_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/config . | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +CONFIGS_BUNDLE: \\|-$' "$config_bundle"
embed .github/workflows/shared-rules.yml '^ +CANONICAL: \\|-$' "$(cat shared/working-with-the-founder.md)"
embed .github/workflows/stalled-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/stalled_prs.py)"
embed .github/workflows/dirty-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/mark_conflicts.py)"
