#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""A caller of a reusable workflow in another repository passes what the workflow declares at its pin.

usage: workflow-pins-check.py [repository root]   (default: the repository of the working directory)

Every job of .github/workflows/*.y*ml with `uses: owner/repo/.github/workflows/x.yml@ref` is compared with that file read
at that ref: a `with:` key that is not under on.workflow_call.inputs, a `secrets:` key that is not under
on.workflow_call.secrets (unless `secrets: inherit`), a required input or secret the caller omits, and a callee with no
workflow_call are errors, and so is a caller job whose permissions (its own, else its workflow's; none when neither is set) do not cover the permissions of every job of the callee (its own, else the callee's workflow-level ones; write covers read), because the run then fails at startup. actionlint checks the local `./` calls; nothing checks the remote ones, which fail only when
the run starts (startup_failure on main). Only the pinned ref is read, so a later change of the callee never fails this check.

A file is read once per commit: from $WORKFLOW_PINS_CACHE (default ~/.cache/workflow-pins/<owner>/<repo>/<sha>/<path>)
or from the GitHub contents API with $GH_TOKEN, $GITHUB_TOKEN or `gh auth token`. WORKFLOW_PINS_OFFLINE=1 reads the cache only.
"""
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml

USES = re.compile(r"^([^/\s]+)/([^/\s]+)/(\.github/workflows/[^@\s]+\.ya?ml)@(\S+)$")
SHA = re.compile(r"^[0-9a-f]{40}$")


class Unreadable(Exception):
    pass


def token():
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=False)
    return out.stdout.strip() if out.returncode == 0 else ""


def read_pinned(owner, repo, path, ref):
    cache = Path(os.environ.get("WORKFLOW_PINS_CACHE") or Path.home() / ".cache" / "workflow-pins")
    cached = cache / owner / repo / ref / path
    if cached.is_file():
        return cached.read_text()
    if os.environ.get("WORKFLOW_PINS_OFFLINE") == "1":
        raise Unreadable("not in the offline cache")
    tok = token()
    if not tok:
        raise Unreadable("no GH_TOKEN, GITHUB_TOKEN or gh login to read it with")
    req = urllib.request.Request(
        f"https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={ref}",
        headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as e:
        raise Unreadable(f"HTTP {e.code} from the contents API (the token cannot read {owner}/{repo}, or the ref does not exist)") from e
    except (urllib.error.URLError, TimeoutError) as e:
        raise Unreadable(f"the contents API is unreachable: {e}") from e
    if not isinstance(body, dict) or body.get("encoding") != "base64":
        raise Unreadable("the contents API did not return a file")
    text = base64.b64decode(body["content"]).decode()
    if SHA.match(ref):
        cached.parent.mkdir(parents=True, exist_ok=True)
        cached.write_text(text)
    return text


def workflow_call(doc):
    triggers = doc.get("on", doc.get(True))
    if isinstance(triggers, dict) and "workflow_call" in triggers:
        return triggers["workflow_call"] or {}
    if triggers == "workflow_call" or (isinstance(triggers, list) and "workflow_call" in triggers):
        return {}
    return None


LEVEL = {"none": 0, "read": 1, "write": 2}


def effective(scoped, default):
    perms = scoped if scoped is not None else default
    if perms == "read-all":
        return {"*": 1}
    if perms == "write-all":
        return {"*": 2}
    return {k: LEVEL.get(str(v), 0) for k, v in (perms or {}).items()} if isinstance(perms, dict) or perms is None else {}


def granted(perms, scope):
    return max(perms.get(scope, 0), perms.get("*", 0))


def check_permissions(where, job, caller_doc, callee, errors):
    have = effective(job.get("permissions"), caller_doc.get("permissions"))
    for callee_id, callee_job in ((callee.get("jobs") or {}).items()):
        if not isinstance(callee_job, dict):
            continue
        need = effective(callee_job.get("permissions"), callee.get("permissions"))
        for scope, level in sorted(need.items()):
            if scope != "*" and level > granted(have, scope):
                errors.append(f"{where}: its job {callee_id} needs `{scope}: {'write' if level == 2 else 'read'}`, which the calling job does not grant (the run fails at startup)")


def check_job(label, job_id, job, errors, caller_doc=None):
    m = USES.match(str(job.get("uses", "")))
    if not m:
        return
    owner, repo, path, ref = m.groups()
    where = f"{label}: job {job_id} calls {owner}/{repo}/{path}@{ref}"
    try:
        callee = yaml.safe_load(read_pinned(owner, repo, path, ref))
    except Unreadable as e:
        errors.append(f"{where}: cannot read it: {e}")
        return
    except yaml.YAMLError as e:
        errors.append(f"{where}: the file at that ref is not YAML: {e}")
        return
    call = workflow_call(callee if isinstance(callee, dict) else {})
    if call is None:
        errors.append(f"{where}: the workflow at that ref has no workflow_call trigger")
        return
    check_permissions(where, job, caller_doc or {}, callee, errors)
    inputs = call.get("inputs") or {}
    secrets = call.get("secrets") or {}
    given = job.get("with") or {}
    for key in given:
        if key not in inputs:
            errors.append(f"{where}: passes the input `{key}`, which the workflow does not declare at that ref (declares: {', '.join(sorted(inputs)) or 'none'})")
    for key, spec in inputs.items():
        if (spec or {}).get("required") and key not in given:
            errors.append(f"{where}: omits the required input `{key}`")
    passed = job.get("secrets")
    if passed == "inherit":
        return
    passed = passed or {}
    for key in passed:
        if key not in secrets:
            errors.append(f"{where}: passes the secret `{key}`, which the workflow does not declare at that ref (declares: {', '.join(sorted(secrets)) or 'none'})")
    for key, spec in secrets.items():
        if (spec or {}).get("required") and key not in passed:
            errors.append(f"{where}: omits the required secret `{key}`")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    errors = []
    files = sorted(p for pat in ("*.yml", "*.yaml") for p in (root / ".github" / "workflows").glob(pat))
    calls = 0
    for f in files:
        doc = yaml.safe_load(f.read_text())
        jobs = (doc or {}).get("jobs") if isinstance(doc, dict) else None
        for job_id, job in (jobs or {}).items():
            if isinstance(job, dict) and USES.match(str(job.get("uses", ""))):
                calls += 1
                check_job(str(f.relative_to(root)), job_id, job, errors, doc)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"{len(errors)} mismatch(es) between a caller and the reusable workflow at its pin", file=sys.stderr)
        return 1
    print(f"{calls} remote reusable workflow call(s): inputs and secrets match the workflow at each pin")
    return 0


if __name__ == "__main__":
    sys.exit(main())
