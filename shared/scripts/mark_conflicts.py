#!/usr/bin/env python3
"""After a push to main: label and comment the open pull requests that now conflict with their base.

GitHub runs no pull_request workflow on a PR in conflict, so nothing else would tell. Plain HTTPS: the runners ship no GitHub CLI.

usage: mark_conflicts.py    (env GH_TOKEN with pull-requests and issues write, GITHUB_REPOSITORY; API_URL and
                             MARK_CONFLICTS_RETRY, the seconds between two asks of an unknown merge state, are for tests)
"""

import json
import os
import sys
import time
import urllib.request

API = os.environ.get("API_URL", "https://api.github.com")
REPO = os.environ["GITHUB_REPOSITORY"]
LABEL = "conflict"
COMMENT = (
    "This PR now conflicts with its base branch. GitHub runs no pull_request workflow on it until the conflict is resolved: "
    "merge the base into the branch (no rebase) and push."
)


def call(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    }
    request = urllib.request.Request(API + path, method=method, data=data, headers=headers)  # noqa: S310 - https, or the loopback stub of the test
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - same URL
        raw = response.read()
    return json.loads(raw) if raw else None


def state(number):
    for _ in range(4):
        merge_state = call("GET", f"/repos/{REPO}/pulls/{number}")["mergeable_state"]
        if merge_state != "unknown":
            return merge_state
        time.sleep(int(os.environ.get("MARK_CONFLICTS_RETRY", "15")))
    return "unknown"


def main():
    try:
        call(
            "POST",
            f"/repos/{REPO}/labels",
            {"name": LABEL, "color": "B60205", "description": "the PR conflicts with its base: merge the base into it"},
        )
    except Exception:  # noqa: S110 - the label may already exist; creating it is best effort
        pass
    for pull in call("GET", f"/repos/{REPO}/pulls?state=open&per_page=100"):
        if any(label["name"] == LABEL for label in pull["labels"]) or state(pull["number"]) != "dirty":
            continue
        call("POST", f"/repos/{REPO}/issues/{pull['number']}/labels", {"labels": [LABEL]})
        call("POST", f"/repos/{REPO}/issues/{pull['number']}/comments", {"body": COMMENT})
        print(f"marked #{pull['number']}")


if __name__ == "__main__":
    sys.exit(main())
