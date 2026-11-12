#!/usr/bin/env bash
# The shared ci-parts picks the parts of `mise run ci` from the sources of the ci:<part> tasks, prepush runs exactly those, and check refuses a part that would not run when it changes.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/ci-parts-test
