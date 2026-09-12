#!/usr/bin/env python3
"""One slot, one writer — `TileHighlights` is the only caller of `Tile`'s highlight
setters (ADR-0221 dec. 3).

A cell wears more than one marking at a time and a `Tile` renders exactly ONE of
them, so something has to arbitrate. `TileHighlights` does: it holds one marking
per slot per cell and hands the tile the topmost. That only works while nothing
else writes the tile directly, and the failure when something does is the shape
this repo keeps meeting — it compiles, it runs, and the picture is wrong only in
the frames after it.

That is not hypothetical. Before ADR-0221 there were THREE writers of
`Tile.current_highlight_type` and no arbiter:

  * `CursorController._set_active_tile` painted CURSOR_ACTIVE and saved what it
    displaced into one member, captured when the cursor ARRIVED;
  * `CursorController._on_camera_mode_changed` wrote the same member again across
    a camera takeover;
  * `TileHighlights.paint`, driven by `StrategyPhaseManager` and
    `PlacementTileHighlighter`, wrote the same slot for the placement colouring.

So a march pick landing on the cursor's tile was erased by the cursor walking off
it — the saved value was already a lie — and `CursorController._process` re-asserted
CURSOR_ACTIVE every frame to paper over the same collision on the one square where
it did not show. ADR-0164 dec. 1 had measured the publish's external clients as
`src/strategy/` only, 14 lines, and that measurement was correct: **two of the three
writers were INSIDE the addon**, so the census that established the publish never
saw them. A guard that only watched the host would have been blind for the same
reason, which is why arm 2 below walks the addon roots too.

Two arms:

  1. **`Tile` declares the underscored spelling, and only that.** A public
     `set_highlight_type` / `clear_highlight` is the pre-ADR-0221 surface,
     verbatim — a rename reverted is a door re-opened.
  2. **`TileHighlights.gd` is the only caller.** `Tile.gd` itself is allowed: its
     `_set_highlight_type(NONE)` delegates to `_clear_highlight()`.

Rendering is NOT what moved. The mesh, the material and the compositor
registration all stay on `Tile`; the underscore moved the AUTHORITY.

A genuine one-off opts arm 2 out with a per-line `# highlight-writer-exempt:
<reason>` marker. There is no exemption for arm 1 — a file that needs one is
arguing with ADR-0221, and that argument belongs in the ADR.

    python3 tools/check_highlight_writer.py

Pure stdlib. Exit 0 if clean, 1 on any violation.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402

TILE = PROJECT_DIR / "addons/exmateria_battlefield/lattice/Tile.gd"
PUBLISH = PROJECT_DIR / "addons/exmateria_battlefield/overlay/TileHighlights.gd"

LINE_EXEMPT = "highlight-writer-exempt:"

# ADR-0148 dec. 3 — a guard's scan root is a WALK, so an extracted file stays
# covered. `tests/` rides along because a test writing a tile directly is exactly
# how the sole-writer rule stops being true without anyone deciding it should.
SCAN_DIRS = [PROJECT_DIR / "src", PROJECT_DIR / "tests"] + list(walk_roots())

# The writers, underscored. Matched as CALLS (`.foo(`) so a declaration in `Tile.gd`
# and the string in this file's own docstring are not hits.
CALL = re.compile(r"\.(_set_highlight_type|_clear_highlight)\s*\(")
# The pre-ADR-0221 public spelling, as a DECLARATION.
PUBLIC_DECL = re.compile(r"^\s*func\s+(set_highlight_type|clear_highlight)\b")
PRIVATE_DECL = re.compile(r"^\s*func\s+(_set_highlight_type|_clear_highlight)\b")


def _strip_comment(line: str) -> str:
    """The code half of a line. Crude on purpose: erring toward LESS code only ever
    makes an arm quieter, never louder — a guard that invents a violation is worse
    than one that misses. `res://` is safe here; `#` is the only comment marker."""
    return line.split("#", 1)[0]


def _gd_files():
    seen = set()
    for root in SCAN_DIRS:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.gd")):
            if path not in seen:
                seen.add(path)
                yield path


def arm1_tile_declares_the_underscored_spelling() -> list:
    """`Tile` offers `_set_highlight_type` / `_clear_highlight`, and no public twin."""
    if not TILE.exists():
        return ["%s is missing — the tile moved and this arm went blind "
                "(ADR-0148 dec. 3)" % TILE.relative_to(PROJECT_DIR)]
    problems = []
    declared = set()
    for n, line in enumerate(TILE.read_text().splitlines(), 1):
        m = PRIVATE_DECL.match(line)
        if m:
            declared.add(m.group(1))
        m = PUBLIC_DECL.match(line)
        if m:
            problems.append(
                "%s:%d declares `%s` — the public spelling is the pre-ADR-0221 "
                "surface that let three writers share one slot with no arbiter. "
                "It is `_%s`, and `TileHighlights` is its only caller."
                % (TILE.relative_to(PROJECT_DIR), n, m.group(1), m.group(1)))
    for want in ("_set_highlight_type", "_clear_highlight"):
        if want not in declared:
            problems.append(
                "%s declares no `%s` — the highlight writer moved or was renamed, "
                "and arm 2 is now scoring a name nothing has (ADR-0221 dec. 3)"
                % (TILE.relative_to(PROJECT_DIR), want))
    return problems


def arm2_the_publish_is_the_only_caller() -> list:
    """Nothing but `TileHighlights.gd` (and `Tile.gd` itself) calls them."""
    problems = []
    allowed = {PUBLISH.resolve(), TILE.resolve()}
    for path in _gd_files():
        if path.resolve() in allowed:
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if LINE_EXEMPT in line:
                continue
            hit = CALL.search(_strip_comment(line))
            if hit:
                problems.append(
                    "%s:%d calls `%s` directly — a cell's markings are SLOTTED and "
                    "`TileHighlights` is the arbiter (ADR-0221 dec. 3). Paint through "
                    "`map.highlights.paint(cell, kind)` / `.clear(cell, kind)`."
                    % (path.relative_to(PROJECT_DIR), n, hit.group(1)))
    if not PUBLISH.exists():
        problems.append(
            "%s is missing — the highlight publish moved and this arm is now "
            "enforcing a rule with no writer left" % PUBLISH.relative_to(PROJECT_DIR))
    return problems


def main() -> int:
    arms = [
        ("1 (Tile declares the underscored spelling)",
         arm1_tile_declares_the_underscored_spelling()),
        ("2 (the publish is the only caller)",
         arm2_the_publish_is_the_only_caller()),
    ]
    failed = False
    for label, problems in arms:
        if problems:
            failed = True
            print("ADR-0221 highlight-writer violations — arm %s:" % label)
            for p in problems:
                print("  %s" % p)
            print()
    if failed:
        print("A cell wears more than one marking at a time and a Tile renders ONE. "
              "The arbitration is TileHighlights's, and it only works while nothing "
              "else writes the tile. See docs/adr/0221.")
        return 1

    print("OK: TileHighlights is the only writer of Tile's highlight (ADR-0221 "
          "dec. 3). %d .gd files walked." % sum(1 for _ in _gd_files()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
