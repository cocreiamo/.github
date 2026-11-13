#!/usr/bin/env bash
# The shared-rules check carries the canonical scripts of shared/scripts and fails when a repository's vendored copy
# (declared in its .github/shared-scripts) diverges, loses its executable bit, is missing or is not declared at all.
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
wf=.github/workflows/shared-rules.yml
scripts=shared/scripts
step() { yq -N ".jobs.check.steps[] | select(.name == \"$1\") | $2" "$wf"; }
tmpdir
git_env_clear

check=$(step "vendored scripts equal the canonical ones" .run)
bundle=$(step "vendored scripts equal the canonical ones" '.env | to_entries | .[] | select(.key | test("^SCRIPTS_BUNDLE_[0-9]+$")) | .value')
[ -n "$bundle" ] || fail "$wf has no step 'vendored scripts equal the canonical ones' whose env carries the keys SCRIPTS_BUNDLE_1, SCRIPTS_BUNDLE_2, ..."
fetch=$(step "fetch the vendored scripts" .run)
[ -n "$fetch" ] && [ "$fetch" != null ] || fail "$wf has no step 'fetch the vendored scripts'"

mkdir "$tmp/embedded"
base64 -d <<<"$bundle" | tar -xzf - -C "$tmp/embedded"
mkdir "$tmp/tracked"
git ls-files -z -- "$scripts" | while IFS= read -r -d '' f; do
  mkdir -p "$(dirname "$tmp/tracked/${f#"$scripts"/}")"
  cp -p "$f" "$tmp/tracked/${f#"$scripts"/}"
done
diff -r "$tmp/tracked" "$tmp/embedded" >/dev/null || fail "the bundle embedded in $wf differs from the tracked files of $scripts (an untracked or ignored file must never be embedded): run tools/embed-scripts.sh"
for f in "$scripts"/*; do
  [ "$(test -x "$f" && echo x)" = "$(test -x "$tmp/embedded/${f##*/}" && echo x)" ] || fail "the executable bit of ${f##*/} differs in the embedded bundle"
done

# run <dir>: the check as the workflow runs it, in <dir>
printf '%s\n' "$check" > "$tmp/check.sh"
set -a; eval "$(yq -N -o shell '.jobs.check.steps[] | select(.name == "vendored scripts equal the canonical ones") | .env' "$wf")"; set +a
run() { (cd "$1" && bash "$tmp/check.sh") >"$tmp/out" 2>&1; }
mkrepo() {
  rm -rf "$tmp/repo"; mkdir -p "$tmp/repo/.github" "$tmp/repo/tasks"
  cp -p "$scripts/wt-gc" "$tmp/repo/tasks/gc"
  cp -p "$scripts/otel-headers.sh" "$tmp/repo/otel.sh"
  printf '# canonical-name  local-path\nwt-gc tasks/gc\n\notel-headers.sh otel.sh\n' > "$tmp/repo/.github/shared-scripts"
}

mkrepo
run "$tmp/repo" || { cat "$tmp/out" >&2; fail "refused a repository whose vendored copies are the canonical ones"; }

mkrepo; echo "# local tweak" >> "$tmp/repo/tasks/gc"
if run "$tmp/repo"; then fail "accepted a diverged copy"; fi
grep -q '^+# local tweak' "$tmp/out" || fail "a diverged copy is refused without the diff"
grep -q 'tasks/gc' "$tmp/out" || fail "a diverged copy is refused without naming it"

mkrepo; rm "$tmp/repo/otel.sh"
if run "$tmp/repo"; then fail "accepted a missing vendored file"; fi

mkrepo; chmod -x "$tmp/repo/tasks/gc"
if run "$tmp/repo"; then fail "accepted a copy that lost its executable bit"; fi

mkrepo; printf 'no-such-script tasks/gc\n' >> "$tmp/repo/.github/shared-scripts"
if run "$tmp/repo"; then fail "accepted a manifest naming a script that is not canonical"; fi

