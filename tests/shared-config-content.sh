#!/usr/bin/env bash
# The canonical .gitignore ignores what the four repositories ignored and what the adopted tools generate, and hides no tracked file; the linter configs
# parse and keep every rule a repository enforced before they were merged (tests/shared_config_test.py).
set -euo pipefail
# shellcheck source=../shared/scripts/testlib.sh
. "$(dirname "$0")/../shared/scripts/testlib.sh"
cd "$(dirname "$0")/.."
tmpdir
configs=$PWD/shared/config
[ -f "$configs/gitignore" ] || fail "shared/config/gitignore does not exist"

while read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
git -C "$tmp" init -q repo
cp "$configs/gitignore" "$tmp/repo/.gitignore"
ignored=(
  .terraform/p x.tfplan plan-hetzner.txt summary.md drift.md x.dec.yaml .env a.pem infra-age.txt gha-creds-1.json ansible/collections/a
  __pycache__/a.pyc lib/__pycache__/a.pyc a.pyc .ruff_cache/a .hypothesis/a .pytest_cache/a mutants/a.py .venv/bin/python
  platform/traefik/charts/a.yaml out/a bazel-bin/a bazel-out/a node_modules/a packages/x/node_modules/a _site/a user.bazelrc
)
for p in "${ignored[@]}"; do
  git -C "$tmp/repo" check-ignore -q --no-index "$p" || fail "$p is not ignored"
done
tracked=(
  README.md CLAUDE.md mise.toml .editorconfig .gitignore .yamllint.yaml ruff.toml .github/workflows/x.yml .github/shared-scripts .claude/settings.json
  .terraform.lock.hcl secrets/infrastructure.enc.yaml tests/policy/a.rego docs/summary.md docs/drift.md docs/out/a.md products/anima/upstream.env
  platform/traefik/kustomization.yaml tools/tests/check.sh MODULE.bazel.lock .bazelrc
)
for p in "${tracked[@]}"; do
  if git -C "$tmp/repo" check-ignore -q --no-index "$p"; then fail "$p is ignored: the common .gitignore must not hide a tracked file"; fi
done
uv run --quiet --no-project --no-config --with pyyaml==6.0.3 python3 -I tests/shared_config_test.py "$configs"
echo "shared-config-content ok"
