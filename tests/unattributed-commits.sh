#!/usr/bin/env bash
# shared-rules.yml fails a pull request carrying a commit GitHub maps to no user (and that is not a bot's) or one authored on a reserved test domain:
# the ruleset blocks such a PR with every check green, so the red must say why. The step carries the check as a bundle; this proves the bundle equals the
# sources and the check against a fake API.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
step=$(yq -N '.jobs.check.steps[] | select(.name == "no unattributed commits")' "$wf")
[ -n "$step" ] || fail "$wf has no step 'no unattributed commits'"
[ "$(yq -N '.jobs.check.steps[] | select(.name == "no unattributed commits") | .if' "$wf")" = "github.event_name == 'pull_request'" ] || fail "the step must run on pull_request only"
tmpdir
mkdir "$tmp/embedded"
yq -N '.jobs.check.steps[] | select(.name == "no unattributed commits") | .env.CHECK_BUNDLE' "$wf" | base64 -d | tar -xzf - -C "$tmp/embedded"
for f in unattributed_commits.py commit-identity; do
  cmp -s "shared/scripts/$f" "$tmp/embedded/$f" || fail "the bundle embedded in $wf carries a different $f: run tools/embed-scripts.sh"
  [ "$(test -x "shared/scripts/$f" && echo x)" = "$(test -x "$tmp/embedded/$f" && echo x)" ] || fail "the executable bit of $f differs in the bundle"
done
python3 -I tests/unattributed_commits_test.py "$tmp/embedded"
echo "unattributed-commits ok"
