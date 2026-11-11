#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.3"]
# ///
"""End of life of every pinned version, against the free endoflife.date API (v1).

The pins are read from the files of the repositories (mise.toml, Ansible variables, the Hetzner image, kustomize
helmCharts, image tags and FROM lines), never from a hand list: only the mapping from a name to an endoflife.date
product lives here. Exit 1 when a pinned version is already end of life or reaches it within --days (default 60).
A pin whose product endoflife.date does not track is listed as informational.

Usage: eol_check.py [--days N] [repository root ...]   (default: the repository of the working directory)
"""

import argparse
import datetime
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

import yaml

API = "https://endoflife.date/api/v1/products/"

MISE_TOOLS = {
    "node": "nodejs",
    "python": "python",
    "go": "go",
    "opentofu": "opentofu",
    "terraform": "terraform",
    "kubectl": "kubernetes",
    "pipx:ansible-core": "ansible-core",
}
ANSIBLE_VARS = {
    "k3s_version": "kubernetes",
    "cilium_version": "cilium",
    "etcdctl_version": "etcd",
    "coredns_image_version": "coredns",
}
CHARTS = {
    "argo-cd": "argo-cd",
    "argo-workflows": "argo-workflows",
    "cert-manager": "cert-manager",
    "longhorn": "longhorn",
    "harbor": "harbor",
    "grafana": "grafana",
    "loki": "grafana-loki",
    "kyverno": "kyverno",
    "keda": "keda",
    "external-dns": "external-dns",
    "istiod": "istio",
}
IMAGES = {
    "cloudnative-pg/postgresql": "postgresql",
    "library/postgres": "postgresql",
    "postgres": "postgresql",
    "library/python": "python",
    "python": "python",
    "library/node": "nodejs",
    "node": "nodejs",
    "library/golang": "go",
    "golang": "go",
    "library/debian": "debian",
    "debian": "debian",
    "library/ubuntu": "ubuntu",
    "ubuntu": "ubuntu",
    "library/redis": "redis",
    "redis": "redis",
    "valkey/valkey": "valkey",
    "library/mariadb": "mariadb",
    "mariadb": "mariadb",
    "keycloak/keycloak": "keycloak",
    "grafana/grafana": "grafana",
    "library/traefik": "traefik",
    "traefik": "traefik",
}
SKIP_DIRS = {".git", ".terraform", "node_modules", "charts", "__pycache__"}
SKIP_PREFIXES = ("docs/research/",)
IMAGE_LINE = re.compile(r"^\s*(?:-\s*)?image:\s*[\"']?(?P<ref>[^\s\"'#]+)")
FROM_LINE = re.compile(r"^FROM\s+(?:--platform=\S+\s+)?(?P<ref>\S+)", re.I)
MISE_LINE = re.compile(r'^\s*"?(?P<tool>[A-Za-z0-9:_./-]+)"?\s*=\s*(?:"(?P<v1>[^"]+)"|\{[^}]*\bversion\s*=\s*"(?P<v2>[^"]+)")')
ANSIBLE_LINE = re.compile(r"^(?P<var>[a-z0-9_]+):\s*[\"']?(?P<v>[^\s\"']+)")
HETZNER_IMAGE = re.compile(r'\bimage\s*=\s*"(?P<os>ubuntu|debian)-(?P<v>\d+(?:\.\d+)?)"')


class Pin:
    def __init__(self, product, version, file, repo):
        self.product, self.version, self.file, self.repo = product, version, file, repo


def files_of(root):
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n")
        found = [root / f for f in out if f and not set(pathlib.PurePath(f).parts) & SKIP_DIRS and not f.startswith(SKIP_PREFIXES)]
        if found:
            return [f for f in found if f.is_file()]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return [
        p
        for p in root.rglob("*")
        if p.is_file() and not set(p.relative_to(root).parts) & SKIP_DIRS and not p.relative_to(root).as_posix().startswith(SKIP_PREFIXES)
    ]


def clean(version):
    v = version.lstrip("v").split("+")[0]
    m = re.match(r"\d+(?:\.\d+)*", v)
    return m.group(0) if m else v


def split_image(ref):
    if "$" in ref or ":" not in ref.split("@")[0].rsplit("/", 1)[-1]:
        return None
    ref = ref.split("@")[0]
    name, tag = ref.rsplit(":", 1)
    parts = name.split("/")
    if len(parts) > 1 and ("." in parts[0] or ":" in parts[0]):
        parts = parts[1:]
    return "/".join(parts), tag


def image_pin(ref):
    parsed = split_image(ref)
    if not parsed or parsed[0] not in IMAGES:
        return None
    product, tag = IMAGES[parsed[0]], parsed[1]
    if product in ("debian", "ubuntu") and not tag[0].isdigit():
        return product, tag.split("-")[0]
    return product, clean(tag)


def app_version(chart, repo, version, directory):
    vendored = directory / "charts" / f"{chart}-{version}" / chart / "Chart.yaml"
    if vendored.is_file():
        return clean(str(yaml.safe_load(vendored.read_text()).get("appVersion", "")))
    cmd = (
        ["helm", "show", "chart", repo, "--version", version]
        if repo.startswith("oci://")
        else ["helm", "show", "chart", chart, "--repo", repo, "--version", version]
    )
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=True).stdout
        return clean(str(yaml.safe_load(out).get("appVersion", "")))
    except (subprocess.SubprocessError, OSError, AttributeError, yaml.YAMLError):
        return ""


