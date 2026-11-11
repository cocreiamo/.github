#!/usr/bin/env bash
# The commons release (scripts + configs + founder section, one versioned archive with a checksum): reproducible, without the tests of the scripts, versioned by the commit title; a throwaway consumer installs it with mise at a pinned checksum (a wrong one is refused), finds the scripts on PATH, and commons-sync makes its configs and founder section equal to the release, --check refusing every drift.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
root=$PWD
tmpdir
git_env_clear

# build
tools/build-release.sh 1.2.3 "$tmp/rel"
tools/build-release.sh 1.2.3 "$tmp/rel2"
cmp "$tmp/rel/commons-1.2.3.tar.gz" "$tmp/rel2/commons-1.2.3.tar.gz" || fail "the archive is not reproducible"
(cd "$tmp/rel" && sha256sum -c --quiet SHA256SUMS) || fail "SHA256SUMS does not match the archive"
tar -tzf "$tmp/rel/commons-1.2.3.tar.gz" | sed 's|^\./||' | sort > "$tmp/list"
grep -qx 'scripts/wt-gc' "$tmp/list" || fail "scripts/wt-gc missing"
grep -qx 'scripts/commons-sync' "$tmp/list" || fail "scripts/commons-sync missing"
grep -qx 'config/gitignore' "$tmp/list" || fail "config/gitignore missing"
grep -qx 'founder-section.md' "$tmp/list" || fail "founder-section.md missing"
grep -qx 'VERSION' "$tmp/list" || fail "VERSION missing"
if grep -E -- '-test$|_test\.py$|__pycache__' "$tmp/list"; then fail "the tests of the scripts ship in the release"; fi
if tools/build-release.sh 1.2 "$tmp/x" 2> /dev/null; then fail "a version that is not MAJOR.MINOR.PATCH was accepted"; fi

# versions
git_repo "$tmp/v"
(
  cd "$tmp/v"
  mkdir -p shared tools other
  echo a > shared/a
  echo b > tools/build-release.sh
  git add -A && git commit -qm "feat: first"
  next() { "$root/tools/next-version.sh"; }
  [ "$(next)" = 1.0.0 ] || fail "no tag: 1.0.0, got $(next)"
  git tag v1.4.2
  [ -z "$(next)" ] || fail "nothing changed since the tag: no release, got $(next)"
  echo o > other/o && git add -A && git commit -qm "fix: elsewhere"
  [ -z "$(next)" ] || fail "a change outside shared/ released: $(next)"
  echo a2 > shared/a && git commit -qam "fix: shared"
  [ "$(next)" = 1.4.3 ] || fail "fix: patch, got $(next)"
  git commit -q --allow-empty -m "feat: new"
  [ "$(next)" = 1.5.0 ] || fail "feat: minor, got $(next)"
  git commit -q --allow-empty -m "feat(scripts)!: drop"
  [ "$(next)" = 2.0.0 ] || fail "type!: major, got $(next)"
  git commit -q --allow-empty -m "docs: x" -m "BREAKING CHANGE: y"
  [ "$(next)" = 2.0.0 ] || fail "BREAKING CHANGE footer: major, got $(next)"
  git commit -q --allow-empty -m "chore: z"
  [ "$(next)" = 1.4.3 ] || fail "chore: patch, got $(next)"
  git tag v1.10.0
  git commit -q --allow-empty -m "feat: after ten"
  echo a3 > shared/a && git commit -qam "feat: after ten, shared"
  [ "$(next)" = 1.11.0 ] || fail "the last tag is the highest version, not the latest string: got $(next)"
)

# a throwaway consumer installs it with mise at a pinned checksum
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$tmp/rel" > "$tmp/server.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do python3 -I -c "import urllib.request as u; u.urlopen('http://127.0.0.1:$port/SHA256SUMS')" 2> /dev/null && break; sleep 0.1; done
sum=$(cut -d' ' -f1 "$tmp/rel/SHA256SUMS")
export MISE_DATA_DIR=$tmp/mise/data MISE_CACHE_DIR=$tmp/mise/cache MISE_STATE_DIR=$tmp/mise/state MISE_CONFIG_DIR=$tmp/mise/config
export MISE_GLOBAL_CONFIG_FILE=$tmp/mise/none.toml MISE_YES=1 MISE_NO_ENV=1 MISE_TRUSTED_CONFIG_PATHS=$tmp/consumer
consumer() { # checksum
  cat > "$tmp/consumer/mise.toml" << T
[tools."http:commons"]
version = "1.2.3"
url = "http://127.0.0.1:$port/commons-1.2.3.tar.gz"
checksum = "sha256:$1"
bin_path = "scripts"
T
}
mkdir -p "$tmp/consumer"
cd "$tmp/consumer"
consumer "$(printf '0%.0s' $(seq 64))"
if mise install > "$tmp/bad.log" 2>&1; then fail "a wrong checksum was installed"; fi
consumer "$sum"
mise install > "$tmp/install.log" 2>&1 || { cat "$tmp/install.log" >&2; fail "the release did not install"; }
mise x -- sh -c 'command -v commons-sync' > /dev/null || fail "the scripts are not on PATH"
mise x -- sh -c 'command -v wt-gc' > /dev/null || fail "wt-gc is not on PATH"
export COMMONS_DIR
COMMONS_DIR=$(mise where http:commons)

git_repo "$tmp/consumer"
mkdir -p .github
printf '%s\n' '# comment' 'gitignore .gitignore' '.shellcheckrc .shellcheckrc' 'ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/bug.yml' > .github/shared-configs
{ printf '# Repo\n\n'; sed 's/Answer first/Answer second/' "$root/shared/working-with-the-founder.md"; printf '\n## Never\n\n- y\n'; } > CLAUDE.md
sync() { mise x -- commons-sync "$@"; }
if sync --check > "$tmp/out" 2>&1; then fail "a repository with no configs and a diverged section passed --check"; fi
grep -q '.gitignore is missing' "$tmp/out" || fail "--check does not name the missing file"
grep -q 'founder section\|Working with the founder' "$tmp/out" || fail "--check does not name the section"
[ ! -e .gitignore ] || fail "--check wrote a file"
sync > /dev/null
sync --check || fail "not equal to the release after the sync"
cmp .gitignore "$root/shared/config/gitignore" || fail ".gitignore is not the release's"
grep -qx '^## Never$' CLAUDE.md && grep -qx -- '- y' CLAUDE.md || fail "the sync touched the rest of CLAUDE.md"
echo '# local' >> .shellcheckrc
if sync --check > /dev/null 2>&1; then fail "an edited config passed --check"; fi
sync > /dev/null
rm .gitignore && ln -s .shellcheckrc .gitignore
if sync --check > /dev/null 2>&1; then fail "a link in place of a copy passed --check"; fi
sync > /dev/null
[ ! -L .gitignore ] || fail "the link was kept"
chmod +x .shellcheckrc
if sync --check > /dev/null 2>&1; then fail "a changed executable bit passed --check"; fi
sync > /dev/null
printf '%s\n' '../outside x' > .github/shared-configs
if sync --check > /dev/null 2>&1; then fail "a manifest line leaving the release passed"; fi
printf '%s\n' 'nothing .nothing' > .github/shared-configs
if sync --check > /dev/null 2>&1; then fail "a config the release lacks passed"; fi
echo "commons-release ok"
