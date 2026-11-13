#!/usr/bin/env bash
# The shared hermetic-tools lexer (shared/scripts/hermetic_tools.py): a quoted parenthesis inside a command substitution, a one-line function after a separator, and the binaries a mise tool installs.
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/shared/scripts:$PWD" python3 -P -m unittest tests/hermetic_tools_test.py
