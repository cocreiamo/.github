#!/usr/bin/env bash
# The Claude Code PreToolUse hook on Bash is the shared claude-pre-bash: its shared test proves it, and claude-pre-bash-wired proves
# that .claude/settings.json wires it (each wiring defect red on a mutated copy).
set -euo pipefail
cd "$(dirname "$0")/.."
shared/scripts/claude-pre-bash-test
shared/scripts/claude-pre-bash-wired
