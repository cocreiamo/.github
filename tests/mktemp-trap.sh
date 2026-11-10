#!/usr/bin/env bash
# The check that a shell script calling mktemp installs an EXIT trap that removes what it made (shared/scripts/mktemp-trap-check), proven by shared/scripts/mktemp-trap-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/mktemp-trap-test
