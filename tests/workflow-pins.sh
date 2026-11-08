#!/usr/bin/env bash
# The check that a caller of a reusable workflow passes only what the workflow declares at its pin, and all it requires (shared/scripts/workflow-pins-check.py), proven by shared/scripts/workflow-pins-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/workflow-pins-test
