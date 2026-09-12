#!/usr/bin/env python3
"""Build the standalone `exmateria-gambit-tactics` repo out of this package.

    uv run python tools/export_standalone.py --check        # verify, write nothing
    uv run python tools/export_standalone.py <dest>         # materialise it
    uv run python tools/export_standalone.py <dest> --check # both

THE SYNC MECHANISM, per register step 6 decision (b). `git subtree` was rejected:
decision 1 picked subtree over *submodules* to keep the files in-tree, which the
monorepo already does, so subtree's only distinguishing capability was history
replay — and decision 4 forbids replaying this history, which carries ~22 MB of
Square Enix-derived data no `.gitignore` can reach once it is in a commit. An
export has no history to replay, and needs no join commit on `main`.

THE PACKAGE ROOT BECOMES THE REPO ROOT. `git ls-files godot-learning` with the
prefix stripped, so `project.godot` lands at the clone root and `res://` is the
repo. That is why the package's `.gitignore` had to move in-package (step 4) and
why `check_generated_assets.py` reads it from inside (step 3): a rule spelled
`godot-learning/…` is dead in the repo that ships.

TRACKED FILES ONLY, like `vendor_packages.py` and for the same reason — an rsync
drags in whatever the worktree happens to hold: build output, a stale `.godot/`,
another session's scratch file. `git ls-files` is the only list that means "this
is part of the package".

`--check` IS THE POINT, not a convenience. An export is a copy, and a copy with no
guard is a cache with no invalidation (`check_vendor_sync.py`'s docstring, learned
from 67 silently drifted `.gd` files). Here the stakes are higher than drift: the
export is the artifact that gets PUBLISHED, so the guard's job is to fail before a
path that must never leave this monorepo does.
"""

from __future__ import annotations

import argparse
import fnmatch
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
REPO = PACKAGE.parent
PREFIX = f"{PACKAGE.name}/"

# Files the export takes from the monorepo ROOT, not from the package.
# (repo-relative source, path in the export)
ROOT_FILES = (("LICENSE", "LICENSE"),)

# Every path the export must carry for a clone to be usable at all. Checked by
# name so that a rename upstream is a loud failure here rather than a clone that
# Godot refuses to open.
REQUIRED = (
    "project.godot",
    ".gitignore",
    "SETUP_FROM_SCRATCH.md",
    "LICENSE",
)

