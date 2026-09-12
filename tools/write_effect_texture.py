"""Byte-exact texture-section writer for the Effect Studio (#280, ADR-0199).

An effect's texture is the LAST section in the file: `texture_ptr` -> EOF, laid
out as palette 1 (512 B) | palette 2 (512 B) | 4-byte VRAM header | indexed
pixel plane. This module owns the plane only — the CLUT is held FIXED (ADR-0199
decision 1), so an import can never invent a colour the sheet does not already
have.

Quantization is an **index delta**, not a blind re-quantize (ADR-0199 decision
2): a texel whose imported colour still equals the colour of the index it
already had keeps that index. This matters because a colour does not identify an
index — corpus-wide, 265 of 401 effects hold the same BGR555 word at two or more
indices (8bpp mean: 88 duplicates of 256) — so blind matching rewrites 43% of
the corpus's pixel bytes on a no-op re-import.

Alpha carries the STP bit, never opacity (ADR-0096).
"""

from __future__ import annotations

from typing import Any, Dict, List, Sequence, Tuple

RGBA = Tuple[int, int, int, int]


def bgr555_to_rgba(word: int) -> RGBA:
    """Decode one BGR555 palette word. Alpha carries STP (ADR-0096)."""
    return (
        (word & 0x1F) * 8,
        ((word >> 5) & 0x1F) * 8,
        ((word >> 10) & 0x1F) * 8,
        128 if (word & 0x8000) else 255,
    )


def quantize_to_clut(
    rgba_pixels: Sequence[RGBA],
    clut_words: Sequence[int],
    original_indices: Sequence[int],
) -> Dict[str, Any]:
    """Map an imported RGBA image back to palette indices against a FIXED CLUT.

    Per texel: keep `original_indices[i]` when its decoded colour still equals
    the imported colour, else take the nearest CLUT entry. Returns
    `{indices, off_palette}` — `off_palette` counts texels that matched no entry
    exactly and had to be approximated.
    """
    decoded = [bgr555_to_rgba(w) for w in clut_words]
    exact: Dict[RGBA, int] = {}
    for i, colour in enumerate(decoded):
        exact.setdefault(colour, i)

    indices: List[int] = []
    off_palette = 0
    for i, want in enumerate(rgba_pixels):
        want = tuple(want)
        keep = original_indices[i] if i < len(original_indices) else -1
        if 0 <= keep < len(decoded) and decoded[keep] == want:
            indices.append(keep)
            continue
        if want in exact:
            indices.append(exact[want])
            continue
        off_palette += 1
        indices.append(_nearest(want, decoded))
    return {"indices": indices, "off_palette": off_palette}


def _nearest(want: RGBA, decoded: Sequence[RGBA]) -> int:
    """Index of the CLUT entry closest to `want` in squared RGB distance, with
    a mismatched STP bit penalised so a flat texel never silently turns
    semi-transparent when a same-colour flat entry exists."""
    best_i, best_d = 0, None
    for i, c in enumerate(decoded):
        d = (c[0] - want[0]) ** 2 + (c[1] - want[1]) ** 2 + (c[2] - want[2]) ** 2
        if c[3] != want[3]:
            d += 1
        if best_d is None or d < best_d:
            best_i, best_d = i, d
    return best_i


def authorable(is_8bpp, sub_palettes: Sequence[int]) -> Dict[str, Any]:
    """Can this sheet be authored through a flat RGBA image? (ADR-0199 dec. 3)

    v1 covers 8bpp sheets drawn through a single sub-palette — 338 of the 401
    non-empty corpus effects. A refusal always carries a reason: silently
    mis-importing a sheet whose export was never truthful is the failure mode
    this gate exists to prevent.

    `is_8bpp` is the per-frame render depth (`flags_byte0 & 0x80`), NOT the
    `+0x403` VRAM stride byte — those are different fields and disagree for all
    60 4bpp effects. `None` means the depth could not be established.
    """
    if is_8bpp is None:
        return {"ok": False, "reason":
                "the sheet's colour depth cannot be established — no frame references "
                "it, its frames disagree on depth, or the frames section does not "
                "parse — so refusing rather than assuming 8bpp"}
    if not is_8bpp:
        return {"ok": False, "reason":
                "4bpp sheets render through per-frame 16-colour sub-palettes, so one "
                "flat RGBA export cannot show the sheet truthfully (58 of the 60 4bpp "
                "effects use 3-7 of them) — faithful 4bpp authoring is a follow-on"}
    distinct = sorted(set(int(s) for s in sub_palettes))
    if len(distinct) > 1:
        return {"ok": False, "reason":
                "this sheet is drawn through sub-palettes %s, so a single flat export "
                "would show most of it in the wrong colours" % distinct}
    return {"ok": True, "reason": ""}


PLANE_OFFSET = 0x404
"""Palette 1 (512 B) + palette 2 (512 B) + the 4-byte VRAM header, all of which
the fixed-CLUT policy leaves untouched."""


