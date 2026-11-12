#!/usr/bin/env bash
# shared-rules.yml fails a repository whose workflows pin cocreiamo/.github at more than one SHA, naming each file:line and SHA, so a hand bump never leaves two versions of the shared workflows running side by side. The step carries the check as a bundle; this proves the bundle equals the source, the sparse checkout reaches the workflows, and the step against fixture repositories.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
name="workflow refs of cocreiamo/.github carry one SHA"
[ -n "$(yq -N ".jobs.check.steps[] | select(.name == \"$name\")" "$wf")" ] || fail "$wf has no step '$name'"
sparse=$(yq -N '.jobs.check.steps[] | select(.uses == "actions/checkout*") | .with."sparse-checkout"' "$wf")
for p in .github/workflows .github/actions; do
  grep -qxF "$p" <<<"$sparse" || fail "the sparse checkout of $wf must include $p"
done
tmpdir
mkdir "$tmp/embedded"
yq -N ".jobs.check.steps[] | select(.name == \"$name\") | .env.PINS_BUNDLE" "$wf" | base64 -d | tar -xzf - -C "$tmp/embedded"
cmp -s shared/scripts/pins-consistent "$tmp/embedded/pins-consistent" || fail "the bundle embedded in $wf carries a different pins-consistent: run tools/embed-scripts.sh"
[ -x "$tmp/embedded/pins-consistent" ] || fail "pins-consistent is not executable in the bundle"
script=$(yq -N ".jobs.check.steps[] | select(.name == \"$name\") | .run" "$wf")
A=1111111111111111111111111111111111111111
B=2222222222222222222222222222222222222222
fixture() { # <file> <sha>
  mkdir -p "$tmp/r/.github/workflows"
  printf 'name: x\non: push\njobs:\n  j:\n    uses: cocreiamo/.github/.github/workflows/pr-title.yml@%s # v1\n' "$2" > "$tmp/r/.github/workflows/$1"
}
run() { (cd "$tmp/r" && bash -c "$script") > "$tmp/out" 2>&1; }

fixture a.yml "$A"; fixture b.yml "$A"
run || { cat "$tmp/out" >&2; fail "refused a repository with one SHA"; }
fixture b.yml "$B"
if run; then fail "accepted a repository with two SHAs"; fi
for want in "$A" "$B" a.yml b.yml; do grep -qF "$want" "$tmp/out" || fail "the refusal must name $want"; done
grep -qE 'b\.yml:5' "$tmp/out" || fail "the refusal must name the line of each ref (file:line)"
echo "shared-rules-pins ok"
