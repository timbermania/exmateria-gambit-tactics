#!/usr/bin/env python3
"""Enforce subject-qualified body-sprite naming (ADR-0027).

The bare field `Unit.sprite_id` implicitly meant the BODY sprite's ID while
WEAPON / EFFECT layers carry their own identifier schemes. ADR-0027 renamed
`Unit.sprite_id` (and the since-retired `UnitRosterData.sprite_id`) to
`body_sprite_id` so the name says which subject it scopes, and bulk-renamed
every dot-access consumer.

This guard locks the rename in on two surfaces:

  1. No bare `.sprite_id` DOT-access survives in src/ or tests/ — every field
     read/write is `.body_sprite_id`. The `\\.sprite_id` (leading-dot) pattern
     deliberately does NOT match the legitimate look-alikes ADR-0027 left in
     place: function parameters (`func f(sprite_id: int)`), string dict keys
     (`"sprite_id"` — a separate UI3 view-model vocabulary), and `.sprite_id_*`
     suffixed names.
  2. `Unit.gd` declares `body_sprite_id` and never re-adds a bare `sprite_id`
     field (the leaked name the rename removed). `UnitRosterData.gd` was the
     other declarer until ADR-0066 retired it into `Character`, which
     deliberately does NOT store a body sprite id (it is derived from
     job + gender), so `Unit.gd` is now the sole declarer.

Exit 0 if the naming holds, 1 on any violation. Pure stdlib.
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
DECLARERS = ("src/units/Unit.gd",)

# Leading-dot field access to the bare name; \b so `.sprite_id_offset` is safe.
DOT_ACCESS = re.compile(r"\.sprite_id\b")
# A bare field declaration `[@export] var sprite_id` (the removed leaked name).
BARE_DECL = re.compile(r"\bvar\s+sprite_id\b")


def _code_lines(path: Path) -> list[str]:
    """Lines with the trailing line-comment stripped (a `.sprite_id` in a doc
    comment describing the old name isn't a live field access)."""
    return [line.split("#", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()]


def _gd_files() -> list[Path]:
    files: list[Path] = []
    for d in SCAN_DIRS:
        files.extend(d.rglob("*.gd"))
    return sorted(files)


def main() -> int:
    problems: list[str] = []

    for path in _gd_files():
        rel = path.relative_to(PROJECT_DIR).as_posix()
        for i, line in enumerate(_code_lines(path), 1):
            if DOT_ACCESS.search(line):
                problems.append(
                    f"{rel}:{i}: bare `.sprite_id` field access — ADR-0027 renamed "
                    "it to `.body_sprite_id` (the ID is BODY-scoped; weapon/effect "
                    "layers have their own identifiers)."
                )

    for rel in DECLARERS:
        path = PROJECT_DIR / rel
        if not path.is_file():
            problems.append(f"{rel}: expected declarer is missing.")
            continue
        code = _code_lines(path)
        for i, line in enumerate(code, 1):
            if BARE_DECL.search(line):
                problems.append(
                    f"{rel}:{i}: declares a bare `sprite_id` field — ADR-0027 "
                    "renamed it to `body_sprite_id`."
                )
        if not any("body_sprite_id" in l for l in code):
            problems.append(
                f"{rel}: no `body_sprite_id` field found — the subject-qualified "
                "name must remain (ADR-0027)."
            )

    if problems:
        print("ADR-0027 body-sprite-naming violations:")
        for p in problems:
            print(f"  {p}")
        print(
            "\nFix: the body sprite ID is `body_sprite_id` everywhere — no bare "
            "`.sprite_id` dot-access, no bare `sprite_id` field. See ADR-0027."
        )
        return 1

    print("OK: body sprite ID is subject-qualified `body_sprite_id`, no bare .sprite_id (ADR-0027).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
