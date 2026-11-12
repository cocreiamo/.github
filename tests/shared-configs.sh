#!/usr/bin/env bash
# The shared-rules check carries the canonical configs of shared/config (the common .gitignore and the linter configs) and fails when a repository's
# copy (declared in its .github/shared-configs) diverges, is missing, is a link or is not declared canonical; the sync rewrites the declared copies.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
configs=shared/config
sync=renovate/sync-founder-section.sh
step() { yq -N ".jobs.check.steps[] | select(.name == \"$1\") | $2" "$wf"; }
tmpdir

[ -d "$configs" ] || fail "$configs does not exist"
check=$(step "vendored configs equal the canonical ones" .run)
bundle=$(awk 'f && /^ *CONFIGS_BUNDLE$/ { exit } f { sub(/^ +/, ""); print } index($0, "<<\x27CONFIGS_BUNDLE\x27") { f = 1 }' <<<"$check")
[ -n "$bundle" ] || fail "$wf has no step 'vendored configs equal the canonical ones' whose run script carries the here-document CONFIGS_BUNDLE"
fetch=$(step "fetch the vendored scripts" .run)
sparse=$(yq -N '.jobs.check.steps[] | select(.uses == "actions/checkout*") | .with."sparse-checkout"' "$wf")
grep -qx '.github/shared-configs' <<<"$sparse" || fail "the sparse checkout does not include .github/shared-configs"

mkdir "$tmp/embedded"
base64 -d <<<"$bundle" | tar -xzf - -C "$tmp/embedded"
diff -r "$configs" "$tmp/embedded" >/dev/null || fail "the bundle embedded in $wf differs from $configs: run tools/embed-scripts.sh"

for name in gitignore .editorconfig .yamllint.yaml ruff.toml .shellcheckrc .gitleaks.toml .typos.toml .markdownlint-cli2.yaml .prettierrc.json .hadolint.yaml .vale.ini \
  .vale/styles/Cocreiamo/Banned.yml .vale/styles/Cocreiamo/EnglishOnly.yml; do
  [ -s "$configs/$name" ] || fail "$configs/$name is missing or empty"
done

printf '%s\n' "$check" > "$tmp/check.sh"
run() { (cd "$1" && bash "$tmp/check.sh") >"$tmp/out" 2>&1; }
mkrepo() {
  rm -rf "$tmp/repo"; mkdir -p "$tmp/repo/.github" "$tmp/repo/deep/er"
  cp "$configs/gitignore" "$tmp/repo/.gitignore"
  cp "$configs/.editorconfig" "$tmp/repo/.editorconfig"
  cp "$configs/ruff.toml" "$tmp/repo/deep/er/ruff.toml"
  printf '# canonical-name  local-path\ngitignore .gitignore\n\n.editorconfig .editorconfig\nruff.toml deep/er/ruff.toml\n' > "$tmp/repo/.github/shared-configs"
}

mkrepo
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "refused a repository whose copies are the canonical ones"; }

mkrepo; echo "extra-entry/" >> "$tmp/repo/.gitignore"
if run "$tmp/repo"; then fail "accepted a .gitignore with a per-repository addition"; fi
grep -q '^+extra-entry/' "$tmp/out" || fail "a diverged copy is refused without the diff"
grep -q '\.gitignore' "$tmp/out" || fail "a diverged copy is refused without naming it"

mkrepo; echo "# local tweak" >> "$tmp/repo/deep/er/ruff.toml"
if run "$tmp/repo"; then fail "accepted a diverged ruff.toml"; fi

mkrepo; rm "$tmp/repo/.editorconfig"
if run "$tmp/repo"; then fail "accepted a missing config"; fi

mkrepo; rm "$tmp/repo/.editorconfig"; ln -s "$PWD/$configs/.editorconfig" "$tmp/repo/.editorconfig"
if run "$tmp/repo"; then fail "accepted a link in place of a copy"; fi

mkrepo; printf 'no-such-config .gitignore\n' >> "$tmp/repo/.github/shared-configs"
if run "$tmp/repo"; then fail "accepted a manifest naming a config that is not canonical"; fi

mkrepo; printf '../scripts/wt-gc x\n' >> "$tmp/repo/.github/shared-configs"
if run "$tmp/repo"; then fail "accepted a canonical name outside shared/config"; fi

