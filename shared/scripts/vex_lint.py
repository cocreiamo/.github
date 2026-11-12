"""Lint OpenVEX documents: a silenced finding must say why (usage: vex_lint.py FILE...)."""

import json
import sys

JUSTIFICATIONS = {
    "component_not_present",
    "vulnerable_code_not_present",
    "vulnerable_code_not_in_execute_path",
    "vulnerable_code_cannot_be_controlled_by_adversary",
    "inline_mitigations_already_exist",
}


def problems(path):
    doc = json.load(open(path))
    out = []
    for key in ("@context", "@id", "author", "timestamp"):
        if not doc.get(key):
            out.append(f"{path}: document lacks {key}")
    for i, st in enumerate(doc.get("statements", [])):
        where = f"{path}: statement {i} ({(st.get('vulnerability') or {}).get('name', '?')})"
        if not (st.get("vulnerability") or {}).get("name"):
            out.append(f"{where}: no vulnerability name")
        if not st.get("products"):
            out.append(f"{where}: no product")
        if st.get("status") == "not_affected":
            if st.get("justification") not in JUSTIFICATIONS:
                out.append(f"{where}: not_affected needs a justification from {sorted(JUSTIFICATIONS)}")
            if len((st.get("impact_statement") or "").strip()) < 20:
                out.append(f"{where}: not_affected needs an impact statement that explains it")
    return out


def main():
    found = [p for f in sys.argv[1:] for p in problems(f)]
    print("\n".join(found), file=sys.stderr if found else sys.stdout)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
