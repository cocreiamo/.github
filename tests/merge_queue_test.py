import http.server, json, os, subprocess, sys, threading

LOG = []
SC = {}
CTX = ["ci", "title / check", "rules / check"]


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL: {name}: got {got!r}, want {want!r}")


def sha(n):
    return str(n).rjust(40, "0")


def pull(n, state="behind", auto=True, draft=False, runs="green"):
    return {"number": n, "head": {"sha": sha(n)}, "auto_merge": {"merge_method": "squash"} if auto else None, "draft": draft,
            "created_at": "2026-11-10T10:%02d:00Z" % n, "state": state, "runs": runs}


def check_runs(runs):
    if runs == "pending":
        return [{"name": c, "id": i, "conclusion": "success" if i else None, "status": "completed" if i else "in_progress"} for i, c in enumerate(CTX)]
    if runs == "failed":
        return [{"name": CTX[0], "id": 1, "conclusion": "failure", "status": "completed"}] + [{"name": c, "id": 1, "conclusion": "success", "status": "completed"} for c in CTX[1:]]
    if runs == "rerun":
        return [{"name": CTX[0], "id": 1, "conclusion": "failure", "status": "completed"}] + [{"name": c, "id": 2, "conclusion": "success", "status": "completed"} for c in CTX]
    return [{"name": c, "id": 1, "conclusion": "success", "status": "completed"} for c in CTX]


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
        if p.startswith("/repos/cocreiamo/x/pulls?"):
            return self.reply(200, [{k: v for k, v in x.items() if k not in ("state", "runs")} for x in SC["pulls"]])
        if p.startswith("/repos/cocreiamo/x/pulls/"):
            n = int(p.rsplit("/", 1)[1])
            x = next(x for x in SC["pulls"] if x["number"] == n)
            return self.reply(200, {"number": n, "mergeable_state": x["state"], "head": x["head"]})
        if p.startswith("/repos/cocreiamo/x/rules/branches/main"):
            return self.reply(200, [{"type": "deletion"}, {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": c} for c in SC["contexts"]]}}])
        if "/check-runs" in p:
            s = p.split("/commits/")[1].split("/")[0]
            x = next(x for x in SC["pulls"] if x["head"]["sha"] == s)
            return self.reply(200, {"check_runs": check_runs(x["runs"])})
        self.reply(404, {})

    def do_PUT(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.append(("PUT", self.path, body))
        if self.headers["Authorization"] != "Bearer tok":
            return self.reply(401, {})
        self.reply(SC["put_code"], {"message": "Updating pull request branch."})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(pulls, dry=False, **kw):
    SC.clear()
    SC.update({"pulls": pulls, "contexts": CTX, "put_code": 202})
    SC.update(kw)
    del LOG[:]
    env = {"PATH": os.environ["PATH"], "API_URL": "http://127.0.0.1:%d" % server.server_port, "GH_TOKEN": "tok", "REPO": "cocreiamo/x", "DRY_RUN": "true" if dry else "false"}
    r = subprocess.run([sys.executable, "-I", sys.argv[1]], env=env, capture_output=True, text=True)
    return r, [c for c in LOG if c[0] != "GET"]


def updated(calls):
    return [c[1].split("/pulls/")[1].split("/")[0] for c in calls]


r, calls = run([pull(5)])
check("a behind, green PR with auto-merge is updated", updated(calls), ["5"])
check("the update names the head it saw", calls[0][2], {"expected_head_sha": sha(5)})
check("the update succeeds", r.returncode, 0)

r, calls = run([pull(7), pull(5), pull(6)])
check("only the oldest ready PR is updated", updated(calls), ["5"])

r, calls = run([pull(5, state="clean", runs="pending"), pull(6)])
check("a PR already up to date and running waits: nobody else is updated", calls, [])

r, calls = run([pull(5, state="blocked", runs="green"), pull(6)])
check("a PR up to date and green is about to merge: nobody else is updated", calls, [])

r, calls = run([pull(5, state="blocked", runs="failed"), pull(6)])
check("an up-to-date red PR does not hold the queue", updated(calls), ["6"])

r, calls = run([pull(5, runs="failed")])
check("a behind PR whose check failed is left alone", calls, [])

r, calls = run([pull(5, runs="rerun")])
check("the latest run of a check counts, not the first failure", updated(calls), ["5"])

r, calls = run([pull(5, runs="pending")])
check("a behind PR whose checks have not finished is left alone", calls, [])

r, calls = run([pull(5, auto=False)])
check("a PR without auto-merge is left alone", calls, [])

r, calls = run([pull(5, draft=True)])
check("a draft is left alone", calls, [])

r, calls = run([pull(5, state="dirty"), pull(6)])
check("a conflicting PR is skipped and the next one is updated", updated(calls), ["6"])

r, calls = run([pull(5, state="unknown"), pull(6)])
check("a PR whose state GitHub has not computed holds the queue", calls, [])

r, calls = run([pull(5)], dry=True)
check("a dry run mutates nothing", calls, [])
if "would update" not in r.stdout:
    sys.exit("FAIL: a dry run does not say what it would do: " + r.stdout)

r, calls = run([pull(5)], contexts=[])
check("no required check in the ruleset: no PR counts as green", calls, [])

r, calls = run([pull(5)], put_code=422)
check("a refused update fails the job", r.returncode != 0, True)
