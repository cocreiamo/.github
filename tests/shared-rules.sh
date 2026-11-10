#!/usr/bin/env bash
# The shared-rules check passes on a CLAUDE.md that carries the canonical section and fails on a diverged or missing one.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
canonical=shared/working-with-the-founder.md
[ -f "$wf" ] || fail "$wf does not exist"
embedded=$(yq -N '.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section") | .env.CANONICAL' "$wf")
[ "$embedded" = "$(cat "$canonical")" ] || fail "the text embedded in $wf differs from $canonical"
script=$(yq -N '.jobs.check.steps[] | select(.name == "CLAUDE.md carries the canonical section") | .run' "$wf")
tmpdir
run() { (cd "$tmp" && CANONICAL="$embedded" bash -c "$script") >/dev/null 2>&1; }

{ printf '# Repo\n\nIntro.\n\n## Layout\n\nx\n\n'; cat "$canonical"; printf '\n\n\n## Never\n\n- y\n'; } > "$tmp/CLAUDE.md"
run || fail "refused a CLAUDE.md that carries the canonical section"
{ printf '# Repo\n\n'; cat "$canonical"; } > "$tmp/CLAUDE.md"
run || fail "refused the canonical section at the end of the file"

sed 's/Answer first/Answer second/' "$tmp/CLAUDE.md" > "$tmp/diverged"
mv "$tmp/diverged" "$tmp/CLAUDE.md"
if run; then fail "accepted a diverged section"; fi
printf '# Repo\n\n## Layout\n\nx\n' > "$tmp/CLAUDE.md"
if run; then fail "accepted a CLAUDE.md without the section"; fi
rm "$tmp/CLAUDE.md"
if run; then fail "accepted a repository without CLAUDE.md"; fi
echo "shared-rules ok"
