#!/usr/bin/env bash
# The shared commit-identity hook script refuses an author or committer on a reserved test domain and accepts a real one (shared/scripts/commit-identity-test).
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/commit-identity-test
