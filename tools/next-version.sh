#!/usr/bin/env bash
# usage: tools/next-version.sh [commit]   (inside a clone with its tags)
# Prints the next release version (MAJOR.MINOR.PATCH, no «v»), or nothing when nothing a consumer installs changed since the
# last tag. The bump follows the Conventional Commit title of the commit (the squash commit on main): «!» after the type or
# a BREAKING CHANGE footer is a major, feat a minor, anything else a patch. No tag yet: 1.0.0.
set -euo pipefail
commit=${1:-HEAD}
paths=(shared tools/build-release.sh)
last=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)
[ -n "$last" ] || { echo 1.0.0; exit 0; }
if git diff --quiet "$last" "$commit" -- "${paths[@]}"; then exit 0; fi
IFS=. read -r major minor patch <<< "${last#v}"
message=$(git log -1 --format=%B "$commit")
subject=${message%%$'\n'*}
breaking='^[a-z]+(\([^)]*\))?!:'
if [[ $subject =~ $breaking ]] || grep -q '^BREAKING CHANGE' <<< "$message"; then echo "$((major + 1)).0.0"
elif [[ $subject == feat:* || $subject == feat\(* ]]; then echo "$major.$((minor + 1)).0"
else echo "$major.$minor.$((patch + 1))"; fi
