#!/usr/bin/env bash
# The Renovate configs are valid (strict) and the validator refuses a bad one; the shared postUpgradeTask command is
# one the callers' allowedCommands accepts; the preset holds the full regime (a fixed window, one PR per group, minor/patch/digest
# merging by themselves, security fixes jumping the window, majors reviewed with their changelog), each rule proven red on a bad copy.
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
jq -e '.osvVulnerabilityAlerts == true' default.json >/dev/null \
  || fail "the shared preset does not read OSV vulnerability alerts: the GitHub alerts need a permission the App token may lack, OSV needs none"
jq -e '.vulnerabilityAlerts | .enabled != false and (.schedule == ["at any time"]) and (.minimumReleaseAge == "0 days") and .prCreation == "immediate"' default.json >/dev/null \
  || fail "a security fix must bypass the schedule and the release age: vulnerabilityAlerts needs schedule «at any time», minimumReleaseAge «0 days» and prCreation immediate"
regime() {
  local f=$1
  jq -e '(.schedule // []) | length > 0 and (index("at any time") | not)' "$f" >/dev/null \
    || { echo "the preset sets no fixed schedule window: grouped updates would open at any hour"; return 1; }
  jq -e '[.packageRules[] | select(.groupName and .groupName != "cocreiamo/.github pin" and (.schedule // [] | index("at any time")))] | length == 0' "$f" >/dev/null \
    || { echo "a grouped update rule jumps the schedule window (only security fixes and the cocreiamo/.github pin may)"; return 1; }
  for g in actions providers "mise tools"; do
    jq -e --arg g "$g" '[.packageRules[] | select(.groupName == $g)] | length == 1' "$f" >/dev/null \
      || { echo "no single group rule «$g»: its updates would open one PR each"; return 1; }
  done
  jq -e '[.packageRules[] | select(.automerge == true and (.matchUpdateTypes // [] | (index("minor") and index("patch") and index("digest"))))] | length >= 1' "$f" >/dev/null \
    || { echo "minor, patch and digest updates do not merge by themselves"; return 1; }
  jq -e '.osvVulnerabilityAlerts == true and (.vulnerabilityAlerts.schedule == ["at any time"])' "$f" >/dev/null \
    || { echo "OSV alerts are off, or a security fix waits for the schedule window"; return 1; }
  jq -e '[.packageRules[] | select(.matchUpdateTypes == ["major"] and .automerge == false and .fetchChangeLogs == "pr" and (.matchDepNames | not))] | length == 1' "$f" >/dev/null \
    || { echo "no rule keeps every major a reviewed PR with its changelog (automerge false, fetchChangeLogs pr)"; return 1; }
}
why=$(regime default.json) || fail "default.json: $why"
bad() {
  jq "$2" default.json > "$tmp/bad.json"
  if regime "$tmp/bad.json" >/dev/null; then fail "the regime check accepted a preset where $1"; fi
}
bad "the window is gone" 'del(.schedule)'
bad "the window is at any time" '.schedule = ["at any time"]'
bad "a group jumps the window" '(.packageRules[] | select(.groupName == "actions")) .schedule = ["at any time"]'
bad "the mise tools group is gone" 'del(.packageRules[] | select(.groupName == "mise tools"))'
bad "digest updates wait for a review" '(.packageRules[] | select(.automerge == true and (.matchUpdateTypes // [] | index("minor")))) .matchUpdateTypes -= ["digest"]'
bad "security fixes wait for the window" '.vulnerabilityAlerts.schedule = .schedule'
bad "OSV alerts are off" '.osvVulnerabilityAlerts = false'
bad "majors merge by themselves" '(.packageRules[] | select(.matchUpdateTypes == ["major"] and (.matchDepNames | not))) .automerge = true'
bad "majors carry no changelog" '(.packageRules[] | select(.matchUpdateTypes == ["major"] and (.matchDepNames | not))) .fetchChangeLogs = "off"'
echo "renovate-config ok"
