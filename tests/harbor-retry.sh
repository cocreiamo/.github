#!/usr/bin/env bash
# The registry scripts of the publish (shared/scripts/harbor-retry, image-scan, image-sign), proven by their shared tests on stub commands.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/harbor-retry-test
shared/scripts/image-scan-test
shared/scripts/image-sign-test
