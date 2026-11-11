"""The canonical linter configs of shared/config parse and keep the rules each repository enforced before they were merged."""

import json
import sys
import tomllib
from pathlib import Path

import yaml

root = Path(sys.argv[1])
errors = []


def check(ok, message):
    if not ok:
        errors.append(message)


ruff = tomllib.loads((root / "ruff.toml").read_text())
check(ruff.get("line-length", 999) <= 140, "ruff line-length must be at most 140 (infrastructure)")
check({"E", "F", "I", "W", "B", "UP", "PLW", "RUF", "S"} <= set(ruff["lint"]["select"]), "ruff select lost a rule family")
check(set(ruff["lint"]["ignore"]) <= {"S603", "S607"}, "ruff ignores more than S603 and S607 (E501 in particular is enforced)")
check("S101" not in ruff["lint"]["ignore"], "ruff ignores S101 everywhere")
for pattern in ("**/*_test.py", "tests/**/test_*.py", "mise-tasks/test/*"):
    check(pattern in ruff["lint"]["per-file-ignores"], f"ruff has no per-file-ignores for {pattern}")

yamllint = yaml.safe_load((root / ".yamllint.yaml").read_text())
check(yamllint["extends"] == "default", "yamllint does not extend default")
rules = yamllint["rules"]
check(rules.get("indentation") == {"spaces": "consistent", "indent-sequences": "consistent"}, "yamllint lost the indentation rule")
check(rules.get("braces") == {"max-spaces-inside": 1} and rules.get("comments") == {"min-spaces-from-content": 1}, "yamllint lost braces or comments")
for ignored in ("secrets/", ".terraform/", "ansible/collections/", "platform/*/charts/", "tests/lint/bad/"):
    check(ignored in yamllint["ignore"], f"yamllint no longer ignores {ignored}")

typos = tomllib.loads((root / ".typos.toml").read_text())
check({"rto", "fo", "macchine", "scap", "alls", "passt"} <= set(typos["default"]["extend-words"]), "typos lost an allowed word")
for excluded in ("seed/", "secrets/", "*.enc.yaml", "platform/dashboards/files/", "schemas/kargo/", "platform/*/upstream/"):
    check(excluded in typos["files"]["extend-exclude"], f"typos no longer excludes {excluded}")

gitleaks = tomllib.loads((root / ".gitleaks.toml").read_text())
check(gitleaks["extend"]["useDefault"] is True, "gitleaks does not extend the default rules")
check(len(gitleaks["allowlists"]) >= 2, "gitleaks lost an allowlist")

md = yaml.safe_load((root / ".markdownlint-cli2.yaml").read_text())
check(md["config"]["default"] is True and md["config"]["MD024"] == {"siblings_only": True}, "markdownlint lost its rule set")
check("**/*.md" in md["globs"], "markdownlint does not lint every Markdown file")

editorconfig = (root / ".editorconfig").read_text()
for line in ("root = true", "end_of_line = lf", "insert_final_newline = true", "trim_trailing_whitespace = true", "indent_style = space", "indent_size = 2"):
    check(line in editorconfig, f"editorconfig lost {line}")

shellcheck = (root / ".shellcheckrc").read_text().split()
check("external-sources=true" in shellcheck and "source-path=." in shellcheck, "shellcheckrc lost external-sources or source-path")
check(not any(w.startswith("disable=") for w in shellcheck), "shellcheckrc disables a check")

vale = (root / ".vale.ini").read_text()
check("BasedOnStyles = Cocreiamo" in vale and "MinAlertLevel = warning" in vale, "vale lost its style or alert level")
for style in ("Banned", "EnglishOnly"):
    check(yaml.safe_load((root / f".vale/styles/Cocreiamo/{style}.yml").read_text())["level"] == "error", f"vale style {style} is not an error")

hadolint = yaml.safe_load((root / ".hadolint.yaml").read_text())
check(hadolint.get("failure-threshold") == "style" and not hadolint.get("ignored"), "hadolint fails below style or ignores a rule")

prettier = json.loads((root / ".prettierrc.json").read_text())
check(prettier.get("endOfLine") == "lf" and prettier.get("tabWidth") == 2 and prettier.get("useTabs") is False, "prettier disagrees with the editorconfig")

if errors:
    sys.exit("FAIL: " + "\nFAIL: ".join(errors))
print("configs ok")
