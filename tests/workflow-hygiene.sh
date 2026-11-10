#!/usr/bin/env bash
# The check that every job has timeout-minutes, no push concurrency group is keyed on the ref alone and no pinned SHA is an annotated tag object (shared/scripts/workflow-hygiene-check.py), proven by shared/scripts/workflow-hygiene-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/workflow-hygiene-test
