#!/usr/bin/env bash
# test-first is proven on fixture histories, the merge of main into a branch included.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/test-first-test
