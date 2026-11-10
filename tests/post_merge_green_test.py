import http.server, json, os, subprocess, sys, threading

RED, GREEN, SIDE = "a" * 40, "c" * 40, "d" * 40
LOG = []
SC = {}


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def pr(number, sha, body_extra="Closes #77", head_ref="revert-12-add-x", node="N"):
    return {"number": number, "node_id": node + str(number), "head": {"ref": head_ref}, "body": "Reverts #12.\n\n%s\n\n<!-- post-merge-revert:%s -->" % (body_extra, sha)}


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
        if "/pulls?state=open" in p:
            if SC["list_fails"]:
                return self.reply(500, {})
            return self.reply(200, SC["open"])
        if "/issues?labels=main-red" in p:
            return self.reply(200, SC["issues"])
        if "/compare/" in p:
            base = p.split("/compare/")[1].split("...")[0]
            return self.reply(200, {"status": SC["compare"].get(base, "diverged")})
        self.reply(404, {})

    def send_body(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.append((self.command, self.path, body))
        if self.headers["Authorization"] != "Bearer tok":
            self.reply(401, {})
            return None
        return body

    def do_POST(self):
        body = self.send_body()
        if body is None:
            return
        if self.path == "/graphql":
            if SC["disable_fails"]:
                return self.reply(200, {"errors": [{"message": "auto merge is not enabled"}]})
            return self.reply(200, {"data": {}})
        self.reply(201, {"number": 90})

    def do_PATCH(self):
        body = self.send_body()
        if body is None:
            return
        self.reply(200, {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(dry=False, **kw):
    SC.clear()
    SC.update({"open": [pr(78, RED)], "compare": {RED: "ahead"}, "issues": [], "list_fails": False, "disable_fails": False})
    SC.update(kw)
    del LOG[:]
    env = {
        "PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "REPO": "cocreiamo/x", "SHA": GREEN,
        "RUN_URL": "https://github.com/cocreiamo/x/actions/runs/2", "ASSIGNEE": "iambilotta", "DRY_RUN": "true" if dry else "false",
    }
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    return r, list(LOG)


def mutating(calls):
    return [c for c in calls if c[0] != "GET"]


r, calls = run()
check("a revert of an earlier red commit is closed: succeeds", r.returncode, 0)
text = json.dumps(calls)
for needle in ("disablePullRequestAutoMerge", GREEN, "actions/runs/2"):
    if needle not in text:
        sys.exit(f"FAIL: the close never sent {needle!r}: {text}")
if not any(c[0] == "PATCH" and c[1].endswith("/pulls/78") and c[2] == {"state": "closed"} for c in calls):
    sys.exit("FAIL: the revert PR is not closed: " + text)
if not any(c[1].endswith("/issues/78/comments") and GREEN in c[2]["body"] for c in calls):
    sys.exit("FAIL: the revert PR got no comment naming the green commit: " + text)
if not any(c[0] == "PATCH" and c[1].endswith("/issues/77") and c[2].get("state") == "closed" for c in calls):
    sys.exit("FAIL: the main-red issue is left open: " + text)
disable = [i for i, c in enumerate(calls) if c[1] == "/graphql"]
close = [i for i, c in enumerate(calls) if c[0] == "PATCH" and c[1].endswith("/pulls/78")]
if not disable or disable[0] > close[0]:
    sys.exit("FAIL: auto-merge must be switched off before the PR is closed")

r, calls = run(dry=True)
check("a dry run succeeds", r.returncode, 0)
check("a dry run mutates nothing", mutating(calls), [])
if "would close" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)

r, calls = run(compare={RED: "behind"})
check("the green commit is older than the red one: succeeds", r.returncode, 0)
check("the green commit is older than the red one: nothing mutated", mutating(calls), [])
r, calls = run(compare={RED: "diverged"})
check("the green commit is on another line: nothing mutated", mutating(calls), [])
r, calls = run(compare={RED: "identical"})
check("the green commit is the red one: nothing mutated", mutating(calls), [])

r, calls = run(open=[{"number": 5, "node_id": "X", "head": {"ref": "feat/x"}, "body": "no marker"}])
check("a PR without the marker is left alone", mutating(calls), [])

r, calls = run(open=[pr(78, RED), pr(79, SIDE)], compare={RED: "ahead", SIDE: "behind"})
check("only the revert of an ancestor is closed", sorted(c[1].rsplit("/", 1)[1] for c in calls if c[0] == "PATCH" and "/pulls/" in c[1]), ["78"])

r, calls = run(open=[pr(78, RED, body_extra="no issue")])
check("a revert with no linked issue is closed alone", r.returncode, 0)
check("a revert with no linked issue: no issue patched", [c for c in calls if c[0] == "PATCH" and "/issues/" in c[1]], [])

r, calls = run(disable_fails=True)
check("auto-merge already off: the PR is still closed", any(c[0] == "PATCH" and c[1].endswith("/pulls/78") for c in calls), True)
check("auto-merge already off: succeeds", r.returncode, 0)

r, calls = run(list_fails=True)
check("an unreadable list fails the job", r.returncode != 0, True)
issues = [c for c in calls if c[0] == "POST" and c[1].endswith("/issues")]
if len(issues) != 1 or "main-red" not in json.dumps(issues):
    sys.exit("FAIL: a failure to close must raise the alert: " + json.dumps(calls))

def issue(number, sha, body="The required job(s) fast failed on the merge commit %s of PR #12 (feat: x) on main: https://github.com/cocreiamo/x/actions/runs/1", **kw):
    return {"number": number, "title": "main is red: feat: x (#12)", "body": body % sha if "%s" in body else body, **kw}


def closed_issues(calls):
    return sorted(c[1].rsplit("/", 1)[1] for c in calls if c[0] == "PATCH" and "/issues/" in c[1] and c[2].get("state") == "closed")


# a main-red issue is closed when the green commit contains its commit, with or without a revert PR
r, calls = run(open=[], issues=[issue(348, RED)])
check("an issue of an earlier red commit is closed", closed_issues(calls), ["348"])
if not any(c[1].endswith("/issues/348/comments") and GREEN in c[2]["body"] for c in calls):
    sys.exit("FAIL: the issue got no comment naming the green commit: " + json.dumps(calls))
check("a closed issue is completed", [c[2]["state_reason"] for c in calls if c[0] == "PATCH" and c[1].endswith("/issues/348")], ["completed"])
r, calls = run(open=[], compare={RED: "identical"}, issues=[issue(348, RED)])
check("an issue of the green commit itself (a repeat that passed) is closed", closed_issues(calls), ["348"])
r, calls = run(open=[], compare={RED: "behind"}, issues=[issue(348, RED)])
check("an issue of a newer commit stays open", mutating(calls), [])
r, calls = run(open=[], compare={RED: "diverged"}, issues=[issue(348, RED)])
check("an issue of another line stays open", mutating(calls), [])
r, calls = run(open=[], issues=[issue(349, RED, body="The job publish failed on %s on main: https://x")])
check("an alert of a job that is never reverted stays open", mutating(calls), [])
r, calls = run(open=[], issues=[issue(350, RED, body="no commit here")])
check("an issue naming no commit stays open", mutating(calls), [])
r, calls = run(open=[], issues=[issue(351, RED, pull_request={"url": "x"})])
check("a pull request is never closed as an issue", mutating(calls), [])
r, calls = run(open=[], issues=[issue(348, RED)], dry=True)
check("a dry run closes no issue", mutating(calls), [])
if "would close issue #348" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)
r, calls = run(issues=[issue(77, RED)])
check("the issue a closed revert links is closed once", closed_issues(calls), ["77"])
r, calls = run(open=[], issues=[issue(348, RED), issue(349, SIDE)], compare={RED: "ahead", SIDE: "behind"})
check("only the issues of ancestors are closed", closed_issues(calls), ["348"])
print("python cases ok")
