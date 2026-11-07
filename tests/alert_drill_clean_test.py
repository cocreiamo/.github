import http.server, json, os, subprocess, sys, threading

LOG = []
RUN_URL = "https://github.com/cocreiamo/x/actions/runs/9"
ISSUES = [
    {"number": 10, "labels": [{"name": "drill"}]},
    {"number": 11, "labels": [{"name": "drill"}]},
    {"number": 12, "labels": [{"name": "drill"}, {"name": "main-red"}]},
    {"number": 13, "labels": [{"name": "main-red"}]},
    {"number": 14, "labels": [{"name": "drill"}], "pull_request": {}},
]


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n)) if n else None

    def do_GET(self):
        LOG.append(("GET", self.path, None))
        if "/issues?state=open&labels=drill" in self.path:
            return self.reply(200, ISSUES)
        self.reply(404, {})

    def do_POST(self):
        LOG.append(("POST", self.path, self.body()))
        self.reply(201, {})

    def do_PATCH(self):
        LOG.append(("PATCH", self.path, self.body()))
        self.reply(200, {})

    def do_DELETE(self):
        LOG.append(("DELETE", self.path, None))
        self.reply(204, {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

env = {"PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "app", "REPO": "cocreiamo/x", "RUN_URL": RUN_URL}
r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
check("the cleanup succeeds", r.returncode, 0)
writes = [c for c in LOG if c[0] != "GET"]
check("nothing is deleted", [c for c in writes if c[0] == "DELETE"], [])
touched = sorted({c[1].split("/")[5] for c in writes})
check("only open drill issues without main-red are touched", touched, ["10", "11"])
for n in ("10", "11"):
    comment = [c for c in writes if c[1] == "/repos/cocreiamo/x/issues/%s/comments" % n]
    check("one comment on #" + n, len(comment), 1)
    check("comment text on #" + n, comment[0][2]["body"], "closed by the next drill run " + RUN_URL)
    patch = [c for c in writes if c[0] == "PATCH" and c[1] == "/repos/cocreiamo/x/issues/" + n]
    check("#%s is closed, not deleted" % n, [c[2]["state"] for c in patch], ["closed"])
    if [c[0] for c in writes if c[1].endswith("/" + n + "/comments") or c[1].endswith("/" + n)] != ["POST", "PATCH"]:
        sys.exit("FAIL: #%s must be commented, then closed" % n)

ISSUES[:] = []
del LOG[:]
r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
check("no stale issue: success", r.returncode, 0)
check("no stale issue: no write", [c for c in LOG if c[0] != "GET"], [])
