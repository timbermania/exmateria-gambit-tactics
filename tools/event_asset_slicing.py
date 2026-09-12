#!/usr/bin/env python3
"""Event-asset slicing -- cut the derived event frames/cells into a template
folder (wayfinder #204, ADR-0072 dec.5).

Consumes the coordinates the derivation (`event_asset_derivation`) recovered and
bakes the owned, self-contained assets the #200 schema wants:

  events/chr/NN.tga + NN.palette.tga   -- a composited EVTCHR cinematic frame
  events/face/NN.tga + NN.palette.tga  -- an EVTFACE dialogue cell

Encoding matches the rest of the template packet (ADR-0022 index-grayscale):
every owned sprite is a 32bpp TGA whose channels carry `index * 17` (the shader
recovers the 0-15 palette index via `sprite_texture.r * 15.0`) plus a 16x16 CLUT
`.palette.tga`. So:

  * chr frames are composited by copying the (already index-grayscale) segment
    atlas pixels tile-by-tile; the palette is a copy of that segment's CLUT.
  * face cells are decoded RGBA (the extract already baked EVTFACE.BIN's 4bpp to
    PNG), so they are re-indexed losslessly (<=16 colours) into the same
    index-grayscale + CLUT form -- uniform with body/portrait/chr.
"""

from __future__ import annotations

import shutil
import struct
import zlib
from pathlib import Path

from extract_spr import write_tga

INDEX_SCALE = 17  # extract_spr_indexed packs a 4-bit index as index * 17 (0..255)


def read_tga_bgra(path: Path) -> tuple[int, int, bytes]:
    """(width, height, pixel_bytes) for a 32bpp BGRA top-left TGA."""
    data = path.read_bytes()
    w, h = struct.unpack("<HH", data[12:16])
    return w, h, data[18:]


def read_png_rgba(path: Path) -> tuple[int, int, list]:
    """(width, height, [(r,g,b,a), ...]) for a truecolour (RGB/RGBA) PNG.

    Minimal decoder (no Pillow dependency) covering the extract's face PNGs:
    8-bit colour type 2/6, all five filter types, non-interlaced."""
    d = path.read_bytes()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    i = 8
    w = h = ct = None
    idat = b""
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        typ = d[i + 4:i + 8]
        chunk = d[i + 8:i + 8 + ln]
        i += 12 + ln
        if typ == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    ch = 4 if ct == 6 else 3
    stride = w * ch
    raw = zlib.decompress(idat)
    out = bytearray()
    prev = bytes(stride)
    pos = 0
    for _y in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b = prev[x]
            c = prev[x - ch] if x >= ch else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line
        prev = bytes(line)
    pixels = []
    for o in range(0, len(out), ch):
        r, g, b = out[o], out[o + 1], out[o + 2]
        a = out[o + 3] if ch == 4 else 255
        pixels.append((r, g, b, a))
    return w, h, pixels


def composite_evtchr_frame(atlas_w: int, atlas_h: int, atlas_bgra: bytes,
                           blocks: list) -> tuple[int, int, list] | None:
    """Composite one EVTCHR frame from its tile block list onto a tight canvas.

    `blocks` are `parse_evtchr_frames` descriptors: a source `rectangle_*` in the
    256x200 segment page placed at signed `location_*`, with `revert`/`invert`
    horizontal/vertical flips. Returns (w, h, [(r,g,b,a), ...]) index-grayscale
    pixels (copied straight from the already-indexed atlas), or None if empty."""
    if not blocks:
        return None
    min_x = min(b["location_x"] for b in blocks)
    min_y = min(b["location_y"] for b in blocks)
    max_x = max(b["location_x"] + b["rectangle_width"] for b in blocks)
    max_y = max(b["location_y"] + b["rectangle_height"] for b in blocks)
    width = max_x - min_x
    height = max_y - min_y
    if width <= 0 or height <= 0:
        return None
    canvas = [(0, 0, 0, 0)] * (width * height)
    for b in blocks:
        rw, rh = b["rectangle_width"], b["rectangle_height"]
        rx, ry = b["rectangle_x"], b["rectangle_y"]
        ox, oy = b["location_x"] - min_x, b["location_y"] - min_y
        for j in range(rh):
            sy = ry + (rh - 1 - j if b["invert"] else j)
            for i in range(rw):
                sx = rx + (rw - 1 - i if b["revert"] else i)
                if 0 <= sx < atlas_w and 0 <= sy < atlas_h:
                    o = (sy * atlas_w + sx) * 4
                    bch, gch, rch, a = (atlas_bgra[o], atlas_bgra[o + 1],
                                        atlas_bgra[o + 2], atlas_bgra[o + 3])
                    canvas[(oy + j) * width + (ox + i)] = (rch, gch, bch, a)
    return width, height, canvas


