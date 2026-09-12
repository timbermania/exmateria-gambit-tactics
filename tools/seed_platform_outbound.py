#!/usr/bin/env python3
"""Goal #5's outbound score for `platform`, with the seeds that say what the zero means.

    uv run python tools/seed_platform_outbound.py

ADR-0159 dec. 2 measured `platform` reaching **fifteen files across seven of the
eleven systems** while `score_goals.outbound_reaches` — goal #5's guard — scored
it **zero**, and proved the zero was blindness rather than absence by staging
`platform`'s four files as an addon root and seeding one literal `preload` of a
`Battlefield` file (0 -> 1). #535 deleted the reach. This runs dec. 2's
measurement again, plus the arm dec. 2 did not run, because a zero that was
already zero before the fix cannot certify the fix on its own.

  UNSEEDED                     `platform` as it stands.
  SEEDED literal preload       dec. 2's arm — the guard must move (0 -> 1), or it
                               is not reporting and neither number below means
                               anything.
  SEEDED the ACTUAL shape      `register_all()`'s own shape put back: `res://`
                               paths in an ARRAY LITERAL, `load()`ed through a
                               loop variable. dec. 2 showed the guard is blind to
                               it. This arm exists so that stays measured — it is
                               why S2 of `check_tune_owner_self_registration.py`
                               has to exist, and why "goal #5 scores zero" is not
                               by itself evidence that `platform` is a leaf.

The non-blind witness is `tools/path_refs.py platform`, which scans `res://`
literals anywhere and therefore DID see the defect: **13 outbound references into
6 systems at trunk `67b469115`, all from `src/core/Tune.gd`, 3 afterwards and all
three to `res://config/…` — Tune's own staging file and registry snapshot, which
are not a system.** It is 13 rather than 17 because a `/root/` autoload path is
not a `res://` literal; the four autoload owners were invisible to every
instrument here, and S2 is the only one that sees all seventeen.

Stages into `addons/_seed_platform_outbound/` under the project (the scan walks
`PROJECT_DIR / addon_rel`) and removes it again, including on failure.
"""
import pathlib
import shutil
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import score_goals as sg  # noqa: E402  (needs the path above)

ROOT = pathlib.Path(__file__).resolve().parents[1]
STAGE = "addons/_seed_platform_outbound"
DEST = ROOT / STAGE

# The shape the defect actually had, as `register_all()` wrote it.
ARRAY_LITERAL_LOOP = (
    'func _revert() -> void:\n'
    '\tfor p in ["res://src/map/Tile.gd", "res://src/units/Unit.gd"]:\n'
    '\t\tvar s := load(p) as GDScript\n'
    '\t\tif s != null and s.has_method("register_tunables"):\n'
    '\t\t\ts.register_tunables()\n')


def stage(files, seed_line=None):
    if DEST.exists():
        shutil.rmtree(DEST)
    for rel in files:
        dst = DEST / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        text = (ROOT / rel).read_text()
        if seed_line and rel.endswith("src/core/Tune.gd"):
            text += "\n" + seed_line + "\n"
        dst.write_text(text)


def report(label, rows, want_nonzero):
    ok = bool(rows) == want_nonzero
    print("  %-4s %-58s %d cross-system reach(es)"
          % ("PASS" if ok else "FAIL", label, len(rows)))
    for r in sorted(rows)[:4]:
        print("           %s" % (r,))
    return ok


def main() -> int:
    files = sorted(r for r, b in sg._tables()["sysof"].items() if b == "platform")
    print("platform (%d files): %s\n" % (len(files), ", ".join(files)))
    ok = True
    try:
        stage(files)
        ok &= report("UNSEEDED (platform as-is)",
                     sg.cross_system(sg.outbound_reaches(STAGE, "platform")), False)
        stage(files, 'var _seed := preload("res://src/map/Tile.gd")')
        ok &= report("SEEDED literal preload of a Battlefield file (dec. 2's arm)",
                     sg.cross_system(sg.outbound_reaches(STAGE, "platform")), True)
        stage(files, ARRAY_LITERAL_LOOP)
        blind = sg.cross_system(sg.outbound_reaches(STAGE, "platform"))
        print("  %-4s %-58s %d cross-system reach(es)"
              % ("NOTE", "SEEDED register_all()'s ACTUAL shape (array + loop load)",
                 len(blind)))
        if blind:
            ok = False
            print("           the guard now SEES the array-literal shape — this note is stale,\n"
                  "           and ADR-0173's reasoning about why S2 exists should be revisited.")
        else:
            print("           blind, as dec. 2 found. Goal #5's guard cannot certify this fix;\n"
                  "           S2 of check_tune_owner_self_registration.py is what can.")
    finally:
        if DEST.exists():
            shutil.rmtree(DEST)
    print("\n%s" % ("the guard is live and reporting"
                    if ok else "AN ARM DID NOT MOVE AS EXPECTED — read the rows above."))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
