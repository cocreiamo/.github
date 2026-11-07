import http.server, importlib.util, json, os, subprocess, sys, threading

spec = importlib.util.spec_from_file_location("prm", sys.argv[1])
prm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prm)

SHA, OTHER = "a" * 40, "b" * 40
PR = {"number": 12, "title": "feat: add x", "head_ref": "add-x", "author": "iambilotta", "node_id": "PR_node"}


def facts(**kw):
    f = {"sha": SHA, "head_sha": SHA, "commit_title": "feat: add x (#12)", "pr": dict(PR), "open_revert": False, "moved_ok": False, "green_after": False}
    f.update(kw)
    return f


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def action(**kw):
    return prm.decide(facts(**kw))["action"]


check("a human PR on the head of main is reverted", action(), "revert")
check("main moved on: skip", action(head_sha=OTHER), "skip")
check("main moved on but the caller judges a commit that is no longer the head: revert", action(head_sha=OTHER, moved_ok=True), "revert")
check("moved_ok never reverts a revert", action(head_sha=OTHER, moved_ok=True, commit_title="revert: feat: add x (#13)"), "alert")
check("moved_ok still skips a revert already open", action(head_sha=OTHER, moved_ok=True, open_revert=True), "skip")
check("main is green again after the commit: skip", action(green_after=True), "skip")
check("green again wins over a revert-worthy PR even when main moved", action(green_after=True, head_sha=OTHER, moved_ok=True), "skip")
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
            self.reply(200, {"workflow_runs": SC["runs"]})
        elif p.endswith("/pulls") and "/commits/" in p:
            self.reply(200, [{"number": 12, "title": "feat: add x", "merged_at": "t", "merge_commit_sha": SHA, "node_id": "PR_node",
                              "head": {"ref": SC["ref"]}, "user": {"login": SC["author"]}}] if SC["pr"] else [])
        elif "/commits/" in p:
            self.reply(200, {"commit": {"message": "feat: add x (#12)\n\nbody"}})
        elif "/pulls?state=open" in p:
            self.reply(200, [{"number": 99, "body": "<!-- post-merge-revert:" + SHA + " -->"}] if SC["open"] else [])
        else:
            self.reply(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.append(("POST", self.path, body))
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


def run(dry=False, **kw):
    SC.clear()
    SC.update({"head": SHA, "ref": "add-x", "author": "iambilotta", "pr": True, "open": False, "revert_fails": False, "runs": [], "runs_forbidden": False, "ref_fails": False})
    SC.update(kw)
    del LOG[:]
    env = {
        "PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "READ_TOKEN": "readtok", "REPO": "cocreiamo/x", "SHA": SHA,
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
check("main moved on: succeeds", r.returncode, 0)
check("main moved on: nothing mutated", mutating(calls), [])

OLD_OK = {"created_at": "2026-01-01T00:00:00Z", "conclusion": "success", "head_sha": OTHER}
NEW_OK = {"created_at": "2026-01-03T00:00:00Z", "conclusion": "success", "head_sha": OTHER}
NEW_RED = {"created_at": "2026-01-03T00:00:00Z", "conclusion": "failure", "head_sha": OTHER}
r, calls = run(runs=[NEW_OK])
check("main is green again: succeeds", r.returncode, 0)
check("main is green again: nothing mutated", mutating(calls), [])
r, calls = run(runs=[OLD_OK, NEW_RED])
check("a green run before the commit and a red one after it: reverted", "revertPullRequest" in json.dumps(calls), True)

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
print("python cases ok")
