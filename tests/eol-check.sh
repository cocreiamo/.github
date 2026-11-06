#!/usr/bin/env bash
# The shared EOL check (shared/scripts/eol_check.py): pin discovery from mise.toml, Ansible variables, the Hetzner image, kustomize charts, image tags and FROM lines, and the 60-day rule against a fake endoflife.date; the default root is the repository of the working directory.
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/shared/scripts" uv run --quiet --no-project --no-config --with pyyaml==6.0.3 python3 -m unittest tests/eol_check_test.py
