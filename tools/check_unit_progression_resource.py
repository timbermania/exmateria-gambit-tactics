#!/usr/bin/env python3
"""Enforce the one-durable-unit-representation contract (ADR-0005).

`UnitProgression` used to be a `Node` (scene-bound live component) mirrored by
~15 stat fields on `UnitRosterData` (a `Resource`, the persistent save form).
The two were kept in step by a hand-written field-by-field copy in both
directions. ADR-0005 collapses that to ONE representation:

  * `UnitProgression` **extends Resource** (never `Node`) — so a roster entry
    can HOLD one and it outlives a battle.
  * A roster entry and the live `Unit` **share the same object by reference**
    (`unit.progression = entry.progression`), so no copy exists.

This guard locks in the shape the ADR deleted-to. It fails if:
  * `UnitProgression` stops extending `Resource` (regresses toward `Node`), or
  * either hand-written copy method (`_sync_progression_from_roster` /
    `update_unit_from_combat`) reappears, or
  * a `.progression.duplicate(...)` copy is introduced (the by-reference share
    is the whole point — duplicating reintroduces the mirror).

Exit 0 if the contract holds, 1 on any violation. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0251 dec. 1 — the class moved into `addons/exmateria_almanac/` at
# extraction #5 (ADR-0243 dec. 6). A HARDCODED PATH IS THE MOVE DEFECT: the
# `_gd_files()` scan below already follows `WALK_ROOTS`, but this one constant
# does not, and a guard whose subject has moved prints "expected ... to exist —
# it does not" and exits 1. That is the loud half; the quiet half is that
# nothing else here asserts `extends Resource` on any other file, so a silent
# rewrite of this line to a path that exists would leave the ADR-0005 contract
# unasserted.
PROGRESSION_REL = "addons/exmateria_almanac/progression/UnitProgression.gd"
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots() + [PROJECT_DIR / "tests"]

# The copy methods ADR-0005 deleted. Their return is the mirror this ADR removes.
FORBIDDEN_METHODS = ("_sync_progression_from_roster", "update_unit_from_combat")
EXTENDS_RESOURCE = re.compile(r"^\s*extends\s+Resource\b")
EXTENDS_ANY = re.compile(r"^\s*extends\s+(\w+)")
DUP_COPY = re.compile(r"\bprogression\s*\.\s*duplicate\s*\(")


def _code_lines(path: Path) -> list[str]:
    """File lines with the trailing line-comment stripped (so a name mentioned
    in a comment/docstring isn't mistaken for real code)."""
    return [line.split("#", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()]


def _gd_files() -> list[Path]:
    files: list[Path] = []
    for d in SCAN_DIRS:
        files.extend(d.rglob("*.gd"))
    return files


def main() -> int:
    problems: list[str] = []

    prog = PROJECT_DIR / PROGRESSION_REL
    if not prog.is_file():
        print(f"ADR-0005: expected {PROGRESSION_REL} to exist — it does not.")
        return 1
    code = _code_lines(prog)
    if not any(EXTENDS_RESOURCE.match(l) for l in code):
        found = next((m.group(1) for l in code if (m := EXTENDS_ANY.match(l))), "<none>")
        problems.append(
            f"{PROGRESSION_REL}: must `extends Resource` (found `extends {found}`). "
            "A Node is scene-bound and can't be held by the roster autoload — "
            "that split is exactly what ADR-0005 deleted."
        )

    for path in _gd_files():
        rel = path.relative_to(PROJECT_DIR).as_posix()
        lines = _code_lines(path)
        for i, line in enumerate(lines, 1):
            for meth in FORBIDDEN_METHODS:
                if re.search(rf"\b{re.escape(meth)}\b", line):
                    problems.append(
                        f"{rel}:{i}: references `{meth}` — ADR-0005 deleted the "
                        "field-by-field progression copy. Share the object by "
                        "reference instead of resurrecting the mirror."
                    )
            if DUP_COPY.search(line):
                problems.append(
                    f"{rel}:{i}: `progression.duplicate(...)` copies progression. "
                    "ADR-0005 shares one object by reference — don't duplicate it."
                )

    if problems:
        print("ADR-0005 one-durable-unit-representation violations:")
        for p in problems:
            print(f"  {p}")
        print(
            "\nFix: keep UnitProgression a Resource that the roster HOLDS and the "
            "live Unit SHARES by reference. See ADR-0005 → Consequences."
        )
        return 1

    print("OK: UnitProgression is a Resource, shared by reference, no copy mirror (ADR-0005).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