mkrepo; printf 'wt-list ../escape\n' >> "$tmp/repo/.github/shared-scripts"
if run "$tmp/repo"; then fail "accepted a manifest path outside the repository"; fi

mkrepo; rm "$tmp/repo/.github/shared-scripts"
if run "$tmp/repo"; then fail "accepted a repository without a manifest"; fi

mkrepo; : > "$tmp/repo/.github/shared-scripts"
if run "$tmp/repo"; then fail "accepted an empty manifest"; fi

mkrepo; printf 'wt-gc tasks/gc extra\n' > "$tmp/repo/.github/shared-scripts"
if run "$tmp/repo"; then fail "accepted a malformed manifest line"; fi

# the fetch step brings the declared files into a sparse checkout
mkrepo
git -C "$tmp/repo" init -q -b main
printf 'x\n' > "$tmp/repo/CLAUDE.md"; printf 'y\n' > "$tmp/repo/other"
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm init
git clone -q --no-checkout "$tmp/repo" "$tmp/sparse"
git -C "$tmp/sparse" sparse-checkout set --no-cone CLAUDE.md .github/shared-scripts
git -C "$tmp/sparse" checkout -q main
[ ! -e "$tmp/sparse/tasks/gc" ] || fail "the sparse fixture already has the vendored file"
(cd "$tmp/sparse" && bash -c "$fetch") >"$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "the fetch step failed"; }
[ -f "$tmp/sparse/tasks/gc" ] && [ -f "$tmp/sparse/otel.sh" ] || fail "the fetch step did not bring the declared files"

# the checkout does not persist its credentials and a sparse checkout is a partial clone: the files come from the remote
# with the job token, so a git that is not handed it must fail
mkdir "$tmp/fakebin"
real_git=$(command -v git)
cat > "$tmp/fakebin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1 \$2" = "sparse-checkout add" ] && [ "\${GIT_CONFIG_KEY_0:-}" != "http.https://github.com/.extraheader" ]; then
  echo "fatal: could not read Username for 'https://github.com'" >&2; exit 128
fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/fakebin/git"
git -C "$tmp/sparse" sparse-checkout set --no-cone CLAUDE.md .github/shared-scripts
(cd "$tmp/sparse" && PATH="$tmp/fakebin:$PATH" GH_TOKEN=token bash -c "$fetch") >"$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "the fetch step does not give git the job token"; }
[ -f "$tmp/sparse/tasks/gc" ] || fail "the fetch step with the token did not bring the declared files"
[ ! -e "$tmp/sparse/other" ] || fail "the fetch step brought a file nobody declared"
# A shared test is vendored as tools/tests/*.sh of the monorepo, whose hermetic-git check refuses a literal git init/commit/commit-tree without
# lib/hermetic-git.sh: a shared test names none (worktrees-test is not vendored there).
literal_git='\bgit( +-[-A-Za-z]+( +[^ -][^ ]*)?)* +(init|commit|commit-tree)\b'
printf '%s\n' "git commit -m x" "git -C d init" "git -c a=b commit-tree T" > "$tmp/bad-literal"
[ "$(grep -cE "$literal_git" "$tmp/bad-literal")" = 3 ] || fail "the literal git pattern does not catch git commit, init and commit-tree"
printf '%s\n' "git log --grep commit" "git status" > "$tmp/ok-literal"
[ "$(grep -cE "$literal_git" "$tmp/ok-literal" || [ $? -eq 1 ])" = 0 ] || fail "the literal git pattern catches a command that is not git init or commit"
for f in "$scripts"/*-test "$scripts"/*.sh; do
  [ "${f##*/}" != worktrees-test ] || continue
  ! grep -qE "$literal_git" "$f" || fail "${f##*/} runs a literal git init/commit: the monorepo's hermetic-git check refuses it; build the command from parts or use another command"
done
echo "shared-scripts ok"
