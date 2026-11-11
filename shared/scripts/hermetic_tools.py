#!/usr/bin/env python3
"""Lists the external commands a shell script calls, one `command<TAB>file` per line (workflow-tools-check.py reads the run steps of workflows with the same lexer).

A small lexer, not a parser: it skips comments, quoted strings and here-document bodies, and takes the first word of every
simple command (after a newline, ; & | ( ) { }, `$(`, a backtick, then, do, else, !). Builtins, keywords, functions
defined in the same file, variable assignments and paths (a word with a slash, which is a script of this repository) are
not commands to resolve.
"""
import pathlib
import re
import subprocess
import sys
import tomllib

KEYWORDS = {"if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "select", "time", "!", "{", "}", "[[", "]]"}
BUILTINS = set(
    subprocess.run(["bash", "-c", "compgen -b"], capture_output=True, text=True, check=True).stdout.split()
)
# mise tool name (last segment of its key) to the binaries it installs, when they differ.
BINARIES = {"cli": ["gh"], "sh": ["shfmt"], "node": ["node", "npm", "npx", "corepack"]}

# What every runner image has, verified on cocreiamo-ci, cocreiamo-ci-light and cocreiamo-ci-large with .github/workflows/runner-tools.yml (monorepo): bash, GNU
# coreutils, findutils, grep, sed, gawk, tar, procps, git, docker, python3 (the other tools/tests use it), mise itself, and the two
# helpers for the workflows (ci-mise-setup installs the mise tools; ci-go-cache keeps the Go build cache). A tool a script uses only
# behind `command -v` is optional and not listed (lsof is on development machines, not on the runners). A tool that is not here comes
# from mise.toml.
PLATFORM = set(
    "bash awk basename base64 cat chmod cp cut date diff dirname du find git grep head id md5sum mkdir mktemp ps readlink realpath rm rmdir sed sleep sort tail tar tee timeout tr xargs"
    " docker python3 mise ci-mise-setup ci-go-cache".split()
)

SEPARATORS = set("\n;&|(){}`")


def commands(text):
    out = []
    i, n = 0, len(text)
    word, quoted, at_command = "", False, True
    pending_heredocs = []
    in_for = False
    depth_paren = 0
    skip_next = False

    def end_word():
        nonlocal word, quoted, at_command, in_for, skip_next
        if word == "" and not quoted:
            return
        w = word
        word, was_quoted = "", quoted
        quoted = False
        if skip_next:
            skip_next = False
            return
        if re.match(r"^[0-9]*(>>?|<|>&|&>)$", w) and not was_quoted:
            skip_next = True
            return
        if not at_command:
            if in_for and w == "in":
                in_for = False
                at_command = False
            return
        if w in KEYWORDS and not was_quoted:
            if w == "for" or w == "select":
                in_for = True
                at_command = False
            elif w in ("then", "do", "else", "elif", "if", "while", "until", "!", "{", "time", "function"):
                at_command = True
            else:
                at_command = False
            return
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=", w) and not was_quoted:
            return
        if re.match(r"^[0-9]*[<>]", w):
            return
        out.append(w)
        at_command = False

    while i < n:
        c = text[i]
        if c == "\n":
            end_word()
            if pending_heredocs:
                i += 1
                for tag, strip in pending_heredocs:
                    while i < n:
                        j = text.find("\n", i)
                        j = n if j < 0 else j
                        line = text[i:j]
                        i = j + 1
                        if (line.strip() if strip else line) == tag:
                            break
                pending_heredocs = []
                at_command = True
                continue
            at_command = True
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            if text[i + 1] == "\n":
                i += 2
                continue
            word += text[i : i + 2]
            i += 2
            continue
        if c == "#" and word == "" and not quoted:
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            word += text[i + 1 : j]
            quoted = True
            i = j + 1
            continue
        if c == '"':
            j = i + 1
            inner = ""
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    inner += text[j : j + 2]
                    j += 2
                    continue
                if text.startswith("$((", j):
                    depth, k = 2, j + 3
                    while k < n and depth:
                        depth += {"(": 1, ")": -1}.get(text[k], 0)
                        k += 1
                    j = k
                    continue
                if text.startswith("$(", j):
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if text[k] == "'":
                            k = text.find("'", k + 1)
                            k = n if k < 0 else k
                        depth += {"(": 1, ")": -1}.get(text[k] if k < n else "", 0)
                        k += 1
                    out.extend(commands(text[j + 2 : k - 1]))
                    j = k
                    continue
                inner += text[j]
                j += 1
            word += inner
            quoted = True
            i = j + 1
            continue
        if c == "(" and word.endswith("=") and not quoted:
            depth, k = 0, i
            while k < n:
                depth += {"(": 1, ")": -1}.get(text[k], 0)
                k += 1
                if depth == 0:
                    break
            word += "()"
            i = k
            continue
        if text.startswith("[[", i) and word == "" and at_command:
            k = text.find("]]", i)
            k = n if k < 0 else k + 2
            at_command = False
            i = k
            continue
        if text.startswith("((", i) and word == "":
            depth, k = 0, i
            while k < n:
                depth += {"(": 1, ")": -1}.get(text[k], 0)
                k += 1
                if depth == 0:
                    break
            at_command = False
            i = k
            continue
        if text.startswith("$((", i):
            depth, k = 2, i + 3
            while k < n and depth:
                depth += {"(": 1, ")": -1}.get(text[k], 0)
                k += 1
            word += "0"
            i = k
            continue
        if text.startswith("$(", i):
            depth, k = 1, i + 2
            while k < n and depth:
                depth += {"(": 1, ")": -1}.get(text[k], 0)
                k += 1
            out.extend(commands(text[i + 2 : k - 1]))
            word += "x"
            i = k
            continue
        if text.startswith("<<", i) and not text.startswith("<<<", i) and not text.startswith("<<(", i):
            m = re.match(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", text[i:])
            if m:
                pending_heredocs.append((m.group(3), m.group(1) == "-"))
                end_word()
                i += m.end()
                continue
        if c in SEPARATORS:
            if c == ")" and depth_paren == 0:
                word, quoted = "", False
                at_command = True
                i += 1
                continue
            end_word()
            if c == "(":
                depth_paren += 1
            if c == ")":
                depth_paren -= 1
            if c in ";&|({`":
                at_command = True
            if c == ")":
                at_command = False
            i += 1
            continue
        if c in " \t":
            end_word()
            i += 1
            continue
        word += c
        i += 1
    end_word()
    return out


CASE_LABEL = re.compile(r"^[ \t]*\(?[A-Za-z0-9_*\"'.-]+(\s*\|\s*[A-Za-z0-9_*\"'.-]+)*[ \t]*\)", re.M)


def external(path, functions):
    yield from external_text(open(path, encoding="utf-8").read(), functions)


def external_text(text, functions):
    optional = set(re.findall(r"command -v ([A-Za-z][A-Za-z0-9._+-]*)", text))
    if re.search(r"^\s*case\b", text, re.M):
        text = CASE_LABEL.sub("", text)
    defined = functions
    for w in commands(text):
        if "/" in w or w in BUILTINS or w in defined or w in optional or w in ("[", "test") or not re.match(r"^[A-Za-z][A-Za-z0-9._+-]*$", w):
            continue
        yield w


def function_names_text(text):
    return set(re.findall(r"(?:^|;|\bthen\b|\belse\b|\bdo\b)\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_:.-]*)\s*\(\)", text, re.M))


def function_names(paths):
    names = set()
    for path in paths:
        names |= function_names_text(open(path, encoding="utf-8").read())
    return names


def declared(mise_toml):
    mise_toml = pathlib.Path(mise_toml)
    # mise loads the .config/mise/conf.d fragments (the vendored shared tools block) with the project's mise.toml
    files = [mise_toml, *sorted((mise_toml.parent / ".config" / "mise" / "conf.d").glob("*.toml"))]
    names = set()
    for path in files:
        if not path.exists():
            continue
        with open(path, "rb") as f:
            tools = tomllib.load(f).get("tools", {})
        for key in tools:
            binary = re.split(r"[:/]", key)[-1]
            names.update(BINARIES.get(binary, [binary]))
    return names


def main(argv):
    mise_toml, files = argv[0], argv[1:]
    allowed = declared(mise_toml) | PLATFORM
    functions = function_names(files + subprocess.check_output(["git", "ls-files", "*.sh"], text=True).split())
    bad = 0
    for path in files:
        for cmd in sorted(set(external(path, functions))):
            if cmd not in allowed:
                print(f"{path}: calls `{cmd}`, which is neither in mise.toml [tools] nor in the platform list of tools/tests/hermetic_tools.py")
                bad = 1
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
