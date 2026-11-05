#!/usr/bin/env bash
# The Renovate configs are valid (strict) and the validator refuses a bad one; the shared postUpgradeTask command is
# one the callers' allowedCommands accepts.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
renovate-config-validator --strict renovate/default.json
echo '{"extends": ["config:recommended"], "notAnOption": true}' > "$tmp/renovate.json"
if (cd "$tmp" && renovate-config-validator --strict renovate.json) >/dev/null 2>&1; then
  echo "FAIL: the validator accepted an invalid config" >&2; exit 1
fi
sha=0123456789abcdef0123456789abcdef01234567
cmd=$(jq -r '.packageRules[] | select(.postUpgradeTasks) | .postUpgradeTasks.commands[0]' renovate/default.json | sed "s/{{{newDigest}}}/$sha/g")
allowed=$(cat renovate/allowed-commands.regex)
grep -Eq "$allowed" <<<"$cmd" || { echo "FAIL: the postUpgradeTasks command does not match renovate/allowed-commands.regex: $cmd" >&2; exit 1; }
if grep -Eq "$allowed" <<<"${cmd/sync-founder-section/other}"; then echo "FAIL: the allowed-commands regex accepts another script" >&2; exit 1; fi
echo "renovate-config ok"