mkrepo; printf 'ruff.toml ../escape\n' >> "$tmp/repo/.github/shared-configs"
if run "$tmp/repo"; then fail "accepted a manifest path outside the repository"; fi

mkrepo; : > "$tmp/repo/.github/shared-configs"
if run "$tmp/repo"; then fail "accepted an empty manifest"; fi

mkrepo; printf 'ruff.toml x extra\n' > "$tmp/repo/.github/shared-configs"
if run "$tmp/repo"; then fail "accepted a malformed manifest line"; fi

mkrepo; rm "$tmp/repo/.github/shared-configs"
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "refused a repository that has not adopted the shared configs yet (no manifest)"; }

# the fetch step brings the declared configs into a sparse checkout, with or without the scripts manifest
mkrepo
printf 'x\n' > "$tmp/repo/CLAUDE.md"
while read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
git -C "$tmp/repo" init -q -b main
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm init
git clone -q --no-checkout "$tmp/repo" "$tmp/sparse"
git -C "$tmp/sparse" sparse-checkout set --no-cone CLAUDE.md .github/shared-scripts .github/shared-configs
git -C "$tmp/sparse" checkout -q main
[ ! -e "$tmp/sparse/deep/er/ruff.toml" ] || fail "the sparse fixture already has the vendored config"
(cd "$tmp/sparse" && bash -c "$fetch") >"$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "the fetch step failed on a repository with only a configs manifest"; }
[ -f "$tmp/sparse/deep/er/ruff.toml" ] && [ -f "$tmp/sparse/.gitignore" ] || fail "the fetch step did not bring the declared configs"

# the sync overwrites the declared copies with the canonical ones, creating directories, and refuses what the check refuses
sync_in() { (cd "$1" && SHARED_RULES_FILE="$OLDPWD/$wf" bash "$OLDPWD/$sync") >"$tmp/out" 2>&1; }
mkrepo; printf '# Repo\n\n## Working with the founder\n\nold\n' > "$tmp/repo/CLAUDE.md"
echo stale > "$tmp/repo/.gitignore"; rm -r "$tmp/repo/deep"
run "$tmp/repo" && fail "the sync fixture should start diverged"
sync_in "$tmp/repo" || { cat "$tmp/out" >&2; fail "the sync failed"; }
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "the configs are not canonical after the sync"; }
printf 'no-such-config .gitignore\n' > "$tmp/repo/.github/shared-configs"
if sync_in "$tmp/repo"; then fail "the sync accepted a non-canonical name"; fi
printf 'ruff.toml ../escape\n' > "$tmp/repo/.github/shared-configs"
if sync_in "$tmp/repo"; then fail "the sync wrote outside the repository"; fi

# the org community files are vendorable under .github/ (this repository stays private, so GitHub's organization defaults do not apply)
community="SECURITY.md PULL_REQUEST_TEMPLATE.md ISSUE_TEMPLATE/bug.yml ISSUE_TEMPLATE/task.yml ISSUE_TEMPLATE/config.yml"
rm -rf "$tmp/repo"; mkdir -p "$tmp/repo/.github/ISSUE_TEMPLATE"; : > "$tmp/repo/.github/shared-configs"
for f in $community; do
  [ -s "$configs/$f" ] || fail "$configs/$f is missing or empty"
  cp "$configs/$f" "$tmp/repo/.github/$f"
  echo "$f .github/$f" >> "$tmp/repo/.github/shared-configs"
  cmp -s ".github/$f" "$configs/$f" || fail "this repository's .github/$f is not the canonical community file"
done
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "refused community files that are the canonical ones under .github/"; }
echo "Contact someone else" >> "$tmp/repo/.github/SECURITY.md"
if run "$tmp/repo"; then fail "accepted a diverged SECURITY.md"; fi
printf '# Repo\n\n## Working with the founder\n\nold\n' > "$tmp/repo/CLAUDE.md"
sync_in "$tmp/repo" || { cat "$tmp/out" >&2; fail "the sync failed on the community files"; }
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "the community files are not canonical after the sync"; }

cmp -s .gitignore "$configs/gitignore" || fail "this repository's own .gitignore is not the canonical one"
echo "shared-configs ok"