def discover(roots):
    pins, untracked = [], []

    def add(product, version, path, repo, label=None):
        if product:
            pins.append(Pin(product, version, str(path), repo))
        else:
            untracked.append(f"{label} {version} ({path})")

    for repo, root in roots.items():
        for path in files_of(root):
            rel = path.relative_to(root)
            text = path.read_text(errors="ignore") if path.stat().st_size < 2_000_000 else ""
            if path.name == "mise.toml" or (path.suffix == ".toml" and rel.parent.as_posix().endswith(".config/mise/conf.d")):
                section = ""
                for line in text.splitlines():
                    if line.startswith("["):
                        section = line.strip()
                    m = MISE_LINE.match(line) if section == "[tools]" else None
                    if m:
                        add(MISE_TOOLS.get(m["tool"]), clean(m["v1"] or m["v2"]), rel, repo, m["tool"])
            elif "group_vars" in rel.parts and path.suffix in (".yml", ".yaml"):
                for line in text.splitlines():
                    m = ANSIBLE_LINE.match(line)
                    if m and m["var"] in ANSIBLE_VARS:
                        add(ANSIBLE_VARS[m["var"]], clean(m["v"]), rel, repo, m["var"])
            elif path.suffix == ".tf":
                for m in HETZNER_IMAGE.finditer(text):
                    add(m["os"], m["v"], rel, repo, m["os"])
            elif path.name == "kustomization.yaml":
                try:
                    charts = (yaml.safe_load(text) or {}).get("helmCharts") or []
                except yaml.YAMLError:
                    charts = []
                for c in charts:
                    if c.get("name") in CHARTS:
                        v = app_version(c["name"], c.get("repo", ""), str(c.get("version")), path.parent)
                        if v:
                            add(CHARTS[c["name"]], v, rel, repo)
                        else:
                            untracked.append(f"chart {c['name']} {c.get('version')}: application version unknown ({rel})")
            if path.suffix in (".yaml", ".yml", ".njk", ".tmpl") or "dockerfile" in path.name.lower():
                for line in text.splitlines():
                    m = IMAGE_LINE.match(line) or FROM_LINE.match(line)
                    if m and (found := image_pin(m["ref"])):
                        add(found[0], found[1], rel, repo)
    return pins, untracked


def cycle_of(releases, version):
    best = None
    for r in releases:
        name = str(r["name"])
        if (
            version == name
            or version.startswith(name + ".")
            or (r.get("codename") and version.lower() == str(r["codename"]).split()[0].lower())
        ):
            if best is None or len(name) > len(str(best["name"])):
                best = r
    return best


def evaluate(pins, fetch, today, days):
    grouped = {}
    for p in pins:
        grouped.setdefault((p.product, p.version), []).append(p)
    failures, untracked = [], []
    for (product, version), group in sorted(grouped.items()):
        files = ", ".join(sorted({f"{p.repo}:{p.file}" for p in group}))
        releases = fetch(product)
        release = cycle_of(releases, version) if releases else None
        if release is None:
            untracked.append(f"{product} {version} ({files}): not tracked by endoflife.date")
            continue
        eol = release.get("eolFrom")
        eol_date = datetime.date.fromisoformat(eol) if isinstance(eol, str) else None
        if release.get("isEol") or (eol_date and eol_date <= today):
            when = f"already end of life since {eol}" if eol else "already end of life"
            failures.append(f"{product} {version} (cycle {release['name']}): {when}; pinned in {files}")
        elif eol_date and (eol_date - today).days <= days:
            failures.append(
                f"{product} {version} (cycle {release['name']}): end of life {eol} ({(eol_date - today).days} days); pinned in {files}"
            )
    return failures, untracked


def fetch_live(product):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(API + product, timeout=30) as response:
                return json.load(response)["result"]["releases"]
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
        except (urllib.error.URLError, TimeoutError, ValueError):
            pass
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"endoflife.date did not answer for {product}")


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=60)
    parser.add_argument("roots", nargs="*", help="repository roots (default: the repository of the working directory)")
    args = parser.parse_args(argv)
    if args.roots:
        roots = {pathlib.Path(r).resolve().name: pathlib.Path(r).resolve() for r in args.roots}
    else:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
        roots = {pathlib.Path(top).name: pathlib.Path(top)}
    pins, untracked = discover(roots)
    failures, more = evaluate(pins, fetch_live, datetime.date.today(), args.days)
    untracked += more
    if untracked:
        print(f"not tracked by endoflife.date (informational, {len(set(untracked))}):")
        for u in sorted(set(untracked)):
            print(f"  {u}")
    for f in failures:
        print(f"FAIL {f}", file=sys.stderr)
    count = len({(p.product, p.version) for p in pins})
    where = ", ".join(roots)
    print(f"end of life: {count} tracked pins in {where}; {len(failures)} within {args.days} days or past")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