# (glob, why). Package-relative, matched against the EXPORT path (prefix already
# stripped). Every entry must still match something — see `stale_excludes()`; an
# exclusion that has rotted into a no-op is an error, not a free pass, the same
# rule `tests/charter_allowlist.tsv` lives under.
#
EXCLUDE = (
    ("docs/EXTRACTION-GAMBIT-REGISTER.tsv",
     "this loop's own work list. It tracks BUILDING the standalone repo and cites "
     "monorepo worktree paths; shipping it into that repo is circular."),

    # DECIDED BY THE USER, 2026-09-12: "hud captures are square data so i can't
    # really include them." Register step 9.
    ("tools/hud_digit_captures/*.bin.gz",
     "Square Enix data. Their own README calls them 'Full 1 MB PSX VRAM dumps "
     "(gzipped) from the fork PCSX-Redux at battle savestates' — 1.68 MB tracked, "
     "5 MB of the console's graphics memory verbatim, not a derivation. This is the "
     "category root decision 4 keeps out of a published repo. They are the ORACLE "
     "for tools/test_parse_frame_font.py, never a build input: the shipping font is "
     "extracted statically from the user's own EVENT/FRAME.BIN by parse_frame_font.py, "
     "so a clone still gets a correct font. `_scratch_reader` already raises "
     "SkipTest when a capture is absent, so their absence costs 4 SKIPPED arms of "
     "19 in that module and no reds."),

    # Same principle, extended by inference rather than by instruction — flagged as
    # such in step 9's register row so it can be reverted in one line. Safe to take:
    # NOTHING reads this file. Ripgrep over the whole package finds no consumer.
    ("example_particle_data_ref_fft.txt",
     "Square Enix data: a CSV dump of effect 2's 47 particles straight off the ROM's "
     "particle table, sitting at the package root since the original import. No code, "
     "test, doc or tool reads it, so excluding it costs nothing at all."),

    # ── DECIDED BY THE USER, 2026-09-12: "making sure no square assets are
    # included." Register step 9. The ruling asked for the CATEGORY, not the one
    # group the handoff happened to name, so the six rules below come out of a
    # sweep of all 170 unclassified data-shaped tracked files (2.45 MB) rather
    # than from the handoff's list.
    #
    # THE LINE THE SWEEP DREW, because the whole package is a reimplementation and
    # "ROM-derived" would exclude the source code: a rule fires on VERBATIM Square
    # CONTENT — map tile arrays, mesh vertices, texture pixels, palette RGB,
    # byte-exact script operands, a captured GPU packet stream. It does NOT fire on
    # a MEASUREMENT OF OBSERVED BEHAVIOUR (a frame count, a landing tick, a struct
    # field value), on an INDEX or ID, or on a DIGEST of content that is itself
    # absent. That is why `tests/data/map_buffer_golden.json` ships — it is 37 KB of
    # sha256 over map buffers and holds no map byte — and why
    # `tests/fixtures/rom_walk_fuzz/` ships, 48 files and 547 KB of SEEDED-RANDOM
    # terrain whose expectations come from our own port, carrying no disc data at
    # all. Keeping the fuzz corpus is what leaves `RomWalkStepperCrossCheckTest`
    # its full oracle; only `RomWalkStepperTest` loses one.

    ("addons/exmateria_battlefield/tests/fixtures/rom_walk/*",
     "Square Enix data: 14 files / 180 KB, each carrying MAP009's tile array "
     "verbatim (surface/height/depth/slope_h/slope_t over an 8x14 map) beside the "
     "live PSX frame trace it is scored against. The tile array is the disc's map "
     "geometry, the same category as a VRAM dump and merely smaller. NOT "
     "regenerable in a clone: tools/gen_rom_walk_fixtures.py bakes them from "
     "research/scenario29_walk_vs_jump/, outside the package, so this exclusion is "
     "permanent rather than deferred. Costs RomWalkStepperTest its wire oracle — "
     "it now prints [SKIP] and exits 0 instead of [FAIL]."),

    ("addons/exmateria_battlefield/tests/fixtures/rom_event_route/*",
     "Square Enix data, same category and found by the same sweep: 27 files / "
     "122 KB of verbatim tile arrays over MAP009, MAP012 and MAP057, eight fields "
     "per tile including `impassable`/`unselectable`. Not named in the handoff; it "
     "is the pathfinder's half of what rom_walk/ is to the stepper. Also baked from "
     "research/, so also permanent. Costs EventPathfinderTest its oracle ([SKIP])."),

    ("tests/fixtures/rom_event_route/*",
     "Square Enix data: the HOST's copy of the route fixture above (1 file, MAP009 "
     "tiles), minted by the same generator in the same run so the two roots cannot "
     "drift. Excluding one and shipping the other would ship the map geometry "
     "anyway. Costs ScenarioPathMotionTest its WIRE arm ([SKIP])."),

    ("assets/doodads/bridge_2tile/*",
     "Square Enix data, and the most literal in this table: 8 files / 129 KB cut "
     "out of MAP022 by `tools/extract_doodad.py --source MAP022 --coords \"5,12 "
     "6,12\"` — its own usage line names the map. Mesh vertices with normals and "
     "UVs, a 65 KB indexed texture, 16 palettes of raw RGB, the terrain draping and "
     "the palette-animation table. Unlike the fixtures this one IS regenerable from "
     "the user's own extract, so it belongs to the same class as every other "
     "iso-data asset and is only here because it was committed instead of "
     "gitignored. Nothing reads it at runtime — DoodadLibrary loads from the "
     "host-injected content root under project-assets, not from res://assets/"
     "doodads — so the exclusion costs no test and no scene."),

    ("tools/goldens/reference_scenes/*.golden.json",
     "Square Enix data: 5 files / 34 KB holding, per scene, the `{19}` Camera "
     "opcode operands BYTE-EXACT as hex (the golden's own docstring says "
     "'byte-exact'), plus MAP062/004/008's level_0 height and impassable grids and "
     "the ENTD spawn tiles. Regenerable from the user's own ISO by "
     "gen_reference_goldens.py, so no capability is lost. Costs "
     "ReferenceRenderDirectionTest its three scene goldens ([SKIP]) and makes "
     "tools/test_reference_goldens.py skip rather than fail — it asserted "
     "path.exists() and is a PRE-FLIGHT guard, so left alone it would have aborted "
     "a clone's whole suite before any test ran."),

    ("tests/goldens/world_map_prims_ss*.txt",
     "Square Enix data: 2 files / 12 KB that WorldMapPrimitivesTest's own header "
     "calls 'the console's own primitives exactly ... copied verbatim' — every "
     "packet's uv window, CLUT id and rgb read out of two PSX savestates. This is "
     "the hud-capture category in text form, which is why the user's ruling on "
     "those reaches it. The oracle that emits them, "
     "research/working_documents/world_map_captures/wldgen.py, is outside the "
     "package, so permanent. The test already skips when the gitignored ROM assets "
     "are absent; it now skips on an absent golden too, instead of push_error."),
)


