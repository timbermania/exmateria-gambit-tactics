#!/usr/bin/env python3
"""The per-side rosters stay RETIRED (ADR-0180).

`PartyRoster`, `EnemyRoster` and `BaseRoster` are deleted. The player population
is the catalogue's owned overlay (`CharacterCatalog.owned_units()`); the enemy
population is the ENTD. There is no second store, and there is no second way to
put a Character into the catalogue.

WHY THIS IS MECHANIZED. ADR-0066 dec. 1 demoted the roster to "a selection/view
over the catalogue" in 2026 and nothing enforced it, so the code stayed the
INVERSE — `BaseRoster._ready()` promoted its own entries INTO the catalogue under
positional `party:N` / `enemy:N` slugs — for a year. The visible symptom was a
Formation screen showing "Marcus", a hand-invented blank Squire, in a frame whose
grid held a real unit. A decision that sits `proposed` and unenforced is a
decision that quietly does not hold; this is the second ADR in that family, and
the guard is what stops there being a third.

WHAT IT CHECKS
  1. `project.godot` declares no roster autoload.
  2. No `src/roster/` directory, and no `{Base,Party,Enemy}Roster.gd` anywhere in
     the walk.
  3. No `.gd` in the walk USES a roster autoload — a member access
     (`PartyRoster.spawn_unit(...)`), a `get_node("/root/PartyRoster")`, or an
     `extends`/`preload` of `res://src/roster/`.
  4. No committed roster seed under `assets/roster/`.

WHAT IT DELIBERATELY DOES NOT CHECK — and this half is load-bearing. `CombatUI.tscn`
has `Node3D`s literally NAMED `FriendlyRoster` and `EnemyRoster`; they are UI
panels with nothing to do with the autoloads, and `UICombatManager` reaches one by
NODE PATH (`$BaseLayer/EnemyRoster`, `has_node("BaseLayer/EnemyRoster")`). A guard
that grepped for the bare word would flag those and be turned off. So arm 3 matches
a USE — a name followed by `.`, or a `/root/` lookup — and never a path segment.
Prose in comments is skipped for the same reason: this file, and the ADR, name the
retired stores on purpose.

Exit 0 if the retirement holds, 1 on any violation. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402

SCAN_DIRS = walk_roots() + [PROJECT_DIR / "tests"]

RETIRED = ("PartyRoster", "EnemyRoster", "BaseRoster")
ROSTER_DIR_RES = "res://src/roster/"
ROSTER_SEED_DIR = PROJECT_DIR / "assets" / "roster"

# A USE, not a mention: `<Name>.` with no `/` in front (so `$BaseLayer/EnemyRoster`
# and "BaseLayer/EnemyRoster" are not uses), or an autoload lookup by /root/ path.
USE = re.compile(r"(?<![\w/])(%s)\s*\." % "|".join(RETIRED))
ROOT_LOOKUP = re.compile(r"/root/(%s)\b" % "|".join(RETIRED))


def _autoload_lines() -> list[str]:
    """The `[autoload]` block of project.godot, one line per entry."""
    text = (PROJECT_DIR / "project.godot").read_text(encoding="utf-8")
    out, inside = [], False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            inside = stripped == "[autoload]"
            continue
        if inside and stripped:
            out.append(stripped)
    return out


def main() -> int:
    problems = []

    # 1. autoloads
    for line in _autoload_lines():
        name = line.split("=", 1)[0].strip()
        if name in RETIRED:
            problems.append(
                "project.godot [autoload]: `%s` is back. The player population is "
                "CharacterCatalog.owned_units(); the enemy population is the ENTD "
                "(ADR-0180)." % name)

    # 2. the scripts themselves
    for root in SCAN_DIRS:
        if not root.is_dir():
            continue
        for gd in sorted(root.rglob("*.gd")):
            if gd.stem in RETIRED:
                problems.append(
                    "%s: a retired roster script is back (ADR-0180)."
                    % gd.relative_to(PROJECT_DIR))
    if (PROJECT_DIR / "src" / "roster").is_dir():
        problems.append("src/roster/: the retired roster package is back (ADR-0180).")

    # 3. uses
    for root in SCAN_DIRS:
        if not root.is_dir():
            continue
        for gd in sorted(root.rglob("*.gd")):
            try:
                text = gd.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue  # prose may name the retired stores
                hit = USE.search(line) or ROOT_LOOKUP.search(line)
                if hit:
                    problems.append(
                        "%s:%d: uses the retired `%s` autoload — %s"
                        % (gd.relative_to(PROJECT_DIR), lineno, hit.group(1),
                           line.strip()))
                if ROSTER_DIR_RES in line:
                    problems.append(
                        "%s:%d: reaches into the deleted %s — %s"
                        % (gd.relative_to(PROJECT_DIR), lineno, ROSTER_DIR_RES,
                           line.strip()))

    # 4. the orphaned seeds
    if ROSTER_SEED_DIR.is_dir():
        seeds = sorted(p.name for p in ROSTER_SEED_DIR.glob("*.json"))
        for seed in ("roster.json", "enemy_roster.json"):
            if seed in seeds:
                problems.append(
                    "assets/roster/%s: the retired roster's committed seed is back. "
                    "ADR-0180 removes a save path deliberately — owned-overlay "
                    "persistence is ADR-0201 §8's deferred work." % seed)

    if problems:
        print("check_rosters_retired: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        print(
            "\nFix: read docs/adr/0180. The player side is "
            "CharacterCatalog.owned_units(), established by folding a MutationScript "
            "through CatalogueReplay; the enemy side is the ENTD, composed with "
            "EntdBattle.compose_teams. Spawning a Unit from a Character is UnitSpawn.")
        return 1

    print("OK: the per-side rosters stay retired — no autoload, no script, no use, "
          "no seed (ADR-0180).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
