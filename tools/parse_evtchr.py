"""EVTCHR.BIN parser — cinematic sprite image atlas (palette + pixels only).

EVTCHR.BIN is loaded by event-script opcode 0x58 `Load EVTCHR` during
cinematic playback (e.g. Ovelia kneeling in Orbonne's chapel).

    file size: 4,208,640 B = 137 segments x 30,720 B (0x7800 ea.)
    per segment:
        +0x0000 .. +0x04FF  cinematic SEQ table (`parse_cinematic_seq.py`)
        +0x0500 .. +0x077F  block pointers + block data (frame composition)
        +0x0780 .. +0x097F  16 palettes of 16 colors (16-bit PSX TIM)  <-- here
        +0x0980 .. +0x6D7F  256x200 4bpp paletted pixel page           <-- here
        +0x6D80 .. +0x77FF  trailing padding

This file parses ONLY the palette + pixel regions. The cinematic SEQ
bytecode at +0x0000..+0x04FF is decoded by `parse_cinematic_seq.py` —
they live in the same physical segment but serve different consumers
(image atlas vs. animation walker).

Palette offset (1920) is ShishiSpriteEditor's PSXImages.xml value. The PIXEL
offset differs: Shishi's PSXImages.xml says 2560 (0x0A00), but that is 1 row
(128 B) too late vs the GAME's on-screen output. Verified 2026-07-09 against live
PSX VRAM at the scn6 carry beat (block 1 uploaded to VRAM (256,0)): decoding from
2432 (0x980) reproduces the displayed sheet PIXEL-PERFECT (identical non-black
count, 100% overlap; first content row 5 == VRAM), while 2560 renders every
cinematic frame 1px too high. The 0x980..0x0A00 region is a blank top row that
belongs to the page; the trailing row Shishi includes is never displayed. So we
key the pixel page to the RUNTIME/VRAM layout (0x980), not Shishi's file offset.
See research/working_documents/EVTCHR_FRAME_RESOLUTION.md §9.
Authority for the segment-layout sections we DON'T parse here: `EVTCHR
Frame Editor v1.1` by Xifanie (bundled .xlsm, "EVTCHR Addresses" sheet).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path


NUM_SEGMENTS = 137
SEGMENT_SIZE = 30_720
PALETTE_OFFSET = 1920
PALETTE_BYTES = 32  # 16 colors x 16 bits
PALETTE_COUNT = 16
PIXEL_OFFSET = 2560
PIXEL_BYTES = 25_600  # 256x200 / 2 (4bpp)


@dataclass(frozen=True)
class Segment:
    """One EVTCHR cinematic-sprite page.

    palettes : 16 entries, each 32 raw bytes (16 PSX TIM colors).
    pixels   : 25,600 raw bytes (256x200 4bpp; low nibble = left pixel).
    """

    palettes: list[bytes]
    pixels: bytes


@dataclass(frozen=True)
class Atlas:
    segments: list[Segment]


def _parse_segment(buf: bytes) -> Segment:
    if len(buf) < PIXEL_OFFSET + PIXEL_BYTES:
        raise ValueError(f"segment too small: {len(buf)} B < {PIXEL_OFFSET + PIXEL_BYTES}")
    palettes = [
        buf[PALETTE_OFFSET + i * PALETTE_BYTES : PALETTE_OFFSET + (i + 1) * PALETTE_BYTES]
        for i in range(PALETTE_COUNT)
    ]
    pixels = buf[PIXEL_OFFSET : PIXEL_OFFSET + PIXEL_BYTES]
    return Segment(palettes=palettes, pixels=pixels)


def decode_psx_color(c: int) -> tuple[int, int, int]:
    """Decode a 16-bit PSX TIM color to (R, G, B) 8-bit.

    Bit layout (LE u16): SBBBBBGG GGGRRRRR — S = semi-transparency flag,
    each channel 5 bits. We left-shift by 3 (= multiply by 8) to span 0..255.
    """
    r5 = c & 0x1F
    g5 = (c >> 5) & 0x1F
    b5 = (c >> 10) & 0x1F
    return (r5 << 3, g5 << 3, b5 << 3)


def decode_palette(pal_bytes: bytes) -> list[tuple[int, int, int]]:
    """One 32-byte palette -> 16 RGB colors."""
    return [decode_psx_color(c) for c in struct.unpack("<16H", pal_bytes)]


def decode_pixels(pixel_bytes: bytes) -> list[int]:
    """4bpp pixel page -> per-pixel palette indices.

    PSX 4bpp convention: each byte holds 2 pixels, low nibble = left pixel.
    """
    out = []
    for b in pixel_bytes:
        out.append(b & 0xF)
        out.append((b >> 4) & 0xF)
    return out


def parse_evtchr(path: str | Path) -> Atlas:
    data = Path(path).read_bytes()
    expected = NUM_SEGMENTS * SEGMENT_SIZE
    if len(data) != expected:
        raise ValueError(f"EVTCHR.BIN size mismatch: got {len(data)}, expected {expected}")
    segments = [
        _parse_segment(data[i * SEGMENT_SIZE : (i + 1) * SEGMENT_SIZE])
        for i in range(NUM_SEGMENTS)
    ]
    return Atlas(segments=segments)


def render_segment_png(segment: Segment, out_path: str | Path, palette_idx: int = 0) -> None:
    """Render one segment to a PNG using a specific palette."""
    from PIL import Image  # local import: PIL is in tools/pyproject but not needed for parsing

    rgb_palette = decode_palette(segment.palettes[palette_idx])
    indices = decode_pixels(segment.pixels)
    img = Image.new("RGB", (256, 200))
    img.putdata([rgb_palette[i] for i in indices])
    img.save(out_path)


def _main() -> int:
    import argparse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, default=None, help="EVTCHR.BIN path (default: project-assets)")
    p.add_argument("--dump-png", type=Path, default=None, help="Directory to write per-segment PNGs into")
    p.add_argument("--segment", type=int, default=None, help="If set, dump only this one segment")
    p.add_argument("--palette", type=int, default=0, help="Palette index (0..15) to use when rendering")
    args = p.parse_args()

    from _repo_paths import event_dir
    in_path = args.input or (event_dir() / "EVTCHR.BIN")
    atlas = parse_evtchr(in_path)
    print(f"Loaded {len(atlas.segments)} segments from {in_path}")

    if args.dump_png is not None:
        args.dump_png.mkdir(parents=True, exist_ok=True)
        ids = [args.segment] if args.segment is not None else range(len(atlas.segments))
        for i in ids:
            out = args.dump_png / f"segment_{i:03d}_pal{args.palette:02d}.png"
            render_segment_png(atlas.segments[i], out, args.palette)
            print(f"  wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
