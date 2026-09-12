"""Byte-exact PARTICLE-TIMELINE writer for E###.BIN (ADR-0089 particle_timeline
amendment).

The inverse of the particle-channel half of `parse_effect.parse_timeline`. Given
the base `E###.BIN` bytes, a parsed (possibly edited) timeline block (the dict
with a `particle_channels` list), and the header's `timeline_section_ptr`,
`patch_particle_timeline_section` returns a NEW byte buffer in which each 128-byte
particle channel's SoA arrays are re-serialized from their raw fields. Every byte
outside those fields is preserved verbatim — a partial patch, mirroring
`write_effect_camera`.

Authoritative raw = each keyframe's `time` (s16), `emitter_id` (u8),
`action_flags` (u16), plus the channel `max_keyframe` (s16). All 25 slots are
written verbatim so an unedited channel round-trips byte-identical.

THE SoA OVERLAP (the risk this writer clears): `time[]` (25 s16, bytes 0x00..0x31)
and `emitter_id[]` (25 u8, bytes 0x31..0x49) SHARE byte 0x31 — it is both
`time[24]`'s high byte and `emitter_id[0]`. The parser reads 0x31 AS
`emitter_id[0]`, so emitter_id is its semantic owner; `time[24]` is a phantom
slot (max_keyframe never reaches 24 in real data). We therefore write **time[]
first, then emitter_id[]**, so emitter_id[0] wins byte 0x31 and the round-trip is
byte-exact. The channel offset math is imported from `parse_effect` so reader and
writer share exactly ONE ROM layout.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import parse_effect as pe


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def _write_u16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<H", buf, offset, value & 0xFFFF)


def _as_s16(value: int) -> int:
    v = int(value) & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def serialize_particle_channel(buf: bytearray, base: int, channel: Dict[str, Any]) -> None:
    """Write one particle channel's raw SoA arrays into `buf` at file offset
    `base`.

    Byte-exact inverse of `parse_particle_channel`. Writes all 25 slots of each
    array + max_keyframe; unaddressed bytes (the 0x7C/0x7D gap, the tail past
    0x7F) stay verbatim. Write ORDER matters: time[] before emitter_id[] so
    emitter_id[0] owns the shared byte 0x31 (see module docstring).
    """
    keyframes = channel["keyframes"]

    # 1. time[] (may write time[24].hi into the shared byte 0x31) ...
    for i in range(pe.PARTICLE_SLOTS):
        _write_s16(buf, base + pe.PARTICLE_OFF_TIME + i * 2, keyframes[i]["time"])

    # 2. ... then emitter_id[], so emitter_id[0] wins byte 0x31.
    for i in range(pe.PARTICLE_SLOTS):
        buf[base + pe.PARTICLE_OFF_EMITTER_ID + i] = int(keyframes[i]["emitter_id"]) & 0xFF

    # 3. action_flags[]
    for i in range(pe.PARTICLE_SLOTS):
        _write_u16(buf, base + pe.PARTICLE_OFF_ACTION_FLAGS + i * 2, keyframes[i]["action_flags"])

    # 4. max_keyframe watermark
    _write_s16(buf, base + pe.PARTICLE_OFF_MAX_KEYFRAME, channel["max_keyframe"])


def patch_particle_timeline_into(
    buf: bytearray, timeline: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the particle channels of `buf` IN PLACE from `timeline` (the
    parsed, possibly edited timeline block). Reusable core shared by the
    standalone `patch_particle_timeline_section` and the per-section serializer
    registry (F1 #264).

    Only the channels present in `timeline["particle_channels"]` are overwritten;
    every other byte stays verbatim. Each channel's file offset is derived from
    its `context` + `channel_index` via the shared `particle_channel_offset`.
    """
    for channel in timeline.get("particle_channels", []):
        base = pe.particle_channel_offset(
            timeline_ptr, channel["context"], channel["channel_index"]
        )
        serialize_particle_channel(buf, base, channel)


def patch_particle_timeline_section(
    base_bytes: bytes, timeline: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the particle channels re-serialized from
    `timeline`. A thin copy wrapper over `patch_particle_timeline_into`."""
    buf = bytearray(base_bytes)
    patch_particle_timeline_into(buf, timeline, timeline_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's particle channels from an edited timeline.json.

    Usage: write_effect_particle_timeline.py <base.bin> <timeline.json> <header.json> <out.bin>
    `header.json` supplies `header.timeline_section_ptr`. Every non-particle byte
    is copied from <base.bin> verbatim.
    """
    ap = argparse.ArgumentParser(
        description="Patch an E###.BIN particle timeline from timeline.json")
    ap.add_argument("base_bin")
    ap.add_argument("timeline_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    timeline = json.loads(Path(args.timeline_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    timeline_ptr = int(header["header"]["timeline_section_ptr"])

    out = patch_particle_timeline_section(base, timeline, timeline_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
