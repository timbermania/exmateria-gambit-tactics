#!/usr/bin/env python3
"""Force every .tga .import to lossless and immune to 3D auto-compression.

A from-scratch asset re-parse plus Godot's detect_3d auto-compression leave some
sprite / UI .tga textures at `compress/mode=2` (VRAM Compressed), which block-
compresses pixel art and ruins it. Worse, any .tga.import left at
`detect_3d/compress_to=1` will get auto-flipped to VRAM the first time the
texture is used in a 3D material -- and this game renders every sprite in 3D --
so "lossless" silently regresses over time.

This normalizes every `*.tga.import` under the project to:
    compress/mode = 0           (Lossless)
    detect_3d/compress_to = 0   (Disabled -- never auto-flip to VRAM)

Idempotent. Run standalone to fix an existing checkout, or from
tools/bootstrap_assets.sh before the Godot import step. Pairs with the
[importer_defaults] block in project.godot, which makes *fresh* imports lossless
from the start; this tool repairs .import files that predate that default or
were already flipped.

Usage:
    uv run python tools/normalize_texture_imports.py            # rewrite in place
    uv run python tools/normalize_texture_imports.py --check     # exit 1 if any stale
"""

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent

# key -> required value
TARGETS = {
    "compress/mode": "0",
    "detect_3d/compress_to": "0",
}

_LINE = re.compile(r"^(compress/mode|detect_3d/compress_to)=(.*?)(\r?\n?)$")


def normalize_text(text: str):
    lines = text.splitlines(keepends=True)
    changed = False
    for i, line in enumerate(lines):
        m = _LINE.match(line)
        if m:
            key, val, nl = m.group(1), m.group(2).strip(), m.group(3)
            want = TARGETS[key]
            if val != want:
                lines[i] = f"{key}={want}{nl}"
                changed = True
    return "".join(lines), changed


def main(argv) -> int:
    check = "--check" in argv[1:]
    files = sorted(PROJECT.rglob("*.tga.import"))
    stale = []
    for f in files:
        new, changed = normalize_text(f.read_text())
        if changed:
            stale.append(f)
            if not check:
                f.write_text(new)

    def rel(p):
        return p.relative_to(PROJECT)

    if check:
        if stale:
            print("%d .tga.import are not lossless / still auto-detect 3D:" % len(stale))
            for f in stale:
                print("  - %s" % rel(f))
            print("Fix: uv run python tools/normalize_texture_imports.py")
            return 1
        print("all %d .tga.import are lossless (compress/mode=0, detect_3d off)" % len(files))
        return 0

    if stale:
        print("normalized %d/%d .tga.import to compress/mode=0, detect_3d/compress_to=0:"
              % (len(stale), len(files)))
        for f in stale:
            print("  - %s" % rel(f))
        print("Re-run `godot --import` to rebuild the texture cache from the new settings.")
    else:
        print("all %d .tga.import already lossless -- nothing to do" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
