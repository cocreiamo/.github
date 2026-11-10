import http.server, json, os, subprocess, sys, threading

SHA = "a" * 40
LOG_TEXT = "\n".join(["2026-11-07T10:00:%02dZ step line %d" % (i % 60, i) for i in range(100)]
                     + ["2026-11-07T10:01:00Z \x1b[31mError: gh: command not found\x1b[0m", "2026-11-07T10:01:01Z ##[error]Process completed with exit code 127."])
SC = {}
LOG = []


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj=None, raw=None, headers=()):
        raw = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        LOG.append(("GET", self.path, None, self.headers.get("Authorization")))
        p = self.path
        if p.startswith("/blob/"):
            if self.headers.get("Authorization"):
                return self.reply(403, {})
            return self.reply(200, raw=LOG_TEXT.encode())
        if p.endswith("/actions/runs/1/jobs?per_page=100"):
            return self.reply(200, {"jobs": [{"id": 5, "name": "build", "conclusion": "success"}, {"id": 6, "name": "publish", "conclusion": "failure"}]})
        if p.endswith("/actions/jobs/6/logs"):
            if SC["logs_fail"]:
                return self.reply(410, {})
            return self.reply(302, {}, headers=[("Location", "http://127.0.0.1:%d/blob/6" % server.server_port)])
        if "/issues?state=open" in p:
            return self.reply(200, [{"number": 40, "body": "<!-- post-merge-alert:publish -->"}, {"number": 41, "body": "<!-- post-merge-alert:other -->"}] if SC["open"] else [])
        self.reply(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.append(("POST", self.path, body, self.headers.get("Authorization")))
        if self.headers["Authorization"] != "Bearer app":
            return self.reply(401, {})
        if self.path.endswith("/issues"):
            return self.reply(201, {"number": 77})
        self.reply(201, {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(dry=False, failed="publish", prefix="main is red: ", label="main-red", app_failed=False, **kw):
    SC.clear()
    SC.update({"open": False, "logs_fail": False})
    SC.update(kw)
    del LOG[:]
    env = {
        "PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "app", "READ_TOKEN": "read", "REPO": "cocreiamo/x",
        "SHA": SHA, "FAILED": failed, "RUN_ID": "1", "RUN_URL": "https://github.com/cocreiamo/x/actions/runs/1", "ASSIGNEE": "iambilotta",
        "DRY_RUN": "true" if dry else "false", "TITLE_PREFIX": prefix, "LABEL": label,
        "APP_TOKEN_FAILED": "true" if app_failed else "false",
    }
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    return r, list(LOG)


def mutating(calls):
    return [c for c in calls if c[0] != "GET"]


r, calls = run(app_failed=True)
check("a dead App token still alerts", r.returncode, 0)
issue = [c for c in mutating(calls) if c[1].endswith("/issues")]
check("the issue is opened", len(issue), 1)
check("the issue says the App token failed", "App token" in issue[0][2]["body"], True)
r, calls = run()
check("a healthy token says nothing about it", any("App token" in (c[2] or {}).get("body", "") for c in mutating(calls) if isinstance(c[2], dict)), False)

r, calls = run()
check("a failed job alerts", r.returncode, 0)
posts = mutating(calls)
check("one issue", [c[1] for c in posts if c[1].endswith("/issues")], ["/repos/cocreiamo/x/issues"])
issue = next(c[2] for c in posts if c[1].endswith("/issues"))
check("issue assignee", issue["assignees"], ["iambilotta"])
check("issue label", issue["labels"], ["main-red"])
for needle in ("publish", "actions/runs/1", "gh: command not found", "exit code 127", "post-merge-alert:publish", SHA):
    if needle not in issue["title"] + issue["body"]:
        sys.exit(f"FAIL: the issue lacks {needle!r}: {issue}")
if "\x1b" in issue["body"] or "step line 3" in issue["body"]:
    sys.exit("FAIL: the issue must carry the failing lines, clean of colour codes, not the whole log: " + issue["body"])
if any(c[1].endswith("/comments") for c in posts):
    sys.exit("FAIL: a new alert must not comment")
if any(c[1] == "/graphql" for c in calls):
    sys.exit("FAIL: an alert never uses graphql")

r, calls = run(open=True)
check("a repeat failure succeeds", r.returncode, 0)
posts = mutating(calls)
check("a repeat failure opens no second issue", [c for c in posts if c[1].endswith("/issues")], [])
check("a repeat failure comments on the open issue", [c[1] for c in posts], ["/repos/cocreiamo/x/issues/40/comments"])
if "actions/runs/1" not in posts[0][2]["body"] or "gh: command not found" not in posts[0][2]["body"]:
    sys.exit("FAIL: the comment lacks the run link or the failing lines")

r, calls = run(logs_fail=True)
check("logs that cannot be read still alert", r.returncode, 0)
issue = next(c[2] for c in mutating(calls) if c[1].endswith("/issues"))
if "actions/runs/1" not in issue["body"]:
    sys.exit("FAIL: the alert without logs lacks the run link")

r, calls = run(failed="publish other", open=True)
check("two failed jobs: success", r.returncode, 0)
check("two failed jobs: one comment on each open issue", sorted(c[1] for c in mutating(calls)),
      ["/repos/cocreiamo/x/issues/40/comments", "/repos/cocreiamo/x/issues/41/comments"])

r, calls = run(prefix="drill: ", label="drill")
check("a drill alert succeeds", r.returncode, 0)
issue = next(c[2] for c in mutating(calls) if c[1].endswith("/issues"))
check("a drill issue title", issue["title"], "drill: publish failed")
check("a drill issue label", issue["labels"], ["drill"])
if not any("labels=drill" in c[1] for c in calls if c[0] == "GET"):
    sys.exit("FAIL: a drill looks for open issues by its own label")

r, calls = run(dry=True)
check("a dry run succeeds", r.returncode, 0)
check("a dry run mutates nothing", mutating(calls), [])
if "would" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)
print("python cases ok")
