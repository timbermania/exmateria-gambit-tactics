#!/usr/bin/env python3
"""Re-copy godot-learning/vendor/ from the sibling packages.

    uv run python tools/vendor_packages.py [--check]

The package ships as a standalone bring-your-own-ISO repo, where
`../exmateria-sound/` and `../fft-iso-patcher/` do not exist. `vendor/` is how
their contents travel with it. This is the writer; `check_vendor_sync.py` is the
guard that fails when the two disagree.

COPIES TRACKED FILES ONLY, via `git ls-files` on the source package. An rsync
would drag in whatever the source worktree happens to be carrying — build
output, a stale `.godot/`, another session's scratch file — and vendor it into
this repo permanently. The one deliberate exception is the prebuilt GDExtension
binary under `exmateria_spu/bin/`, which is NOT tracked upstream and IS shipped
here, so a clone runs without building godot-cpp first.

Refuses to run in a standalone checkout: with no source package there is nothing
to copy from, and silently rewriting `vendor/` from nothing would delete the only
copy that exists.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
REPO = PACKAGE.parent
VENDOR = PACKAGE / "vendor"

# (vendored name, source prefix relative to the repo root)
SOURCES = (
    ("exmateria_sound", "exmateria-sound/addons/exmateria_sound"),
    ("exmateria_spu", "exmateria-sound/addons/exmateria_spu"),
    ("fft_iso_patcher", "fft-iso-patcher/fft_iso_patcher"),
)

# Built, not tracked upstream, shipped here on purpose (decision 7: a clone runs
# immediately). Windows/macOS builds belong here too when someone cross-compiles;
# today only the Linux one exists on any machine we have.
PREBUILT = (
    ("exmateria_spu",
     "exmateria-sound/addons/exmateria_spu/bin/"
     "libexmateria_spu.linux.template_debug.x86_64.so"),
)


def tracked(prefix: str) -> list[str]:
    out = subprocess.run(["git", "ls-files", "-z", prefix],
                         cwd=REPO, capture_output=True, text=True, check=True).stdout
    return [p for p in out.split("\0") if p]


def main(argv: list[str]) -> int:
    missing = [rel for _, rel in SOURCES if not (REPO / rel).is_dir()]
    if missing:
        print("vendor_packages: no source package for " + ", ".join(missing),
              file=sys.stderr)
        print("  This is a standalone checkout — vendor/ is already the only copy.\n"
              "  Re-vendoring from nothing would delete it. Nothing written.",
              file=sys.stderr)
        return 1

    total = 0
    for name, prefix in SOURCES:
        dst = VENDOR / name
        if dst.exists():
            shutil.rmtree(dst)
        files = tracked(prefix)
        for rel in files:
            target = dst / Path(rel).relative_to(prefix)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / rel, target)
        total += len(files)
        print(f"  {name:<18} {len(files):>4} tracked file(s)")

    for name, rel in PREBUILT:
        src = REPO / rel
        if not src.exists():
            print(f"  {name:<18} !! no prebuilt binary at {rel}\n"
                  f"  {'':<18}    build it: cd exmateria-sound && scons "
                  f"platform=linux target=template_debug")
            continue
        dst = VENDOR / name / "bin" / src.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src.resolve(), dst)   # resolve(): the source is often a symlink
        total += 1
        print(f"  {name:<18} + prebuilt {src.name} ({dst.stat().st_size // 1024} KiB)")

    print(f"vendor_packages: {total} file(s) into {VENDOR.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
