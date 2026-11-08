#!/usr/bin/env bash
# The check that every run step of a workflow calls only tools its runner has (shared/scripts/workflow-tools-check.py), proven by shared/scripts/workflow-tools-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/workflow-tools-test
