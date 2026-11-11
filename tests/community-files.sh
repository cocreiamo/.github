#!/usr/bin/env bash
# The organization's default community health files exist where GitHub reads them (.github/ of the .github repository), the issue templates are valid
# forms that use no label (a label must exist in every repository), and the security policy names the founder's address only.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
founder=francesco.bilotta@cocreiamo.com
[ -f .github/SECURITY.md ] || fail ".github/SECURITY.md is missing"
grep -qF "$founder" .github/SECURITY.md || fail "SECURITY.md does not name $founder"
others=$(grep -ohE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' .github/SECURITY.md .github/ISSUE_TEMPLATE/* | sort -u | grep -vxF "$founder" || true)
[ -z "$others" ] || fail "an address other than $founder: $others"
[ -f .github/ISSUE_TEMPLATE/config.yml ] || fail ".github/ISSUE_TEMPLATE/config.yml is missing"
count=0
for f in .github/ISSUE_TEMPLATE/*.yml; do
  [ "${f##*/}" != config.yml ] || continue
  count=$((count + 1))
  [ "$(yq -N '.name | type' "$f")" = '!!str' ] || fail "$f has no name"
  [ "$(yq -N '.description | type' "$f")" = '!!str' ] || fail "$f has no description"
  [ "$(yq -N '.body | length > 0' "$f")" = true ] || fail "$f has no body"
  [ "$(yq -N '.labels | type' "$f")" = '!!null' ] || fail "$f sets labels: a label must exist in every repository that uses the template"
  [ "$(yq -N '[.body[] | select(.validations.required == true)] | length > 0' "$f")" = true ] || fail "$f has no required field"
done
[ "$count" -ge 2 ] || fail "want at least two issue templates, found $count"
[ "$(yq -N '.contact_links | length' .github/ISSUE_TEMPLATE/config.yml)" -ge 1 ] || fail "config.yml has no contact link"
if grep -rqi 'gmail\|@example' .github/SECURITY.md .github/ISSUE_TEMPLATE; then fail "a community file names a foreign address"; fi
echo "community-files ok"
