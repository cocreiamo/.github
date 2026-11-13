#!/usr/bin/env bash
# The comment rule (shared/scripts/comment-hygiene): an added comment that cites a record, tells history or keeps dead code is refused, proven by shared/scripts/comment-hygiene-test.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/comment-hygiene-test
