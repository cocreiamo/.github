#!/usr/bin/env bash
# The shared mise tools block (shared/scripts/mise-tools.toml) pins each tool once, mise loads it as a conf.d fragment, and this repository pins the same versions (shared/scripts/mise-tools-test).
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/mise-tools-test
