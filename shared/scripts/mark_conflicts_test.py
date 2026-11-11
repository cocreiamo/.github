import http.server
import json
import os
import subprocess
import sys
import threading
import unittest
from pathlib import Path

SCRIPT = Path(os.environ.get("MARK_CONFLICTS_SCRIPT") or Path(__file__).with_name("mark_conflicts.py"))


class Api:
    def __init__(self, states, labelled=(), unknown_once=(), label_create_fails=False, deny_all=False):
        self.states = states
        self.labelled = set(labelled)
        self.unknown_once = set(unknown_once)
        self.label_create_fails = label_create_fails
        self.deny_all = deny_all
        self.posts = []
        api = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, code, obj):
                raw = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                if api.deny_all:
                    return self.reply(403, {"message": "denied"})
                if "/pulls?state=open" in self.path:
                    return self.reply(200, [{"number": n, "labels": [{"name": "conflict"}] if n in api.labelled else []} for n in api.states])
                n = int(self.path.rsplit("/", 1)[1])
                if n in api.unknown_once:
                    api.unknown_once.discard(n)
                    return self.reply(200, {"number": n, "mergeable_state": "unknown"})
                self.reply(200, {"number": n, "mergeable_state": api.states[n]})

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
                api.posts.append((self.path, body, self.headers["Authorization"]))
                if self.path.endswith("/labels") and "/issues/" not in self.path and api.label_create_fails:
                    return self.reply(422, {"message": "already_exists"})
                self.reply(201, {})

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def run(self):
        env = {
            "PATH": os.environ["PATH"],
            "API_URL": f"http://127.0.0.1:{self.server.server_port}",
            "GH_TOKEN": "tok-secret",
            "GITHUB_REPOSITORY": "cocreiamo/x",
            "MARK_CONFLICTS_RETRY": "0",
        }
        result = subprocess.run([sys.executable, "-I", str(SCRIPT)], env=env, capture_output=True, text=True, check=False)
        self.server.shutdown()
        return result

    def marked(self, suffix):
        return sorted(int(p.split("/")[-2]) for p, _, _ in self.posts if "/issues/" in p and p.endswith(suffix))


class MarkConflicts(unittest.TestCase):
    def test_only_an_unlabelled_pr_in_conflict_gets_the_label_and_the_comment(self):
        api = Api({1: "clean", 2: "dirty", 3: "behind", 4: "dirty"}, labelled={4}, unknown_once={2})
        result = api.run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(api.marked("/labels"), [2])
        self.assertEqual(api.marked("/comments"), [2])

    def test_the_comment_tells_how_to_resolve_it(self):
        api = Api({5: "dirty"})
        api.run()
        body = next(b["body"] for p, b, _ in api.posts if p.endswith("/issues/5/comments"))
        self.assertIn("merge the base into the branch", body)

    def test_the_token_is_sent_as_a_bearer_and_never_printed(self):
        api = Api({5: "dirty"})
        result = api.run()
        self.assertTrue(all(auth == "Bearer tok-secret" for _, _, auth in api.posts))
        self.assertNotIn("tok-secret", result.stdout + result.stderr)

    def test_an_existing_label_is_not_an_error(self):
        api = Api({5: "dirty"}, label_create_fails=True)
        result = api.run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(api.marked("/labels"), [5])

    def test_nothing_in_conflict_writes_no_comment(self):
        api = Api({1: "clean", 2: "blocked"})
        api.run()
        self.assertEqual(api.marked("/comments"), [])

    def test_an_api_refusal_fails_the_run(self):
        self.assertNotEqual(Api({1: "dirty"}, deny_all=True).run().returncode, 0)

    def test_the_script_never_calls_gh(self):
        self.assertNotRegex(SCRIPT.read_text(), r"\bgh\b|subprocess")


if __name__ == "__main__":
    unittest.main()
