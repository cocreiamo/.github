import unittest

import post_merge_skip as pms

SHA = "a" * 40
HEAD = "b" * 40


def fake(pulls, trees, checks):
    def api(path):
        if path.endswith(f"/commits/{SHA}/pulls"):
            return pulls
        for sha, tree in trees.items():
            if path.endswith(f"/git/commits/{sha}"):
                return {"tree": {"sha": tree}}
        if path.endswith(f"/commits/{HEAD}/check-runs?per_page=100"):
            return {"check_runs": checks}
        raise AssertionError(path)

    return api


PR = [{"merged_at": "2026-11-07T00:00:00Z", "merge_commit_sha": SHA, "head": {"sha": HEAD}}]
GREEN = [{"name": "ci", "conclusion": "success"}]


class Decide(unittest.TestCase):
    def decide(self, api):
        return pms.decide(api, "o/r", SHA, "ci")

    def test_same_tree_and_green_check_skips(self):
        self.assertTrue(self.decide(fake(PR, {SHA: "t1", HEAD: "t1"}, GREEN))[0])

    def test_different_tree_runs(self):
        self.assertFalse(self.decide(fake(PR, {SHA: "t1", HEAD: "t2"}, GREEN))[0])

    def test_red_or_missing_check_runs(self):
        for checks in ([{"name": "ci", "conclusion": "failure"}], [{"name": "other", "conclusion": "success"}], []):
            self.assertFalse(self.decide(fake(PR, {SHA: "t1", HEAD: "t1"}, checks))[0])

    def test_no_pull_request_runs(self):
        self.assertFalse(self.decide(fake([], {SHA: "t1"}, GREEN))[0])

    def test_pull_request_not_merged_as_this_commit_runs(self):
        other = [{"merged_at": "2026-11-07T00:00:00Z", "merge_commit_sha": "c" * 40, "head": {"sha": HEAD}}]
        self.assertFalse(self.decide(fake(other, {SHA: "t1", HEAD: "t1"}, GREEN))[0])

    def test_any_api_error_runs(self):
        def boom(path):
            raise OSError("down")

        self.assertFalse(self.decide(boom)[0])


if __name__ == "__main__":
    unittest.main()
