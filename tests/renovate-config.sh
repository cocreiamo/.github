#!/usr/bin/env bash
# The Renovate configs are valid (strict) and the validator refuses a bad one; the shared postUpgradeTask command is
# one the callers' allowedCommands accepts.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
tmpdir
for f in default.json renovate/default.json renovate.json; do
  renovate-config-validator --no-global --strict "$f" >"$tmp/out" 2>&1 || { tail -n 15 "$tmp/out" >&2; fail "$f is not a valid Renovate config"; }
done
echo '{"extends": ["config:recommended"], "notAnOption": true}' > "$tmp/renovate.json"
if (cd "$tmp" && renovate-config-validator --no-global --strict renovate.json) >/dev/null 2>&1; then
  fail "the validator accepted an invalid config"
fi
[ "$(jq -c .extends renovate.json)" = '["github>cocreiamo/.github"]' ] || fail "renovate.json must extend the root preset github>cocreiamo/.github"
[ "$(jq -c .extends renovate/default.json)" = '["github>cocreiamo/.github"]' ] || fail "renovate/default.json must only point at the root preset (repositories that still extend the old path keep working)"
for dep in node helm; do
  jq -e --arg d "$dep" '.packageRules[] | select(.matchDepNames == [$d] and .matchUpdateTypes == ["major"] and .enabled == false)' default.json >/dev/null \
    || fail "the $dep major is not held back (the runners lack libatomic for node 26; helm 4 needs kustomize and the charts checked)"
done
sha=0123456789abcdef0123456789abcdef01234567
cmd=$(jq -r '.packageRules[] | select(.postUpgradeTasks) | .postUpgradeTasks.commands[0]' default.json | sed "s/{{{newDigest}}}/$sha/g")
allowed=$(cat renovate/allowed-commands.regex)
grep -Eq "$allowed" <<<"$cmd" || fail "the postUpgradeTasks command does not match renovate/allowed-commands.regex: $cmd"
if grep -Eq "$allowed" <<<"${cmd/sync-founder-section/other}"; then fail "the allowed-commands regex accepts another script"; fi
in_workflow=$(yq -N '.jobs.renovate.steps[] | select(.name == "extra environment") | .env.BASE_COMMAND' .github/workflows/renovate.yml)
[ "$in_workflow" = "$allowed" ] || fail "renovate.yml allows a command other than renovate/allowed-commands.regex"
for perm in statuses checks; do
  [ "$(yq -N ".jobs.renovate.steps[] | select(.uses == \"actions/create-github-app-token*\") | .with.permission-$perm" .github/workflows/renovate.yml)" = read ] \
    || fail "the token cannot read $perm: Renovate fails with integration-unauthorized when it reads a branch status"
done
jq -e '.packageRules[] | select(.matchDepNames == ["cocreiamo/.github"] and (.groupName | type == "string") and .groupName != "")' default.json >/dev/null \
  || { echo "FAIL: every cocreiamo/.github ref of a repository must move in one PR (a named group on the rule for cocreiamo/.github)" >&2; exit 1; }
jq -e '(.minimumReleaseAge // "") | test("^[0-9]+ days?$")' default.json >/dev/null \
  || fail "the shared preset sets no minimumReleaseAge: a version published minutes ago would merge by itself"
jq -e '.platformAutomerge == true and ([.packageRules[] | select(.automerge == true and (.matchUpdateTypes | index("minor")) and (.matchUpdateTypes | index("patch")))] | length) >= 1' default.json >/dev/null \
  || fail "the shared preset does not merge minor and patch updates by itself through the platform"
if jq -e '[.packageRules[] | select(.matchUpdateTypes != null and (.matchUpdateTypes | index("major")) and .automerge == true)] | length == 0 | not' default.json >/dev/null; then
  fail "the shared preset merges a major update by itself: majors stay PRs with the changelog"
fi
echo "renovate-config ok"
