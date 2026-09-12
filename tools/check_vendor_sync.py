#!/usr/bin/env python3
"""The vendored copy of an out-of-package dependency must equal the package.

    uv run python tools/check_vendor_sync.py [--list]

`godot-learning/vendor/` holds copies of three things this package does not own:
the two ExMateria sound addons and `fft_iso_patcher`'s ISO core. They exist
because the package ships as a standalone bring-your-own-ISO repo where
`../exmateria-sound/` and `../fft-iso-patcher/` do not exist at all.

A COPY WITH NO GUARD IS A CACHE WITH NO INVALIDATION. `check_addon_sync.py`
already learned this the expensive way about the *host deployment* copy: 67 `.gd`
files had silently drifted, every one missing the vault anchors a commit had
added, and nothing looked wrong because no file was present on one side and
absent on the other — the game just loaded an older addon than the package held,
including in every test run. This is the same copy shape one level out, so it
gets the same guard before it can earn the same story.

IN THE STANDALONE REPO THERE IS NOTHING TO COMPARE TO, and that is a PASS, not a
skip that hides a drift: the vendored tree is then the only copy and cannot
disagree with anything. The guard says which case it is by name rather than
printing a verdict that reads the same either way.
"""

from __future__ import annotations

import filecmp
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
VENDOR = PACKAGE / "vendor"

# (vendored dir, the package it is a copy of, what it is for)
VENDORED = (
    ("exmateria_sound", "../exmateria-sound/addons/exmateria_sound",
     "the FFT music + battle SFX addon; a hard dependency of the game's audio"),
    ("exmateria_spu", "../exmateria-sound/addons/exmateria_spu",
     "the generic PSX SPU addon — `Spu` is a global class_name the sound addon "
     "names in 11 files, so one without the other is a parse-error cascade"),
    ("fft_iso_patcher", "../fft-iso-patcher/fft_iso_patcher",
     "the stdlib-only ISO core: the disc extractor, and the ISO9660 walk "
     "tools/build_sprite_file_map.py joins against BATTLE.BIN's sprite table"),
)

# Build output and caches are not part of the comparison: the vendored tree ships
# a prebuilt .so on purpose, and the package side may or may not have been built.
IGNORE_SUFFIXES = (".so", ".dll", ".dylib", ".pyc", ".uid", ".import")
IGNORE_DIRS = {"__pycache__", ".godot", "bin"}


def _files(root: Path) -> set[str]:
    out = set()
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if IGNORE_DIRS & set(p.relative_to(root).parts):
            continue
        if p.suffix in IGNORE_SUFFIXES:
            continue
        out.add(p.relative_to(root).as_posix())
    return out


def compare(vendored: Path, package: Path) -> list[str]:
    """Differences between two trees, as human-readable lines."""
    v, k = _files(vendored), _files(package)
    out = [f"only in vendor/: {r}" for r in sorted(v - k)]
    out += [f"missing from vendor/: {r}" for r in sorted(k - v)]
    out += [f"differs: {r}" for r in sorted(v & k)
            if not filecmp.cmp(vendored / r, package / r, shallow=False)]
    return out


def main(argv: list[str]) -> int:
    print("check_vendor_sync.py — godot-learning/vendor/ mirrors its packages\n")
    problems, standalone = 0, 0
    for name, rel, why in VENDORED:
        vendored, package = VENDOR / name, (PACKAGE / rel).resolve()
        if not vendored.is_dir():
            print(f"fail: vendor/{name} is MISSING — {why}")
            problems += 1
            continue
        if not package.is_dir():
            standalone += 1
            print(f"ok:   {name}: {len(_files(vendored))} file(s); no package at "
                  f"{rel} — standalone checkout, the vendored tree is the only copy")
            continue
        diffs = compare(vendored, package)
        if diffs:
            problems += 1
            print(f"fail: {name} has DRIFTED from {rel} — {len(diffs)} difference(s):")
            for d in diffs[:20]:
                print(f"        {d}")
            if len(diffs) > 20:
                print(f"        … and {len(diffs) - 20} more")
            print(f"        re-vendor with: uv run python tools/vendor_packages.py")
        else:
            print(f"ok:   {name}: {len(_files(vendored))} file(s) byte-identical to {rel}")
        if "--list" in argv:
            for r in sorted(_files(vendored)):
                print(f"        {r}")
    print()
    if problems:
        print(f"check_vendor_sync: {problems} vendored tree(s) wrong")
        return 1
    where = "standalone" if standalone == len(VENDORED) else "monorepo"
    print(f"check_vendor_sync: {len(VENDORED)} vendored tree(s) correct ({where} checkout)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
