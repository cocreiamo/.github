#!/usr/bin/env bash
# The shared test library (fail, tmpdir, stub_bin, fake_gh) behaves as the tests that source it rely on.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/testlib-test
