#!/usr/bin/env python3
"""Guard: every quoted `res://` SOURCE path in the tree resolves to a file on disk.

    uv run python tools/check_res_paths.py [--list] [--tsv]

WHY THIS EXISTS, AND WHY NOTHING ELSE REPORTS IT. Extraction #3's loop pass 6
moves 46 files and re-points **259 inbound `res://` references** — 32 production,
227 across 123 test files (`tools/path_refs.py Battlefield`). A `class_name` move
is caught by the parser. A `res://` path move is caught by nothing that runs
first, and the specific failure this repo has already measured is worse than
uncaught:

> a `.tscn` whose script `ext_resource` points at a moved path still **loads**.
> Godot prints a parse error to stderr, mounts the node **stripped of its
> script**, and the failure surfaces at whatever line first touches a property.
> — measured headful on the 4.8 fork, ADR-0157 -> *Soft spots*, Spike A

`rc` is not the verdict there either: the engine exits 0. So the scene comes up,
the test drives a node with no script, and the `[PASS]` marker prints. This guard
is the one that reads the path instead of the outcome.

WHAT IS IN THE UNIVERSE, AND WHY IT IS SOURCE FILES ONLY. Every `res://` literal
whose target suffix is one of `.gd .tscn .tres .gdshader .gdshaderinc .glsl
.glslinc` — the hand-written, git-tracked set. Widening it to *every* `res://`
literal was measured and rejected: 4,387 literals, 16 unresolved, and 13 of the
16 are ROM-derived assets this repo gitignores by design (`assets/ui/opntex/*`,
`assets/world_map/*`, `assets/sprites/02.png`). A guard that is red on a correct
checkout teaches everyone to ignore it. Source files are the set that is always
present, so an unresolved one is always a defect.

THE LITERAL MUST BE QUOTED, WHICH IS NOT PEDANTRY. Matching bare `res://…`
reports `tests/AudioBusLayoutTest.gd:16`, where the path appears inside a `##`
docstring, in backticks, as prose *about* an engine default the file is
explaining. That is this repo's own recurring defect — an assertion matching its
own comment — arriving from the other side. Requiring the surrounding quote drops
it and costs nothing: a `res://` path that reaches the engine is a string.

The obvious alternative, running the file through a comment stripper first, is
wrong here for a reason already paid for once: `res://` contains `//`, so a
shader-comment stripper eats every `#include "res://…"` line in the tree. Whole
comment LINES are skipped (`#` for GDScript, `//` for shaders); nothing else is
stripped.

WHAT THIS DOES NOT CHECK.
  - That the target is the RIGHT file. Set equality against the move manifest is
    `tools/check_move_manifest.py`'s arm 3; this arm only says the address
    resolves.
  - `.uid` sidecars and `.import` files. Godot regenerates both, and an `.import`
    row points into `.godot/imported/`, which is not tracked.
  - `uid://` references. A `.tscn` carries both; the uid is the engine's own
    index and is repaired by `--import`, while the path is the half a `git mv`
    breaks.
  - Anything under `docs/`, excluded as a referrer for the reason `path_refs.py`
    gives: prose about a path is not a path. (`tools/` is NOT excluded — see the
    note on SKIP_TOPS.)
  - `addons/exmateria_sound` and `addons/exmateria_spu`. `rglob` does not descend
    a symlinked directory and these are symlinks into `exmateria-sound/`, which is
    the RIGHT answer here rather than a hole: that package ships its own
    `project.godot`, so its `res://` resolves against a different root and every
    row would be a false positive. `_walk_roots.walk_files` exists for the
    instruments that DO need to descend; this one does not. Measured: 0 rows from
    either path.

KNOWN, TICKETED, AND NAMED — NEVER FILTERED. `KNOWN_BREAKS` is a list of exact
(referrer, target) pairs with an issue number each. It is a named list rather
than a rule for the reason #424 established on this codebase: an exclusion
expressed as a FILTER manufactures its own debt and cannot tell a break that was
triaged from one that merely matches the pattern. A pair whose break is REPAIRED
also fails here, so the list cannot rot silently.
"""
import os, pathlib, re, sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# Referrer files whose `res://` literals are read.
REFERRER_SUFFIXES = {".gd", ".gdshader", ".gdshaderinc", ".glsl", ".glslinc",
                     ".tscn", ".tres", ".godot", ".cfg"}
