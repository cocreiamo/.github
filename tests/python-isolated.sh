#!/usr/bin/env bash
# The check that every python call in a shell script, a workflow or a mise task runs isolated (shared/scripts/python-isolated-check), proven by shared/scripts/python-isolated-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/python-isolated-test
