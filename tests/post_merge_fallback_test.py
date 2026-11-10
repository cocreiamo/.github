import http.server, json, os, subprocess, sys, threading

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
        self.reply(200, [])

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.append(("POST", self.path, body, self.headers["Authorization"]))
        self.reply(201, {"number": 9})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = {"PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "run", "REPO": "cocreiamo/x", "SHA": "a" * 40,
       "FAILED": "build", "ASSIGNEE": "iambilotta", "RUN_URL": "https://github.com/cocreiamo/x/actions/runs/1"}
r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
issues = [c for c in LOG if c[0] == "POST" and c[1].endswith("/issues")]
if len(issues) != 1 or "App token" not in issues[0][2]["body"] or issues[0][3] != "Bearer run" or issues[0][2]["labels"] != ["main-red"]:
    sys.exit("FAIL: the fallback must open one main-red issue with the run token saying the App token failed: %r" % LOG)
if r.returncode == 0:
    sys.exit("FAIL: the fallback job must end red")
print("post-merge fallback ok")
