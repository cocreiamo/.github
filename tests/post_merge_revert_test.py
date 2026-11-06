import importlib.util, json, os, stat, subprocess, sys, tempfile

spec = importlib.util.spec_from_file_location("prm", sys.argv[1])
prm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prm)

SHA, OTHER = "a" * 40, "b" * 40
PR = {"number": 12, "title": "feat: add x", "head_ref": "add-x", "author": "iambilotta", "node_id": "PR_node"}


def facts(**kw):
    f = {"sha": SHA, "head_sha": SHA, "commit_title": "feat: add x (#12)", "pr": dict(PR), "open_revert": False}
    f.update(kw)
    return f


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def action(**kw):
    return prm.decide(facts(**kw))["action"]


check("a human PR on the head of main is reverted", action(), "revert")
check("main moved on: skip", action(head_sha=OTHER), "skip")
check("a revert PR already open: skip", action(open_revert=True), "skip")
check("main moved on wins over everything", action(head_sha=OTHER, pr=None), "skip")
check("never revert a revert (commit title)", action(commit_title="revert: feat: add x (#13)"), "alert")
check("never revert a revert (branch)", action(pr={**PR, "head_ref": "revert-12-add-x"}), "alert")
check("never revert a revert (git default title)", action(commit_title='Revert "feat: add x" (#13)'), "alert")
check("never revert a Renovate PR", action(pr={**PR, "author": "cocreiamo-claude-code-pr[bot]", "head_ref": "renovate/x"}), "alert")
check("never revert any bot PR", action(pr={**PR, "author": "cocreiamo-image-updater[bot]"}), "alert")
check("no PR behind the commit: alert only", action(pr=None), "alert")
for name in ("skip", "alert", "revert"):
    assert prm.decide(facts(**({"head_sha": OTHER} if name == "skip" else {})))["reason"]

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["GH_LOG"], "a").write(json.dumps(a) + "\n")
e = os.environ
if a[:1] == ["api"] and "-f" not in a and "-X" not in a and a[1] != "graphql":
    p = a[1]
    if p.endswith("/git/ref/heads/main"):
        print(json.dumps({"object": {"sha": e["FAKE_HEAD"]}}))
    elif p.endswith("/pulls") and "/commits/" in p:
        print(json.dumps([{"number": 12, "title": "feat: add x", "merged_at": "t", "merge_commit_sha": e["FAKE_SHA"], "node_id": "PR_node",
                           "head": {"ref": e["FAKE_REF"]}, "user": {"login": e["FAKE_AUTHOR"]}}] if e.get("FAKE_PR", "1") == "1" else []))
    elif "/commits/" in p:
        print(json.dumps({"commit": {"message": e["FAKE_MESSAGE"]}}))
    elif "/pulls?state=open" in p:
        print(json.dumps([{"number": 99, "body": "<!-- post-merge-revert:" + e["FAKE_SHA"] + " -->"}] if e.get("FAKE_OPEN") else []))
    else:
        print("null")
elif "graphql" in a:
    if e.get("FAKE_REVERT_FAILS"):
        sys.stderr.write("conflict"); sys.exit(1)
    print(json.dumps({"data": {"revertPullRequest": {"revertPullRequest": {"number": 78, "url": "https://x/78"}}}}))
elif a[:1] == ["api"] and a[1].endswith("/issues"):
    print(json.dumps({"number": 77, "html_url": "https://x/77"}))
else:
    print("{}")
'''


def run(dry=False, **kw):
    d = tempfile.mkdtemp()
    gh = os.path.join(d, "gh")
    open(gh, "w").write(FAKE)
    os.chmod(gh, os.stat(gh).st_mode | stat.S_IXUSR)
    log = os.path.join(d, "log")
    env = {
        "PATH": d + ":" + os.environ["PATH"], "GH_LOG": log, "REPO": "cocreiamo/x", "SHA": SHA, "FAILED": "fast, slow-lint",
        "RUN_URL": "https://github.com/cocreiamo/x/actions/runs/1", "ASSIGNEE": "iambilotta", "DRY_RUN": "true" if dry else "false",
        "FAKE_HEAD": SHA, "FAKE_SHA": SHA, "FAKE_REF": "add-x", "FAKE_AUTHOR": "iambilotta", "FAKE_MESSAGE": "feat: add x (#12)\n\nbody",
    }
    env.update(kw)
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    calls = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
    return r, calls


def mutating(calls):
    return [c for c in calls if "-f" in c or "graphql" in c or c[0] == "pr" or "-X" in c]


r, calls = run()
check("the real flow succeeds", r.returncode, 0)
text = json.dumps(calls)
for needle in ("graphql", "revert: feat: add x", "Closes #77", "post-merge-revert:" + SHA, "fast, slow-lint", "actions/runs/1", "assignees[]=iambilotta", "labels[]=main-red"):
    if needle not in text:
        sys.exit(f"FAIL: the real flow never sent {needle!r}: {text}")
if not any(c[:2] == ["pr", "merge"] and "--auto" in c and "--squash" in c and "78" in c for c in calls):
    sys.exit("FAIL: the revert PR is not set to auto-merge")
if not any(c[0] == "api" and c[1].endswith("/issues/12/comments") for c in calls):
    sys.exit("FAIL: the original PR got no comment")

r, calls = run(dry=True)
check("a dry run succeeds", r.returncode, 0)
check("a dry run mutates nothing", mutating(calls), [])
if "would revert" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)

r, calls = run(FAKE_HEAD=OTHER)
check("main moved on: succeeds", r.returncode, 0)
check("main moved on: nothing mutated", mutating(calls), [])

r, calls = run(FAKE_OPEN="1")
check("revert already open: nothing mutated", mutating(calls), [])

r, calls = run(FAKE_AUTHOR="cocreiamo-claude-code-pr[bot]", FAKE_REF="renovate/x")
check("renovate: succeeds", r.returncode, 0)
text = json.dumps(calls)
if "graphql" in text or "main-red" not in text:
    sys.exit("FAIL: a Renovate PR must raise the alert and never be reverted: " + text)

r, calls = run(FAKE_PR="0")
if "graphql" in json.dumps(calls) or "main-red" not in json.dumps(calls):
    sys.exit("FAIL: a commit with no PR must alert only")

r, calls = run(FAKE_REVERT_FAILS="1")
check("a revert that cannot be made fails the job", r.returncode != 0, True)
if "main-red" not in json.dumps(calls):
    sys.exit("FAIL: the alert must go out before the revert is tried")
print("python cases ok")
