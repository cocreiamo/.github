#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""Every `run:` step of every workflow calls only tools its runner has.

usage: workflow-tools-check.py [repository root]   (default: the repository of the working directory)

hermetic_tools.py (next to this file) lists the commands a shell script calls and holds the short list of what every
self-hosted runner image has. This reads .github/workflows/*.y*ml with the same rules, step by step: a tool is available
in a step when it is on that list, or when it is pinned in the repository's mise.toml and an earlier step of the same job
(or an earlier command of the same step) ran `ci-mise-setup`, `mise install` or `mise x`/`mise exec`, or an earlier step
is a setup action that installs it. `uses:` steps are not read (actionlint covers them), nor are steps with a shell that
is not bash or sh, nor jobs that run in a container, which has its own image.
"""
import importlib.util
import re
import sys
from pathlib import Path

import yaml

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("hermetic_tools", Path(__file__).resolve().parent / "hermetic_tools.py")
ht = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ht)

SETUP_COMMANDS = {"ci-mise-setup"}
MISE_SETUP = re.compile(r"(?:^|[\s;&|(`])mise\s+(?:install|x|exec)\b", re.M)
# setup action (owner/name) to the tools it puts on PATH; None means every tool of mise.toml.
SETUP_ACTIONS = {
    "actions/setup-node": ["node", "npm", "npx", "corepack"],
    "actions/setup-python": ["python3", "pip"],
    "actions/setup-go": ["go", "gofmt"],
    "astral-sh/setup-uv": ["uv", "uvx"],
    "jdx/mise-action": None,
}
EXPRESSION = re.compile(r"\$\{\{.*?\}\}", re.S)


def unavailable(text, have, pinned, functions):
    """Commands of one step that no tool list covers, in order, with the reason."""
    text = EXPRESSION.sub("x", text)
    functions = functions | ht.function_names_text(text)
    commands = list(ht.external_text(text, functions))
    setup_at = None
    if any(c in SETUP_COMMANDS for c in commands):
        setup_at = min(i for i, c in enumerate(commands) if c in SETUP_COMMANDS)
    if MISE_SETUP.search(text) and "mise" in commands:
        mise_at = commands.index("mise")
        setup_at = mise_at if setup_at is None else min(setup_at, mise_at)
    seen = set()
    for i, cmd in enumerate(commands):
        if cmd in ht.PLATFORM or cmd in have or cmd in seen:
            continue
        seen.add(cmd)
        if cmd in pinned and setup_at is not None and i > setup_at:
            continue
        if cmd in pinned:
            yield cmd, "mise.toml pins it, but no earlier step of the job runs ci-mise-setup, mise install or mise x"
        else:
            yield cmd, "it is not on the runner image and mise.toml does not pin it"


def check_workflow(path, pinned):
    doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    default_shell = ((doc.get("defaults") or {}).get("run") or {}).get("shell")
    problems = []
    for job, spec in (doc.get("jobs") or {}).items():
        if not isinstance(spec, dict) or "container" in spec:
            continue
        job_shell = (((spec.get("defaults") or {}).get("run") or {}).get("shell")) or default_shell
        have = set()
        for n, step in enumerate(spec.get("steps") or [], 1):
            used = step.get("uses")
            if used:
                action = str(used).split("@")[0]
                if action in SETUP_ACTIONS:
                    have |= pinned if SETUP_ACTIONS[action] is None else set(SETUP_ACTIONS[action])
                continue
            run = step.get("run")
            shell = step.get("shell") or job_shell
            if not isinstance(run, str) or (shell and not re.match(r"^(bash|sh)(\s|$)", str(shell))):
                continue
            label = step.get("name") or run.strip().splitlines()[0][:60]
            for cmd, why in unavailable(run, have, pinned, set()):
                problems.append(f"{path}: job {job}, step {n} ({label}): calls `{cmd}`: {why}")
            commands = list(ht.external_text(EXPRESSION.sub("x", run), set()))
            if any(c in SETUP_COMMANDS for c in commands) or (MISE_SETUP.search(run) and "mise" in commands):
                have |= pinned
    return problems


def main(argv):
    root = Path(argv[0]) if argv else Path(".")
    pinned = ht.declared(root / "mise.toml") if (root / "mise.toml").exists() else set()
    problems = []
    for path in sorted((root / ".github" / "workflows").glob("*.y*ml")):
        problems += check_workflow(path, pinned)
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
