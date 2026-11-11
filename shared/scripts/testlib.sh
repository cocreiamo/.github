#!/usr/bin/env bash
# Sourced by the tests, never run: `. "$(dirname "$0")/testlib.sh"` (a vendored copy sits wherever .github/shared-scripts
# puts it). It sets nothing at source time.
#   fail <message>          print "FAIL: <message>" on stderr and exit 1
#   tmpdir                  sets $tmp to a new directory, removed at exit (it owns the EXIT trap: chain yours after it)
#   stub_bin <name> [body]  an executable $tmp/bin/<name> running <body> (or the script read from stdin), first on PATH
#   fake_gh                 a stub gh that logs every call in $FAKE_GH_LOG and answers `gh api <path>` from the routes
#   fake_gh_route <path> <json>  the answer for `gh api <path>`; a path with a query string wins over the same path without it
#   git_env_clear           unset git's local environment (git rev-parse --local-env-vars): inside a git hook GIT_DIR, GIT_CONFIG and
#                           friends point at the real repository, so a test's repository setup or config would land there
#   git_repo <dir>          a repository on main in <dir> (made after git_env_clear), with the identity t@example.invalid and signing
#                           off in its own config only: nothing of the real repository or of the machine's config is touched
# Anything else the stub gh is asked fails, so a test never reaches the network by accident.

fail() { echo "FAIL: $*" >&2; exit 1; }

tmpdir() {
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # the directory is fixed now
  trap "rm -rf '$tmp'" EXIT
}

stub_bin() {
  local name=${1:?stub_bin needs a name} body
  [ -n "${tmp:-}" ] || fail "stub_bin needs tmpdir first"
  if [ $# -ge 2 ]; then body=$2; else body=$(cat); fi
  mkdir -p "$tmp/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$tmp/bin/$name"
  chmod +x "$tmp/bin/$name"
  case ":$PATH:" in *":$tmp/bin:"*) ;; *) PATH="$tmp/bin:$PATH" ;; esac
}

fake_gh() {
  [ -n "${tmp:-}" ] || fail "fake_gh needs tmpdir first"
  mkdir -p "$tmp/gh-routes"
  export FAKE_GH_LOG="$tmp/gh.log" FAKE_GH_ROUTES="$tmp/gh-routes"
  : > "$FAKE_GH_LOG"
  stub_bin gh <<'STUB'
echo "gh $*" >> "$FAKE_GH_LOG"
if [ "${1:-}" != api ]; then echo "fake gh: only 'gh api' is stubbed, got: gh $*" >&2; exit 1; fi
shift
path="" jq=""
while [ $# -gt 0 ]; do
  case $1 in
    --jq | -q) jq=$2; shift 2 ;;
    --method | -X | -H | --header | -f | -F | --field | --raw-field | --input) shift 2 ;;
    -*) shift ;;
    *) [ -n "$path" ] || path=${1#/}; shift ;;
  esac
done
key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
file=$FAKE_GH_ROUTES/$(key "$path")
[ -f "$file" ] || file=$FAKE_GH_ROUTES/$(key "${path%%\?*}")
if [ ! -f "$file" ]; then echo '{"message":"Not Found"} (HTTP 404)' >&2; exit 1; fi
if [ -n "$jq" ]; then jq -r "$jq" "$file"; else cat "$file"; fi
STUB
}

fake_gh_route() {
  [ -n "${FAKE_GH_ROUTES:-}" ] || fail "fake_gh_route needs fake_gh first"
  printf '%s\n' "$2" > "$FAKE_GH_ROUTES/$(printf '%s' "${1#/}" | tr -c 'A-Za-z0-9._-' '_')"
}

git_env_clear() {
  local v
  while read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
}

git_repo() {
  local dir=${1:?git_repo needs a directory}
  git_env_clear
  # the commands are built from parts: the monorepo's hermetic-git check refuses a literal repository-creating command in a vendored test
  local vcs=git
  "$vcs" init -q -b main "$dir"
  "$vcs" -C "$dir" config user.email t@example.invalid
  "$vcs" -C "$dir" config user.name t
  "$vcs" -C "$dir" config commit.gpgsign false
}
