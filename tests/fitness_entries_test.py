import atexit
import tempfile
import unittest
from pathlib import Path

import fitness_entries

TESTS = {"test:foo": {"description": "a task", "file": "tools/tasks/foo"}}
OVERLAY = "id: cocreiamo/task/test:foo\nrepo: cocreiamo\ntask: test:foo\nruns:\n- local\n"
PLAIN = (
    "id: cocreiamo/test/bar.sh\nrepo: cocreiamo\ninvariant: a test\nruns:\n- pr-ci\n"
    "command: mise run ci -- policy\nfile: tools/tests/bar.sh\n"
)

BASE = tempfile.TemporaryDirectory()
atexit.register(BASE.cleanup)


def repo(files, entries):
    root = Path(tempfile.mkdtemp(dir=BASE.name))
    for rel in files:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text("def check_x(a):\n")
    (root / "docs" / "fitness-functions").mkdir(parents=True)
    for name, text in entries.items():
        (root / "docs" / "fitness-functions" / name).write_text(text)
    return root


def run(root, name="cocreiamo"):
    return fitness_entries.problems(name, root, tasks=TESTS)


class FitnessEntries(unittest.TestCase):
    def test_complete_catalogue_passes(self):
        root = repo(["tools/tests/bar.sh", "tools/tasks/foo"], {"cocreiamo_test_bar.sh.yaml": PLAIN, "cocreiamo_task_test_foo.yaml": OVERLAY})
        self.assertEqual(run(root), [])

    def test_check_without_entry_is_refused(self):
        root = repo(["tools/tests/bar.sh", "tools/policy/p.rego"], {"cocreiamo_test_bar.sh.yaml": PLAIN})
        found = run(root)
        self.assertEqual(len(found), 1)
        self.assertIn("tools/policy/p.rego", found[0])

    def test_missing_directory_is_refused(self):
        root = Path(tempfile.mkdtemp(dir=BASE.name))
        self.assertIn("docs/fitness-functions", run(root)[0])

    def test_entry_for_a_file_that_is_gone_is_refused(self):
        root = repo([], {"cocreiamo_test_bar.sh.yaml": PLAIN})
        self.assertTrue(any("tools/tests/bar.sh does not exist" in p for p in run(root)))

    def test_file_must_be_named_after_its_id(self):
        root = repo(["tools/tests/bar.sh"], {"wrong.yaml": PLAIN})
        self.assertTrue(any("must be named cocreiamo_test_bar.sh.yaml" in p for p in run(root)))

    def test_entry_of_another_repository_is_refused(self):
        root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": PLAIN.replace("repo: cocreiamo", "repo: deploy")})
        self.assertTrue(any("repo must be cocreiamo" in p for p in run(root)))

    def test_id_must_start_with_the_repository(self):
        root = repo(["tools/tests/bar.sh"], {"deploy_test_bar.sh.yaml": PLAIN.replace("id: cocreiamo/", "id: deploy/")})
        self.assertTrue(any("the id must be cocreiamo/<kind>/<name>" in p for p in run(root)))

    def test_runs_must_be_a_non_empty_list_of_known_values(self):
        for runs in ("runs:\n- weekly\n", "runs: pr-ci\n", "runs: []\n"):
            root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": PLAIN.replace("runs:\n- pr-ci\n", runs)})
            self.assertTrue(run(root), runs)

    def test_missing_field_is_refused(self):
        root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": PLAIN.replace("command: mise run ci -- policy\n", "")})
        self.assertTrue(any("field command is missing" in p for p in run(root)))

    def test_overlay_must_not_restate_what_mise_knows(self):
        root = repo(["tools/tasks/foo"], {"cocreiamo_task_test_foo.yaml": OVERLAY + "invariant: x\nfile: tools/tasks/foo\n"})
        self.assertTrue(any("invariant, file comes from mise" in p for p in run(root)))

    def test_overlay_of_an_unknown_task_is_refused(self):
        root = repo([], {"cocreiamo_task_test_foo.yaml": OVERLAY.replace("test:foo", "test:nope").replace("test_foo", "test_nope")})
        self.assertTrue(any("mise has no task test:nope" in p for p in fitness_entries.problems("cocreiamo", root, tasks=TESTS)))

    def test_task_without_description_is_refused(self):
        root = repo(["tools/tasks/foo"], {"cocreiamo_task_test_foo.yaml": OVERLAY})
        found = fitness_entries.problems("cocreiamo", root, tasks={"test:foo": {"description": "", "file": "tools/tasks/foo"}})
        self.assertTrue(any("has no #MISE description" in p for p in found))

    def test_symbol_must_be_defined_in_the_file(self):
        entry = PLAIN + "symbol: check_x\n"
        root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": entry})
        self.assertEqual(run(root), [])
        root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": entry.replace("check_x", "check_y")})
        self.assertTrue(any("check_y is not defined" in p for p in run(root)))

    def test_dotgithub_discovers_tests_and_hooks(self):
        root = repo(["tests/a.sh", "hooks/pre-commit", "tools/tests/ignored.sh"], {})
        found = run(root, "dotgithub")
        self.assertEqual(len(found), 2)

    def test_infrastructure_discovers_its_tasks_policies_and_contracts(self):
        root = repo(
            ["mise-tasks/test/a", "mise-tasks/check/b", "mise-tasks/verify", "mise-tasks/lint", "tests/policy/p.rego", "tests/contracts/c.py", "lib/ignored.py"],
            {},
        )
        self.assertEqual(len(run(root, "infrastructure")), 6)

    def test_duplicate_id_is_refused(self):
        root = repo(["tools/tests/bar.sh"], {"cocreiamo_test_bar.sh.yaml": PLAIN, "cocreiamo_test_bar.sh.yml.yaml": PLAIN})
        self.assertTrue(any("duplicate id" in p for p in run(root)))


if __name__ == "__main__":
    unittest.main()
