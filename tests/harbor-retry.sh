#!/usr/bin/env bash
# The registry scripts of the publish (shared/scripts/harbor-retry, image-scan, image-sign): the retry policy sorts and retries a failure as Harbor means it, proven by shared/scripts/harbor-retry-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/harbor-retry-test
