"""Checks the translation catalogs against the code that reads them.

Every catalog must be a flat object of strings with no key English lacks and
the same %N placeholders as English. Every key the code names, literally or
through one of the families below, must exist in English.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
I18N = ROOT / "i18n"
PHASES = ["starting", "searching", "none", "missing", "agent", "solaar", "incompatible", "bridge"]
# Keys the code builds from a name rather than spelling out.
BUILT = (
    ["phase.%s.title" % p for p in PHASES]
    + ["battery." + s for s in ["discharging", "charging", "full", "unknown", "offline"]]
    + ["change." + c for c in ["failed", "device-gone", "ambiguous-name", "invalid-change", "missing", "agent", "solaar", "incompatible"]]
    + ["warning.low", "warning.critical", "fnLock.onNote", "fnLock.offNote"]
)
LITERAL = re.compile(r'\b(?:tr|t)\("([A-Za-z][\w.-]*)"\)')
PLACEHOLDER = re.compile(r"%\d")


def main():
    problems = []
    english = json.loads((I18N / "en.json").read_text(encoding="utf-8"))
    sources = [p.read_text(encoding="utf-8") for p in [*ROOT.glob("*.qml"), ROOT / "Model.js"]]
    wanted = set(BUILT)
    for text in sources:
        wanted.update(LITERAL.findall(text))
    problems += ["en.json lacks %r" % key for key in sorted(wanted - set(english))]

    for path in sorted(I18N.glob("*.json")):
        try:
            catalog = json.loads(path.read_text(encoding="utf-8"))
        except ValueError as error:
            problems.append("%s: %s" % (path.name, error))
            continue
        for key, value in catalog.items():
            if key not in english:
                problems.append("%s: %r is not in en.json" % (path.name, key))
            elif not isinstance(value, str) or not value.strip():
                problems.append("%s: %r is not a non-empty string" % (path.name, key))
            elif sorted(PLACEHOLDER.findall(value)) != sorted(PLACEHOLDER.findall(english[key])):
                problems.append("%s: %r has other placeholders than English" % (path.name, key))

    for problem in problems:
        print("check_i18n: " + problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
