"""The one reading of `tests/run_all_tests.sh`'s TESTS array, and of the binder set.

THREE FILES WERE READING THE ARRAY THREE WAYS. `freeze_test_baseline.py` asked
BASH; `scoped_tests.py` ran an anchored regex; `run_unlisted_audio_binders.sh`
inlined a copy of the bash one inside a heredoc. All three agree TODAY — 410
stems each — and they agree by an accident of formatting, not by construction.

BASH IS THE READING THAT CANNOT DISAGREE, and the array is why. Its body is full
of prose comments containing quoted words, so the obvious `"([A-Za-z0-9_]+)"`
regex returns **437** names, 27 of them words like `container` and `Squire`.
Anchoring to `^\\s*"…"` gets back to 410 — but only while every entry stays on its
own line with no leading token. Two stems on one line, a `${VAR}` entry, or a
continuation would each read wrong, silently, in one instrument and not the other
two. Asking the shell to expand the array it is going to expand anyway cannot.

THE COST OF THE THIRD READING IS NOT HYPOTHETICAL EITHER. This same branch wrote
`413` into six docstrings and two CLAUDE.mds and had all eight go stale in the
branch that wrote them. A number nobody derives is a number nobody can re-derive;
so is a derivation nobody shares.

Also here: `MOVING`/`ADDON`, ADR-0153 dec. 2's four moving symbols and the addon
path, and the grep over `tests/*.gd` that turns them into the binder set. That
grep was written twice — once in `freeze_test_baseline.binders()` and once inside
`run_unlisted_audio_binders.sh`'s heredoc — and the second copy exists precisely
so the runner and the register agree about which tests are the subset. Two copies
of "which tests are the subset" is the one thing that pairing cannot afford.

Pure stdlib. Callers run from the package root.
"""
import collections
import os
import pathlib
import re
import subprocess
import sys
import tempfile

RUNNER = pathlib.Path("tests/run_all_tests.sh")

# ADR-0153 dec. 2's four moving symbols, and the addon path. A test that names
# any of them is in the extraction's subset; see docs/TEST-BASELINE-E2.tsv.
MOVING = ("ExMateriaEffectSfx", "BusLimiter", "ExMateriaAudioEngine", "SpuAudioDebugPanel")
ADDON = ("addons/exmateria_sound",)


def runner_tests(runner: pathlib.Path = None) -> list[str]:
    """The stems `tests/run_all_tests.sh` lists, in the array's own order.

    Read by BASH, for the reason in this module's docstring. The array body is
    sliced out and re-expanded rather than sourced, so the runner's own side
    effects (mkdir, godot invocations) never run.
    """
    src = (runner or RUNNER).read_text()
    s = src.index("TESTS=(")
    e = src.index("\n)\n", s)
    script = src[s:e] + '\n)\nprintf "%s\\n" "${TESTS[@]}"\n'
    # VIA A FILE, NOT `bash -c` (#417). Linux caps a SINGLE argv entry at
    # MAX_ARG_STRLEN (128 KiB), regardless of the much larger total ARG_MAX, so
    # passing the array body as one argument works right up until the array grows
    # past it and then dies with `OSError: [Errno 7] Argument list too long`.
    # Adopting #417's 275 scenes crossed that line: the body is ~2,000 lines of
    # entries and prose. A file has no such ceiling, and the reading is otherwise
    # identical — still bash expanding the array bash would expand.
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
        fh.write(script)
        tmp = fh.name
    try:
        out = subprocess.run(["bash", tmp], capture_output=True, text=True)
    finally:
        os.unlink(tmp)
    if out.returncode != 0:
        sys.exit("could not read the TESTS array: " + out.stderr)
    return [l for l in out.stdout.splitlines() if l.strip()]


def binders(tests_dir: pathlib.Path = None) -> dict:
    """test stem -> {'moving','addon'}, by grep over tests/*.gd."""
    out = collections.defaultdict(set)
    for p in sorted((tests_dir or pathlib.Path("tests")).rglob("*.gd")):
        t = p.read_text(errors="replace")
        if any(n in t for n in MOVING):
            out[p.stem].add("moving")
        if any(n in t for n in ADDON):
            out[p.stem].add("addon")
    return out


def unlisted_binders() -> list[str]:
    """Binder stems the runner does NOT list, and which have a scene to run.

    21 of the 39 at the freeze (#401): a test nobody runs cannot be diffed after
    a move, which is why `docs/TEST-BASELINE-E2.tsv` has a `not-run` state at all.
    """
    listed = set(runner_tests())
    tests = pathlib.Path("tests")
    return sorted(stem for stem in binders()
                  if stem not in listed and (tests / (stem + ".tscn")).is_file())


# --- #417: every scene under tests/, and which of them a runner reaches -------
#
# `runner_tests()` above answers "what does the array say". It cannot answer
# "what is there", and for two months nobody asked: 332 of the 744 scenes under
# `tests/` were in no runner's list, 300 of them emitting PASS/FAIL markers, and
# an unrun test looked exactly like a test nobody meant to run. The three
# functions below are the other half of the reading, and they are HERE so the
# runner, the coverage guard and the register cannot disagree about the set.

