#!/usr/bin/env python3
"""Decide whether the checks of a push to main can be skipped: the merged commit has the tree of the head of the pull
request it came from, and the required check of that head was green. Every check runs once.

usage: post_merge_skip.py REQUIRED_CHECK    (env GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA)
prints `skip=true` or `skip=false` and the reason on stderr; any doubt or API error prints skip=false.
"""

import json
import os
import sys
import urllib.request


def decide(api, repo, sha, required):
    try:
        pulls = api(f"/repos/{repo}/commits/{sha}/pulls")
        merged = [p for p in pulls if p.get("merged_at") and p.get("merge_commit_sha") == sha]
        if not merged:
            return False, "no pull request was merged as this commit"
        head = merged[0]["head"]["sha"]
        if api(f"/repos/{repo}/git/commits/{sha}")["tree"]["sha"] != api(f"/repos/{repo}/git/commits/{head}")["tree"]["sha"]:
            return False, "the merged tree differs from the tree of the pull request head"
        runs = api(f"/repos/{repo}/commits/{head}/check-runs?per_page=100")["check_runs"]
        if not any(r["name"] == required and r["conclusion"] == "success" for r in runs):
            return False, f"the check {required} of the pull request head is not green"
        return True, f"same tree as the pull request head {head[:9]}, whose {required} was green"
    except Exception as e:  # any doubt runs the checks
        return False, f"cannot decide ({type(e).__name__}): {e}"


def main():
    token = os.environ["GITHUB_TOKEN"]

    def api(path):
        req = urllib.request.Request(
            "https://api.github.com" + path,
            headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"},
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)

    skip, why = decide(api, os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"], sys.argv[1])
    print(f"skip={str(skip).lower()}")
    print(why, file=sys.stderr)


if __name__ == "__main__":
    main()
