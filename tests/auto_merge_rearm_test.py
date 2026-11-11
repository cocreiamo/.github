"""Runs the script embedded in auto-merge-rearm.yml (argv[1]) against a loopback GraphQL stub."""
import http.server
import json
import os
import subprocess
import sys
import threading
import unittest

SCRIPT = sys.argv.pop(1)
REPLIES = []
REQUESTS = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        REQUESTS.append((self.headers["Authorization"], json.loads(self.rfile.read(int(self.headers["Content-Length"])))))
        raw = json.dumps(REPLIES.pop(0)).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(reply):
    REPLIES.append(reply)
    REQUESTS.clear()
    env = {
        "PATH": os.environ["PATH"],
        "GRAPHQL_URL": f"http://127.0.0.1:{server.server_port}/graphql",
        "GH_TOKEN": "tok-secret",
        "PR_NODE_ID": "PR_node_1",
    }
    return subprocess.run([sys.executable, "-I", "-c", open(SCRIPT).read()], env=env, capture_output=True, text=True, check=False)


class Rearm(unittest.TestCase):
    def test_it_enables_squash_auto_merge_of_the_pr_with_the_app_token(self):
        result = run({"data": {"enablePullRequestAutoMerge": {"clientMutationId": None}}})
        self.assertEqual(result.returncode, 0, result.stderr)
        auth, body = REQUESTS[0]
        self.assertEqual(auth, "Bearer tok-secret")
        self.assertEqual(body["variables"], {"id": "PR_node_1"})
        self.assertIn("enablePullRequestAutoMerge", body["query"])
        self.assertIn("mergeMethod:SQUASH", body["query"])

    def test_a_graphql_error_fails_the_job_and_does_not_print_the_token(self):
        result = run({"errors": [{"message": "Pull request is not mergeable"}]})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Pull request is not mergeable", result.stderr)
        self.assertNotIn("tok-secret", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
