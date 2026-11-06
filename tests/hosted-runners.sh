#!/usr/bin/env bash
# A job runs on a GitHub-hosted runner only when .github/hosted-runners lists it with a reason, and a listed job has no
# secret, no environment, no write permission and a short timeout. Every other job stays on [self-hosted, cocreiamo-ci].
set -euo pipefail
cd "$(dirname "$0")/.."

# check <workflows dir> <allowlist file>: prints one line per violation.
check() {
  local dir=$1 list=$2 f file job runs hosted key listed
  declare -A allowed=()
  while read -r file job reason; do
    case ${file:-} in '' | '#'*) continue ;; esac
    [ -n "${reason:-}" ] || { echo "$list: $file $job has no reason"; continue; }
    allowed["$file:$job"]=1
  done < "$list"
  declare -A seen=()
  for f in "$dir"/*.yml; do
    file=$(basename "$f")
    for job in $(yq -N '.jobs | to_entries | .[] | select(.value.uses == null) | .key' "$f"); do
      runs=$(yq -N -o=json -I=0 ".jobs.\"$job\".\"runs-on\"" "$f")
      hosted=true
      case $runs in *'"self-hosted"'*) hosted=false ;; esac
      key="$file:$job"
      if [ "$hosted" = false ]; then
        [ -z "${allowed[$key]:-}" ] || echo "$key: listed as hosted but runs on $runs"
        continue
      fi
      seen[$key]=1
      [ -n "${allowed[$key]:-}" ] || { echo "$key: runs on $runs but is not in $list"; continue; }
      [ "$runs" = '"ubuntu-24.04"' ] || echo "$key: hosted jobs run on ubuntu-24.04 (pinned), not $runs"
      [ "$(yq -N ".jobs.\"$job\".environment" "$f")" = null ] || echo "$key: a hosted job has no environment"
      yq -N ".jobs.\"$job\"" "$f" | grep -Eq 'secrets\.' && echo "$key: a hosted job uses no secret"
      yq -N ".jobs.\"$job\".permissions // {} | .[]" "$f" | grep -qvx read && echo "$key: a hosted job has read permissions only"
      t=$(yq -N ".jobs.\"$job\".\"timeout-minutes\" // 99" "$f")
      [ "$t" -le 5 ] || echo "$key: a hosted job times out within 5 minutes"
    done
  done
  for key in "${!allowed[@]}"; do
    [ -n "${seen[$key]:-}" ] || echo "$key: listed in $list but not a hosted job"
  done
  return 0
}

out=$(check .github/workflows .github/hosted-runners)
[ -z "$out" ] || { echo "$out" >&2; exit 1; }

w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
refuse() { # name, expected message, workflow body, allowlist body
  mkdir -p "$w/$1"
  printf '%s\n' "$3" > "$w/$1/a.yml"
  printf '%s\n' "$4" > "$w/$1/list"
  got=$(check "$w/$1" "$w/$1/list"); [[ $got == *"$2"* ]] || { echo "FAIL: case '$1' was not refused ($2)" >&2; exit 1; }
}
hosted='jobs:
  j:
    runs-on: ubuntu-24.04
    timeout-minutes: 2
    permissions:
      contents: read
    steps:
      - run: true'
refuse unlisted 'not in' "$hosted" ''
refuse secret 'no secret' "$(printf '%s\n      - run: echo ${{ secrets.X }}' "$hosted")" 'a.yml j why'
refuse environment 'no environment' "$(printf '%s\n    environment: production' "$hosted")" 'a.yml j why'
refuse write 'read permissions only' "${hosted/contents: read/contents: write}" 'a.yml j why'
refuse unpinned 'pinned' "${hosted/ubuntu-24.04/ubuntu-latest}" 'a.yml j why'
refuse slow 'times out' "${hosted/timeout-minutes: 2/timeout-minutes: 30}" 'a.yml j why'
refuse noreason 'no reason' "$hosted" 'a.yml j'
refuse stale 'not a hosted job' 'jobs:
  j:
    runs-on: [self-hosted, cocreiamo-ci]
    steps:
      - run: true' 'a.yml j why'
mkdir -p "$w/ok"; printf '%s\n' "$hosted" > "$w/ok/a.yml"; echo 'a.yml j why' > "$w/ok/list"
[ -z "$(check "$w/ok" "$w/ok/list")" ] || { echo "FAIL: a listed, clean hosted job was refused" >&2; exit 1; }
echo "hosted-runners ok"
