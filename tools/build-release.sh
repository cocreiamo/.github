#!/usr/bin/env bash
# usage: tools/build-release.sh <version> <output dir>
# Builds the commons release: commons-<version>.tar.gz (scripts/ = shared/scripts without its tests, config/ = shared/config,
# founder-section.md, VERSION) and SHA256SUMS, byte for byte reproducible from the same tree.
set -euo pipefail
version=${1:?version, for example 1.2.3}
out=${2:?output directory}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be MAJOR.MINOR.PATCH" >&2; exit 2; }
cd "$(dirname "$0")/.."
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/scripts" "$out"
tar -cf - -C shared/scripts --exclude='*-test' --exclude='*_test.py' --exclude=__pycache__ . | tar -xf - -C "$stage/scripts"
cp -a shared/config "$stage/config"
cp shared/working-with-the-founder.md "$stage/founder-section.md"
printf '%s\n' "$version" > "$stage/VERSION"
archive="commons-$version.tar.gz"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - -C "$stage" . | gzip -n -9 > "$out/$archive"
(cd "$out" && sha256sum "$archive" > SHA256SUMS)
