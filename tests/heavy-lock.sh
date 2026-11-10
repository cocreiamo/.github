#!/usr/bin/env bash
# heavy-lock is a shared script: its behaviour test runs here, where the canonical copy lives.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/heavy-lock-test