def patch_texture_into(buf: bytearray, plane: bytes, texture_ptr: int) -> None:
    """Splice `plane` over [texture_ptr + 0x404, EOF) in place.

    The pixel plane runs to EOF with zero slack in all 401 corpus effects, so
    the section length is unambiguous and a mismatch is always an error rather
    than a short write.
    """
    start = int(texture_ptr) + PLANE_OFFSET
    end = len(buf)
    if texture_ptr <= 0 or start >= end:
        raise ValueError(
            "texture: no pixel plane (texture_ptr=%r, file is %d bytes)"
            % (texture_ptr, len(buf)))
    blob = bytes(plane)
    if len(blob) != end - start:
        raise ValueError(
            "texture: plane is %d bytes but the section is %d — same-size "
            "replacement only (a resize is the deferred defrag path)"
            % (len(blob), end - start))
    buf[start:end] = blob


def read_plane(data: bytes, texture_ptr: int) -> bytes:
    """The indexed pixel plane: [texture_ptr + 0x404, EOF).

    Corpus-measured: the plane fills to EOF with zero slack in all 401 non-empty
    effects, so EOF is the section's true end and no length field is consulted.
    """
    return bytes(data[int(texture_ptr) + PLANE_OFFSET:])


def read_clut(data: bytes, texture_ptr: int, is_8bpp: bool) -> List[int]:
    """The sheet's palette, as BGR555 words.

    8bpp reads all 256 entries of palette 1 at +0x000. (4bpp would read 16
    entries of palette 2 at +0x200, but is out of v1 scope — `authorable`
    refuses it before this is reached.)
    """
    base = int(texture_ptr) + (0x000 if is_8bpp else 0x200)
    count = 256 if is_8bpp else 16
    return [data[base + i * 2] | (data[base + i * 2 + 1] << 8) for i in range(count)]


def decode_to_rgba(indices: Sequence[int], clut_words: Sequence[int]) -> List[RGBA]:
    """Decode an indexed plane to the RGBA an artist sees. Alpha is STP
    (ADR-0096), so this is the exact inverse of `quantize_to_clut` for any
    untouched sheet."""
    decoded = [bgr555_to_rgba(w) for w in clut_words]
    return [decoded[i] for i in indices]


def texture_dimensions(data: bytes, texture_ptr: int) -> Tuple[int, int]:
    """(width, height) in texels, derived exactly as `extract_effect_texture.lua`
    does so an exported TGA matches the existing tool byte for byte.

    Byte +0x403 selects the VRAM upload STRIDE (0 -> 128, non-0 -> 256), not the
    render depth — those are different fields and disagree for every 4bpp
    effect. Height comes from the 16-bit word at +0x400 shifted by the matching
    amount; a zero falls back to the plane length.
    """
    base = int(texture_ptr)
    combined = data[base + 0x400] | (data[base + 0x401] << 8)
    stride_flag = data[base + 0x403]
    row_bytes, shift = (256, 8) if stride_flag else (128, 7)
    height = combined >> shift
    if height == 0:
        plane = len(data) - (base + PLANE_OFFSET)
        row_bytes = 256
        height = plane // row_bytes if plane > 0 else 0
    return row_bytes, height


# --- locating the sheet -------------------------------------------------------

def embedded_header_offset(data: bytes) -> int:
    """Locate a DATA header that `parse_effect.find_header_offset` misses.

    That scan only looks for an embedded header when the file OPENS with a MIPS
    prologue (0x27BD____). Three corpus effects — E259/E338/E464 — open with
    0x00054040 instead, so it returns 0 and a bogus header at offset 0 is read.
    Without this fallback a corpus scan silently covers 398 of 401 while
    reporting success.

    A header is 10 ascending, in-bounds u32 pointers opening with frames_ptr =
    0x28 (time_scale_ptr at index 5 may be 0, so it is skipped).
    """
    for off in range(0, len(data) - 40, 4):
        if int.from_bytes(data[off:off + 4], "little") != 0x28:
            continue
        ptrs = [int.from_bytes(data[off + i * 4:off + i * 4 + 4], "little")
                for i in range(10)]
        if any(off + p > len(data) for p in ptrs):
            continue
        ordered = [ptrs[i] for i in (0, 1, 2, 3, 4, 6, 7, 8, 9)]
        if all(b >= a for a, b in zip(ordered, ordered[1:])):
            return off
    return 0


def sheet_facts(data: bytes):
    """`(header, is_8bpp, sub_palettes)` for one effect.

    `is_8bpp` is None when the depth cannot be established (no frames reference
    the sheet, its frames disagree, or the section does not parse). Depth is the
    per-frame render flag `flags_byte0 & 0x80`, NOT the +0x403 stride byte.
    """
    import parse_effect as pe                      # local: keeps this module importable alone

    base = pe.find_header_offset(data)
    if base == 0 and int.from_bytes(data[:4], "little") != 0x28:
        base = embedded_header_offset(data)
    header = pe.parse_header(data, base)
    try:
        framesets, _ = pe.parse_frames_section(
            data, header["frames_ptr"], header["animation_ptr"] - header["frames_ptr"])
    except Exception:                              # noqa: BLE001
        return header, None, []
    depths, subs = set(), set()
    for fs in framesets:
        for fr in fs.get("frames", []):
            depths.add(bool(fr["is_8bpp"]))
            subs.add(int(fr["palette_id"]))
    if len(depths) != 1:
        return header, None, sorted(subs)
    return header, depths.pop(), sorted(subs)


