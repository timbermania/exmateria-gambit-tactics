"""Byte-exact PALETTE-section writer for E###.BIN (Subsystem 1, #266).

The inverse of `parse_effect.parse_all_palette_keyframes`. Given the base
`E###.BIN` bytes, a parsed (possibly edited) `palette` block, and the header's
`timeline_section_ptr`, `patch_palette_section` returns a NEW byte buffer in
which the nine palette/field-tint channels (for_each / phase1 / phase2 x
affected_units / caster / target) are re-serialized from their raw keyframe
fields. Every byte outside the written palette fields is preserved verbatim — a
partial patch (mirroring write_effect_screen).

Unlike screen, a palette keyframe has NO `raw` sub-block: its flat fields
(`time_value`, `rgb` list, `ctrl`) ARE the raw bytes on disk (parse_palette_
channel reads them straight through), so the writer writes them straight back.

Offset math (per-channel bases, the 33-keyframe count, the 198-byte track size)
is imported from `parse_effect` so reader and writer share ONE ROM layout.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from parse_effect import (
    MAX_PALETTE_KEYFRAMES,
    PALETTE_TRACK_OFFSETS,
    PALETTE_TRACK_SIZE,
)

# Field offsets within a palette channel (mirror parse_palette_channel).
_OFF_TIME = 0x00     # + i*2, signed 16-bit
_OFF_RGB = 0x42      # + i*3, u8 R/G/B
_OFF_CTRL = 0xA5     # + i,   u8
# max_keyframe: s16 LE at base_offset + PALETTE_TRACK_SIZE (198).


def _write_u8(buf: bytearray, offset: int, value: int) -> None:
    buf[offset] = value & 0xFF


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def serialize_palette_channel(
    buf: bytearray, base_offset: int, channel: Dict[str, Any]
) -> None:
    """Write one palette channel's raw bytes into `buf` at `base_offset`.

    Byte-exact inverse of `parse_palette_channel`: for each of the 33 keyframes
    writes time_value (s16 LE), RGB (three u8), ctrl (u8); then max_keyframe
    (s16 LE) at `base_offset + PALETTE_TRACK_SIZE`.
    """
    keyframes = channel["keyframes"]
    for i in range(MAX_PALETTE_KEYFRAMES):
        kf = keyframes[i]
        rgb = kf["rgb"]
        _write_s16(buf, base_offset + _OFF_TIME + i * 2, int(kf["time_value"]))
        _write_u8(buf, base_offset + _OFF_RGB + i * 3 + 0, int(rgb[0]))
        _write_u8(buf, base_offset + _OFF_RGB + i * 3 + 1, int(rgb[1]))
        _write_u8(buf, base_offset + _OFF_RGB + i * 3 + 2, int(rgb[2]))
        _write_u8(buf, base_offset + _OFF_CTRL + i, int(kf["ctrl"]))
    _write_s16(buf, base_offset + PALETTE_TRACK_SIZE, int(channel["max_keyframe"]))


def patch_palette_into(
    buf: bytearray, palette: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the palette channels of `buf` IN PLACE from `palette` (the
    parsed, possibly edited block). Reusable core shared by the standalone
    `patch_palette_section` and the per-section serializer registry (F1 #264).

    Only the known palette fields are overwritten; all other bytes — including
    unused/padding keyframes inside a channel — stay verbatim. Contexts/channels
    absent from `palette` are left untouched. Mirrors parse_all_palette_
    keyframes' per-channel base math (for_each = timeline_ptr + 8; phase1/phase2
    = timeline_ptr directly)."""
    for context, offsets in PALETTE_TRACK_OFFSETS.items():
        if context not in palette:
            continue
        base = timeline_ptr + 8 if context == "for_each" else timeline_ptr
        ctx_channels = palette[context]
        for channel_name, channel_offset in offsets.items():
            if channel_name not in ctx_channels:
                continue
            serialize_palette_channel(
                buf, base + channel_offset, ctx_channels[channel_name]
            )


def patch_palette_section(
    base_bytes: bytes, palette: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the palette channels re-serialized from
    `palette`. A thin copy wrapper over `patch_palette_into` (the in-place core)."""
    buf = bytearray(base_bytes)
    patch_palette_into(buf, palette, timeline_ptr)
    return bytes(buf)


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's palette section from an edited palette.json.

    Usage: write_effect_palette.py <base.bin> <palette.json> <header.json> <out.bin>
    `header.json` supplies `header.timeline_section_ptr`. Every non-palette byte is
    copied from <base.bin> verbatim (a partial patch, the counterpart of the camera
    writer). The Studio layers this on top of the screen+camera writers' output BIN.
    """
    ap = argparse.ArgumentParser(description="Patch an E###.BIN palette section from palette.json")
    ap.add_argument("base_bin")
    ap.add_argument("palette_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    palette = json.loads(Path(args.palette_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    timeline_ptr = int(header["header"]["timeline_section_ptr"])

    out = patch_palette_section(base, palette, timeline_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
