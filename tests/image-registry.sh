#!/usr/bin/env bash
# No script, test or workflow pulls straight from Docker Hub, ghcr.io, quay.io or registry.k8s.io (shared/scripts/image-registry-check), proven by shared/scripts/image-registry-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/image-registry-test
