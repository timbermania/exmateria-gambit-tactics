#!/usr/bin/env python3
"""Guard: the two terrain enum tables are spelled TWICE, and they must agree.

`tools/fft_exporter/models/terrain.py` owns `TerrainSlopeType` (13 members) and
`TerrainSurfaceType` (64 members) and writes their **names** into every shipped
`assets/maps/MAP###/terrain.json`.  `addons/exmateria_battlefield/terrain/RomTerrain.gd`
reads those names back and needs the **bytes**, because the ROM's planner indexes
its movement-cost row `surface & 0x3F` and reads `slope_type` two bits at a time.
Nothing in Godot can import a Python enum, so the mapping exists twice.

    uv run python godot-learning/tools/check_rom_terrain_tables.py

WHY THIS IS THE DELIVERABLE AND NOT A NICETY.  A disagreement between the two
copies is invisible to every other instrument in this repo:

  * the GDScript table is a `const Dictionary` — no test that does not already
    know the right answer can tell 14 from 15;
  * `RomTerrain._tile_from_row` maps an UNKNOWN name to byte 0, which is `Flat` /
    `NaturalSurface`, a legal tile.  A missing row does not raise, it silently
    flattens the map;
  * a wrong byte routes.  `Waterway` at the wrong index costs 1 instead of 2 and
    the Igros moat stops being a moat — the planner returns a fully-formed route
    that is simply not the ROM's.  There is no crash and no red anywhere.

So the check is set equality on the NAMES and equality on every VALUE, both ways.
Add a member to the Python enum without adding it here and this goes red; that is
the entire point.

Exit 0 = the tables agree.  Exit 1 = they do not, with the disagreement named.
"""
import ast
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_PKG = os.path.normpath(os.path.join(_HERE, ".."))

PY_TABLE = os.path.join(_PKG, "tools", "fft_exporter", "models", "terrain.py")
GD_TABLE = os.path.join(_PKG, "addons", "exmateria_battlefield", "terrain",
                        "RomTerrain.gd")

#: (python enum class, GDScript const name, expected member count).  The counts are
#: pinned so that a table LOSING members reads as a failure rather than as two
#: copies that agree about less than they used to.
PAIRS = [
    ("TerrainSlopeType", "SLOPE_BYTE", 13),
    ("TerrainSurfaceType", "SURFACE_BYTE", 64),
]


def python_enums(path):
    """{class name: {member: value}} for every `class X(Enum)` in the file.

    Parsed rather than imported: `fft_exporter` drags in the whole exporter package
    and this guard runs in the pre-flight, where the cheapest possible dependency
    footprint is the difference between a guard that runs and one that gets skipped.
    """
    tree = ast.parse(open(path).read())
    out = {}
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        if not any(isinstance(b, ast.Name) and b.id == "Enum" for b in node.bases):
            continue
        members = {}
        for stmt in node.body:
            if (isinstance(stmt, ast.Assign) and len(stmt.targets) == 1
                    and isinstance(stmt.targets[0], ast.Name)
                    and isinstance(stmt.value, ast.Constant)
                    and isinstance(stmt.value.value, int)):
                members[stmt.targets[0].id] = stmt.value.value
        out[node.name] = members
    return out


_ENTRY = re.compile(r'^\s*"([A-Za-z0-9_]+)"\s*:\s*(\d+)\s*,\s*$')


def gdscript_dict(path, const_name):
    """{name: value} out of a `const NAME: Dictionary = { "k": 1, ... }` literal.

    A line scan, not an evaluator: the tables are one entry per line by construction
    and a guard that needs a GDScript parser is a guard that stops being maintained.
    Anything inside the braces that is not `"Name": <int>,` is reported rather than
    skipped, so a table reformatted onto one line fails loudly instead of reading
    as empty.
    """
    lines = open(path).read().splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^const\s+%s\s*:" % re.escape(const_name), line):
            start = i
            break
    if start is None:
        raise SystemExit("FAIL  %s: no `const %s` in %s"
                         % (const_name, const_name, path))
    out, bad = {}, []
    for line in lines[start + 1:]:
        if line.startswith("}"):
            return out, bad
        if not line.strip() or line.strip().startswith("#"):
            continue
        m = _ENTRY.match(line)
        if m:
            out[m.group(1)] = int(m.group(2))
        else:
            bad.append(line)
    raise SystemExit("FAIL  %s: unterminated dict literal in %s"
                     % (const_name, path))


def main():
    enums = python_enums(PY_TABLE)
    failures = []
    for py_name, gd_name, expect_n in PAIRS:
        if py_name not in enums:
            failures.append("%s: not found in %s" % (py_name, PY_TABLE))
            continue
        py = enums[py_name]
        gd, bad = gdscript_dict(GD_TABLE, gd_name)
        for line in bad:
            failures.append("%s: unparsable entry %r" % (gd_name, line))
        if len(py) != expect_n:
            failures.append("%s: %d members, expected %d — the enum changed shape; "
                            "update PAIRS deliberately" % (py_name, len(py), expect_n))
        if len(gd) != expect_n:
            failures.append("%s: %d entries, expected %d" % (gd_name, len(gd), expect_n))
        only_py = sorted(set(py) - set(gd))
        only_gd = sorted(set(gd) - set(py))
        if only_py:
            failures.append("%s has names %s is missing: %s"
                            % (py_name, gd_name, ", ".join(only_py)))
        if only_gd:
            failures.append("%s has names %s does not define: %s"
                            % (gd_name, py_name, ", ".join(only_gd)))
        for name in sorted(set(py) & set(gd)):
            if py[name] != gd[name]:
                failures.append("%s.%s = %d but %s[\"%s\"] = %d"
                                % (py_name, name, py[name], gd_name, name, gd[name]))
        print("  %-20s %2d members  <->  %-14s %2d entries"
              % (py_name, len(py), gd_name, len(gd)))
    if failures:
        print()
        for f in failures:
            print("FAIL  %s" % f)
        print("\nThe exporter writes these NAMES into terrain.json and RomTerrain.gd "
              "reads them\nback as BYTES. A disagreement flattens or mis-costs tiles "
              "and never raises.")
        return 1
    print("\nOK  both terrain enum tables agree, name for name and byte for byte")
    return 0


if __name__ == "__main__":
    sys.exit(main())
