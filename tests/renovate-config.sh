#!/usr/bin/env bash
# The Renovate configs are valid (strict) and the validator refuses a bad one; the shared postUpgradeTask command is
# one the callers' allowedCommands accepts.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in renovate/default.json renovate.json; do
  renovate-config-validator --no-global --strict "$f" >"$tmp/out" 2>&1 || { tail -n 15 "$tmp/out" >&2; echo "FAIL: $f is not a valid Renovate config" >&2; exit 1; }
done
echo '{"extends": ["config:recommended"], "notAnOption": true}' > "$tmp/renovate.json"
if (cd "$tmp" && renovate-config-validator --no-global --strict renovate.json) >/dev/null 2>&1; then
  echo "FAIL: the validator accepted an invalid config" >&2; exit 1
fi
sha=0123456789abcdef0123456789abcdef01234567
cmd=$(jq -r '.packageRules[] | select(.postUpgradeTasks) | .postUpgradeTasks.commands[0]' renovate/default.json | sed "s/{{{newDigest}}}/$sha/g")
allowed=$(cat renovate/allowed-commands.regex)
grep -Eq "$allowed" <<<"$cmd" || { echo "FAIL: the postUpgradeTasks command does not match renovate/allowed-commands.regex: $cmd" >&2; exit 1; }
if grep -Eq "$allowed" <<<"${cmd/sync-founder-section/other}"; then echo "FAIL: the allowed-commands regex accepts another script" >&2; exit 1; fi
in_workflow=$(yq -N '.jobs.renovate.steps[] | select(.uses == "renovate*") | .env.RENOVATE_ALLOWED_COMMANDS' .github/workflows/renovate.yml | jq -r '.[0]')
[ "$in_workflow" = "$allowed" ] || { echo "FAIL: renovate.yml allows a command other than renovate/allowed-commands.regex" >&2; exit 1; }
echo "renovate-config ok"
