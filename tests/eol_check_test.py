import datetime
import pathlib
import tempfile
import unittest

import eol_check as eol

TODAY = datetime.date(2026, 11, 6)


def release(name, eol_from=None, codename=None):
    return {
        "name": name,
        "codename": codename,
        "isEol": bool(eol_from and datetime.date.fromisoformat(eol_from) <= TODAY),
        "eolFrom": eol_from,
    }


API = {
    "nodejs": [release("24", "2028-04-30"), release("22", "2027-04-30"), release("20", "2026-04-30")],
    "postgresql": [release("18", "2030-11-14"), release("14", "2026-12-25")],
    "kubernetes": [release("1.36", "2027-06-28"), release("1.33", "2026-06-28")],
    "ubuntu": [release("24.04", "2029-04-01", "Noble Numbat")],
    "debian": [release("13", "2028-08-09", "Trixie"), release("12", "2026-06-10", "Bookworm")],
    "argo-cd": [release("3.5", None)],
}


def fetch(product):
    return API.get(product)


def write(root, rel, text):
    path = pathlib.Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class Discovery(unittest.TestCase):
    def pins(self, files):
        with tempfile.TemporaryDirectory() as root:
            for rel, text in files.items():
                write(root, rel, text)
            return eol.discover({"r": pathlib.Path(root)})

    def found(self, files):
        pins, untracked = self.pins(files)
        return {(p.product, p.version) for p in pins}, untracked

    def test_mise_tools(self):
        pins, untracked = self.found(
            {
                "mise.toml": "[tools]\n"
                'node = "24.15.0"\nkubectl = "1.36.5"\n"pipx:ansible-core" = { version = "2.21.5" }\n'
                'shellcheck = "0.11.0"\n'
            }
        )
        self.assertIn(("nodejs", "24.15.0"), pins)
        self.assertIn(("kubernetes", "1.36.5"), pins)
        self.assertIn(("ansible-core", "2.21.5"), pins)
        self.assertTrue(any("shellcheck" in u for u in untracked))

    def test_the_tools_of_the_shared_conf_d_file_are_pins_too(self):
        pins, _ = self.found({".config/mise/conf.d/shared-tools.toml": '[tools]\nnode = "24.15.0"\n', "mise.toml": '[tools]\nkubectl = "1.36.5"\n'})
        self.assertIn(("nodejs", "24.15.0"), pins)
        self.assertIn(("kubernetes", "1.36.5"), pins)

    def test_ansible_vars_and_hetzner_image(self):
        pins, _ = self.found(
            {
                "ansible/group_vars/k3s_cluster/main.yml": "k3s_version: v1.36.5+k3s1\ncilium_version: 1.20.3\n",
                "tofu/hetzner/main.tf": '  image = "ubuntu-24.04"\n',
            }
        )
        self.assertIn(("kubernetes", "1.36.5"), pins)
        self.assertIn(("cilium", "1.20.3"), pins)
        self.assertIn(("ubuntu", "24.04"), pins)

    def test_image_tags_and_from_lines(self):
        pins, _ = self.found(
            {
                "platform/cnpg/catalog.yaml": "    - image: ghcr.io/cloudnative-pg/postgresql:18.6-2026-standard-trixie@sha256:abc\n",
                "app/image.dockerfile": "FROM golang:1.27.3-trixie@sha256:abc AS build\nFROM docker.io/library/debian:trixie-slim\n"
                "FROM ${BASE} AS x\nFROM build AS y\n",
            }
        )
        self.assertIn(("postgresql", "18.6"), pins)
        self.assertIn(("go", "1.27.3"), pins)
        self.assertIn(("debian", "trixie"), pins)
        self.assertFalse({p for p in pins if p[1] in ("build", "x", "y")})

    def test_helm_chart_uses_the_app_version_of_the_vendored_chart(self):
        pins, _ = self.found(
            {
                "platform/argocd/kustomization.yaml": "helmCharts:\n  - name: argo-cd\n    repo: https://x\n    version: 10.11.6\n",
                "platform/argocd/charts/argo-cd-10.11.6/argo-cd/Chart.yaml": "appVersion: v3.5.6\n",
            }
        )
        self.assertIn(("argo-cd", "3.5.6"), pins)

    def test_helm_chart_without_app_version_is_listed_as_unresolved(self):
        pins, untracked = self.found(
            {"platform/argocd/kustomization.yaml": "helmCharts:\n  - name: argo-cd\n    repo: file:///nonexistent\n    version: 10.11.6\n"}
        )
        self.assertFalse(pins)
        self.assertTrue(any("argo-cd" in u for u in untracked))

    def test_vendored_and_generated_directories_are_skipped(self):
        pins, _ = self.found(
            {"node_modules/x/mise.toml": '[tools]\nnode = "10.0.0"\n', "platform/a/charts/b/values.yaml": "image: python:2.7\n"}
        )
        self.assertEqual(pins, set())

    def test_pages_saved_under_docs_research_are_skipped(self):
        pins, _ = self.pins(
            {"docs/research/x/sources/Dockerfile": "FROM python:2.7\n", "docs/other/Dockerfile": "FROM python:2.7\n"}
        )
        files = [p.file for p in pins]
        self.assertTrue(any(f.endswith("docs/other/Dockerfile") for f in files))
        self.assertFalse(any("docs/research" in f for f in files))


