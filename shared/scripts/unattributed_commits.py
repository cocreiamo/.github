#!/usr/bin/env python3
"""Fails naming every commit of a pull request that the ruleset would block as unattributed: its author maps to no GitHub user (a bot's does not count),
or its author email is on a reserved test domain (the list is the one of commit-identity, next to this file).
Env: GH_TOKEN, REPO, BASE_SHA, HEAD_SHA; API_URL and PER_PAGE are for tests."""
import json, os, subprocess, sys, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.environ.get("API_URL", "https://api.github.com")


def get(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"], "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError("GET %s: %s %s" % (path, e.code, e.read()[:200].decode(errors="replace")))


def reserved(name, email):
    env = {"PATH": os.environ["PATH"], "HOME": "/nonexistent", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_NAME": name or "x", "GIT_AUTHOR_EMAIL": email, "GIT_COMMITTER_NAME": name or "x", "GIT_COMMITTER_EMAIL": email}
    return subprocess.run([os.path.join(HERE, "commit-identity")], env=env, capture_output=True).returncode != 0


def main():
    repo, base, head = os.environ["REPO"], os.environ["BASE_SHA"], os.environ["HEAD_SHA"]
    per = int(os.environ.get("PER_PAGE", "100"))
    commits, page = [], 1
    while True:
        batch = get("/repos/%s/compare/%s...%s?per_page=%d&page=%d" % (repo, base, head, per, page))["commits"]
        commits += batch
        if len(batch) < per:
            break
        page += 1
    bad = []
    for c in commits:
        who = c["commit"]["author"]
        name, email = who.get("name") or "", who.get("email") or ""
        if c.get("author") is None and not name.endswith("[bot]"):
            bad.append("%s: author %s <%s> maps to no GitHub user" % (c["sha"][:10], name, email))
        elif email and reserved(name, email):
            bad.append("%s: author %s <%s> is on a reserved test domain" % (c["sha"][:10], name, email))
    for line in bad:
        print("::error::" + line)
    if bad:
        print("The ruleset blocks a pull request with commits it cannot attribute, whatever the checks say. Fix: create a new branch from main, "
              "squash this work into one commit made under your real identity (git config user.email), push it and open the pull request again (no force push).")
        return 1
    print("ok: %d commits, all attributed" % len(commits))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print("::error::the attribution check failed: %s" % e)
        sys.exit(1)
