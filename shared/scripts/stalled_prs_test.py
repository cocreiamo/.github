import datetime as dt
import unittest

import stalled_prs as s

NOW = dt.datetime(2026, 11, 7, 12, 0, tzinfo=dt.UTC)


def pr(number, age_hours, **kw):
    created = NOW - dt.timedelta(hours=age_hours)
    base = {
        "number": number,
        "title": f"pr {number}",
        "draft": False,
        "created_at": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "html_url": f"https://github.com/o/r/pull/{number}",
        "mergeable_state": "clean",
        "auto_merge": {"merge_method": "squash"},
        "head": {"sha": f"sha{number}"},
    }
    return {**base, **kw}


def run(name, conclusion="success", id_=1, status="completed"):
    return {"name": name, "conclusion": conclusion, "status": status, "id": id_}


class Reason(unittest.TestCase):
    def test_a_conflict_is_stalled(self):
        self.assertIn("conflict", s.reason(pr(1, 9, mergeable_state="dirty"), [run("ci")]))

    def test_a_red_check_is_stalled_and_named(self):
        self.assertIn("ci", s.reason(pr(1, 9), [run("ci", "failure"), run("lint")]))

    def test_a_rerun_that_passed_supersedes_the_failed_run(self):
        self.assertIsNone(s.reason(pr(1, 9), [run("ci", "failure", 1), run("ci", "success", 2)]))

    def test_no_check_at_all_is_stalled(self):
        self.assertIn("no check", s.reason(pr(1, 9), []))

    def test_auto_merge_off_is_stalled(self):
        self.assertIn("auto-merge", s.reason(pr(1, 9, auto_merge=None), [run("ci")]))

    def test_a_running_check_is_progress(self):
        self.assertIsNone(s.reason(pr(1, 9, mergeable_state="blocked"), [run("ci", None, status="in_progress")]))

    def test_green_with_auto_merge_and_still_blocked_is_stalled(self):
        self.assertIn("blocked", s.reason(pr(1, 9, mergeable_state="blocked"), [run("ci")]))

    def test_green_and_clean_is_about_to_merge(self):
        self.assertIsNone(s.reason(pr(1, 9), [run("ci")]))


class Stalled(unittest.TestCase):
    def test_young_and_draft_pull_requests_are_left_alone(self):
        pulls = [pr(1, 5, mergeable_state="dirty"), pr(2, 50, mergeable_state="dirty", draft=True), pr(3, 7, mergeable_state="dirty")]
        found = s.stalled(pulls, lambda p: [run("ci")], NOW)
        self.assertEqual([f["number"] for f in found], [3])

    def test_the_oldest_comes_first(self):
        pulls = [pr(1, 8, mergeable_state="dirty"), pr(2, 30, mergeable_state="dirty")]
        self.assertEqual([f["number"] for f in s.stalled(pulls, lambda p: [run("ci")], NOW)], [2, 1])


class FakeApi:
    def __init__(self, issues):
        self.issues, self.calls = issues, []

    def __call__(self, method, path, body=None):
        self.calls.append((method, path, body))
        return self.issues if method == "GET" else {}


FOUND = [{"number": 7, "title": "t", "url": "u", "age_hours": 30, "reason": "conflict with main"}]


class Issue(unittest.TestCase):
    def test_an_open_issue_is_updated_not_duplicated(self):
        api = FakeApi([{"number": 5}])
        s.sync_issue(api, "o/r", FOUND, NOW)
        writes = [c for c in api.calls if c[0] != "GET"]
        self.assertEqual([w[0] for w in writes], ["PATCH"])
        self.assertTrue(writes[0][1].endswith("/issues/5"))
        self.assertIn("#7", writes[0][2]["body"])
        self.assertIn("conflict with main", writes[0][2]["body"])

    def test_no_issue_yet_creates_one_with_the_label(self):
        api = FakeApi([])
        s.sync_issue(api, "o/r", FOUND, NOW)
        writes = [c for c in api.calls if c[0] != "GET"]
        self.assertEqual([w[0] for w in writes], ["POST"])
        self.assertEqual(writes[0][2]["labels"], [s.LABEL])

    def test_nothing_stalled_closes_the_open_issue(self):
        api = FakeApi([{"number": 5}])
        s.sync_issue(api, "o/r", [], NOW)
        writes = [c for c in api.calls if c[0] != "GET"]
        self.assertEqual(writes[0][2], {"state": "closed"})

    def test_nothing_stalled_and_no_issue_writes_nothing(self):
        api = FakeApi([])
        s.sync_issue(api, "o/r", [], NOW)
        self.assertEqual([c for c in api.calls if c[0] != "GET"], [])


if __name__ == "__main__":
    unittest.main()
