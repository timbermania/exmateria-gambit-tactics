#!/usr/bin/env python3
"""Mutation seed for `check_tune_owner_self_registration.py` — each rule fires on a known defect.

    uv run python tools/seed_tune_owner_self_registration.py

A guard that prints is not a guard that reports. All four rules were CLEAN on
arrival (#535 measured 13/13 class-load owners calling `register_tunables()` from
`_static_init` and 4/4 autoloads calling it from `_ready`), so a run that says
nothing says nothing. Each rule is handed the defect it exists to catch and must
go from clean to flagged.

Nothing is written to the tree. `check_tune_owner_self_registration.evaluate()`
takes the owner rows and Tune.gd's literals as INPUT, so the seed mutates data —
the repo's worktrees are shared with other agents, and a control that edits
production code to prove a guard works is a race, not a control.

S2 gets a SECOND arm that is not synthetic: the pre-#535 `src/core/Tune.gd`, read
from trunk, still carries `register_all()`'s seventeen owner paths. Feeding those
literals in must flag — that is the rule catching the exact defect #535 removed,
on the real bytes that had it, rather than on a string this file made up. If a
future change re-centralizes the replay, this is the arm that says so.
"""
import importlib.util
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "ctosr", HERE / "check_tune_owner_self_registration.py")
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

FOUND = g.owners()
SCRIPTS, ROOTS = g.tune_literals()
AUTO = g.autoloads()

# The live examples each rule is seeded against, named rather than positional so a
# reordered scan cannot silently seed the wrong file.
CLASS_LOAD = "src/units/Unit.gd"
AUTOLOAD_SCRIPT = "src/audio/AudioHostAdapter.gd"
ARG_TAKING = "src/effects/studio/SequenceThumbnail.gd"
CONTROL_REV = "origin/import-godot-game"


def rows_with(rel, *, static_init=None, ready=None):
    """FOUND with one file's boot-path flags overridden."""
    out = []
    for r, st, args, si, rd in FOUND:
        if r == rel:
            si = si if static_init is None else static_init
            rd = rd if ready is None else ready
        out.append((r, st, args, si, rd))
    return out


def run(found=None, scripts=None, roots=None):
    return g.evaluate(found or FOUND,
                      SCRIPTS if scripts is None else scripts,
                      ROOTS if roots is None else roots, AUTO)


def show(label, idx, rows, want):
    hit = bool(rows[idx])
    ok = hit == want
    print("  %-4s %-56s %s" % ("PASS" if ok else "FAIL", label,
                               "flagged" if hit else "clean"))
    for r in rows[idx][:3]:
        print("           %s" % (r,))
    return ok


def precondition() -> bool:
    """The three named files must be in the scan with the shape each seed assumes."""
    ok = True
    shape = {r: (st, args) for r, st, args, _si, _rd in FOUND}
    for rel, want in ((CLASS_LOAD, (True, False)), (AUTOLOAD_SCRIPT, (False, False)),
                      (ARG_TAKING, (True, True))):
        got = shape.get(rel)
        if got != want:
            ok = False
            print("  FAIL precondition: %s is %s, seed assumes %s "
                  "(static, takes_args) — this seed would test nothing" % (rel, got, want))
    return ok


def pre_535_literals():
    """`register_all()`'s owner paths, read from the pre-#535 Tune.gd on trunk."""
    root = HERE.parents[1]
    src = subprocess.run(["git", "show", "%s:godot-learning/src/core/Tune.gd" % CONTROL_REV],
                         cwd=root, capture_output=True, text=True).stdout
    if "func register_all()" not in src:
        return None, None
    return (re.findall(r'"(res://[^"]+\.gd)"', src), re.findall(r'"(/root/[^"]*)"', src))


ok = precondition()

print("\nS1 — a class-load owner whose _static_init does not call register_tunables()")
ok &= show("UNSEEDED", 0, run(), False)
ok &= show("SEEDED (Unit._static_init stops calling it)", 0,
           run(found=rows_with(CLASS_LOAD, static_init=False)), True)

print("\nS2 — Tune.gd naming an owner (the inversion, mechanized)")
ok &= show("UNSEEDED", 1, run(), False)
ok &= show("SEEDED (one owner path re-added to Tune.gd)", 1,
           run(scripts=SCRIPTS + ["res://src/units/Unit.gd"]), True)
ok &= show("SEEDED (an autoload path re-added to Tune.gd)", 1,
           run(roots=ROOTS + ["/root/AudioHostAdapter"]), True)
pre_scripts, pre_roots = pre_535_literals()
if pre_scripts is None:
    ok = False
    print("  FAIL could not read the pre-#535 Tune.gd from %s" % CONTROL_REV)
else:
    ok &= show("SEEDED (the REAL pre-#535 Tune.gd, %d+%d paths)"
               % (len(pre_scripts), len(pre_roots)), 1,
               run(scripts=pre_scripts, roots=pre_roots), True)

print("\nS3 — an autoload owner whose _ready does not call register_tunables()")
ok &= show("UNSEEDED", 2, run(), False)
ok &= show("SEEDED (AudioHostAdapter._ready stops calling it)", 2,
           run(found=rows_with(AUTOLOAD_SCRIPT, ready=False)), True)

print("\nS4 — an arg-taking register_tunables called with no arguments")
ok &= show("UNSEEDED", 3, run(), False)
ok &= show("SEEDED (SequenceThumbnail gains a bare _static_init call)", 3,
           run(found=rows_with(ARG_TAKING, static_init=True)), True)

print("\n%s" % ("all four rules are live and reporting"
                if ok else "A RULE DID NOT MOVE UNDER ITS SEED — it is not measuring."))
sys.exit(0 if ok else 1)
