#!/usr/bin/env python3
"""Decide whether the checks of a push to main can be skipped: the merged commit has the tree the pull request run tested,
and the required check of that head was green. Every check runs once.

The run of a pull request checks out the merge ref (the head merged into the main of that moment), so when main moved after the
branch was cut the head tree is not the tree that was tested. A job of the run records it as a notice annotation titled
`tested-tree` whose message is `git rev-parse HEAD^{tree}` (`echo "::notice title=tested-tree::$(git rev-parse 'HEAD^{tree}')"`);
the newest such annotation among the check runs of the head is compared with the squash tree. Without one, the head tree is.

usage: post_merge_skip.py REQUIRED_CHECK    (env GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA)
prints `skip=true` or `skip=false` and the reason on stderr; any doubt or API error prints skip=false.
"""

import json
import os
import sys
import urllib.request


def tested_tree(api, repo, runs):
    """The tree recorded by the newest check run that carries a `tested-tree` notice, or None."""
    for r in sorted(runs, key=lambda r: r.get("completed_at") or "", reverse=True):
        if not (r.get("output") or {}).get("annotations_count"):
            continue
        try:
            notes = api(f"/repos/{repo}/check-runs/{r['id']}/annotations?per_page=100")
        except Exception:  # an unreadable annotation is no tested tree: the head tree decides
            return None
        for n in notes:
            if n.get("title") == "tested-tree":
                return n["message"].strip()
    return None


def decide(api, repo, sha, required):
    try:
        pulls = api(f"/repos/{repo}/commits/{sha}/pulls")
        merged = [p for p in pulls if p.get("merged_at") and p.get("merge_commit_sha") == sha]
        if not merged:
            return False, "no pull request was merged as this commit"
        head = merged[0]["head"]["sha"]
        runs = api(f"/repos/{repo}/commits/{head}/check-runs?per_page=100")["check_runs"]
        if not any(r["name"] == required and r["conclusion"] == "success" for r in runs):
            return False, f"the check {required} of the pull request head is not green"
        squash = api(f"/repos/{repo}/git/commits/{sha}")["tree"]["sha"]
        tested = tested_tree(api, repo, runs)
        if tested == squash:
            return True, f"same tree as the merge ref the run of pull request head {head[:9]} tested, whose {required} was green"
        if squash == api(f"/repos/{repo}/git/commits/{head}")["tree"]["sha"]:
            return True, f"same tree as the pull request head {head[:9]}, whose {required} was green"
        return False, "the merged tree is neither the tree the pull request run tested nor the tree of its head"
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
