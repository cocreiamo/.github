import http.server, importlib.util, json, os, subprocess, sys, threading

spec = importlib.util.spec_from_file_location("prm", sys.argv[1])
prm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prm)

SHA, OTHER = "a" * 40, "b" * 40
PR = {"number": 12, "title": "feat: add x", "head_ref": "add-x", "author": "iambilotta", "node_id": "PR_node"}


def facts(**kw):
    f = {"sha": SHA, "head_sha": SHA, "commit_title": "feat: add x (#12)", "pr": dict(PR), "open_revert": False, "moved_ok": False, "green_after": False, "head_green": False,
         "first": {"sha": SHA, "conclusion": "failure", "known_red": True, "run_id": None, "rerunnable": False}}
    f.update(kw)
    return f


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def action(**kw):
    return prm.decide(facts(**kw))["action"]


check("a human PR on the head of main is reverted", action(), "revert")
LATER = {"sha": OTHER, "conclusion": "failure", "known_red": True, "run_id": 3, "rerunnable": False}
check("main moved on and the commit is the first red of its streak: revert", action(head_sha=OTHER), "revert")
check("main moved on and the streak began earlier: skip, the run of the newer commit alerts", action(head_sha=OTHER, first=LATER), "skip")
check("a later red commit of the streak: alert only", action(first=LATER), "alert")
check("a streak that began at an unverified commit: alert, its run is repeated", prm.decide(facts(first={**LATER, "conclusion": "cancelled", "known_red": False, "rerunnable": True}))["rerun"], 3)
check("moved_ok never reverts a revert", action(head_sha=OTHER, moved_ok=True, commit_title="revert: feat: add x (#13)"), "alert")
check("moved_ok still skips a revert already open", action(head_sha=OTHER, moved_ok=True, open_revert=True), "skip")
check("main is green again after the commit: skip", action(green_after=True), "skip")
check("green again wins over a revert-worthy PR even when main moved", action(green_after=True, head_sha=OTHER, moved_ok=True), "skip")
check("main is green at its head: skip", action(head_green=True), "skip")
check("green at the head wins over a moved head with moved_ok", action(head_green=True, head_sha=OTHER, moved_ok=True), "skip")
check("a revert PR already open: skip", action(open_revert=True), "skip")
check("main moved on wins over everything for a later commit of the streak", action(head_sha=OTHER, pr=None, first=LATER), "skip")
check("never revert a revert (commit title)", action(commit_title="revert: feat: add x (#13)"), "alert")
check("never revert a revert (branch)", action(pr={**PR, "head_ref": "revert-12-add-x"}), "alert")
check("never revert a revert (git default title)", action(commit_title='Revert "feat: add x" (#13)'), "alert")
check("never revert a Renovate PR", action(pr={**PR, "author": "cocreiamo-claude-code-pr[bot]", "head_ref": "renovate/x"}), "alert")
check("never revert any bot PR", action(pr={**PR, "author": "cocreiamo-image-updater[bot]"}), "alert")
check("no PR behind the commit: alert only", action(pr=None), "alert")
for name in ("skip", "alert", "revert"):
    assert prm.decide(facts(**({"head_green": True} if name == "skip" else {"pr": None} if name == "alert" else {})))["reason"]

