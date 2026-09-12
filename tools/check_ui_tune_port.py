#!/usr/bin/env python3
"""No UI member names the host autoload `Tune`; they route through `TunePort`.

THE DEFECT THIS EXISTS FOR. `Tune` is an autoload -- a name `project.godot`'s
`[autoload]` block creates and NOTHING else declares. An addon cannot ship
`project.godot` entries (ADR-0262 dec. 6), so the moment UI's 121 files move
under `addons/exmateria_ui/`, every bare `Tune.` becomes a name that does not
resolve in any project that does not autoload it -- including a stranger's.
#1268 routed all 107 through `ExMateriaPlatform.TunePort`. This keeps them there.

WHY THIS IS NOT ALREADY COVERED. `check_addon_portability.py` arm 2a asks exactly
this question, but only of files UNDER AN ADDON ROOT. UI is still in `src/ui3/`,
so arm 2a cannot see it, and between now and the `git mv` a new bare `Tune.` reds
nothing. This guard owns precisely that window.

WHY IT DOES NOT HARDCODE `src/ui3/`. A guard whose subject is a directory goes
silently GREEN when that directory moves -- it stops LOOKING, and green reads as
clean. The subject here is the MEMBERSHIP, derived from `classify_blueprint` by
`ui_facade_census.members()` (ADR-0306 §1.1), and an EMPTY subject is a FAILURE,
not a pass: when M5 empties, the files have moved and arm 2a now owns the
question -- delete this guard in that commit, deliberately, rather than letting it
certify a tree it is no longer reading.

THE BLANKER IS STATEFUL, AND THAT IS THE POINT. These files are heavily
documented; `Tune` appears in prose throughout. A line-by-line blanker cannot see
a `\"\"\"...\"\"\"` block -- ADR-0306 §4 records three defects of that exact family,
one of which published a name off a sentence. A `Tune.` inside a doc block is
CODE-SHAPED PROSE and must not red; a `Tune.` inside a triple-quoted block that
the naive blanker would miss must red. Both directions are asserted in
`test_check_ui_tune_port.py`.

Usage:  python3 tools/check_ui_tune_port.py [--verbose]
"""
import argparse
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BARE = re.compile(r"(?<![\w.])Tune\.")


def _census():
    spec = importlib.util.spec_from_file_location(
        "ui_facade_census", ROOT / "tools/ui_facade_census.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def violations(census):
    """[(rel, lineno, text)] -- bare `Tune.` in member CODE."""
    out = []
    for rel in census.members()[0]:
        p = ROOT / rel
        if p.suffix != ".gd":
            continue
        for lineno, blanked in census.code_lines(p.read_text()):
            if BARE.search(blanked):
                raw = p.read_text().splitlines()[lineno - 1].strip()
                out.append((rel, lineno, raw))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    census = _census()
    subject = census.members()[0]

    if not subject:
        print("check_ui_tune_port: FAIL -- the subject is EMPTY.\n"
              "  M5 resolved to zero files, so this guard read nothing and would\n"
              "  have exited green. Either the membership moved under an addon root\n"
              "  (in which case check_addon_portability arm 2a owns this question and\n"
              "  THIS GUARD SHOULD BE DELETED in that same commit) or the classifier\n"
              "  changed. A guard that stopped looking is not a guard that passed.")
        return 1

    bad = violations(census)
    if bad:
        print(f"check_ui_tune_port: FAIL -- {len(bad)} bare `Tune.` reach(es) in "
              f"{len({b[0] for b in bad})} UI member(s).")
        print("  A member must route through the port:\n"
              "    const TunePort = ExMateriaPlatform.TunePort   # ADR-0211 dec. 4 -- ALIAS,\n"
              "                                                  # never preload an addon path\n"
              "  and `TunePort.get_value` takes a REQUIRED fallback the bare `Tune.get_value`\n"
              "  does not -- pass the same literal the slug's own `bind` registered.\n"
              "  NOTE: a const is a MEMBER, so a subclass INHERITS the alias and redeclaring\n"
              "  it is a parse error (FormationMapHost, UIUnitInfoWindow).")
        for rel, lineno, text in bad:
            print(f"    {rel}:{lineno}  {text}")
        return 1

    print(f"check_ui_tune_port: OK -- {len(subject)} UI members, 0 bare `Tune.` reaches.")
    if a.verbose:
        aliased = sum(1 for rel in subject
                      if (ROOT / rel).suffix == ".gd"
                      and "const TunePort = ExMateriaPlatform.TunePort"
                      in (ROOT / rel).read_text())
        print(f"  {aliased} member(s) declare the alias; the rest inherit it or do not use it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
