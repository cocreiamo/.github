#!/usr/bin/env bash
# A repository references cocreiamo/.github, and each watched action, at one SHA only; the check is proven on fixtures and runs on this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/pins-consistent-test
shared/scripts/pins-consistent .
echo "pins-consistent ok"