# Target suffixes that must resolve. Hand-written, git-tracked source only.
TARGET_SUFFIXES = "gd|tscn|tres|gdshader|gdshaderinc|glsl|glslinc"
# Excluded as REFERRERS (prose about a path is not a path) and entirely.
#
# `tools/` is NOT here, and that is a deliberate departure from `path_refs.py`,
# which does exclude it. The reason path_refs gives — prose about a path is not a
# path — is about `.md`; `tools/` also holds 120 real `.gd` probes and capture
# rigs, and three of them named a moved file after extraction #3's loop pass 6.
# Excluding the directory would have hidden all three. The false positives the
# exclusion was protecting against are Python fixtures with synthetic `res://`
# keys (`tools/test_materialize_tunables.py`), and those are already out of
# scope: `.py` is not in REFERRER_SUFFIXES.
SKIP_TOPS = {".godot", ".git", "project-assets", "docs"}

# The optional `*` is `project.godot`'s enabled-singleton marker, and it is not
# cosmetic: `Autoload="*res://path.gd"` puts a character between the opening quote
# and the scheme, so a quote-adjacent pattern is blind to EVERY autoload entry.
# Extraction #3's own register counts three of them among its path references
# (`docs/EXTRACTION-3-PATH-REFERENCES.md`), and the first version of this guard
# reported nothing when one was seeded broken.
LITERAL = re.compile(
    r"""(["'])\*?(res://[^"']+\.(?:%s))\1""" % TARGET_SUFFIXES)

# (referrer, target, why). Both directions fail: an unlisted break and a listed
# break that has been repaired.
# EMPTY, and that is the success state: #533 arm 1's `GPUCallbackE317Test.tscn`
# was the whole population, and it was DELETED rather than repaired — its script
# was never in git at any commit, so there was nothing to restore. A row here is
# debt; an empty list means every quoted source literal in the tree resolves.
KNOWN_BREAKS = []


def scan():
    """Yield (referrer, line_no, target, resolves) for every quoted source literal."""
    for q in sorted(PROJECT_DIR.rglob("*")):
        rel = q.relative_to(PROJECT_DIR).as_posix()
        if rel.split("/")[0] in SKIP_TOPS:
            continue
        if q.suffix not in REFERRER_SUFFIXES or not q.is_file():
            continue
        comment = "#" if q.suffix == ".gd" else "//"
        for i, ln in enumerate(q.read_text(errors="replace").splitlines(), 1):
            if ln.lstrip().startswith(comment):
                continue
            for m in LITERAL.finditer(ln):
                target = m.group(2)
                yield rel, i, target, (PROJECT_DIR / target[len("res://"):]).exists()


def main() -> int:
    os.chdir(PROJECT_DIR)
    rows = list(scan())
    broken = [(r, i, t) for r, i, t, ok in rows if not ok]
    known = {(r, t) for r, t, _ in KNOWN_BREAKS}
    hit = {(r, t) for r, _, t in broken}

    if "--tsv" in sys.argv:
        print("referrer\tline\ttarget\tresolves")
        for r, i, t, ok in rows:
            print(f"{r}\t{i}\t{t}\t{int(ok)}")
        return 0

    print(f"{len(rows)} quoted res:// source references across "
          f"{len({r for r, _, _, _ in rows})} files")

    if "--list" in sys.argv:
        for r, i, t, ok in rows:
            if not ok:
                print(f"  {r}:{i}  ->  {t}")

    fail = []
    for r, i, t in broken:
        if (r, t) in known:
            continue
        fail.append(f"unresolved  {r}:{i}  ->  {t}")
    for r, t, why in KNOWN_BREAKS:
        if (r, t) not in hit:
            fail.append(f"KNOWN_BREAKS names a pair that now RESOLVES (or whose "
                        f"referrer is gone) — delete the row: {r} -> {t}  [{why}]")

    # Count the INTERSECTION, not the list length. `len(KNOWN_BREAKS)` reads as a
    # claim that every named row is still broken, which is exactly what the stale
    # arm above exists to disprove — the summary must not assert it.
    live_known = sum(1 for r, t, _ in KNOWN_BREAKS if (r, t) in hit)
    print(f"{len(broken)} unresolved, {live_known} of them known and named "
          f"({len(KNOWN_BREAKS)} row(s) on the list)")
    for r, t, why in KNOWN_BREAKS:
        print(f"  KNOWN{'' if (r, t) in hit else ' (STALE)'}  {r} -> {t}\n         {why}")

    print()
    if fail:
        for f in fail:
            print(f"[FAIL] {f}")
        print(f"\n{len(fail)} failure(s). A moved file whose referrers were not "
              f"re-pointed is the shape this reports; the scene still LOADS.")
        return 1
    print("[PASS] every quoted res:// source reference resolves.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
