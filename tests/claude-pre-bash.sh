#!/usr/bin/env bash
# The Claude Code PreToolUse hook on Bash is the shared claude-pre-bash, and its shared test proves it.
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/claude-pre-bash-test
