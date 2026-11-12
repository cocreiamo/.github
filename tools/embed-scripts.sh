#!/usr/bin/env bash
# Writes shared/scripts and shared/config into .github/workflows/shared-rules.yml (and the founder section, as the text the check holds CLAUDE.md to) as the base64 of a gzipped tar (a caller's token cannot
# read this private repository's files, so the workflow carries the scripts it compares against), and
# shared/scripts/stalled_prs.py into .github/workflows/stalled-prs.yml and shared/scripts/mark_conflicts.py into .github/workflows/dirty-prs.yml
# (the reusable workflows run them from there).
# tests/shared-scripts.sh, tests/shared-configs.sh and tests/stalled-prs.sh and tests/maintenance-reusables.sh fail until this has been run after a change to shared/scripts or shared/config.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp); trap 'rm -f "$tmp" "$tmp.text"' EXIT

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

# embed_heredoc <workflow> <name> <text>: replaces the body of the here-document `<<'<name>'` with <text>. A bundle lives in the run
# script, not in env: one environment variable is capped at 131072 bytes by the kernel, a run script is a file.
embed_heredoc() {
  printf '%s\n' "$3" > "$tmp.text"
  awk -v name="$2" -v text="$tmp.text" '
    skip && $0 ~ "^ *" name "$" { skip = 0 }
    skip { next }
    { print }
    index($0, "<<\x27" name "\x27") {
      match($0, /^ */); ind = RLENGTH
      while ((getline line < text) > 0) print sprintf("%*s", ind, "") line
      close(text)
      skip = 1
    }
  ' "$1" > "$tmp"
  cat "$tmp" > "$1"
}

bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts . | gzip -n -9 | base64 -w76)
embed_heredoc .github/workflows/shared-rules.yml SCRIPTS_BUNDLE "$bundle"
check_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts commit-identity unattributed_commits.py | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +CHECK_BUNDLE: \\|-$' "$check_bundle"
pins_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pins-consistent | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +PINS_BUNDLE: \\|-$' "$pins_bundle"
rules_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/scripts pr-size comment-hygiene claude-md-duplicates claude-md-paragraphs | gzip -n -9 | base64 -w76)
embed .github/workflows/shared-rules.yml '^ +RULES_BUNDLE: \\|-$' "$rules_bundle"
config_bundle=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C shared/config . | gzip -n -9 | base64 -w76)
embed_heredoc .github/workflows/shared-rules.yml CONFIGS_BUNDLE "$config_bundle"
embed .github/workflows/shared-rules.yml '^ +CANONICAL: \\|-$' "$(cat shared/working-with-the-founder.md)"
embed .github/workflows/stalled-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/stalled_prs.py)"
embed .github/workflows/dirty-prs.yml '^ +SCRIPT: \\|$' "$(cat shared/scripts/mark_conflicts.py)"
