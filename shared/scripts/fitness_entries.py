#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""Every check of a repository has an entry in its own docs/fitness-functions/, and every entry is valid.

usage: fitness_entries.py <cocreiamo|dotgithub> [root] [--entries <dir>]

The schema is the one of docs/fitness-functions.md in cocreiamo/deploy ("Where an entry lives"): one mapping per file, named after
its id; a mise task is an overlay (id, repo, task, runs) whose invariant, command and file come from `mise tasks ls --json`; any
other check carries id, repo, invariant, runs, command, file and, for a function inside a file, symbol. The checks of a
repository are discovered by the same patterns as deploy's test:fitness-catalogue.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

RUNS = {"pr-ci", "nightly", "checkpoint", "admission", "local"}
DIR = Path("docs") / "fitness-functions"
PATTERNS = {
    "cocreiamo": ("tools/tests/*", "tools/policy/*.rego", "tools/tasks/check/*", "tools/tasks/ci"),
    "dotgithub": ("tests/*.sh", "hooks/*"),
}
DERIVED = ("invariant", "command", "file", "symbol")


def discovered(repo, root):
    found = set()
    for pattern in PATTERNS[repo]:
        found |= {str(p.relative_to(root)) for p in sorted(root.glob(pattern)) if p.is_file()}
    return found


def mise_tasks(root):
    run = subprocess.run(["mise", "tasks", "ls", "--json"], cwd=root, capture_output=True, text=True)
    try:
        listed = json.loads(run.stdout)
    except json.JSONDecodeError:
        listed = []
    return {
        t["name"]: {"description": " ".join((t.get("description") or "").split()), "file": os.path.relpath(t["source"], root)}
        for t in listed
    }


def problems(repo, root, entries_dir=None, tasks=None):
    root = Path(root)
    entries_dir = Path(entries_dir) if entries_dir else root / DIR
    found, listed, seen = [], set(), set()
    if not entries_dir.is_dir():
        return [f"{DIR} is missing: one entry per check, named after its id"]
    for path in sorted(entries_dir.glob("*.yaml")):
        name = DIR / path.name
        try:
            entry = yaml.safe_load(path.read_text())
        except yaml.YAMLError as error:
            found.append(f"{name}: not valid YAML ({error})")
            continue
        if not isinstance(entry, dict) or not entry.get("id"):
            found.append(f"{name}: one mapping with an id per file")
            continue
        who = str(entry["id"])
        wanted = re.sub(r"[^A-Za-z0-9.-]+", "_", who) + ".yaml"
        if path.name != wanted:
            found.append(f"{name}: the file of {who} must be named {wanted}")
        if who in seen:
            found.append(f"{who}: duplicate id")
        seen.add(who)
        if entry.get("repo") != repo:
            found.append(f"{who}: repo must be {repo}")
        if not who.startswith(repo + "/") or who.count("/") < 2:
            found.append(f"{who}: the id must be {repo}/<kind>/<name>")
        if "task" in entry:
            keys = ("task", "runs")
            restated = [k for k in DERIVED if k in entry]
            if restated:
                found.append(f"{who}: {', '.join(restated)} comes from mise for a task entry: remove it from the overlay")
        else:
            keys = ("invariant", "runs", "command", "file")
        found += [f"{who}: field {k} is missing" for k in keys if not entry.get(k)]
        runs = entry.get("runs")
        if runs and (not isinstance(runs, list) or any(r not in RUNS for r in runs)):
            found.append(f"{who}: runs must be a list drawn from {sorted(RUNS)}")
        file = entry.get("file")
        if "task" in entry:
            if tasks is None:
                tasks = mise_tasks(root)
            task = tasks.get(entry["task"])
            if task is None:
                found.append(f"{who}: mise has no task {entry['task']}")
                continue
            if not task["description"]:
                found.append(f"{who}: the task {entry['task']} has no #MISE description (it is the invariant)")
            file = task["file"]
        if file:
            listed.add(file)
            if not (root / file).is_file():
                found.append(f"{who}: {file} does not exist")
            elif entry.get("symbol") and not re.search(rf"^def {re.escape(str(entry['symbol']))}\(", (root / file).read_text(), re.M):
                found.append(f"{who}: {entry['symbol']} is not defined in {file}")
    for file in sorted(discovered(repo, root) - listed):
        found.append(
            f"{file} is a check with no entry: add {DIR}/<id with every run of characters outside [A-Za-z0-9.-] replaced by _>.yaml "
            "(format: docs/fitness-functions.md of cocreiamo/deploy)"
        )
    return found


if __name__ == "__main__":
    args = sys.argv[1:]
    entries = None
    if "--entries" in args:
        i = args.index("--entries")
        entries = args[i + 1]
        del args[i : i + 2]
    if not args or args[0] not in PATTERNS:
        sys.exit(f"usage: fitness_entries.py <{'|'.join(PATTERNS)}> [root] [--entries <dir>]")
    out = problems(args[0], args[1] if len(args) > 1 else ".", entries)
    if out:
        sys.exit("fitness-entries:\n" + "\n".join(out))
    print("fitness-entries: every check has an entry")