TESTS_DIR = pathlib.Path("tests")
STRANGER_DIR = pathlib.Path("tests/stranger")
ADDONS_DIR = pathlib.Path("addons")


def stranger_rigs(stranger_dir: pathlib.Path = None) -> list:
    """Every `tests/stranger/<addon>/run.sh`, sorted. ADR-0194 dec. 3.

    ONE reading, for the same reason the TESTS array has one: the runner's final
    phase, `freeze_test_baseline`'s `# stranger` header and `scoped_tests`'s
    advice all have to agree about which rigs exist, and three globs written
    three times agree by accident until the day one of them does not.
    `shared/` is not a rig — it holds the arms the rigs share.
    """
    root = stranger_dir or STRANGER_DIR
    return sorted(p for p in root.glob("*/run.sh") if p.parent.name != "shared")


def addon_owned_tests(addons_dir: pathlib.Path = None) -> dict:
    """`addons/<name>/tests/*.tscn`, stem -> path. ADR-0194 dec. 2.

    The counterpart to `scene_stems`: these are the tests that LEFT `tests/`, so
    a drop in `runner_tests()` is only auditable beside a rise here. Deliberately
    the whole `addons/` tree and not `classify_blueprint.WALK_ROOTS` — a vendored
    addon that grows a tests/ directory is still an addon-owned test, and reading
    the narrower list would make it invisible in exactly the register built to
    stop a number moving alone.
    """
    root = addons_dir or ADDONS_DIR
    return {p.stem: p for p in sorted(root.glob("*/tests/**/*.tscn"))}
SKIPS = pathlib.Path("tests/skip_tests.tsv")

# A scene's own test scripts: `tests/<stem>.gd` plus every `res://tests/*.gd` the
# .tscn mounts as an ext_resource. Reading the SCENE and not just the stem matters
# — `EffectStudio*` scenes mount their harness beside the test script, and a marker
# printed from the harness is still a marker the reader scores.
SCENE_SCRIPT_RE = re.compile(r'path="res://(tests/[^"]+\.gd)"')
MARKER_RE = re.compile(r"\[PASS\]|\[FAIL\]|\[VERDICT\]")
# The `[NOT_A_TEST] <why>` declaration tests/lib/verdict.sh scores (#463) — a WHY
# on the same line is required there and required here, for the same reason: a
# declaration without one is a silence with a label on it.
NOT_A_TEST_RE = re.compile(r"\[NOT_A_TEST\][ \t]+\S")


def scene_stems(tests_dir: pathlib.Path = None) -> dict:
    """Every `tests/**/*.tscn`, stem -> path. THE universe the guard classifies.

    Recursive on purpose: `tests/tools/` holds four capture/regen scenes that a
    non-recursive `tests/*.tscn` glob has never counted, which is why the ticket's
    census said 740 and the tree holds 744.
    """
    return {p.stem: p for p in sorted((tests_dir or TESTS_DIR).rglob("*.tscn"))}


def scene_scripts(scene: pathlib.Path) -> list:
    """The `tests/*.gd` files a scene mounts, plus its same-stem script."""
    out = set(SCENE_SCRIPT_RE.findall(scene.read_text(errors="replace")))
    sibling = scene.with_suffix(".gd")
    if sibling.is_file():
        out.add(str(sibling))
    return sorted(pathlib.Path(r) for r in out if pathlib.Path(r).is_file())


def scene_text(scene: pathlib.Path) -> str:
    return "".join(p.read_text(errors="replace") for p in scene_scripts(scene))


def emits_markers(scene: pathlib.Path) -> bool:
    """Does anything this scene mounts print a verdict the reader can score?"""
    return bool(MARKER_RE.search(scene_text(scene)))


def declares_not_a_test(scene: pathlib.Path) -> bool:
    """Does the scene say, on verdict.sh's own channel, that it asserts nothing?"""
    return bool(NOT_A_TEST_RE.search(scene_text(scene)))


def skips(path: pathlib.Path = None) -> dict:
    """`tests/skip_tests.tsv` -> stem -> (klass, reason). The NAMED exclusions.

    A dict of prose in a Python tool is not a channel (see tests/lib/verdict.sh on
    `RED_REASONS`), and neither is a comment in a bash array. This file is the one
    place a decision NOT to run a scene is written down, and
    `tools/check_test_list_coverage.py` is what makes writing it unavoidable.
    """
    p = path or SKIPS
    out = {}
    if not p.is_file():
        return out
    for i, line in enumerate(p.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"{p}:{i}: expected 3 tab-separated fields, got {len(parts)}")
        stem, klass, reason = (s.strip() for s in parts)
        out[stem] = (klass, reason)
    return out


if __name__ == "__main__":
    if "--unlisted" in sys.argv:
        print("\n".join(unlisted_binders()))
    elif "--scenes" in sys.argv:
        print("\n".join(sorted(scene_stems())))
    else:
        print("\n".join(runner_tests()))
