#!/usr/bin/env bash
# The committed .claude/settings.json sends Claude Code telemetry to otel.cocreiamo.com: every setting and the headers helper are required, and the check refuses each one missing.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=.github
check() { python3 -I tests/claude_telemetry_check.py "$@"; }
w="$(mktemp -d)"
trap 'rm -rf "$w"' EXIT
mkdir -p "$w/.claude"
printf '#!/bin/sh\n' > "$w/.claude/otel-headers.sh"; chmod +x "$w/.claude/otel-headers.sh"
check --expected "$repo" > "$w/.claude/settings.json"
check "$w" "$repo" 2>/dev/null || { echo "claude telemetry: the check refused its own expected settings" >&2; exit 1; }
python3 -I - "$w" <<'PY' > "$w/keys"
import json, sys
doc = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print("\n".join(["env." + k for k in doc["env"]] + ["otelHeadersHelper"]))
PY
while read -r key; do
  python3 -I - "$w" "$key" <<'PY'
import json, sys
p = sys.argv[1] + "/.claude/settings.json"
doc = json.load(open(p))
k = sys.argv[2]
if k.startswith("env."):
    del doc["env"][k[4:]]
else:
    del doc[k]
json.dump(doc, open(sys.argv[1] + "/.claude/broken.json", "w"))
PY
  mkdir -p "$w/broken/.claude"; cp "$w/.claude/broken.json" "$w/broken/.claude/settings.json"; cp "$w/.claude/otel-headers.sh" "$w/broken/.claude/"
  if check "$w/broken" "$repo" 2>/dev/null; then echo "claude telemetry: the check accepted settings without $key" >&2; exit 1; fi
done < "$w/keys"
rm "$w/.claude/otel-headers.sh"
if check "$w" "$repo" 2>/dev/null; then echo "claude telemetry: the check accepted a missing headers helper" >&2; exit 1; fi
check "$PWD" "$repo"
echo "claude telemetry: settings of this repository ok"
