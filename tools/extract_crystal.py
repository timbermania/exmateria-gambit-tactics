#!/usr/bin/env python3
"""Extract the FFT crystal graphic (the {92} SS=1 "turn to crystal" animation)
from OTHER.SPR — deterministic, ISO-derived (issue #154, doc §12.7).

RE summary (see inflict_status_op92_decode.md §12.7): {92} Status=1 sets the unit's
Crystal bit (+0x58 = 0x40) and the render substitutes a dedicated animated crystal
graphic drawn over the tile — NOT a recolor of the unit sprite (poison's computed
FUN_800927bc pass-2 recolor does NOT fire for crystal). The graphic is 8 diamond
frames in OTHER.SPR's top (uncompressed 256x256 4bpp) section, using OTHER.SPR
sub-palette ROW 10. Live VRAM confirms: the on-screen crystal CLUT == row 10 with a
+(-1,0,+1) rounding from the palette-load pass.

  Frames (top section, y = 101..122, 22px tall):
    x-starts 3,19,34,50,66,82,98,115  (~16px pitch, widths 11..14)
  They read as a shimmer/pulse: detailed diamond -> bright white/cyan diamond.

Outputs a horizontal sheet PNG (RGBA, index 0 transparent) + per-frame PNGs +
manifest.json. Pure file read — no emulator, no VRAM.

Usage:
  python3 extract_crystal.py [OTHER.SPR] [out_dir]
  (defaults: ../project-assets/fft-extract/BATTLE/OTHER.SPR ; ./crystal_out)
"""
import os, sys, json
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SPR = os.path.abspath(os.path.join(
    HERE, "..", "..", "project-assets", "fft-extract", "BATTLE", "OTHER.SPR"))

# Committed game asset (ISO-derived, deterministic — satisfies the assets-from-ISO
# rule). The runtime CrystalSprite3D loads this horizontal 8-frame sheet.
GAME_ASSET = os.path.abspath(os.path.join(
    HERE, "..", "assets", "sprites", "textures", "crystal", "crystal_sheet.png"))

# Animation cadence — RE'd live (op92 rig, per-vblank GPU::Vsync sampler,
# inflict_status_op92_decode.md §12.8): the crystal is a bespoke death/crystal VFX
# (FUN_8006d818 family), NOT OTHER.SEQ-driven (the y=101..122 band is referenced by
# no OTHER.SHP frame). Forward loop 0->7, 4 vblanks per frame, period 32 vblanks
# (~0.533 s at 60 Hz), synchronized across crystals.
FRAME_VBLANKS = 4
FRAME_COUNT_LOOP = 8   # forward 0..7 then repeat

TOP_OFF = 0x200          # uncompressed 256x256 4bpp top section
PAL_ROW = 10             # crystal sub-palette row (16 colours)
BAND_Y0, BAND_Y1 = 101, 122
FRAME_X = [3, 19, 34, 50, 66, 82, 98, 115]
FRAME_PITCH = 16         # frame cell width (x_start .. x_start+15)
FRAME_H = BAND_Y1 - BAND_Y0 + 1


def bgr555(v):
    r = (v & 0x1F) * 255 // 31
    g = ((v >> 5) & 0x1F) * 255 // 31
    b = ((v >> 10) & 0x1F) * 255 // 31
    return (r, g, b)


def main():
    spr = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SPR
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "crystal_out")
    raw = open(spr, "rb").read()
    os.makedirs(out, exist_ok=True)

    # palette row 10 -> RGBA, index 0 transparent
    pal = []
    for i in range(16):
        v = raw[PAL_ROW * 32 + i * 2] | (raw[PAL_ROW * 32 + i * 2 + 1] << 8)
        r, g, b = bgr555(v & 0x7FFF)
        pal.append((r, g, b, 0 if i == 0 else 255))

    def px(x, y):
        b = raw[TOP_OFF + y * 128 + (x >> 1)]
        return (b & 0xF) if (x & 1) == 0 else (b >> 4)

    n = len(FRAME_X)
    sheet = Image.new("RGBA", (FRAME_PITCH * n, FRAME_H), (0, 0, 0, 0))
    frames_meta = []
    for i, x0 in enumerate(FRAME_X):
        fr = Image.new("RGBA", (FRAME_PITCH, FRAME_H), (0, 0, 0, 0))
        for yy in range(FRAME_H):
            for xx in range(FRAME_PITCH):
                fr.putpixel((xx, yy), pal[px(x0 + xx, BAND_Y0 + yy)])
        fr.save(os.path.join(out, f"crystal_{i}.png"))
        sheet.paste(fr, (i * FRAME_PITCH, 0))
        frames_meta.append({"index": i, "src_x": x0, "src_y": BAND_Y0,
                            "w": FRAME_PITCH, "h": FRAME_H})
    sheet.save(os.path.join(out, "crystal_sheet.png"))

    manifest = {
        "source": os.path.relpath(spr),
        "section": "OTHER.SPR top (0x200, 256x256 4bpp)",
        "palette_row": PAL_ROW,
        "frame_count": n,
        "frame_size": [FRAME_PITCH, FRAME_H],
        "band_y": [BAND_Y0, BAND_Y1],
        "frames": frames_meta,
        "trigger": "{92} Inflict Status SS=1 (Crystal); unit +0x58 & 0x40",
        "note": "in-game CLUT == palette_row + (-1,0,+1) from the FUN_800927bc load pass",
        "animation": {
            "mechanism": "bespoke death/crystal VFX (FUN_8006d818), NOT OTHER.SEQ",
            "loop": "forward 0..7 then repeat",
            "frame_vblanks": FRAME_VBLANKS,
            "period_vblanks": FRAME_VBLANKS * FRAME_COUNT_LOOP,
            "source": "RE'd live per-vblank, inflict_status_op92_decode.md §12.8",
        },
    }
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=2)

    # Also emit the committed game asset (same deterministic sheet).
    os.makedirs(os.path.dirname(GAME_ASSET), exist_ok=True)
    sheet.save(GAME_ASSET)
    print(f"wrote {n} frames + crystal_sheet.png + manifest.json to {out}")
    print(f"wrote game asset -> {GAME_ASSET}")


if __name__ == "__main__":
    main()
