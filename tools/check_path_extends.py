#!/usr/bin/env python3
"""A script that is EXTENDED BY PATH must not declare a `class_name` (ADR-0004).

ADR-0004 took two decisions. One of them — "rosters share a base script" — has
no referent since ADR-0180 deleted the rosters. The OTHER outlives them:

    subclasses extend by path (`extends "res://path/To.gd"`), not by a
    `class_name` symbol.

The reason is a real, reproduced failure. A newly-added `class_name` is
invisible until Godot rebuilds its global class cache, so a base script that
carries one fails to resolve at autoload-parse time on a fresh checkout —
"Could not find base class BaseRoster" — and, more recently, `Identifier
"UnitSpawn" not declared` on the very first run after that class landed. Extending
by path never consults the cache.

ADR-0180 retired the guard that enforced this, because that guard named the
roster files. The convention it protected is cited by ~95 files across 8 systems,
so the enforcement is GENERALISED off the rosters rather than deleted with them:
every `extends "res://…"` target in the walk is checked, whatever it is called
and wherever it lives.

Exit 0 if the contract holds, 1 on any violation. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402

SCAN_DIRS = walk_roots() + [PROJECT_DIR / "tests"]

PATH_EXTENDS = re.compile(r'^\s*extends\s+"(res://[^"]+)"')
CLASS_NAME = re.compile(r"^\s*class_name\s+(\w+)")


def _declares_class_name(path: Path):
    """The `class_name` a script declares, or None. Ignores commented-out lines."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        m = CLASS_NAME.match(line)
        if m:
            return m.group(1)
    return None


def main() -> int:
    problems = []
    checked = 0
    targets = set()
    for root in SCAN_DIRS:
        if not root.is_dir():
            continue
        for gd in sorted(root.rglob("*.gd")):
            try:
                text = gd.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                m = PATH_EXTENDS.match(line)
                if not m:
                    continue
                checked += 1
                res_path = m.group(1)
                base = PROJECT_DIR / res_path[len("res://"):]
                targets.add(res_path)
                if not base.is_file():
                    problems.append(
                        f"{gd.relative_to(PROJECT_DIR)}:{lineno}: extends a path that "
                        f"does not exist — {res_path}")
                    continue
                declared = _declares_class_name(base)
                if declared:
                    problems.append(
                        f"{base.relative_to(PROJECT_DIR)}: declares `class_name {declared}` "
                        f"but is extended BY PATH from "
                        f"{gd.relative_to(PROJECT_DIR)}:{lineno}. A base script in a parse "
                        f"chain must stay class_name-less (ADR-0004) — the global class "
                        f"cache is not built yet when it is first needed.")

    if problems:
        print("check_path_extends: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        print(
            "\nFix: DROP the `class_name` from the base script (a leaf helper nothing "
            "extends may keep one), or have the subclass extend the symbol instead of "
            "the path — but only once you have confirmed nothing in an autoload's parse "
            "chain reaches it.")
        return 1

    print("OK: %d path-extends across %d base script(s); none declares a class_name "
          "(ADR-0004)." % (checked, len(targets)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