def tracked_package_files() -> list[str]:
    """Export-relative paths of every tracked file in the package."""
    out = subprocess.run(["git", "ls-files", "-z", PACKAGE.name],
                         cwd=REPO, capture_output=True, text=True, check=True).stdout
    return sorted(p[len(PREFIX):] for p in out.split("\0") if p.startswith(PREFIX))


def tracked_root_files() -> list[tuple[str, str]]:
    return [(src, dst) for src, dst in ROOT_FILES
            if subprocess.run(["git", "ls-files", "--error-unmatch", src],
                              cwd=REPO, capture_output=True).returncode == 0]


def excluded(path: str, exclude=EXCLUDE) -> str | None:
    """The REASON this path is excluded, or None. Reason, not bool: a caller that
    names which rule fired is the difference between a fixable failure and a
    verdict nobody can act on."""
    for glob, why in exclude:
        if path == glob or fnmatch.fnmatch(path, glob):
            return why
    return None


def manifest(package_files=None, root_files=None, exclude=EXCLUDE) -> list[str]:
    """What the export will contain, sorted."""
    package_files = tracked_package_files() if package_files is None else package_files
    root_files = tracked_root_files() if root_files is None else root_files
    kept = [p for p in package_files if excluded(p, exclude) is None]
    return sorted(kept + [dst for _, dst in root_files])


def stale_excludes(package_files=None, exclude=EXCLUDE) -> list[str]:
    """EXCLUDE globs that match no tracked path. A dead rule is an error, not a
    free pass — the same rule `tests/charter_allowlist.tsv` lives under."""
    live = tracked_package_files() if package_files is None else package_files
    return [glob for glob, _ in exclude
            if not any(p == glob or fnmatch.fnmatch(p, glob) for p in live)]


def on_disk_files(dest: Path) -> list[str]:
    """Export-relative paths of every regular file already in `dest`."""
    if not dest.is_dir():
        return []
    return sorted(q.relative_to(dest).as_posix() for q in dest.rglob("*")
                  if q.is_file() and ".git/" not in q.relative_to(dest).as_posix())


def violations(package_files, root_files, exclude=EXCLUDE, required=REQUIRED,
               on_disk=None) -> list[str]:
    """Every invariant, over EXPLICIT inputs, as human-readable violations.

    Pure on purpose. The live-repo arms below can only ever show this returning
    nothing; a guard whose failing direction cannot be reached is a guard nobody
    has seen work.
    """
    problems: list[str] = []
    files = manifest(package_files, root_files, exclude)

    # 1. an export DIRECTORY holds nothing the manifest does not name.
    #
    # This used to read "no exported path is untracked", comparing the manifest
    # against the same list the manifest was built from — tautological, and the
    # arm written to watch it fire could not. The real hazard is the one every
    # copy has: `build()` writes INTO `dest`, so a path deleted upstream survives
    # in a directory that was exported before. Scored against the filesystem,
    # which is the only side that can disagree.
    if on_disk is not None:
        named = set(files)
        for p in on_disk:
            if p not in named:
                problems.append(
                    f"[stale] {p} is in the export directory but not in the manifest "
                    f"— deleted upstream and left behind by an earlier export")

    # 2. nothing excluded leaks through.
    for p in files:
        why = excluded(p, exclude)
        if why is not None:
            problems.append(f"[leaked] {p} is excluded ({why}) but is in the export")

    # 3. no exclusion has rotted into a no-op.
    for glob in stale_excludes(package_files, exclude):
        problems.append(
            f"[stale-exclude] {glob!r} matches no tracked path — delete the rule, "
            f"do not leave it as a permanent exemption")

    # 4. the clone is usable.
    present = set(files)
    for p in required:
        if p not in present:
            problems.append(f"[missing] {p} is required for a usable clone and is not exported")

    return problems


