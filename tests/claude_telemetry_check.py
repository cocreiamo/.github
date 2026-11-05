#!/usr/bin/env python3
"""Fails when .claude/settings.json of a repository loses the Claude Code telemetry config.

Usage: claude_telemetry_check.py <repo-root> <repo-name>      check
       claude_telemetry_check.py --expected <repo-name>        print the settings the check expects
"""

import json
import os
import sys

HELPER = '"$(git rev-parse --show-toplevel)/.claude/otel-headers.sh"'


def expected(repo):
    return {
        "env": {
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_METRICS_EXPORTER": "otlp",
            "OTEL_LOGS_EXPORTER": "otlp",
            "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.cocreiamo.com",
            "OTEL_LOG_USER_PROMPTS": "1",
            "OTEL_LOG_TOOL_DETAILS": "1",
            "OTEL_RESOURCE_ATTRIBUTES": f"service.name=claude-code,repo={repo}",
        },
        "otelHeadersHelper": HELPER,
    }


def problems(root, repo):
    path = os.path.join(root, ".claude", "settings.json")
    try:
        with open(path) as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        return [f"{path}: {e}"]
    found = []
    env = doc.get("env") if isinstance(doc.get("env"), dict) else {}
    want = expected(repo)
    for key, value in want["env"].items():
        if env.get(key) != value:
            found.append(f"env.{key} must be {value!r}, is {env.get(key)!r}")
    if doc.get("otelHeadersHelper") != want["otelHeadersHelper"]:
        found.append(f"otelHeadersHelper must be {want['otelHeadersHelper']!r}")
    helper = os.path.join(root, ".claude", "otel-headers.sh")
    if not (os.path.isfile(helper) and os.access(helper, os.X_OK)):
        found.append(".claude/otel-headers.sh must exist and be executable")
    return found


def main(argv):
    if len(argv) == 3 and argv[1] == "--expected":
        print(json.dumps(expected(argv[2]), indent=2))
        return 0
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    found = problems(argv[1], argv[2])
    for line in found:
        print(f"claude telemetry: {line}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
