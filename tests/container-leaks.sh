#!/usr/bin/env bash
# The check that a test container is removed or labelled so a killed run cannot leak it (shared/scripts/container-leaks-check), proven by shared/scripts/container-leaks-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/container-leaks-test
