#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""Four hygiene rules for .github/workflows/*.y*ml.

usage: workflow-hygiene-check.py [repository root]   (default: the working directory)

1. Every job that has a runner of its own declares `timeout-minutes` (a stuck job holds a runner slot for six hours).
2. In a workflow with a `push` trigger no concurrency group (workflow or job level) is keyed on the ref alone: two pushes
   to main share the group and the queue drops the older pending run, so a commit is never checked. A group that names
   the ref must also name `github.sha` or `github.run_id`.
3. A `uses: owner/repo@<40-hex>` pin must be a commit, not an annotated tag object (`git/tags/<sha>` answers for a tag
   object; a tag object pin is not a commit and fails to resolve for some consumers). Local `./` actions and non-SHA refs are not read.
4. In a repository with the mise task `ci` (mise-tasks/ci/_default or [tasks.ci] in mise.toml), a workflow with a `pull_request`
   trigger runs its checks only as `mise run ci -- <part>`: a `run:` that calls another `mise run`, a script of tests/, hooks/
   or shared/scripts/, or `bash tests/...` defines a check a second time in YAML, where the pre-push hook and `affected` do not see it.

The kind of a SHA never changes: it is cached in $WORKFLOW_HYGIENE_KINDS (default ~/.cache/workflow-hygiene/<owner>/<repo>/<sha>,
content `commit` or `tag`), else read from the GitHub API with $GH_TOKEN, $GITHUB_TOKEN or `gh auth token`.
WORKFLOW_HYGIENE_OFFLINE=1 reads the cache only (an unknown SHA is then an error).
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml

USES = re.compile(r"^([^/\s@.][^/\s@]*)/([^/\s@]+)(?:/[^@\s]*)?@([0-9a-f]{40})$")
REF_KEY = re.compile(r"github\.(ref|ref_name)\b")
UNIQUE_KEY = re.compile(r"github\.(sha|run_id)\b")


def token():
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=False)
    return out.stdout.strip() if out.returncode == 0 else ""


def api(owner, repo, kind, sha, tok):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{owner}/{repo}/git/{kind}/{sha}",
        headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            json.load(resp)
        return True
    except urllib.error.HTTPError as e:
        if e.code in (404, 422):
            return False
        raise


def kind_of(owner, repo, sha):
    cache = Path(os.environ.get("WORKFLOW_HYGIENE_KINDS") or Path.home() / ".cache" / "workflow-hygiene")
    cached = cache / owner / repo / sha
    if cached.is_file():
        return cached.read_text().strip()
    if os.environ.get("WORKFLOW_HYGIENE_OFFLINE") == "1":
        return None
    tok = token()
    if not tok:
        return None
    try:
        if api(owner, repo, "commits", sha, tok):
            kind = "commit"
        elif api(owner, repo, "tags", sha, tok):
            kind = "tag"
        else:
            return None
    except (urllib.error.URLError, TimeoutError):
        return None
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_text(kind + "\n")
    return kind


def groups(doc):
    found = []
    top = doc.get("concurrency")
    if top:
        found.append(("workflow", top))
    for name, job in (doc.get("jobs") or {}).items():
        if isinstance(job, dict) and job.get("concurrency"):
            found.append((f"job {name}", job["concurrency"]))
    return found


CI_CALL = re.compile(r"^mise run ci -- [a-z][a-z0-9-]*(?: (?:[a-z][a-z0-9-]*|--[a-z-]+))*$")
COMMAND_START = r"(?:^|\b(?:if|then|do|else)\s+|&&\s*|\|\|\s*|;\s*)"
OTHER_CHECK = re.compile(COMMAND_START + r"(?:mise run\b|bash\s+(?:\./)?tests/|(?:\./)?(?:tests|hooks|shared/scripts)/)")


def has_ci_task(root):
    if (root / "mise-tasks" / "ci" / "_default").exists() or (root / "mise-tasks" / "ci").is_file():
        return True
    mise = root / "mise.toml"
    return mise.is_file() and re.search(r"^\[tasks\.(?:ci|\"ci\")\]", mise.read_text(encoding="utf-8"), re.M) is not None


def ci_entry_problems(path, doc):
    triggers = doc.get("on", doc.get(True))
    if not (triggers == "pull_request" or (isinstance(triggers, list) and "pull_request" in triggers) or (isinstance(triggers, dict) and "pull_request" in triggers)):
        return []
    problems = []
    for name, job in (doc.get("jobs") or {}).items():
        for step in (job.get("steps") or []) if isinstance(job, dict) else []:
            for line in str(step.get("run") or "").splitlines():
                line = line.strip()
                if line and not CI_CALL.match(line) and OTHER_CHECK.search(line):
                    problems.append(f"{path}: job {name}: `{line}` runs a check outside `mise run ci -- <part>`: define it as a part (a mise task ci:<part> with sources) and call that")
    return problems


def check_workflow(path, ci_entry=False):
    doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    triggers = doc.get("on", doc.get(True))
    pushes = triggers == "push" or (isinstance(triggers, list) and "push" in triggers) or (isinstance(triggers, dict) and "push" in triggers)
    problems = ci_entry_problems(path, doc) if ci_entry else []
    jobs = doc.get("jobs") or {}
    for name, job in jobs.items():
        if isinstance(job, dict) and "uses" not in job and "timeout-minutes" not in job:
            problems.append(f"{path}: job {name}: no timeout-minutes")
    if pushes:
        for where, conc in groups(doc):
            group = conc if isinstance(conc, str) else str((conc or {}).get("group", ""))
            if REF_KEY.search(group) and not UNIQUE_KEY.search(group):
                problems.append(f"{path}: {where}: concurrency group {group!r} is keyed on the ref alone: queued pushes to one branch cancel each other; add github.sha or github.run_id")
    uses = []
    for name, job in jobs.items():
        if not isinstance(job, dict):
            continue
        if isinstance(job.get("uses"), str):
            uses.append((name, job["uses"]))
        for step in job.get("steps") or []:
            if isinstance(step.get("uses"), str):
                uses.append((name, step["uses"]))
    for name, ref in uses:
        m = USES.match(ref)
        if not m:
            continue
        owner, repo, sha = m.groups()
        kind = kind_of(owner, repo, sha)
        if kind == "tag":
            problems.append(f"{path}: job {name}: {owner}/{repo}@{sha} is an annotated tag object, not a commit: pin the commit it points to (`gh api repos/{owner}/{repo}/git/tags/{sha} -q .object.sha`)")
        elif kind is None:
            problems.append(f"{path}: job {name}: could not tell whether {owner}/{repo}@{sha} is a commit (unknown SHA, no token or no network)")
    return problems


def main(argv):
    root = Path(argv[0]) if argv else Path(".")
    problems = []
    ci_entry = has_ci_task(root)
    for path in sorted((root / ".github" / "workflows").glob("*.y*ml")):
        problems += check_workflow(path, ci_entry)
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
