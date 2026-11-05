#!/usr/bin/env bash
# The shared-rules check passes on a CLAUDE.md that carries the canonical section and fails on a diverged or missing one.
set -euo pipefail
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
canonical=shared/working-with-the-founder.md
[ -f "$wf" ] || { echo "FAIL: $wf does not exist" >&2; exit 1; }
embedded=$(yq -N '.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section") | .env.CANONICAL' "$wf")
[ "$embedded" = "$(cat "$canonical")" ] || { echo "FAIL: the text embedded in $wf differs from $canonical" >&2; exit 1; }
script=$(yq -N '.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section") | .run' "$wf")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { (cd "$tmp" && CANONICAL="$embedded" bash -c "$script") >/dev/null 2>&1; }

{ printf '# Repo\n\nIntro.\n\n## Layout\n\nx\n\n'; cat "$canonical"; printf '\n\n\n## Never\n\n- y\n'; } > "$tmp/CLAUDE.md"
run || { echo "FAIL: refused a CLAUDE.md that carries the canonical section" >&2; exit 1; }
{ printf '# Repo\n\n'; cat "$canonical"; } > "$tmp/CLAUDE.md"
run || { echo "FAIL: refused the canonical section at the end of the file" >&2; exit 1; }

sed 's/Answer first/Answer second/' "$tmp/CLAUDE.md" > "$tmp/diverged"
mv "$tmp/diverged" "$tmp/CLAUDE.md"
if run; then echo "FAIL: accepted a diverged section" >&2; exit 1; fi
printf '# Repo\n\n## Layout\n\nx\n' > "$tmp/CLAUDE.md"
if run; then echo "FAIL: accepted a CLAUDE.md without the section" >&2; exit 1; fi
rm "$tmp/CLAUDE.md"
if run; then echo "FAIL: accepted a repository without CLAUDE.md" >&2; exit 1; fi
echo "shared-rules ok"