class Evaluation(unittest.TestCase):
    def run_check(self, pins, days=60):
        return eol.evaluate([eol.Pin(*p) for p in pins], fetch, TODAY, days)

    def test_supported_version_passes(self):
        failures, untracked = self.run_check([("nodejs", "24.15.0", "mise.toml", "r")])
        self.assertEqual((failures, untracked), ([], []))

    def test_eol_within_the_window_fails_with_product_version_date_and_file(self):
        failures, _ = self.run_check([("postgresql", "14.2", "catalog.yaml", "deploy")])
        self.assertEqual(len(failures), 1)
        for word in ("postgresql", "14.2", "2026-12-25", "catalog.yaml", "49 days"):
            self.assertIn(word, failures[0])

    def test_already_eol_fails(self):
        failures, _ = self.run_check([("nodejs", "20.1.0", "mise.toml", "r")])
        self.assertIn("already end of life", failures[0])

    def test_boundary_is_inclusive_and_beyond_passes(self):
        self.assertEqual(len(self.run_check([("postgresql", "14.2", "f", "r")], days=49)[0]), 1)
        self.assertEqual(self.run_check([("postgresql", "14.2", "f", "r")], days=48)[0], [])

    def test_unknown_product_or_cycle_is_informational(self):
        failures, untracked = self.run_check([("coredns", "1.14.7", "f", "r"), ("nodejs", "99.0.0", "g", "r")])
        self.assertEqual(failures, [])
        self.assertEqual(len(untracked), 2)

    def test_codename_matches_a_debian_cycle(self):
        failures, _ = self.run_check([("debian", "bookworm", "d.dockerfile", "m")])
        self.assertIn("2026-06-10", failures[0])

    def test_no_eol_date_passes(self):
        self.assertEqual(self.run_check([("argo-cd", "3.5.6", "f", "r")])[0], [])

    def test_the_same_pin_in_two_files_is_one_finding(self):
        failures, _ = self.run_check([("postgresql", "14.2", "a.yaml", "r"), ("postgresql", "14.2", "b.yaml", "r")])
        self.assertEqual(len(failures), 1)
        self.assertIn("a.yaml", failures[0])
        self.assertIn("b.yaml", failures[0])


class Main(unittest.TestCase):
    def run_main(self, argv, cwd):
        import contextlib
        import io
        import os
        import subprocess

        subprocess.run(["git", "init", "-q", cwd], check=True)
        previous, eol.fetch_live = eol.fetch_live, fetch
        out, err = io.StringIO(), io.StringIO()
        old = os.getcwd()
        try:
            os.chdir(cwd)
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = eol.main(argv)
        finally:
            os.chdir(old)
            eol.fetch_live = previous
        return code, out.getvalue(), err.getvalue()

    def test_default_root_is_the_repository_of_the_working_directory(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "mise.toml", '[tools]\nnode = "20.11.0"\n')
            code, out, err = self.run_main([], d)
            self.assertEqual(code, 1)
            self.assertIn("nodejs 20.11.0", err)
            self.assertIn(pathlib.Path(d).name, out)

    def test_a_repository_with_no_near_eol_pin_passes(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "mise.toml", '[tools]\nnode = "24.15.0"\n')
            code, _, err = self.run_main([], d)
            self.assertEqual((code, err), (0, ""))


if __name__ == "__main__":
    unittest.main()
