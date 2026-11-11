#!/usr/bin/env bash
# The shared git-env-cleared check refuses a script that creates a git repository without clearing git's local environment, in each repository layout (shared/scripts/git-env-cleared-test).
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/git-env-cleared-test
