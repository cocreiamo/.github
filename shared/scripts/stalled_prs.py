#!/usr/bin/env python3
"""List the pull requests open for more than STALLED_AFTER_HOURS that make no progress, in one issue per repository.

A pull request is stalled when it is not a draft and: it conflicts with main, a check is red, no check ran, auto-merge is
off, or every check is green and it still does not merge. A running check is progress.

usage: stalled_prs.py    (env GITHUB_TOKEN, GITHUB_REPOSITORY)
"""

import datetime as dt
import json
import os
import urllib.request

STALLED_AFTER_HOURS = 6
LABEL = "stalled-prs"
RED = {"failure", "timed_out", "cancelled", "action_required", "startup_failure"}


def latest(checks):
    by_name = {}
    for c in checks:
        if c["name"] not in by_name or c["id"] > by_name[c["name"]]["id"]:
            by_name[c["name"]] = c
    return list(by_name.values())


def reason(pull, checks):
    checks = latest(checks)
    if pull.get("mergeable_state") == "dirty":
        return "conflict with main"
    red = sorted(c["name"] for c in checks if c.get("conclusion") in RED)
    if red:
        return "red check: " + ", ".join(red)
    if not checks:
        return "no check ran"
    if any(c.get("status") != "completed" for c in checks):
        return None
    if not pull.get("auto_merge"):
        return "auto-merge is off: nobody has merged it"
    if pull.get("mergeable_state") in ("blocked", "behind", "unstable"):
        return f"every check is green but it does not merge ({pull['mergeable_state']})"
    return None


def stalled(pulls, checks_of, now):
    found = []
    for pull in pulls:
        created = dt.datetime.strptime(pull["created_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.UTC)
        age = (now - created).total_seconds() / 3600
        if pull.get("draft") or age <= STALLED_AFTER_HOURS:
            continue
        why = reason(pull, checks_of(pull))
        if why:
            found.append(
                {"number": pull["number"], "title": pull["title"], "url": pull["html_url"], "age_hours": round(age), "reason": why}
            )
    return sorted(found, key=lambda f: -f["age_hours"])


def body_of(found, now):
    lines = [
        f"Pull requests open for more than {STALLED_AFTER_HOURS} hours that make no progress ({now:%Y-%m-%d %H:%M} UTC).",
        "Drive each to merged or closed with a written reason.",
        "",
    ]
    lines += [f"- #{f['number']} {f['title']} ({f['age_hours']} h): {f['reason']} {f['url']}" for f in found]
    return "\n".join(lines)


def sync_issue(api, repo, found, now):
    open_issue = (api("GET", f"/repos/{repo}/issues?state=open&labels={LABEL}") or [None])[0]
    if not found:
        if open_issue:
            api("PATCH", f"/repos/{repo}/issues/{open_issue['number']}", {"state": "closed"})
        return
    body = body_of(found, now)
    if open_issue:
        api("PATCH", f"/repos/{repo}/issues/{open_issue['number']}", {"body": body})
    else:
        api("POST", f"/repos/{repo}/issues", {"title": "stalled pull requests", "labels": [LABEL], "body": body})


def main():
    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]

    def api(method, path, body=None):
        req = urllib.request.Request(
            "https://api.github.com" + path,
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
            headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"},
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)

    def detail(number):
        return api("GET", f"/repos/{repo}/pulls/{number}")

    def checks_of(pull):
        return api("GET", f"/repos/{repo}/commits/{pull['head']['sha']}/check-runs?per_page=100")["check_runs"]

    now = dt.datetime.now(dt.UTC)
    listed = api("GET", f"/repos/{repo}/pulls?state=open&per_page=100")
    old = [
        p
        for p in listed
        if (now - dt.datetime.strptime(p["created_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.UTC)).total_seconds()
        > STALLED_AFTER_HOURS * 3600
    ]
    found = stalled([detail(p["number"]) for p in old], checks_of, now)
    sync_issue(api, repo, found, now)
    print(f"{len(found)} stalled pull request(s) of {len(listed)} open")


if __name__ == "__main__":
    main()
