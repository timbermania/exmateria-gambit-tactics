#!/usr/bin/env python3
"""Keep the terrain LEVEL from being silently dropped again (ADR-0219).

The defect this guard exists for shipped for the life of the project and nothing
could see it. `DynamicTerrainBuilder.add_terrain` read `terrain_data.terrain.
level_0` and stopped; the exporter had been writing `level_1` the whole time;
`grep -rn "level_1" --include=*.gd` returned **0**. 202 selectable tiles across
44 maps were never built, and the visible symptom was Algus walking UNDER the
Igros bridge at MAP009 `(4, 11)` where the ROM walks him over it.

Nothing about that was a hard bug to fix. It was a hard bug to SEE — every layer
agreed with every other layer, because they all agreed to ignore the same byte.
So the four arms below each pin one thing that had to be true for the silence to
hold:

  1. **The build path names levels by INDEX, not by literal.** A `"level_0"`
     string in `DynamicTerrainBuilder.gd` is the original defect, verbatim. The
     loop reads `"level_%d" % level` and stops when the data stops offering one,
     so a THIRD level would report itself rather than vanish.
  2. **A query does not construct a ground key inline.** `terrain_at(Vector3i(x,
     z, 0))` is a level-0 assumption spelled as an accident;
     `terrain_at(TerrainCell.ground(x, z))` is the same assumption spelled as a
     declaration. With arm 2 green, `grep -rn "TerrainCell.ground"` is a
     COMPLETE census of the ground-plane assumptions in the tree — which is the
     property that was missing, not the fix.
  3. **The ROM's bound has a runtime control.** `tile_ptr` bounds-checks
     `level < 2` (`sltiu v0,a2,0x2` @0x8018400c), `TerrainCell.LEVEL_COUNT` is
     that 2, and `add_terrain` asserts against it. A fourth level in the data is
     then a loud failure instead of a quiet truncation.
  4. **The corpus still carries a second level.** 202 selectable level-1 tiles
     across 44 of the 119 exported maps. Flatten-at-export — ADR-0219's rejected
     alternative (c), and the one that will keep looking like the cheap fix —
     takes this to zero. Skipped, not failed, where `assets/maps/` is absent
     (a bare worktree; the maps are gitignored ROM-derived content).

Arms 1–3 are static text over the source; arm 4 reads the exported corpus. Pure
stdlib. Exit 0 if clean, 1 on any violation.

A genuine one-off opts arm 2 out with a per-line `# terrain-level-exempt:
<reason>` marker. There is no exemption for arms 1 and 3 — a file that needs one
is arguing with ADR-0219, and that argument belongs in the ADR.
"""
import json
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402

BUILDER = PROJECT_DIR / "addons/exmateria_battlefield/terrain/DynamicTerrainBuilder.gd"
CELL = PROJECT_DIR / "addons/exmateria_schema/lattice/TerrainCell.gd"
MAPS = PROJECT_DIR / "assets/maps"

LINE_EXEMPT = "terrain-level-exempt:"

# ADR-0148 dec. 3 — a guard's scan root is a WALK, so an extracted file stays
# covered. `tests/` rides along because a test is exactly where a ground-plane
# assumption gets re-introduced without anyone calling it one.
SCAN_DIRS = [PROJECT_DIR / "src", PROJECT_DIR / "tests"] + list(walk_roots())

# Arm 2: the cell-keyed members of the Lattice port and the TerrainIndex store.
# Each takes a CELL; handing one a fresh `Vector3i(..., 0)` is the assumption.
CELL_KEYED = ("terrain_at", "world_position_at", "_tile_at", "get_tile",
              "remove_tile", "is_cliff_edge")
GROUND_LITERAL = re.compile(
    r"\.(?:%s)\(\s*Vector3i\([^()]*,\s*0\s*\)" % "|".join(CELL_KEYED))

# Arm 1: the literal grid names the loop replaced.
LITERAL_LEVEL = re.compile(r'"level_[0-9]+"')


def _rel(path: Path) -> str:
    """Display path, project-relative where it can be. A guard that raises while
    formatting its own SKIP message is a guard that fails closed for no reason."""
    try:
        return str(path.relative_to(PROJECT_DIR))
    except ValueError:
        return str(path)


def _gd_files():
    seen = set()
    for root in SCAN_DIRS:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.gd")):
            if path not in seen:
                seen.add(path)
                yield path


def _strip_comment(line: str) -> str:
    """The code half of a line. Crude on purpose: a `#` inside a string is rare
    here and erring toward LESS code only ever makes an arm quieter, never
    louder — a guard that invents a violation is worse than one that misses."""
    return line.split("#", 1)[0]


def arm1_build_path_reads_the_data() -> list:
    """The level loop is data-driven, not a literal."""
    problems = []
    if not BUILDER.exists():
        return ["%s is missing — the terrain build path moved and this arm went "
                "blind (ADR-0148 dec. 3)" % BUILDER.relative_to(PROJECT_DIR)]
    text = BUILDER.read_text()
    for n, line in enumerate(text.splitlines(), 1):
        code = _strip_comment(line)
        hit = LITERAL_LEVEL.search(code)
        if hit:
            problems.append(
                "%s:%d names a level grid by literal (%s) — read the levels the "
                "data offers (`\"level_%%d\" %% level`), ADR-0219 dec. 5"
                % (BUILDER.relative_to(PROJECT_DIR), n, hit.group(0)))
    if '"level_%d"' not in text:
        problems.append(
            "%s no longer builds its grid key from a level INDEX — the "
            "data-driven loop is what makes a third level report itself"
            % BUILDER.relative_to(PROJECT_DIR))
    return problems


