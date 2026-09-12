#!/usr/bin/env python3
"""Prove `tests/TuneOwnerSelfRegistrationTest.gd` reports a boot path that has gone wrong (#535).

Successor to `tools/seed_register_all_coverage.py`, which seeded the manifest that
`Tune.register_all()` used to hold. The list is gone (ADR-0173), so the defects are
different: an owner whose own boot path stops binding, an owner that binds nothing, a
`reset_overrides()` that goes back to clearing declarations, and a discovery walk that finds nobody.

A guard is worth exactly what its FAILING arm is worth, and this test has three phases
plus an anti-vacuity floor. Every one of them gets an arm.

    control                    nothing mutated                     -> everything green
    owner_stops_registering    Unit._static_init drops the call    -> phase 2 red
    autoload_stops_registering AudioHostAdapter._ready drops it    -> phase 2 red
    owner_binds_nothing        SkirtGeometryGenerator binds none   -> phase 2 red
    discovery_finds_nobody     the walk points at an empty root    -> the FLOOR red
    reset_overrides_clears_reg reset_overrides() clears it too     -> phase 3 red

THE LAST CASE IS ALSO THE FINDING, AND IT IS WHY IT RUNS SEVEN OTHER SCENES. Making
`reset_overrides()` clear the registry too collapses it back into `reset()`, which is the
pre-#535 world. All seven feature tests that
used to call `Tune.register_all()` right after `Tune.reset()` report it — but **only three
report it as an assertion**. The other four print `[PASS]` and are scored **THREW**, because
`get_value()`'s R5 assert fires inside a production node they spawned. Read off the `[PASS]`
marker they look green; read through the verdict reader they are red. That distinction is
the whole of #451 and it is worth keeping on a rig, because the first reading of this very
measurement got it wrong.

⚠️ THIS SCRIPT EDITS PRODUCTION SOURCE, so it REFUSES to run in the worktree it lives in.
The repo's worktrees are shared with other agents; a control that writes to production code
to prove a guard is a race, not a control. (The static half,
`seed_tune_owner_self_registration.py`, dodges this by taking the owner rows as data — a
runtime test cannot.) Point `--worktree` at a scratch checkout:

    git worktree add --detach /tmp/wt-seed HEAD
    (cd /tmp/wt-seed && tools/link_worktree_godot_assets.sh <this-worktree-root>)
    uv run python tools/seed_owner_self_registration_coverage.py --worktree /tmp/wt-seed

Needs a headful Godot; one scene at a time, so it is safe at the VRAM this box has
(ADR-0158 / #533: it is the PARALLEL arm that is invalid).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

TUNE = "src/core/Tune.gd"
UNIT = "src/units/Unit.gd"
AUDIO = "src/audio/AudioHostAdapter.gd"
SKIRT = "src/map/SkirtGeometryGenerator.gd"
TEST = "tests/TuneOwnerSelfRegistrationTest.gd"
SELF = ("TuneOwnerSelfRegistrationTest", "res://tests/TuneOwnerSelfRegistrationTest.tscn")

# The seven tests that called Tune.register_all() before #535 deleted it.
FORMER_CALLERS = [
    "CameraFeelTunablesTest", "CursorTunablesTest", "ScenarioCinematicTunablesTest",
    "ScenarioDialogueBoxTunablesTest", "ScenarioWeatherTunablesTest",
    "UnitForwardTunableTest", "VitalsLayoutTunablesTest",
]
# Measured, per test, through `tests/lib/verdict.sh` (#535, 2026-08-25). ALL SEVEN report the
# pre-#535 world; the interesting part is that they report it in two different channels, and
# only one of them is an assertion:
#
#   FAIL   the test's own assertion fires — a scrub does not reach the spawned node, because
#          the on_update it wired coalesced onto a null default.
#   THREW  the test still prints [PASS], and `get_value()`'s R5 assert fires anyway —
#          "get_value(render.ui_pixel_aspect) before its bind". Rule 9 of the verdict reader turns
#          a green that throws red. Reading the [PASS] marker instead of the verdict is what
#          #451 exists to prevent, and it is exactly the mistake this file's first draft made:
#          these four were written up as "cannot report the event" off the marker alone.
#
# Distinct from #534 arm 2's `drop_camera_owner`, which drops ONE owner from the old manifest
# and genuinely leaves CameraFeelTunablesTest PASS — the camera re-registers at its own class
# load. That finding stands; this mutation is a wider one and reaches further.
REPORTS_BY_ASSERTION = {"CursorTunablesTest", "ScenarioDialogueBoxTunablesTest",
                        "ScenarioWeatherTunablesTest"}


def scene(name: str) -> str:
    return "res://tests/%s.tscn" % name


def self_arm(want: str):
    return [(SELF[0], SELF[1], want)]


# (case, [(file, old, new)], [(label, scene, want)]). Each anchor must match exactly once:
# if the file is reformatted the seed FAILS to apply and says so, rather than quietly
# testing nothing.
CASES = [
    ("control", [], self_arm("PASS")),
    ("owner_stops_registering",
     [(UNIT, "static func _static_init() -> void:\n\tif Engine.is_editor_hint():\n"
             "\t\treturn\n\tregister_tunables()",
       "static func _static_init() -> void:\n\tif Engine.is_editor_hint():\n\t\treturn")],
     self_arm("FAIL")),
    ("autoload_stops_registering",
     [(AUDIO, "func _ready() -> void:\n\tregister_tunables()\n",
       "func _ready() -> void:\n")],
     self_arm("FAIL")),
    ("owner_binds_nothing",
     [(SKIRT, "static func register_tunables() -> void:\n"
              "\tTune.bind(LAND_SKIRT_DEBUG_SLUG, LAND_SKIRT_DEBUG_DEFAULT)",
       "static func register_tunables() -> void:\n\tpass")],
     self_arm("FAIL")),
    ("discovery_finds_nobody",
     [(TEST, 'const _SCAN_ROOTS := ["res://src", "res://addons"]',
       'const _SCAN_ROOTS := ["res://no_such_root"]')],
     self_arm("FAIL")),
    ("reset_overrides_clears_registry",
     [(TUNE, "func reset_overrides() -> void:\n\t_overrides.clear()\n",
       "func reset_overrides() -> void:\n\t_registry.clear()\n\t_overrides.clear()\n")],
     self_arm("FAIL") + [
         (n, scene(n), "FAIL" if n in REPORTS_BY_ASSERTION else "THREW")
         for n in FORMER_CALLERS]),
]


def sh(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def verdict(gl: Path, log: Path, rc: int) -> str:
    """Score with tests/lib/verdict.sh — the ONE verdict reader (#451), never a local rule."""
    out = sh(["bash", "-c", f'source tests/lib/verdict.sh; test_verdict "{log}" {rc}'], gl)
    return (out.stdout or out.stderr).strip().splitlines()[-1].strip()


def run_scene(gl: Path, godot: str, scn: str, log: Path, timeout_s: int) -> tuple[str, list[str]]:
    with log.open("w") as fh:
        rc = subprocess.run([godot, "--path", ".", scn], cwd=gl, stdout=fh,
                            stderr=subprocess.STDOUT, timeout=timeout_s).returncode
    named = [ln.strip() for ln in log.read_text(errors="replace").splitlines()
             if ln.startswith("[FAIL] ") and " " in ln[7:].strip()]
    return verdict(gl, log, rc), named


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--worktree", required=True,
                    help="scratch worktree root (NOT this one) — its source gets mutated")
    ap.add_argument("--godot", default="godot", help="the 4.8 fork on $PATH")
    ap.add_argument("--timeout", type=int, default=360)
    ap.add_argument("--case", action="append", help="run only these cases (repeatable)")
    args = ap.parse_args()

    here = Path(__file__).resolve().parents[2]
    dest = Path(args.worktree).resolve()
    if dest == here:
        print(f"refusing to mutate the worktree this script lives in ({here}).\n"
              "It is shared; see this file's docstring for the scratch-worktree recipe.",
              file=sys.stderr)
        return 2
    gl = dest / "godot-learning"
    if not (gl / TUNE).exists():
        print(f"not a populated worktree: {gl / TUNE} missing", file=sys.stderr)
        return 2

    touched = sorted({f for _c, muts, _r in CASES for f, _o, _n in muts})
    dirty = sh(["git", "status", "--porcelain", "--"]
               + [f"godot-learning/{f}" for f in touched], dest).stdout.strip()
    if dirty:
        print(f"already modified in {dest} — refusing to stack a case on it:\n{dirty}",
              file=sys.stderr)
        return 2

    pristine = {f: (gl / f).read_text() for f in touched}
    logs = gl / "tests" / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, str, str, str, str]] = []
    bad = False

    try:
        for case, muts, runs in CASES:
            if args.case and case not in args.case:
                continue
            for f, old, new in muts:
                text = pristine[f]
                if text.count(old) != 1:
                    print(f"case {case}: anchor appears {text.count(old)}x in {f} (want 1) — the "
                          f"file was reformatted and this case would test nothing:\n  {old!r}",
                          file=sys.stderr)
                    return 3
                (gl / f).write_text(text.replace(old, new))
            for label, scn, want in runs:
                log = logs / f"_seed_{case}_{label}.log"
                got, named = run_scene(gl, args.godot, scn, log, args.timeout)
                bad |= got != want
                rows.append((case, label, got, want, "; ".join(named[:2]) or "—"))
                print(f"[{'ok ' if got == want else 'BAD'}] {case:<32}{label:<32} -> {got:<9} "
                      f"(want {want})")
                for n in named[:2]:
                    print(f"          {n}")
            for f in touched:
                (gl / f).write_text(pristine[f])
    finally:
        for f in touched:
            (gl / f).write_text(pristine[f])

    print(f"\n{'case':<27}{'scene':<32}{'verdict':<9}{'want':<6}first named failure")
    for case, label, got, want, named in rows:
        print(f"{case:<32}{label:<32}{got:<9}{want:<6}{named[:60]}")
    print(f"\n{len(touched)} file(s) restored in {gl}.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
