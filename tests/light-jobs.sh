#!/usr/bin/env bash
# A job asks for the light pool [self-hosted, cocreiamo-ci-light] only when .github/light-jobs lists it with a reason,
# and a listed job has no secret, no environment, no write permission and a short timeout. Every other job that has a
# runner stays on [self-hosted, cocreiamo-ci].
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."

# check <workflows dir> <allowlist file>: prints one line per violation.
check() {
  local dir=$1 list=$2 f file job runs key t
  declare -A allowed=() seen=()
  while read -r file job reason; do
    case ${file:-} in '' | '#'*) continue ;; esac
    [ -n "${reason:-}" ] || { echo "$list: $file $job has no reason"; continue; }
    allowed["$file:$job"]=1
  done < "$list"
  for f in "$dir"/*.yml; do
    file=$(basename "$f")
    for job in $(yq -N '.jobs | to_entries | .[] | select(.value.uses == null) | .key' "$f"); do
      runs=$(yq -N -o=json -I=0 ".jobs.\"$job\".\"runs-on\"" "$f")
      key="$file:$job"
      # The guarded form is the hosted label in a public repository and this pool in a private one.
      if [[ $runs == *'github.repository_visibility'* ]]; then
        runs=$(grep -o '\[[^]]*\]' <<< "$runs" | tr -d '\\ ')
      fi
      case $runs in
        *cocreiamo-ci-light*) seen[$key]=1 ;;
        '["self-hosted","cocreiamo-ci"]') continue ;;
        *) echo "$key: runs on $runs, not [self-hosted, cocreiamo-ci]"; continue ;;
      esac
      [ -n "${allowed[$key]:-}" ] || { echo "$key: asks for the light pool but is not in $list"; continue; }
      [ "$runs" = '["self-hosted","cocreiamo-ci-light"]' ] || echo "$key: a light job carries exactly [self-hosted, cocreiamo-ci-light], not $runs"
      [ "$(yq -N ".jobs.\"$job\".environment" "$f")" = null ] || echo "$key: a light job has no environment"
      if yq -N ".jobs.\"$job\"" "$f" | grep -Eq 'secrets\.'; then echo "$key: a light job uses no secret"; fi
      if yq -N ".jobs.\"$job\".permissions // {} | .[]" "$f" | grep -qvx read; then echo "$key: a light job has read permissions only"; fi
      t=$(yq -N ".jobs.\"$job\".\"timeout-minutes\" // 99" "$f")
      [ "$t" -le 5 ] || echo "$key: a light job times out within 5 minutes"
    done
  done
  for key in "${!allowed[@]}"; do
    [ -n "${seen[$key]:-}" ] || echo "$key: listed in $list but not a light job"
  done
  return 0
}

out=$(check .github/workflows .github/light-jobs)
[ -z "$out" ] || { echo "$out" >&2; exit 1; }

tmpdir
refuse() { # name, expected message, workflow body, allowlist body
  local got
  mkdir -p "$tmp/$1"
  printf '%s\n' "$3" > "$tmp/$1/a.yml"
  printf '%s\n' "$4" > "$tmp/$1/list"
  got=$(check "$tmp/$1" "$tmp/$1/list")
  [[ $got == *"$2"* ]] || fail "case '$1' was not refused ($2)"
}
light='jobs:
  j:
    runs-on: [self-hosted, cocreiamo-ci-light]
    timeout-minutes: 2
    permissions:
      contents: read
    steps:
      - run: true'
refuse unlisted 'not in' "$light" ''
refuse secret 'no secret' "$(printf '%s\n      - run: echo ${{ secrets.X }}' "$light")" 'a.yml j why'
refuse environment 'no environment' "$(printf '%s\n    environment: production' "$light")" 'a.yml j why'
refuse write 'read permissions only' "${light/contents: read/contents: write}" 'a.yml j why'
refuse mixed 'carries exactly' "${light/\[self-hosted, cocreiamo-ci-light\]/[self-hosted, cocreiamo-ci, cocreiamo-ci-light]}" 'a.yml j why'
refuse slow 'times out' "${light/timeout-minutes: 2/timeout-minutes: 30}" 'a.yml j why'
refuse noreason 'no reason' "$light" 'a.yml j'
refuse hosted 'not [self-hosted' "${light/\[self-hosted, cocreiamo-ci-light\]/ubuntu-24.04}" ''
refuse stale 'not a light job' "${light/-light/}" 'a.yml j why'
mkdir -p "$tmp/ok"; printf '%s\n' "$light" > "$tmp/ok/a.yml"; echo 'a.yml j why' > "$tmp/ok/list"
[ -z "$(check "$tmp/ok" "$tmp/ok/list")" ] || fail "a listed, clean light job was refused"
echo "light-jobs ok"
