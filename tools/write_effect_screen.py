"""Byte-exact SCREEN-section writer for E###.BIN (#255 slice 5).

This is the inverse of `parse_effect.parse_all_screen_keyframes`. Given the base
`E###.BIN` bytes, a parsed (possibly edited) `screen` block, and the header's
`timeline_section_ptr`, `patch_screen_section` returns a NEW byte buffer in
which the three screen colour channels (for_each / phase1 / phase2) are
re-serialized from their authoritative `raw` sub-blocks. Every byte outside the
written screen fields is preserved verbatim — a partial patch (#254 decision 4),
mirroring the effect-editor's memory writer which only pokes the fields it knows
and leaves the rest of the loaded buffer untouched.

The `raw` sub-block is the source of truth (#254 decision 2); the sibling
derived fields (`duration_frames`, `mode`, `blend_mode`) are ignored here.

Offset math (channel bases, field strides, the 33-keyframe count) is imported
from `parse_effect` so there is exactly ONE ROM layout shared by reader and
writer.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from parse_effect import MAX_SCREEN_KEYFRAMES, SCREEN_TRACK_OFFSETS

# Field offsets within a screen channel (mirror parse_screen_channel).
_OFF_TIME = 0x00     # + i*2, signed 16-bit
_OFF_START = 0x42    # + i*3, u8 R/G/B
_OFF_END = 0xA5      # + i*3, u8 R/G/B
_OFF_CTRL = 0x108    # + i,   u8
_OFF_MAX_KF_TAIL = 298  # s16 at end of a channel (phase1/phase2 default)


def _write_u8(buf: bytearray, offset: int, value: int) -> None:
    buf[offset] = value & 0xFF


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    # Accept the full signed/unsigned 16-bit range; parse reads back with "<h".
    struct.pack_into("<h", buf, offset, _as_s16(value))


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def serialize_screen_channel(
    buf: bytearray,
    base_offset: int,
    channel: Dict[str, Any],
    max_kf_offset: Optional[int] = None,
) -> None:
    """Write one screen channel's `raw` bytes into `buf` at `base_offset`.

    Byte-exact inverse of `parse_screen_channel`: for each of the 33 keyframes
    writes time_value (s16 LE), start RGB, end RGB, ctrl; then max_keyframe
    (s16 LE) at `max_kf_offset` (for_each) or `base_offset + 298` (phase1/2).
    """
    for i in range(MAX_SCREEN_KEYFRAMES):
        raw = channel["keyframes"][i]["raw"]
        _write_s16(buf, base_offset + _OFF_TIME + i * 2, raw["time_value"])
        _write_u8(buf, base_offset + _OFF_START + i * 3 + 0, raw["start_r"])
        _write_u8(buf, base_offset + _OFF_START + i * 3 + 1, raw["start_g"])
        _write_u8(buf, base_offset + _OFF_START + i * 3 + 2, raw["start_b"])
        _write_u8(buf, base_offset + _OFF_END + i * 3 + 0, raw["end_r"])
        _write_u8(buf, base_offset + _OFF_END + i * 3 + 1, raw["end_g"])
        _write_u8(buf, base_offset + _OFF_END + i * 3 + 2, raw["end_b"])
        _write_u8(buf, base_offset + _OFF_CTRL + i, raw["ctrl"])

    max_kf = channel["max_keyframe"]
    if max_kf_offset is not None:
        _write_s16(buf, max_kf_offset, max_kf)
    else:
        _write_s16(buf, base_offset + _OFF_MAX_KF_TAIL, max_kf)


def patch_screen_into(
    buf: bytearray, screen: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the screen colour channels of `buf` IN PLACE from `screen`
    (the parsed, possibly edited block). This is the reusable core shared by the
    standalone `patch_screen_section` and the per-section serializer registry
    (F1 #264) — both hand the same bytearray to a chain of section serializers.

    Only the known screen fields are overwritten; all other bytes — including
    unsupported/unknown bytes inside the channel region — stay verbatim.
    Contexts absent from `screen` are left untouched. Mirrors
    `parse_all_screen_keyframes`' per-context base math.
    """
    # for_each: base is timeline_ptr + 8, with an explicit max_keyframe offset.
    if "for_each" in screen:
        for_each_base = timeline_ptr + 8
        off = SCREEN_TRACK_OFFSETS["for_each"]
        serialize_screen_channel(
            buf,
            for_each_base + off["data"],
            screen["for_each"],
            for_each_base + off["max_keyframe"],
        )

    # phase1 / phase2: base is timeline_ptr; max_keyframe at data + 298.
    for context in ("phase1", "phase2"):
        if context in screen:
            off = SCREEN_TRACK_OFFSETS[context]
            serialize_screen_channel(
                buf, timeline_ptr + off["data"], screen[context], None
            )


def patch_screen_section(
    base_bytes: bytes, screen: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the screen colour channels
    re-serialized from `screen` (the parsed, possibly edited block). A thin copy
    wrapper over `patch_screen_into` — the in-place core."""
    buf = bytearray(base_bytes)
    patch_screen_into(buf, screen, timeline_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------

_RAW_KEYS = ("time_value", "start_r", "start_g", "start_b",
             "end_r", "end_g", "end_b", "ctrl")


def _keyframe_raw(kf: Dict[str, Any]) -> Dict[str, int]:
    """The authoritative raw sub-block for one keyframe. If the JSON already
    carries a `raw` block it wins; otherwise it is reconstructed from the flat
    fields (which ARE the raw bytes — start_r is the 0-255 byte on disk). This
    lets the game write a flat screen.json (its load shape) with no `raw` block."""
    raw = kf.get("raw")
    if raw is not None:
        return raw
    return {k: int(kf[k]) for k in _RAW_KEYS}


def screen_json_to_writer_block(screen_json: Dict[str, Any]) -> Dict[str, Any]:
    """Adapt a screen.json (flat keyframe fields, the game's write-back shape)
    into the `screen` block `patch_screen_section` consumes (each keyframe a
    `{"raw": {...}}`), preserving max_keyframe per context."""
    block: Dict[str, Any] = {}
    for context in ("for_each", "phase1", "phase2"):
        if context not in screen_json:
            continue
        chan = screen_json[context]
        kfs: List[Dict[str, Any]] = [
            {"raw": _keyframe_raw(kf)} for kf in chan["keyframes"]
        ]
        block[context] = {"max_keyframe": int(chan["max_keyframe"]), "keyframes": kfs}
    return block


def repack(base_bytes: bytes, screen_json: Dict[str, Any], timeline_ptr: int) -> bytes:
    """Patch a base E###.BIN with an (edited) screen.json — the `json -> bin`
    half of the Studio save loop."""
    return patch_screen_section(
        base_bytes, screen_json_to_writer_block(screen_json), timeline_ptr
    )


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's screen section from an edited screen.json.

    Usage: write_effect_screen.py <base.bin> <screen.json> <header.json> <out.bin>
    `header.json` supplies `header.timeline_section_ptr` (parse_effect's header
    export). Every non-screen byte is copied from <base.bin> verbatim.
    """
    ap = argparse.ArgumentParser(description="Patch an E###.BIN screen section from screen.json")
    ap.add_argument("base_bin")
    ap.add_argument("screen_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    screen_json = json.loads(Path(args.screen_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    timeline_ptr = int(header["header"]["timeline_section_ptr"])

    out = repack(base, screen_json, timeline_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
