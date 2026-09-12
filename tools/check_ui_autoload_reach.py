#!/usr/bin/env python3
"""A UI member may reach NO autoload identifier — a stranger rig declares zero.

Every one of the eight stranger rigs under `tests/stranger/*/project.godot` has an
EMPTY `[autoload]` block. That is not an oversight: it is what makes the rig a test.
An addon cannot ship `project.godot` entries (ADR-0262 dec. 6), so any bare autoload
identifier a member names resolves in the HOST and is simply undefined in a stranger
project. `addons/exmateria_catalogue` ships `CharacterCatalog.gd` and the HOST declares
the autoload pointing at it — the script travels, the registration does not.

So `Tune` was never the problem; it was one of SEVEN. Pass 6 step 2 ported `Tune` to
`ExMateriaPlatform.TunePort` and left six standing (ADR-0308).

This is a RATCHET, not a gate. The reaches below exist today and the suite must stay
green while they are paid off one port at a time. It fails three ways:

  * a reach appears that BASELINE does not allow, or a count GROWS  -> a regression;
  * a BASELINE entry is listed but the real count is now LOWER      -> pay down the
    entry too, or the ratchet stops ratcheting and silently re-admits the reach;
  * the subject is EMPTY                                            -> the census
    broke, or the move happened; see the note under `main`.

When BASELINE is empty and the measured reach is zero, the UI half of arm 2a is clear
and THIS FILE SHOULD BE DELETED along with its block in `tests/run_all_tests.sh` —
exactly as `tools/check_ui_tune_port.py` is deleted at the move.
"""
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Per autoload: how many reaches stand today, and the ticket that pays it off.
# A count here is a DEBT, never a budget — see the module docstring.
BASELINE = {
    "UI3Registry":      (1,  "dissolves AT the move -- UI's own autoload becomes a preload"),
}

SHADERS = (".gdshader", ".gdshaderinc")


def _census():
    spec = importlib.util.spec_from_file_location(
        "ui_facade_census", ROOT / "tools" / "ui_facade_census.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def autoload_names(text):
    """The identifiers the HOST registers. Parsed, never hardcoded: a new autoload
    must come under this guard the day it is added, without anyone remembering."""
    if "[autoload]" not in text:
        return []
    blk = text.split("[autoload]", 1)[1].split("\n[", 1)[0]
    out = []
    for ln in blk.splitlines():
        if "=" in ln and not ln.lstrip().startswith(";"):
            n = ln.split("=", 1)[0].strip()
            if n:
                out.append(n)
    return out


def measure(census, members, names):
    pats = {n: re.compile(r"(?<![\w.])%s\b" % re.escape(n)) for n in names}
    counts = {}
    sites = {}
    for rel in members:
        p = ROOT / rel
        if p.suffix not in {".gd", ".tscn", *SHADERS}:
            continue
        try:
            txt = p.read_text()
        except OSError:
            continue
        for i, ln in census.code_lines(txt, shader=p.suffix.startswith(".gdshader")):
            for n, pat in pats.items():
                if pat.search(ln):
                    counts[n] = counts.get(n, 0) + 1
                    sites.setdefault(n, []).append(f"{rel}:{i}")
    return counts, sites


def main():
    census = _census()
    members, _bucket = census.members()
    if not members:
        print("check_ui_autoload_reach: FAIL -- the subject is EMPTY.")
        print("  Either ui_facade_census.members() broke, or src/ui3 has moved into")
        print("  the addon. If it moved, DELETE this guard and its run_all_tests.sh")
        print("  block in the same commit -- it cannot referee an addon it cannot see.")
        return 1

    names = autoload_names((ROOT / "project.godot").read_text())
    if not names:
        print("check_ui_autoload_reach: FAIL -- project.godot declares no autoloads.")
        print("  That is the one reading this guard cannot distinguish from success.")
        return 1

    counts, sites = measure(census, members, names)
    problems = []

    for n in sorted(counts):
        have = counts[n]
        if n not in BASELINE:
            problems.append(
                f"NEW autoload reach: `{n}` x{have} -- not in BASELINE.\n"
                f"      first site: {sites[n][0]}\n"
                f"      A member may reach no autoload at all. Route it through a port,\n"
                f"      or if this is a genuine new debt, add it to BASELINE with a ticket.")
        elif have > BASELINE[n][0]:
            problems.append(
                f"GREW: `{n}` is {have}, BASELINE allows {BASELINE[n][0]} "
                f"(+{have - BASELINE[n][0]}).\n"
                f"      newest sites: {', '.join(sites[n][-3:])}\n"
                f"      {BASELINE[n][1]}")

    for n, (allow, note) in sorted(BASELINE.items()):
        have = counts.get(n, 0)
        if have < allow:
            problems.append(
                f"PAID DOWN but still listed: `{n}` is {have}, BASELINE says {allow}.\n"
                f"      Lower it to {have} (or drop the entry at 0) in the SAME commit.\n"
                f"      A baseline that outlives its debt re-admits the reach silently.\n"
                f"      {note}")

    total = sum(counts.get(n, 0) for n in BASELINE)
    owed = sum(v[0] for v in BASELINE.values())

    if problems:
        print(f"check_ui_autoload_reach: {len(problems)} problem(s)")
        for p in problems:
            print(f"  * {p}")
        return 1

    if not BASELINE and total == 0:
        print("check_ui_autoload_reach: the debt is CLEAR -- delete this guard.")
        return 0

    print(f"check_ui_autoload_reach: OK -- {len(members)} UI members, "
          f"{total} autoload reach(es) owed across {len(BASELINE)} identifier(s), "
          f"none new, none grown.")
    for n, (allow, note) in sorted(BASELINE.items(), key=lambda kv: -kv[1][0]):
        print(f"    {n:<18} {counts.get(n, 0):>3}/{allow:<3} {note}")
    print(f"  arm 2a will not pass until this reads 0/{owed} -> 0 and the guard is deleted.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
