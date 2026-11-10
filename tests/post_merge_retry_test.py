import http.server, json, os, subprocess, sys, threading

LOG = []
SC = {}


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
        LOG.append(("GET", self.path))
        self.reply(200, {"run_attempt": SC["attempt"], "conclusion": SC["conclusion"]})

    def do_POST(self):
        LOG.append(("POST", self.path))
        if self.headers["Authorization"] != "Bearer tok":
            return self.reply(401, {})
        self.reply(SC["rerun_status"], {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(dry=False, attempt=1, conclusion="failure", rerun_status=201):
    SC.clear()
    SC.update({"attempt": attempt, "conclusion": conclusion, "rerun_status": rerun_status})
    del LOG[:]
    env = {"PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "REPO": "cocreiamo/x", "RUN_ID": "7", "DRY_RUN": "true" if dry else "false"}
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    return r.returncode, [c for c in LOG if c[0] == "POST"]


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


RERUN = [("POST", "/repos/cocreiamo/x/actions/runs/7/rerun-failed-jobs")]
check("a red first attempt is repeated", run(), (0, RERUN))
check("a second attempt is never repeated", run(attempt=2), (0, []))
check("a green run is not repeated", run(conclusion="success"), (0, []))
check("a cancelled run is not repeated", run(conclusion="cancelled"), (0, []))
check("a dry run repeats nothing", run(dry=True), (0, []))
code, posts = run(rerun_status=403)
check("a refused repeat fails the job", (code != 0, posts), (True, RERUN))
print("python cases ok")
