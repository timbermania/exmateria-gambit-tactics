#!/usr/bin/env python3
"""Guard: the OUT-OF-BATTLE vitals builder is named only where somebody argued it is safe.

    uv run python tools/check_vitals_funnel.py          # guard
    uv run python tools/check_vitals_funnel.py --list   # print the current namer set, for rebasing

THE DEFECT THIS EXISTS FOR. `FormationScene.vitals_view_from_character` cannot report
damage *even in principle*: `UnitProgression` holds no current HP, only
`get_effective_hp()`, so the builder writes `current_hp = max_hp` literally. Live damage
lands elsewhere — `CombatLoop._apply_hp_change` writes `unit.unit_stats.current_hp`. So a
BATTLE surface pushing that dict shows every unit at full HP however hurt, and it reads as
a refresh bug rather than a wrong-source bug. It shipped twice: the map-cursor hover pair,
then the battlefield Status screen, where it was the same wrong line spelled FOUR times.

Both are fixed — the battlefield builder is `FormationMapHost.vitals_view_for(character,
unit)`, and `FormationDetailTransition` routes all four of its `set_unit_view` sites through
ONE `_vitals_view(character)` funnel that asks the MAP host for the live unit. This guard
keeps the population of identity-only namers from growing back.

⚠️ COUNT THE BUILDER, NOT THE PUSH. The first cut of this census matched `set_unit_view(...)`
and was weak in a way worth recording, because

    var v := FormationScene.vitals_view_from_character(character)
    _detail.set_unit_view(v)

walks straight past a push-shaped match while reintroducing the whole bug. That split was
SEEDED and confirmed to sail past the push spelling. The builder has to be NAMED to be
called, so counting the builder has no such escape.

⚠️ COMMENT LINES ARE STRIPPED BEFORE MATCHING. The failure this prevents is silent and
permanent: the moment somebody documents the retired spelling beside the funnel — and a
docstring saying "we no longer write X" is a likely thing to write — an unstripped census
matches its own prose and goes green for the rest of the file's life.

This is load-bearing TODAY, not defensive, and going repo-wide is what showed it: three
production files — `src/ui3/UnitInfoCluster.gd`, `src/ui3/UnitInfoPresenter.gd` and
`src/ui3/detail/DetailScene.gd` — name the builder ONLY in prose, and two more (the map host
and the transition) carry a comment mention beside their real one. Without the strip a CLEAN
tree reds three times.

WHAT THIS GUARD CANNOT SEE, stated because this repo's blind spots have all scored
non-zero eventually:

  - **Inheritance.** `FormationMapHost extends FormationScene`, so the base's identity-only
    push in `FormationScene._update_vitals_for_selection` is INHERITED by the battlefield
    host. It is safe only because the host OVERRIDES that method (`FormationMapHost.gd`,
    `_update_vitals_for_selection`) to push `_hovered_unit`/`_selected_unit` instead. Delete
    the override and this guard stays green while the bug is back. A namer register is a
    register of NAMES; it is not a proof of reach.
  - **Other builders.** `vitals_view_for`'s own numerator overlay is not checked here; the
    behavioural arms in `FormationMapHostTest` and `FormationVitalsViewTest` own that.

WHY A REGISTER OF LINES AND NOT A COUNT. A count has to be re-tuned every time a file is
trimmed, and a threshold nobody dares move is a guard nobody trusts. Naming the surviving
line says "the census read the right file AND found the right line" — which is the thing a
zero-offender verdict cannot say about itself.

THREE ARMS, because a two-armed ratchet still lets the list rot:

  1. GREW    — a non-comment namer line that is in no row is RED. The fifth site.
  2. STALE   — a row whose file is gone, or whose line is no longer in that file, is RED.
               Without this the register would keep excusing namers that had already been
               removed, and the excuse list would only ever grow.
  3. BLIND   — finding ZERO namer lines anywhere is RED. An empty register and a walk that
               examined nothing are the same output; this guard refuses to report absence
               it cannot distinguish from not looking.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE.parent

# The builder's bare name. Matched WITHOUT the `FormationScene.` prefix on purpose: the
# subclass calls it unqualified (`var view := vitals_view_from_character(character)`) and a
# prefix-qualified match would miss exactly the file that is closest to the battlefield.
BUILDER = "vitals_view_from_character"

# Production source only. Tests name the builder freely — that is their job — and docs/ADRs
# quote it by design; neither can push a view at a player.
ROOTS = ("src", "addons")

# THE REGISTER. file -> {stripped line: why it is safe}. Every row is an argument, not an
# exemption: "it was already there" is the state this register exists to delete.
ALLOWED: dict[str, dict[str, str]] = {
    "src/ui3/formation/FormationScene.gd": {
        "static func vitals_view_from_character(character) -> Dictionary:":
            "the definition itself.",
        "_cluster.set_unit_view(vitals_view_from_character(character))":
            "the ROSTER host's own docked-pair repaint, in `_update_vitals_for_selection`. "
            "Out of battle there is no live unit to read, so the identity IS the truth. "
            "⚠️ Inherited by FormationMapHost, which overrides the method — see the "
            "inheritance note in this file's docstring.",
    },
    "src/ui3/formation/FormationMapHost.gd": {
        "var view := vitals_view_from_character(character)":
            "the BATTLEFIELD builder's base layer. `vitals_view_for` starts from the "
            "identity's view and overlays the live UnitStats numerators + statuses over it; "
            "the denominators, name, job, level and portrait stay the identity's, because a "
            "Change-Job commit is what moves those.",
    },
    "src/ui3/formation/FormationDetailTransition.gd": {
        "return FormationScene.vitals_view_from_character(character)":
            "`_vitals_view`'s ROSTER leg — the one the funnel returns when `_map_host()` is "
            "null. The battlefield leg beside it goes to `FormationMapHost.vitals_view_for`. "
            "This is THE row the four-sites-spelled-wrong defect collapsed into; a SECOND "
            "namer in this file is that bug coming back.",
    },
    "src/ui3/detail/DetailSceneBoot.gd": {
        "detail.set_unit_view(FormationScene.vitals_view_from_character(c))":
            "a standalone screenshot BOOT. It constructs a synthetic Character and there is "
            "no battlefield, no CombatLoop and no live unit anywhere in the scene — the "
            "identity is the only source that exists.",
    },
    "src/ui3/detail/StartActionMenuBoot.gd": {
        "detail.set_unit_view(FormationScene.vitals_view_from_character(c))":
            "same as DetailSceneBoot — a standalone boot over a synthetic Character.",
    },
}


def namer_lines(path: Path) -> list[tuple[int, str]]:
    """Non-comment lines in `path` that NAME the builder, as (1-indexed lineno, stripped)."""
    out: list[tuple[int, str]] = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if line.startswith("#"):
            continue          # never let a file's own prose answer for its code
        if BUILDER in line:
            out.append((n, line))
    return out


def walk() -> dict[str, list[tuple[int, str]]]:
    found: dict[str, list[tuple[int, str]]] = {}
    for root in ROOTS:
        base = PKG / root
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            hits = namer_lines(path)
            if hits:
                found[path.relative_to(PKG).as_posix()] = hits
    return found


def main() -> int:
    found = walk()

    if "--list" in sys.argv:
        for rel in sorted(found):
            print(rel)
            for n, line in found[rel]:
                print("    %-5d %s" % (n, line))
        return 0

    fail: list[str] = []

    # arm 3 — BLIND. Do this first: every other verdict below is meaningless if the walk
    # examined nothing (a moved package root, a renamed builder, an rglob that followed no
    # symlink). A zero from a blind instrument is not absence.
    total = sum(len(v) for v in found.values())
    if total == 0:
        print("check_vitals_funnel: RED — the walk found ZERO mentions of `%s` under %s."
              % (BUILDER, "/, ".join(ROOTS) + "/"))
        print("  That is not 'no offenders'; it is 'this guard examined nothing'. The "
              "builder was renamed, or the package layout moved out from under ROOTS.")
        return 1

    # arm 1 — GREW.
    for rel in sorted(found):
        rows = ALLOWED.get(rel)
        for n, line in found[rel]:
            if rows is None:
                fail.append("GREW  %s:%d names the out-of-battle builder and the file is in "
                            "no row:\n           %s" % (rel, n, line))
            elif line not in rows:
                fail.append("GREW  %s:%d is a namer line in no row:\n           %s"
                            % (rel, n, line))

    # arm 2 — STALE.
    for rel, rows in sorted(ALLOWED.items()):
        if not (PKG / rel).exists():
            fail.append("STALE %s is listed but does not exist — the row cannot be checked "
                        "against anything." % rel)
            continue
        present = {line for _, line in found.get(rel, [])}
        for line in sorted(rows):
            if line not in present:
                fail.append("STALE %s no longer contains its listed line — delete the row, or "
                            "the file is exempt from arm 1 forever:\n           %s"
                            % (rel, line))

    if fail:
        print("check_vitals_funnel: RED — %d problem(s)" % len(fail))
        for f in fail:
            print("  " + f)
        print("\n`%s` writes current_hp = max_hp by construction. A battle surface pushing it "
              "shows FULL HP for every unit in the fight, however hurt — and it reads as a "
              "refresh bug, not a wrong-source bug. The battlefield builder is "
              "`FormationMapHost.vitals_view_for(character, unit)`." % BUILDER)
        return 1

    print("check_vitals_funnel: OK — %d mention(s) of `%s` across %d production file(s), "
          "every one of them argued for in this guard's register"
          % (total, BUILDER, len(found)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
