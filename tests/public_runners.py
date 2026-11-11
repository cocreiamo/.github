#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""A public repository never runs on the self-hosted runners (a fork pull request would execute code on the CI host).

usage: public_runners.py [workflows dir]

Every job reachable from a trigger other than workflow_call (push, pull_request, pull_request_target, schedule,
workflow_dispatch, workflow_run, merge_group, ...), directly or through a local `uses: ./.github/workflows/<file>` call,
carries a `runs-on` that is a GitHub-hosted label or the one guarded form
    ${{ fromJSON(github.repository_visibility == 'public' && '"ubuntu-24.04"' || '[<self-hosted labels>]') }}
which resolves to the hosted label in a public repository and to the self-hosted pool only in a private one.
A workflow that only has workflow_call is not reached: it runs in the context of its caller.
"""

import re
import sys
from pathlib import Path

import yaml

HOSTED = re.compile(r"^(ubuntu|windows|macos)-[0-9a-z.]+$")
GUARDED = re.compile(
    r"""^\$\{\{ fromJSON\(github\.repository_visibility == 'public' && '"ubuntu-[0-9.]+"' \|\| '\[("[a-z0-9-]+")(, ?"[a-z0-9-]+")*\]'\) \}\}$"""
)
LOCAL = re.compile(r"^\./\.github/workflows/([^/@]+\.ya?ml)(@.*)?$")


def allowed(runs_on):
    if isinstance(runs_on, str):
        return bool(HOSTED.match(runs_on) or GUARDED.match(runs_on.strip()))
    return False


def violations(directory):
    docs = {}
    for path in sorted(Path(directory).glob("*.y*ml")):
        docs[path.name] = yaml.safe_load(path.read_text())
    out = []
    reached = {}
    stack = []
    for name, doc in docs.items():
        triggers = doc.get(True, doc.get("on")) or {}
        names = [triggers] if isinstance(triggers, str) else list(triggers)
        if any(t != "workflow_call" for t in names):
            stack.append((name, name))
    while stack:
        name, root = stack.pop()
        if name in reached or name not in docs:
            continue
        reached[name] = root
        for job in (docs[name].get("jobs") or {}).values():
            m = LOCAL.match(str(job.get("uses", "")))
            if m:
                stack.append((m.group(1), root))
    for name, root in sorted(reached.items()):
        for job_id, job in (docs[name].get("jobs") or {}).items():
            if "runs-on" in job and not allowed(job["runs-on"]):
                via = "" if name == root else f" (reached from {root})"
                out.append(f"{name}: job {job_id}{via} runs on {job['runs-on']!r}, reachable from a trigger of a possibly public repository")
    return out


if __name__ == "__main__":
    found = violations(sys.argv[1] if len(sys.argv) > 1 else ".github/workflows")
    print("\n".join(found))
    sys.exit(1 if found else 0)
