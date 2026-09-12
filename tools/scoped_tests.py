#!/usr/bin/env python3
"""Which tests can reach a change? — the scoped subset of `tests/run_all_tests.sh`.

The full suite is ~50 minutes and **most of that is not test work**: measured over
one run, 59% of tests finish in under 6s, which is roughly Godot's boot cost, so
more than half the wall clock is one engine startup per listed test. Trimming slow
tests barely helps (80% of the clock is 66% of the tests). Running *fewer* tests is
the only lever that pays, and the only safe way to choose them is to derive them.

THE SUITE SIZE IS NOT WRITTEN DOWN HERE, and that is deliberate. This docstring
said "410 engine startups" for 282 tests, in company with `run_tests_parallel.py`
and `_runner_tests.py`, all three stale together because each RECORDED the number
instead of reading it. `len(_runner_tests.runner_tests())` is the reading that
cannot disagree; ADR-0194's Consequences names the repair as citing it rather than
quoting a fresher number, which is the same defect one iteration later.

    uv run python tools/scoped_tests.py                    # vs the working tree
    uv run python tools/scoped_tests.py --since HEAD~3     # vs a commit
    uv run python tools/scoped_tests.py --files a.gd b.gd  # an explicit change set
    uv run python tools/scoped_tests.py --run              # emit a runnable command

SEEDS are the changed files (`git diff --name-only`, or `--files`). EDGES are
`closure.py`'s seven static edges, reused rather than re-implemented — preload /
load literals, `.tscn`/`.tres` ext_resource, `extends`, bare `class_name`
references, shader includes, and the subtree rule. A test is AFFECTED when its
own forward closure contains a changed file.

## The blind spot, which is the same one closure.py has

Every edge is static, so the affected set is a **FLOOR, not a verdict**: a path
the code builds at runtime (`"res://addons/…/%s.gd" % name`) is invisible to it,
and so is anything reached only through a duck-typed call. A green scoped run
says "nothing in the statically reachable set broke" and says NOTHING about the
rest. Two rules follow, and they are not advisory:

  * Iterate on the scoped set. **Verify a ticket on the full suite.**
  * Anything that lands — a lift, a merge, a baseline freeze — is full-suite.

## Two different questions, and conflating them is what makes scoping look useless

A file reachable from an **autoload** is loaded by every test, because Godot
instantiates autoloads before any scene. That sounds like "scoping cannot help",
and it is why the first version of this tool bailed out on the whole
`exmateria_sound` addon. It is the wrong conclusion, because it answers two
questions at once:

  * **Can the change fail the test at LOAD time?** A parse error, a dangling
    preload, a stale call arity. Through an autoload this hits every test
    IDENTICALLY — so detecting it needs ONE test, not 410. Any test at all.
  * **Can the change move what the test ASSERTS?** Only tests whose own closure
    reaches the change. Godot injects autoloads; a test scene does not name them
    unless its own scripts do, so the forward walk from `tests/X.tscn` already
    answers exactly this.

So the recommendation is always `1 smoke + N assert-reach`, and the autoload
line is a note about the smoke test's job, not a reason to run everything.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys

# closure.py walks RELATIVE paths from godot-learning/ and reads `project.godot`
# out of the cwd, so this tool used to work only when run from there — while the
# root CLAUDE.md prescribed `uv run python godot-learning/tools/scoped_tests.py`,
# which died on `FileNotFoundError: 'project.godot'`. chdir here rather than
# teaching every doc a cwd rule; `changed()`'s git calls use `cwd=".."` and the
# seeds it reads are repo-root-relative either way.
os.chdir(pathlib.Path(__file__).resolve().parent.parent)

# closure.py is a script: importing it runs its whole residue report. Reuse it
# anyway — re-implementing the edge model is how three instruments end up with
# three different answers — but swallow the report and keep only the machinery.
_stdout, sys.stdout = sys.stdout, open("/dev/null", "w")
try:
    import closure as cl
    import _runner_tests
    import run_tests_parallel as rtp
finally:
    sys.stdout.close()
    sys.stdout = _stdout

PREFIX = "godot-learning/"
# The canonical package is edited in exmateria-sound/; the host reaches it only
# through the gitignored mirror sync_exmateria_sound.sh writes. Without this the
# tool sees an addon-only change as "nothing changed" and scopes to zero tests —
# an empty affected set that looks like good news.
ADDON_SRC = "exmateria-sound/addons/exmateria_sound/"
ADDON_DST = "addons/exmateria_sound/"
# The load-time canary: pure logic, no GPU, first in the runner's own array, and
# among the cheapest tests in the suite. Any test would do — that is the point.
SMOKE = "JsonAssetTest"


def changed(since: str | None, files: list[str] | None) -> list[str]:
    if files:
        raw = files
    else:
        cmd = ["git", "diff", "--name-only"] + ([since] if since else [])
        raw = subprocess.run(cmd, capture_output=True, text=True,
                             cwd="..").stdout.split()
        # untracked files count too — a new scene nothing has committed yet is
        # still a thing a test can reach.
        if not since:
            raw += subprocess.run(["git", "ls-files", "--others",
                                   "--exclude-standard"], capture_output=True,
                                  text=True, cwd="..").stdout.split()
    out = []
    for f in raw:
        if f.startswith(ADDON_SRC):
            rel = ADDON_DST + f[len(ADDON_SRC):]
        elif f.startswith(PREFIX):
            rel = f[len(PREFIX):]
        else:
            rel = f
        if rel in cl.existing:
            out.append(rel)
    return sorted(set(out))


def in_edges() -> dict[str, set[str]]:
    """Reverse the graph once. One forward walk per test scene is the same
    information, slower."""
    rev: dict[str, set[str]] = {}
    for f in cl.universe:
        for tgt in cl.out_edges(f):
            rev.setdefault(tgt, set()).add(f)
    return rev


def depths(seeds: set[str], rev: dict[str, set[str]], cap: int) -> dict[str, int]:
    """file -> fewest static hops from it DOWN to a changed file, up to `cap`."""
    d = {f: 0 for f in seeds}
    frontier = set(seeds)
    for hop in range(1, cap + 1):
        nxt = set()
        for f in frontier:
            for src in rev.get(f, ()):
                if src not in d:
                    d[src] = hop
                    nxt.add(src)
        frontier = nxt
        if not frontier:
            break
    return d


def scene_scripts(scene: str) -> list[str]:
    """A test scene's own scripts — depth is measured from the CODE, and a .tscn
    that is one hop from its script would otherwise cost a hop of the budget."""
    return cl.out_edges(scene) if scene in cl.existing else []


def runner_tests() -> set[str]:
    """The stems `tests/run_all_tests.sh` actually lists.

    This used to run its own anchored regex over the array body. It agreed with
    `freeze_test_baseline`'s bash reading — 410 either way — by an accident of
    formatting, not by construction; see `_runner_tests`.
    """
    return set(_runner_tests.runner_tests())


def scene_paths() -> dict:
    """EVERY scene under `tests/`, stem -> path, not just the ones the runner lists.

    Scoping off the runner's array would inherit the runner's blind spot, and the
    blind spot is not hypothetical: of the six test files that directly
    `preload()` `sound_opcodes.gd`, **five are absent from TESTS=(** — they are
    among the unlisted binders #401 found had never been run at all. A tool that
    reads the array would have reported one affected test and been wrong by five.

    #417: this used to be a fourth reading — its own `glob("*.tscn")`, flat, which
    missed the four scenes under `tests/tools/` and is why this tool said 740 while
    the tree held 744. The enumeration now comes from `_runner_tests`, which is
    also what `tools/check_test_list_coverage.py` reads, so the guard and the
    scoper cannot disagree about which scenes exist.
    """
    out = {stem: str(path) for stem, path in _runner_tests.scene_stems().items()}
    # ADR-0194 dec. 2: eight tests are no longer under `tests/` at all — they ship
    # inside the addons they guard. Left out, this tool would report `0 of 748`
    # for a change to `ColorRecipe.gd` and be wrong by exactly the tests written
    # to catch it: the same blind spot the `tests/**` glob was widened to close.
    for stem, path in _runner_tests.addon_owned_tests().items():
        out.setdefault(stem, str(path))
    return out


def all_tests() -> list[str]:
    """The stems of `scene_paths()`, sorted."""
    return sorted(scene_paths())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="diff against this commit instead of the working tree")
    ap.add_argument("--files", nargs="*", help="explicit change set")
    # 3, not 2, and the two CLAUDE.mds are why: both document "Default 3" and both
    # prescribe `--depth 3` in the command they tell you to run, in the same branch
    # that left this at 2. A default that contradicts its own documentation is a
    # trap for the one invocation that omits the flag.
    ap.add_argument("--depth", type=int, default=3,
                    help="max static hops from a test to a changed file (default 3). "
                         "Unlimited depth does not discriminate — see the curve.")
    ap.add_argument("--run", action="store_true", help="print a runnable command")
    a = ap.parse_args()

    seeds = changed(a.since, a.files)
    if not seeds:
        print("no changed files under src/ assets/ addons/ tools/ tests/ — nothing to scope")
        return 0
    seedset = set(seeds)
    print(f"changed files in the universe: {len(seeds)}")
    for s in seeds[:12]:
        print(f"  {s}")
    if len(seeds) > 12:
        print(f"  … and {len(seeds) - 12} more")

    rev = in_edges()
    dep = depths(seedset, rev, max(a.depth, 12))

    hot_autoloads = sorted(n for n, path in cl.autoloads.items() if path in dep)

    listed = runner_tests()
    scene_of = scene_paths()
    stems = sorted(scene_of)
    orphans = sorted(listed - set(stems))

    # The depth CURVE is the finding, not a footnote: in a densely wired tree the
    # transitive closure stops discriminating. One leaf file (sound_opcodes.gd) is
    # "reached" by 71% of tests at unlimited depth and by a handful at depth 2.
    print("\nreach curve — tests within N static hops of a changed file:")
    prev = None
    for n in (1, 2, 3, 4, 6, 8, 12):
        c = sum(1 for st in stems if dep.get(scene_of[st], 99) <= n
                or any(dep.get(f, 99) <= n - 1 for f in scene_scripts(scene_of[st])))
        if c == 0 and n > 1:
            continue
        bar = "#" * int(c / max(len(stems), 1) * 40)
        print(f"  <= {n:>2} hops  {c:>4}/{len(stems)}  {bar}")
        if prev == c and c == len(stems):
            break
        prev = c

    affected = [st for st in stems
                if dep.get(scene_of[st], 99) <= a.depth
                or any(dep.get(f, 99) <= a.depth - 1
                       for f in scene_scripts(scene_of[st]))]
    # `not in the array` used to mean one thing: nothing runs it. Since ADR-0194
    # it means two, and only one of them is a finding. An addon-owned test
    # (`addons/<name>/tests/`) and a rig's own scene (`tests/stranger/`) are
    # ABSENT FROM THE ARRAY BY DECISION — dec. 4 — and the runner invokes their
    # rig in its final phase. Reporting them as "a full run_all_tests.sh would
    # MISS them" would be false, and false in the direction that teaches a reader
    # to ignore the line that is true.
    owned = _runner_tests.addon_owned_tests()
    def by_rig(st):
        path = scene_of.get(st, "")
        return st in owned or path.startswith("tests/stranger/")
    unlisted = [st for st in affected if st not in listed and not by_rig(st)]

    if hot_autoloads:
        print(f"\nLOADED BY EVERY TEST via autoload: {', '.join(hot_autoloads)}")
        print("  A parse error / dangling preload / stale arity here fails every test the")
        print("  SAME way, so ONE test detects it. That is the smoke test below, not a")
        print(f"  reason to run {len(listed)}.")

    print(f"\n{len(affected)} of {len(stems)} test scenes are within {a.depth} hops — these "
          f"are the ones whose ASSERTIONS can move")
    for stem in affected:
        if stem in listed:
            note = ""
        elif by_rig(stem):
            note = "   <- run by a stranger rig, not by the array (ADR-0194 dec. 4)"
        else:
            note = "   <- NOT in run_all_tests.sh"
        print(f"  {stem}{note}")
    if unlisted:
        print(f"\n{len(unlisted)} of them the runner does NOT list, so a full "
              f"`run_all_tests.sh` would MISS them. Run them by scene.")
    if orphans:
        print(f"\n{len(orphans)} stems the runner lists have no tests/<stem>.tscn: "
              f"{', '.join(orphans[:6])}{' …' if len(orphans) > 6 else ''}")

    # ADR-0194 dec. 11. When the change cannot leave one addon, the cheapest
    # complete answer is that addon's rig — one boot, its own tests, in a project
    # that did nothing for it — and the expensive half is the consumers, which
    # this tool has always been able to count and never said out loud in the same
    # breath. Printing both is what turns "run only what you changed" from a
    # discipline into a command, and the GAP between the two numbers is the
    # scoreboard for whether this refactor is paying off: an instrument cannot go
    # stale the way a docstring can.
    roots = {"/".join(f.split("/")[:2]) for f in seeds if f.startswith("addons/")}
    if len(roots) == 1 and all(f.startswith("addons/") for f in seeds):
        root = roots.pop()
        rig = pathlib.Path(root.replace("addons/", "tests/stranger/", 1)) / "run.sh"
        owned = _runner_tests.addon_owned_tests()
        mine = sorted(st for st in affected
                      if str(owned.get(st, "")).startswith(root + "/"))
        rest = [st for st in affected if st not in mine]
        print(f"\nCHANGE IS CONFINED TO {root}")
        if rig.is_file():
            print(f"  run:   bash {rig}")
            print(f"         ({len(mine)} addon-owned test(s), one boot, no host project)")
        else:
            print(f"  run:   nothing cheap — {root} has no rig at {rig} yet (ADR-0194 dec. 3),")
            print(f"         so there is no way to exercise it without the host")
        print(f"  owed:  {len(rest)} consumer test(s)"
              + (" + 1 smoke" if hot_autoloads else "") + ", before landing.")
        print("         A consumer test is a fact about the GAME and stays with the assembly")
        print("         however small it is; the rig cannot speak for it.")

    print(f"\nDEPTH {a.depth} IS A DIAL, AND THE CURVE ABOVE IS WHY IT HAS TO BE.")
    print("  Static edges only, so this is a FLOOR: a runtime-built path is invisible.")
    print("  Iterate here; verify the ticket on the FULL suite.")

    if a.run:
        picks = list(affected)
        if hot_autoloads and SMOKE not in picks:
            picks.insert(0, SMOKE)   # the load-time canary, cheapest in the suite
        if not picks:
            print("\nnothing to run")
            return 0
        # `res://tests/<stem>.tscn` is not an address any more — an addon-owned
        # test lives in its addon. Use the path the enumeration already has.
        scenes = " ".join(f"res://{scene_of.get(s, f'tests/{s}.tscn')}" for s in picks)
        print(f"\n# {len(picks)} tests"
              + (f" (1 smoke + {len(affected)} assert-reach)" if hot_autoloads else ""))
        # Two scenes in the suite are interactive diagnostics: they run their
        # checks, print a verdict, and then SIT THERE with a window open. Only
        # `-- --ci` makes them quit. Both real runners append it
        # (`run_tests_parallel.CI_ARG_TESTS`, mirrored in `run_all_tests.sh`);
        # this one did not, so a scoped set containing one hung for the whole
        # 360 s timeout and `tail -3` showed RID-leak warnings where the verdict
        # goes — a test that PASSED, read as a hang. The set is IMPORTED, not
        # respelled: a third copy is a third thing to drift.
        ci_scenes = [f"res://{scene_of.get(s, f'tests/{s}.tscn')}"
                     for s in picks if s in rtp.CI_ARG_TESTS]
        cmd = (f"for S in {scenes}; do echo \"== $S\"; "
               f"timeout 360 godot --path . \"$S\" 2>&1 | tail -3; done")
        if ci_scenes:
            # `$A` is deliberately unquoted: it word-splits into `--` `--ci`, and
            # vanishes for every other scene.
            pick = 'case " $CI " in *" $S "*) A="-- --ci";; *) A="";; esac; '
            cmd = ('CI="' + " ".join(ci_scenes) + '"\n'
                   + f"for S in {scenes}; do echo \"== $S\"; " + pick
                   + 'timeout 360 godot --path . "$S" $A 2>&1 | tail -3; done')
        print(cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
