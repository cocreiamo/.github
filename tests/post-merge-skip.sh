#!/usr/bin/env bash
# The post-merge skip decision (shared/scripts/post_merge_skip.py): skip only when the merged tree is the tree of the pull request head whose required check was green; any doubt runs the checks.
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/shared/scripts" python3 -m unittest tests/post_merge_skip_test.py