# --- the artist-facing file ---------------------------------------------------

def decode_tga(raw: bytes) -> Dict[str, Any]:
    """Read a 32-bit uncompressed TGA into `{ok, width, height, pixels, error}`,
    `pixels` being RGBA quads in top-left-origin row order.

    Mirrors `src/effects/studio/TextureTga.gd`, including the bottom-left-origin
    flip: descriptor bit 5 clear is the TGA default in Photoshop/GIMP/Aseprite,
    so an artist's save routinely arrives that way and must be flipped rather
    than read upside down.
    """
    if len(raw) < 18:
        return {"ok": False, "error": "file is %d bytes — too short for a TGA header" % len(raw)}
    if raw[2] != 2:
        return {"ok": False, "error": "image type %d is not 2 (uncompressed true-colour)" % raw[2]}
    if raw[16] != 32:
        return {"ok": False, "error":
                "%d bits per pixel — the studio's format is 32-bit RGBA" % raw[16]}

    width = raw[12] | (raw[13] << 8)
    height = raw[14] | (raw[15] << 8)
    start = 18 + raw[0]
    need = width * height * 4
    if len(raw) - start < need:
        return {"ok": False, "error":
                "%dx%d needs %d texel bytes, file holds %d"
                % (width, height, need, len(raw) - start)}

    bottom_up = (raw[17] & 0x20) == 0
    row = width * 4
    pixels: List[RGBA] = []
    for y in range(height):
        src = start + ((height - 1 - y) if bottom_up else y) * row
        for x in range(0, row, 4):
            b, g, r, a = raw[src + x], raw[src + x + 1], raw[src + x + 2], raw[src + x + 3]
            pixels.append((r, g, b, a))
    return {"ok": True, "width": width, "height": height, "pixels": pixels, "error": ""}


def import_tga(base_bytes: bytes, tga_path: str) -> Dict[str, Any]:
    """Replace the texture of `base_bytes` from the RGBA .tga at `tga_path`.

    The whole v1 import in one call: scope gate -> decode -> index delta against
    the base's own plane -> splice. Returns `{ok, bytes, off_palette, error}`;
    never raises — a refusal is reported, not thrown, because the studio surfaces
    it to an author.
    """
    header, is_8bpp, subs = sheet_facts(base_bytes)
    verdict = authorable(is_8bpp, subs)
    if not verdict["ok"]:
        return {"ok": False, "bytes": b"", "off_palette": 0, "error": verdict["reason"]}

    try:
        with open(tga_path, "rb") as fh:
            raw = fh.read()
    except OSError as e:
        return {"ok": False, "bytes": b"", "off_palette": 0, "error": "cannot read %s: %s" % (tga_path, e)}

    img = decode_tga(raw)
    if not img["ok"]:
        return {"ok": False, "bytes": b"", "off_palette": 0, "error": img["error"]}

    tex_ptr = header["texture_ptr"]
    want_w, want_h = texture_dimensions(base_bytes, tex_ptr)
    if (img["width"], img["height"]) != (want_w, want_h):
        return {"ok": False, "bytes": b"", "off_palette": 0, "error":
                "imported sheet is %dx%d but this effect's texture is %dx%d — v1 replaces "
                "at the same dimensions only (a resize cascades into every frame's UVs)"
                % (img["width"], img["height"], want_w, want_h)}

    plane = read_plane(base_bytes, tex_ptr)
    clut = read_clut(base_bytes, tex_ptr, is_8bpp)
    result = quantize_to_clut(img["pixels"], clut, list(plane))

    buf = bytearray(base_bytes)
    patch_texture_into(buf, bytes(result["indices"]), tex_ptr)
    return {"ok": True, "bytes": bytes(buf),
            "off_palette": result["off_palette"], "error": ""}


def main(argv=None) -> int:
    """CLI the studio's EffectTextureSaver shells out to."""
    import argparse

    ap = argparse.ArgumentParser(description="Replace an effect's texture from an RGBA .tga")
    ap.add_argument("--base-bin", required=True, help="the E###.BIN to patch")
    ap.add_argument("--tga", required=True, help="the RGBA .tga to import")
    ap.add_argument("--out-bin", required=True, help="where to write the patched BIN")
    args = ap.parse_args(argv)

    with open(args.base_bin, "rb") as fh:
        base = fh.read()
    result = import_tga(base, args.tga)
    if not result["ok"]:
        import sys
        print("write_effect_texture: %s" % result["error"], file=sys.stderr)
        return 1
    with open(args.out_bin, "wb") as fh:
        fh.write(result["bytes"])
    if result["off_palette"]:
        print("write_effect_texture: %d texels were off-palette and were snapped to the "
              "nearest entry (the CLUT is fixed)" % result["off_palette"])
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