SC = {}
LOG = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        LOG.append(("GET", self.path, None))
        p = self.path
        if "/actions/" in p and (SC["runs_forbidden"] or self.headers["Authorization"] != "Bearer readtok"):
            self.reply(403, {"message": "Resource not accessible by integration"})
        elif SC["ref_fails"] and p.endswith("/git/ref/heads/main"):
            self.reply(500, {})
        elif p.endswith("/git/ref/heads/main"):
            self.reply(200, {"object": {"sha": SC["head"]}})
        elif p.endswith("/actions/runs/1"):
            self.reply(200, {"workflow_id": 5, "created_at": "2026-01-02T00:00:00Z"})
        elif "/actions/workflows/5/runs" in p:
            self.reply(200, {"workflow_runs": SC["runs"] + [{"id": i + 10, "created_at": "2025-12-%02dT00:00:00Z" % (10 + len(SC["chain"]) - i), "conclusion": c, "head_sha": s}
                                                             for i, (s, c) in enumerate(SC["chain"]) if c != "missing"]})
        elif p.endswith("/pulls") and "/commits/" in p:
            sha = p.split("/commits/")[1].split("/")[0]
            i = SC["shas"].index(sha) if sha in SC["shas"] else -1
            n, t, node = (100 + i, "feat: change " + sha[:1], "PR_" + sha[:1]) if i >= 0 else (12, "feat: add x", "PR_node")
            self.reply(200, [{"number": n, "title": t, "merged_at": "t", "merge_commit_sha": sha, "node_id": node,
                              "head": {"ref": SC["ref"]}, "user": {"login": SC["author"]}}] if SC["pr"] else [])
        elif "/commits/" in p:
            sha = p.split("/commits/")[1]
            i = SC["shas"].index(sha) if sha in SC["shas"] else -1
            parents = [{"sha": SC["shas"][i + 1]}] if 0 <= i < len(SC["shas"]) - 1 else []
            self.reply(200, {"commit": {"message": ("feat: change %s (#%d)" % (sha[:1], 100 + i) if i >= 0 else "feat: add x (#12)") + "\n\nbody"}, "parents": parents})
        elif "/issues?labels=main-red" in p:
            j = SC["judged"]
            title = "main is red: feat: change %s (#%d)" % (j[:1], 100 + SC["shas"].index(j)) if j in SC["shas"] else "main is red: feat: add x (#12)"
            self.reply(200, [{"number": 55, "title": title}] if SC["known_issue"] else [])
        elif "/pulls?state=open" in p:
            self.reply(200, [{"number": 99, "body": "<!-- post-merge-revert:" + SC["open_for"] + " -->"}] if SC["open"] else [])
        else:
            self.reply(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"]) or 0) or "null")
        LOG.append(("POST", self.path, body))
        if "/rerun-failed-jobs" in self.path:
            return self.reply(SC["rerun_status"], {})
        if self.headers["Authorization"] != "Bearer tok":
            return self.reply(401, {})
        if self.path == "/graphql":
            if "revertPullRequest" in body["query"]:
                if SC["revert_fails"]:
                    return self.reply(200, {"errors": [{"message": "conflict"}]})
                return self.reply(200, {"data": {"revertPullRequest": {"revertPullRequest": {"id": "NEW_node", "number": 78, "url": "https://x/78"}}}})
            return self.reply(200, {"data": {}})
        if self.path.endswith("/issues"):
            return self.reply(201, {"number": 77})
        self.reply(201, {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(dry=False, sha=SHA, attempt="", retry="", ignore="", **kw):
    SC.clear()
    SC.update({"head": SHA, "ref": "add-x", "author": "iambilotta", "pr": True, "open": False, "revert_fails": False, "runs": [], "runs_forbidden": False, "ref_fails": False,
               "chain": [], "shas": [], "open_for": SHA, "rerun_status": 201, "known_issue": False, "judged": sha})
    SC.update(kw)
    del LOG[:]
    env = {
        "PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "READ_TOKEN": "readtok", "REPO": "cocreiamo/x", "SHA": sha, "RUN_ATTEMPT": attempt, "RETRY": retry, "IGNORE_HEAD_GREEN": ignore,
        "FAILED": "fast, slow-lint", "RUN_URL": "https://github.com/cocreiamo/x/actions/runs/1", "ASSIGNEE": "iambilotta",
        "DRY_RUN": "true" if dry else "false",
    }
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    return r, list(LOG)


def mutating(calls):
    return [c for c in calls if c[0] != "GET"]


r, calls = run()
check("the real flow succeeds", r.returncode, 0)
text = json.dumps(calls)
for needle in ("revertPullRequest", "revert: feat: add x", "Closes #77", "post-merge-revert:" + SHA, "fast, slow-lint", "actions/runs/1", '"assignees": ["iambilotta"]', '"labels": ["main-red"]'):
    if needle not in text:
        sys.exit(f"FAIL: the real flow never sent {needle!r}: {text}")
if not any(c[1] == "/graphql" and "enablePullRequestAutoMerge" in c[2]["query"] and c[2]["variables"] == {"id": "NEW_node"} and "SQUASH" in c[2]["query"] for c in calls):
    sys.exit("FAIL: the revert PR is not set to auto-merge")
if not any(c[1].endswith("/issues/12/comments") for c in calls):
    sys.exit("FAIL: the original PR got no comment")

r, calls = run(dry=True)
check("a dry run succeeds", r.returncode, 0)
check("a dry run mutates nothing", mutating(calls), [])
if "would revert" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)

r, calls = run(head=OTHER)
check("main moved on, first red of its streak: succeeds", r.returncode, 0)
check("main moved on, first red of its streak: reverted", "revertPullRequest" in json.dumps(calls), True)

OLD_OK = {"created_at": "2026-01-01T00:00:00Z", "conclusion": "success", "head_sha": OTHER}
NEW_OK = {"created_at": "2026-01-03T00:00:00Z", "conclusion": "success", "head_sha": OTHER}
NEW_RED = {"created_at": "2026-01-03T00:00:00Z", "conclusion": "failure", "head_sha": OTHER}
r, calls = run(runs=[NEW_OK])
check("main is green again: succeeds", r.returncode, 0)
check("main is green again: nothing mutated", mutating(calls), [])
r, calls = run(runs=[OLD_OK, NEW_RED])
check("a green run before the commit and a red one after it: reverted", "revertPullRequest" in json.dumps(calls), True)

HEAD_OK = {"created_at": "2025-12-31T00:00:00Z", "conclusion": "success", "head_sha": SHA}
r, calls = run(runs=[HEAD_OK])
check("main is green at its head: succeeds", r.returncode, 0)
check("main is green at its head: nothing mutated", mutating(calls), [])

r, calls = run(dry=True, ignore="true", runs=[HEAD_OK, NEW_OK])
check("ignore-head-green: a dry run on a green main still decides", r.returncode, 0)
if "would revert" not in r.stdout:
    sys.exit("FAIL: ignore-head-green does not exercise the whole decision: " + r.stdout)
check("ignore-head-green: a dry run mutates nothing", mutating(calls), [])
r, calls = run(dry=True, runs=[HEAD_OK, NEW_OK])
check("without ignore-head-green a green main is skipped", "would revert" in r.stdout, False)
r, calls = run(ignore="true", runs=[HEAD_OK])
check("ignore-head-green never reverts for real", mutating(calls), [])

r, calls = run(open=True)
check("revert already open: nothing mutated", mutating(calls), [])

r, calls = run(author="cocreiamo-claude-code-pr[bot]", ref="renovate/x")
check("renovate: succeeds", r.returncode, 0)
text = json.dumps(calls)
if "revertPullRequest" in text or "main-red" not in text:
    sys.exit("FAIL: a Renovate PR must raise the alert and never be reverted: " + text)

r, calls = run(pr=False)
if "revertPullRequest" in json.dumps(calls) or "main-red" not in json.dumps(calls):
    sys.exit("FAIL: a commit with no PR must alert only")

r, calls = run(revert_fails=True)
check("a revert that cannot be made fails the job", r.returncode != 0, True)
if "main-red" not in json.dumps(calls) or not any(c[1].endswith("/issues/77/comments") for c in calls):
    sys.exit("FAIL: the alert must go out before the revert is tried, and say when it failed")
r, calls = run(runs_forbidden=True)
check("runs unreadable: the decision still goes on and reverts", r.returncode, 0)
check("runs unreadable: reverted", "revertPullRequest" in json.dumps(calls), True)
check("the runs API is never called with the App token", [c for c in calls if "/actions/" in c[1]] != [], True)

r, calls = run(ref_fails=True)
check("a failure inside the decision fails the job", r.returncode != 0, True)
issues = [c for c in calls if c[0] == "POST" and c[1].endswith("/issues")]
if len(issues) != 1 or "main-red" not in json.dumps(issues) or "revertPullRequest" in json.dumps(calls):
    sys.exit("FAIL: an exception in the decision must raise the alert and revert nothing: " + json.dumps(calls))

G, C, R1, R2 = "1" * 40, "2" * 40, "3" * 40, "4" * 40
CH = "cocreiamo/x/actions/runs/"


def reverted(calls):
    return [c[2]["variables"]["id"] for c in calls if c[1] == "/graphql" and "revertPullRequest" in c[2]["query"]]


def reruns(calls):
    return [c[1].split("/actions/runs/")[1].split("/")[0] for c in calls if "/rerun-failed-jobs" in c[1]]


def chain(*pairs):
    shas = [s for s, _ in pairs]
    return {"chain": list(pairs), "shas": shas, "head": shas[0]}


# green, cancelled, red, red: the red run of the last commit blames nobody
r, calls = run(sha=R2, **chain((R2, "failure"), (R1, "failure"), (C, "cancelled"), (G, "success")))
check("green, cancelled, red, red: the second red is not reverted", reverted(calls), [])
check("green, cancelled, red, red: the alert goes out", "main-red" in json.dumps(calls), True)
check("green, cancelled, red, red: succeeds", r.returncode, 0)
r, calls = run(sha=R1, **chain((R2, "failure"), (R1, "failure"), (C, "cancelled"), (G, "success")))
check("green, cancelled, red: the red after an unverified commit is not reverted", reverted(calls), [])
r, calls = run(sha=C, **chain((R2, "failure"), (R1, "failure"), (C, "failure"), (G, "success")))
check("the first red of the streak is reverted even when main moved on", reverted(calls), ["PR_2"])
r, calls = run(sha=R2, **chain((R2, "failure"), (R1, "success")))
check("a red after a green commit is reverted", reverted(calls), ["PR_4"])

# the incident of 2026-11-08: first red skipped as main moved on, second cancelled, third red
r, calls = run(sha=R1, **chain((R2, "failure"), (C, "cancelled"), (R1, "failure"), (G, "success")))
check("incident: the first red is reverted although two commits followed", reverted(calls), ["PR_3"])
r, calls = run(sha=R2, **chain((R2, "failure"), (C, "cancelled"), (R1, "failure"), (G, "success")))
check("incident: the last red is not reverted", reverted(calls), [])
r, calls = run(sha=R1, open=True, open_for=R1, **chain((R2, "failure"), (C, "cancelled"), (R1, "failure"), (G, "success")))
check("incident: a revert of the first red already open", reverted(calls), [])
r, calls = run(sha=C, **chain((C, "failure"), (R1, "in_progress"), (G, "success")))
check("an unfinished parent run counts as unknown", reverted(calls), [])

r, calls = run(sha=R1, **chain((R2, "failure"), (R1, "failure"), (C, "failure"), (G, "success")))
check("main moved on, a later red of the streak: nothing mutated", mutating(calls), [])

r, calls = run(sha=R2, **chain((R2, "failure"), (R1, "missing"), (G, "success")))
check("a commit with no run is stepped over, not unknown", reverted(calls), ["PR_4"])

# a transient failure: with retry the first attempt only alerts, the repeat decides
r, calls = run(sha=R2, attempt="1", retry="true", **chain((R2, "failure"), (R1, "success")))
check("retry, attempt 1: nothing is reverted", reverted(calls), [])
check("retry, attempt 1: the alert goes out", "main-red" in json.dumps(calls), True)
check("retry, attempt 1: succeeds", r.returncode, 0)
r, calls = run(sha=R2, attempt="2", retry="true", **chain((R2, "failure"), (R1, "success")))
check("retry, attempt 2: the repeat is red, reverted", reverted(calls), ["PR_4"])
r, calls = run(sha=R2, attempt="1", **chain((R2, "failure"), (R1, "success")))
check("no retry configured, attempt 1: judged at once", reverted(calls), ["PR_4"])
r, calls = run(sha=R2, attempt="2", retry="true", known_issue=True, **chain((R2, "failure"), (R1, "success")))
check("an open issue of the same title is reused", [c for c in calls if c[0] == "POST" and c[1].endswith("/issues")], [])
check("an open issue of the same title gets the comment", any(c[1].endswith("/issues/55/comments") for c in calls), True)
check("the revert closes the reused issue", "Closes #55" in json.dumps(calls), True)
r, calls = run(sha=R2, **chain((R2, "failure"), (R1, "failure"), (C, "cancelled"), (G, "success")))
check("an unverified first commit is rerun", reruns(calls), ["12"])
r, calls = run(dry=True, sha=R2, **chain((R2, "failure"), (R1, "failure"), (C, "cancelled"), (G, "success")))
check("a dry run reruns nothing", reruns(calls), [])
print("python cases ok")