def reindex_rgba_to_grayscale(pixels: list) -> tuple[list, list]:
    """Re-index a <=16-colour truecolour cell into (index-grayscale pixels, CLUT).

    Returns index-grayscale `(index*17, index*17, index*17, alpha)` pixels plus a
    first-seen-order palette list of the distinct `(r,g,b,a)` colours (<=16)."""
    palette: list = []
    index_of: dict = {}
    out: list = []
    for px in pixels:
        if px not in index_of:
            index_of[px] = len(palette)
            palette.append(px)
        idx = index_of[px]
        v = idx * INDEX_SCALE
        out.append((v, v, v, px[3]))
    if len(palette) > 16:
        raise ValueError(f"cell has {len(palette)} colours (>16); not 4bpp-losslessly indexable")
    return out, palette


def segment_clut_row(segment_palette_src: Path, row: int) -> list:
    """The 16 `(r,g,b,a)` colours on `row` of a 16x16 segment CLUT `.palette.tga`.

    A segment's embedded CLUT is 16 palettes x 16 colours (EVTCHR block +0x780);
    the `{7F}` palette byte picks which row a unit samples."""
    w, _h, bgra = read_tga_bgra(segment_palette_src)
    out: list = []
    for col in range(16):
        o = (row * w + col) * 4
        out.append((bgra[o + 2], bgra[o + 1], bgra[o], bgra[o + 3]))  # BGRA -> RGBA
    return out


def write_clut_from_palette(path: Path, palette: list) -> None:
    """Write a 16x16 CLUT `.palette.tga` with `palette` colours on row 0."""
    pixels: list = []
    for row in range(16):
        for col in range(16):
            if row == 0 and col < len(palette):
                r, g, b, a = palette[col]
                pixels.append((r, g, b, a))
            else:
                pixels.append((0, 0, 0, 0))
    write_tga(str(path), 16, 16, pixels)


def emit_chr_frame(out_dir: Path, index: int, atlas_dims: tuple,
                   blocks: list, segment_palette_src: Path,
                   palette_row: int | None = None) -> bool:
    """Slice one composited EVTCHR frame to `out_dir/NN.tga` + `NN.palette.tga`.

    `palette_row` is the `{7F}`-bound CLUT row when the derivation knew it (#204):
    the frame then carries JUST that row's 16 colours on CLUT row 0, so units that
    share a segment and differ only by palette row get distinct, self-contained
    CLUTs. When `None` (single-resident-segment tier -- row unknown) the whole 16x16
    segment CLUT is copied verbatim (loses no colour; the row is left to the
    consumer). Returns False (nothing written) if the frame composites empty."""
    atlas_w, atlas_h, atlas_bgra = atlas_dims
    frame = composite_evtchr_frame(atlas_w, atlas_h, atlas_bgra, blocks)
    if frame is None:
        return False
    w, h, pixels = frame
    out_dir.mkdir(parents=True, exist_ok=True)
    write_tga(str(out_dir / f"{index:02d}.tga"), w, h, pixels)
    clut_path = out_dir / f"{index:02d}.palette.tga"
    if palette_row is None:
        shutil.copyfile(segment_palette_src, clut_path)
    else:
        write_clut_from_palette(clut_path, segment_clut_row(segment_palette_src, palette_row))
    return True


def emit_face_cell(out_dir: Path, index: int, face_png: Path) -> bool:
    """Re-index one EVTFACE cell to `out_dir/NN.tga` + `NN.palette.tga`."""
    w, h, rgba = read_png_rgba(face_png)
    pixels, palette = reindex_rgba_to_grayscale(rgba)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_tga(str(out_dir / f"{index:02d}.tga"), w, h, pixels)
    write_clut_from_palette(out_dir / f"{index:02d}.palette.tga", palette)
    return True
