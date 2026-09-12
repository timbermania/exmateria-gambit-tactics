#!/usr/bin/env python3
"""
Direct-crop title-menu glyphs from a PCSX-Redux framebuffer screenshot.

Slot-9 of the user's pcsx-redux savestate sits on the title menu with NEW GAME
selected. The simplest ground-truth for the selected/unselected text is the
live PSX render itself: crop NEW GAME (white, selected) and the others (dim
navy, unselected) straight out of `shot.png`.

This sidesteps OPNTEX1's 4bpp + STP-blend reconstruction (palette 4's idx 0
is white STP, idx 1-4 are opaque slate that PSX blends additively into the
parchment — we can't replicate that exactly without a custom shader, and an
opaque PIL extraction looks wrong; see `parse_opntex.py` for the partial
extraction path that still emits OPNTEX glyphs for completeness).

Output (default `godot-learning/assets/ui/opening_menu/`):
    new_game_selected.png       (cropped from y=151..159, selected white)
    continue_unselected.png     (cropped from y=162..171)
    tutorial_unselected.png     (cropped from y=174..183)
    sound_unselected.png        (cropped from y=186..195)
    copyright.png               (cropped from y=210..219)

We also crop a "selected" version of CONTINUE/TUTORIAL/SOUND by sampling the
NEW GAME palette (the only selected row in the savestate) and using OPNTEX1
glyph data — done in `parse_opntex.py`, not here.
"""

import argparse
from pathlib import Path

from PIL import Image


# y-bounds per line and a uniform x-window that includes left padding
# and a tail-pad past the longest glyph (TUTORIAL).
MENU_X0, MENU_X1 = 137, 222  # exclusive end
COPYRIGHT_X0, COPYRIGHT_X1 = 100, 220

LINES = [
    ("new_game_selected",    151, 160, (MENU_X0, MENU_X1)),
    ("continue_unselected",  162, 172, (MENU_X0, MENU_X1)),
    ("tutorial_unselected",  174, 184, (MENU_X0, MENU_X1)),
    ("sound_unselected",     186, 196, (MENU_X0, MENU_X1)),
    ("copyright",            210, 220, (COPYRIGHT_X0, COPYRIGHT_X1)),
]


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shot", default="/tmp/menu_capture/shot.png",
                        help="decoded PCSX-Redux framebuffer (320x240 RGB).")
    parser.add_argument("--out-dir",
                        default=str(repo_root / "godot-learning/assets/ui/opening_menu"))
    args = parser.parse_args()

    src = Image.open(args.shot).convert("RGBA")
    if src.size != (320, 240):
        raise SystemExit(f"expected 320x240 shot, got {src.size}")
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    for name, y0, y1, (x0, x1) in LINES:
        crop = src.crop((x0, y0, x1, y1))
        # Knock parchment background to alpha=0: any pixel that's brownish
        # (R > B and luma < 0.6 max) is bg. Keep bright (selected) and
        # blue-leaning (unselected) text.
        out_img = Image.new("RGBA", crop.size, (0, 0, 0, 0))
        for y in range(crop.height):
            for x in range(crop.width):
                r, g, b, _ = crop.getpixel((x, y))
                bright = min(r, g, b) > 160
                navy = b > r + 8 and b > 30
                if bright or navy:
                    out_img.putpixel((x, y), (r, g, b, 255))
        out_img.save(out / f"{name}.png")
        print(f"wrote {out / (name + '.png')}  ({out_img.width}x{out_img.height})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