def check(dest: Path | None = None) -> list[str]:
    """`violations()` against this worktree, and against `dest` if one is given."""
    return violations(tracked_package_files(), tracked_root_files(),
                      on_disk=None if dest is None else on_disk_files(dest))


def build(dest: Path) -> tuple[int, int]:
    """Materialise the export at `dest` as an EXACT mirror of the manifest.

    Returns (written, removed). Exact, not additive: `vendor_packages.py` learned
    the same lesson one level in and `rmtree`s each vendored dir first. Writing
    into a directory a previous export used would otherwise publish a file that
    has since been deleted from the package, and nothing in the diff would show
    it — the file is present on both sides, just stale on one.
    """
    dest.mkdir(parents=True, exist_ok=True)
    named = set(manifest())

    removed = 0
    for stale in on_disk_files(dest):
        if stale not in named:
            (dest / stale).unlink()
            removed += 1

    written = 0
    for rel in tracked_package_files():
        if excluded(rel) is not None:
            continue
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PACKAGE / rel, target)
        written += 1
    for src, dst in tracked_root_files():
        shutil.copy2(REPO / src, dest / dst)
        written += 1
    return written, removed


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dest", nargs="?", type=Path, help="where to materialise the export")
    ap.add_argument("--check", action="store_true", help="verify the invariants; write nothing")
    ap.add_argument("--list", action="store_true", help="print the export manifest")
    args = ap.parse_args(argv)

    if args.list:
        try:
            for p in manifest():
                print(p)
        except BrokenPipeError:
            # `--list | head` is the obvious way to use this; a traceback there
            # reads as a tool defect. Swallow it and let the shell's rc stand.
            sys.stderr.close()
        return 0

    if not args.dest and not args.check:
        ap.error("give a destination, --check, or --list")

    def report(problems: list[str]) -> int:
        print(f"export_standalone: {len(problems)} violation(s)\n", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1

    # THE MANIFEST invariants gate the build: a stale exclusion or a missing
    # required path means we do not know what we are publishing, so nothing is
    # written. The DESTINATION invariant does NOT gate it — `build()` is the thing
    # that fixes a stale destination, so checking for one first and then refusing
    # to build was a deadlock whose only escape was dropping the flag you added
    # for safety.
    manifest_problems = violations(tracked_package_files(), tracked_root_files())
    if manifest_problems:
        return report(manifest_problems)

    if args.check and not args.dest:
        dropped = len(tracked_package_files()) - len(
            [p for p in tracked_package_files() if excluded(p) is None])
        print(f"export_standalone: {len(manifest())} file(s) would export "
              f"({dropped} excluded by {len(EXCLUDE)} rule(s), "
              f"{len(REQUIRED)} required root path(s) present)")
        return 0

    written, removed = build(args.dest)
    note = f", {removed} stale file(s) removed" if removed else ""
    print(f"export_standalone: {written} file(s) -> {args.dest}{note}")

    rc = 0
    if args.check:
        # Scored AFTER the build, against what is actually on disk — the only
        # reading that describes the artifact someone would publish.
        problems = check(args.dest)
        if problems:
            rc = report(problems)
        else:
            print(f"export_standalone: {args.dest} verified — "
                  f"{len(manifest())} file(s), nothing stale, nothing excluded leaked")

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
