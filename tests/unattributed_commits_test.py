import http.server, json, os, subprocess, sys, threading

DIR = sys.argv[1]
SC = {}


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def commit(sha, login, name, email):
    return {"sha": sha * 40, "author": {"login": login} if login else None, "commit": {"author": {"name": name, "email": email}}}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/repos/cocreiamo/x/compare/base...head?"):
            page = int(self.path.split("page=")[1].split("&")[0])
            per = int(self.path.split("per_page=")[1].split("&")[0])
            raw = json.dumps({"commits": SC["commits"][(page - 1) * per:page * per]}).encode()
            self.send_response(200)
        else:
            raw = b"{}"
            self.send_response(404)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(commits):
    SC["commits"] = commits
    env = {"PATH": os.environ["PATH"], "HOME": "/nonexistent", "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok",
           "REPO": "cocreiamo/x", "BASE_SHA": "base", "HEAD_SHA": "head", "PER_PAGE": "2"}
    r = subprocess.run([sys.executable, "-I", DIR + "/unattributed_commits.py"], env=env, capture_output=True, text=True, cwd=DIR)
    return r.returncode, r.stdout + r.stderr


good = commit("1", "me", "Me", "me@cocreiamo.com")
rc, out = run([good, commit("2", "you", "You", "you@b.it")])
check("attributed commits pass", rc, 0)

rc, out = run([good, commit("a", None, "T", "t@gmail.com")])
check("a commit GitHub maps to no user fails", rc, 1)
for want in ("a" * 10, "t@gmail.com", "no GitHub user", "squash", "force push"):
    if want not in out:
        sys.exit("FAIL: the message does not say %r: %s" % (want, out))
if "1" * 10 in out:
    sys.exit("FAIL: the message names an attributed commit: " + out)

rc, out = run([commit("a", None, "A", "a@x.io"), good, commit("b", None, "B", "b@y.io")])
check("every offending commit is named, across pages", (rc, "a" * 10 in out, "b" * 10 in out), (1, True, True))

rc, out = run([commit("c", None, "renovate[bot]", "1+renovate[bot]@users.noreply.github.com")])
check("an unmapped bot author is not a failure", rc, 0)

for email in ("t@example.invalid", "t@EXAMPLE.COM", "ci@runner.test", "x@a.b.example", "x@localhost"):
    rc, out = run([commit("d", "me", "Me", email)])
    check("a mapped author on the reserved domain of %s fails" % email, rc, 1)
    if email not in out or "reserved test domain" not in out:
        sys.exit("FAIL: the message does not name %s and the reserved domain: %s" % (email, out))

rc, out = run([commit("e", "me", "Me", "me@notexample.com")])
check("a lookalike domain passes", rc, 0)

rc, out = run([])
check("no commit passes", rc, 0)

SC["commits"] = [good]
env = {"PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "REPO": "cocreiamo/x", "BASE_SHA": "nope", "HEAD_SHA": "head"}
r = subprocess.run([sys.executable, "-I", DIR + "/unattributed_commits.py"], env=env, capture_output=True, text=True, cwd=DIR)
check("an unreadable comparison fails the check instead of passing it", r.returncode != 0, True)