def arm2_no_inline_ground_key() -> list:
    """A ground-plane assumption is a declaration, not a literal."""
    problems = []
    for path in _gd_files():
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if LINE_EXEMPT in line:
                continue
            if GROUND_LITERAL.search(_strip_comment(line)):
                problems.append(
                    "%s:%d asks the port for a cell built inline at level 0 — "
                    "say `TerrainCell.ground(x, z)`, so the census of "
                    "ground-plane assumptions stays greppable (ADR-0219)"
                    % (path.relative_to(PROJECT_DIR), n))
    return problems


def arm3_the_rom_bound_has_a_control() -> list:
    """`LEVEL_COUNT` is the ROM's 2, and the builder asserts against it."""
    problems = []
    if not CELL.exists():
        return ["%s is missing — the cell type moved and this arm went blind"
                % CELL.relative_to(PROJECT_DIR)]
    m = re.search(r"const\s+LEVEL_COUNT\s*:\s*int\s*=\s*(\d+)", CELL.read_text())
    if m is None:
        problems.append(
            "%s declares no LEVEL_COUNT — the ROM bounds-checks `level < 2` "
            "(`sltiu v0,a2,0x2` @0x8018400c) and that bound is a named constant "
            "here, not a 2 spelled at each site" % CELL.relative_to(PROJECT_DIR))
    elif int(m.group(1)) != 2:
        problems.append(
            "%s says LEVEL_COUNT = %s; the ROM's `tile_ptr` bound is 2 "
            "(@0x8018400c). Moving it needs the ROM evidence, not a number."
            % (CELL.relative_to(PROJECT_DIR), m.group(1)))
    if BUILDER.exists():
        builder = BUILDER.read_text()
        if not re.search(r"assert\((?:[^()]|\([^()]*\))*LEVEL_COUNT", builder):
            problems.append(
                "%s no longer asserts the level against TerrainCell.LEVEL_COUNT "
                "— without it a third level is truncated silently, which is the "
                "shape of the defect ADR-0219 fixed"
                % BUILDER.relative_to(PROJECT_DIR))
    return problems


def arm4_the_corpus_still_has_a_second_level():
    """The exported maps carry level-1 content. Returns (problems, report)."""
    if not MAPS.exists():
        return [], ("SKIP: %s is absent (gitignored ROM-derived content; see "
                    "SETUP.md) — the corpus arm did not run" % _rel(MAPS))
    missing = []
    selectable = 0
    maps_with = 0
    total = 0
    for d in sorted(p for p in MAPS.iterdir() if (p / "terrain.json").exists()):
        total += 1
        terrain = json.loads((d / "terrain.json").read_text()).get("terrain", {})
        if "level_1" not in terrain:
            missing.append(d.name)
            continue
        # `unselectable` is READ, not interpreted: the mint criterion lives in
        # `DynamicTerrainBuilder._slot_is_occupied` and stays there. A second copy
        # of it here would be the duplication ADR-0218 spent ten doubles learning
        # to avoid, and this arm does not need one — it asks whether the DATA
        # still carries a second level, not how many tiles the game mints from it.
        n = sum(1 for row in terrain["level_1"] for t in row
                if t is not None and not t.get("unselectable", False))
        if n:
            maps_with += 1
            selectable += n
    problems = []
    if missing:
        problems.append(
            "%d exported map(s) carry no `level_1` grid at all (%s%s) — the "
            "exporter dropped the level, which is ADR-0219's rejected "
            "alternative (c), flatten-at-export"
            % (len(missing), ", ".join(missing[:5]),
               "…" if len(missing) > 5 else ""))
    if selectable == 0 and total:
        problems.append(
            "no selectable level-1 tile in any of the %d exported maps. The "
            "corpus carried 202 across 44 maps when ADR-0219 landed; zero means "
            "the second level stopped being exported (MAP009 (4,11) and MAP060's "
            "six Bridge tiles are the ones to look at first)." % total)
    return problems, ("corpus: %d selectable level-1 tiles across %d of %d "
                      "exported maps" % (selectable, maps_with, total))


def main() -> int:
    arms = [
        ("1 (the build path reads the data)", arm1_build_path_reads_the_data()),
        ("2 (no inline ground key)", arm2_no_inline_ground_key()),
        ("3 (the ROM bound has a control)", arm3_the_rom_bound_has_a_control()),
    ]
    corpus_problems, corpus_report = arm4_the_corpus_still_has_a_second_level()
    arms.append(("4 (the corpus still has a second level)", corpus_problems))

    failed = False
    for label, problems in arms:
        if problems:
            failed = True
            print("ADR-0219 terrain-level violations — arm %s:" % label)
            for p in problems:
                print("  %s" % p)
            print()
    if failed:
        print("The terrain level is the ROM's third tile coordinate: "
              "`tile_ptr(x, z, level)` @0x80183fb4. It is not a height and not a "
              "world Z. See docs/adr/0219 and docs/context/38-terrain-lattice.md.")
        return 1

    print("OK: the terrain level survives the build path (ADR-0219). %s."
          % corpus_report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
