#!/usr/bin/env python3
"""The two harness facts only a RUN can record about itself — #454, map #450.

    uv run python tools/harness_stamp.py        # two banner lines, on stdout

`tools/suite_register.py` reads a register's provenance out of the runner's own
banner rather than stamping it at take time, because the commit, the engine, the
addon deployment copy and the `.godot/` cache are properties of the RUN and every
one of them can change before anybody reads the register. Two of those four the
runners already print. These are the other two.

WHY THE CACHE STATE IS PROVENANCE AND NOT TRIVIA. A cold `.godot/` makes Godot
reimport on first boot, which inflates the first test's wall clock by minutes and
puts a re-import at the front of a run whose per-test budget is being measured.
Two registers taken either side of a cache wipe are not comparable on cost, and
`# godot_cache` is what makes that checkable instead of assumed. #454 §4: the real
constraint on comparing two registers was never the file, it is harness parity —
so record the harness.

ONE OWNER EACH. The addon line is `check_addon_sync.stamp()`, the tool that owns
the comparison; this file does not re-derive it. Both runners call THIS, so the
sequential and parallel arms cannot print two different shapes — the same reason
`run_tests_parallel.format_progress` is byte-compatible with the shell runner's
per-test block.

Pure stdlib. Run from the package root.
"""
import pathlib
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR / "tools"))
import check_addon_sync  # noqa: E402
import check_test_list_coverage  # noqa: E402


def godot_cache_stamp(root: pathlib.Path = None) -> str:
    """`warm (N imported)` / `COLD (...)` — what the engine had to redo.

    Counts `.godot/imported`, which is the artifact whose absence costs the
    minutes. `shader_cache` is reported separately because a warm import cache
    with a cold shader cache still front-loads pipeline compilation onto the
    first GPU test, and 60 of the suite's scenes are GPU tests.
    """
    root = pathlib.Path(root or PROJECT_DIR)
    cache = root / ".godot"
    if not cache.is_dir():
        return ("COLD — no .godot/; the first run reimports and its wall clock is "
                "not comparable to a warm one")
    imported = cache / "imported"
    n = sum(1 for _ in imported.iterdir()) if imported.is_dir() else 0
    shaders = "shader cache present" if (cache / "shader_cache").is_dir() \
        else "NO shader cache — first GPU scene pays pipeline compilation"
    if n == 0:
        return f"COLD — .godot/ exists but 0 imported files; {shaders}"
    return f"warm — {n} imported files; {shaders}"


def test_coverage_stamp(root: pathlib.Path = None) -> str:
    """What the tree held when this run started — #417's triple, in the banner.

    IT BELONGS TO THE RUN, NOT TO THE TAKE, and that is not a formality: the
    array grew by 275 entries in a single commit, so a register that derived its
    own coverage figure at read time would report today's tree beside a run from
    before it. Both arms print it from HERE, which is also why the parallel
    runner — which runs no pre-flights — can state its coverage at all.

    `check_test_list_coverage.classify()` is the owner; this counts its states
    and does not re-derive them.
    """
    try:
        states = check_test_list_coverage.classify(
            pathlib.Path(root) if root else None)
    except Exception as e:                       # a stamp must never abort a run
        return f"UNKNOWN — {type(e).__name__}: {e}"
    n = {}
    for state, _ in states.values():
        n[state] = n.get(state, 0) + 1
    return (f"{len(states)} scenes on disk; {n.get('listed', 0)} listed, "
            f"{n.get('declares', 0)} declares, {n.get('skipped', 0)} skipped, "
            f"{n.get('UNCLASSIFIED', 0)} unclassified")


def banner_lines(root: pathlib.Path = None) -> str:
    """The three `  key value` lines, indented to match the runners' banners.

    Two spaces exactly: `suite_register.FIELD_RE` reads banner fields at that
    indent, and never as `  -> WORD`, the shape `freeze_test_baseline.verdicts()`
    reads as a test's verdict.
    """
    return (f"  addon_sync {check_addon_sync.stamp()}\n"
            f"  godot_cache {godot_cache_stamp(root)}\n"
            f"  test_coverage {test_coverage_stamp(root)}")


if __name__ == "__main__":
    print(banner_lines())
