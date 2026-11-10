import unittest

import post_merge_skip as pms

SHA = "a" * 40
HEAD = "b" * 40


def fake(pulls, trees, checks, annotations=None):
    def api(path):
        for run_id, notes in (annotations or {}).items():
            if path.endswith(f"/check-runs/{run_id}/annotations?per_page=100"):
                return notes
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


def tested(tree):
    return [{"title": "tested-tree", "message": tree, "annotation_level": "notice"}]


def run(run_id, completed_at, name="changes"):
    return {"id": run_id, "name": name, "conclusion": "success", "completed_at": completed_at, "output": {"annotations_count": 1}}


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

    def test_main_moved_but_the_tested_merge_ref_tree_is_the_squash_tree_skips(self):
        checks = GREEN + [run(7, "2026-11-07T00:01:00Z")]
        api = fake(PR, {SHA: "t1", HEAD: "t2"}, checks, {7: tested("t1")})
        skip, why = self.decide(api)
        self.assertTrue(skip, why)

    def test_main_moved_after_the_test_runs(self):
        checks = GREEN + [run(7, "2026-11-07T00:01:00Z")]
        self.assertFalse(self.decide(fake(PR, {SHA: "t3", HEAD: "t2"}, checks, {7: tested("t1")}))[0])

    def test_the_latest_tested_tree_wins(self):
        old, new = run(7, "2026-11-07T00:01:00Z"), run(8, "2026-11-07T00:09:00Z")
        trees = {SHA: "t1", HEAD: "t2"}
        self.assertTrue(self.decide(fake(PR, trees, GREEN + [old, new], {7: tested("t2"), 8: tested("t1")}))[0])
        self.assertFalse(self.decide(fake(PR, trees, GREEN + [old, new], {7: tested("t1"), 8: tested("t2")}))[0])

    def test_a_red_check_still_runs_whatever_the_tested_tree(self):
        checks = [{"name": "ci", "conclusion": "failure"}, run(7, "2026-11-07T00:01:00Z")]
        self.assertFalse(self.decide(fake(PR, {SHA: "t1", HEAD: "t2"}, checks, {7: tested("t1")}))[0])

    def test_an_annotation_error_falls_back_to_the_head_tree(self):
        checks = GREEN + [run(7, "2026-11-07T00:01:00Z")]

        def api(path):
            if "/annotations" in path:
                raise OSError("down")
            return fake(PR, {SHA: "t1", HEAD: "t2"}, checks)(path)

        self.assertFalse(self.decide(api)[0])

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
