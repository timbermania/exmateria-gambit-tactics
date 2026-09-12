"""Byte-exact SOUND-TIMELINE writer for E###.BIN (Subsystem 3, #268).

The inverse of `parse_effect.parse_sound_keyframes`. Given the base `E###.BIN`
bytes, a parsed (possibly edited) `sound` block, and the header's
`timeline_section_ptr`, `patch_sound_section` returns a NEW byte buffer in which
the nine SFX-trigger channels — six outer (phase1/phase2, 30 B each) plus three
for-each (54 B each) — are re-serialized from their raw keyframe fields. Every
byte outside the written sound fields is preserved verbatim: a partial patch
(mirroring write_effect_palette).

Only the TIER-1 timeline tracks are written. A keyframe has two editable raw
fields: `duration_frames` (the s16 time_value, LE at off + i*2) and `sound_id`
(u8, after the KF-count time block). Per-channel `max_keyframe` (s16 at the fixed
tail) round-trips verbatim. NOTE (FEDS 3-tier map): sound_id is not a raw SFX id —
0/1 skip, N>=2 indexes SoundContainer[N-2] (TIER-2) which resolves via a mode to a
FEDS pair (TIER-3, header[0x20]); duration_frames is a per-keyframe frames-left
countdown. This writer touches ONLY the raw TIER-1 bytes — TIER-2/TIER-3 untouched.

The ROM read is `lbu a0,0x12(v0)` for the sound_id at 0x801a47e0 (outer walker,
per parse_effect's master_parser legend). Offset math (per-phase channel bases,
the KF counts, the max_keyframe tail) is imported from `parse_effect` so reader
and writer share ONE ROM layout.
"""

from __future__ import annotations

import struct
from typing import Any, Dict, List, Tuple

from parse_effect import (
    SOUND_PHASE1_OFFSETS,
    SOUND_PHASE2_OFFSETS,
    SOUND_ANIMATE_OFFSETS,
    SOUND_OUTER_KF,
    SOUND_FOREACH_KF,
    SOUND_OUTER_MAXKF_OFF,
    SOUND_FOREACH_MAXKF_OFF,
)


def _write_u8(buf: bytearray, offset: int, value: int) -> None:
    buf[offset] = value & 0xFF


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def serialize_sound_channel(
    buf: bytearray, base_offset: int, channel: Dict[str, Any], kf_count: int, maxkf_off: int
) -> None:
    """Write one sound channel's raw bytes into `buf` at `base_offset`.

    Byte-exact inverse of parse_effect's `_parse_outer_sound_channel` /
    `_parse_foreach_sound_channel`: for each of `kf_count` keyframes writes
    duration_frames (the s16 time_value, LE at + i*2) then sound_id (u8, at
    base + kf_count*2 + i); then max_keyframe (s16 LE) at base + `maxkf_off`.
    Padding/unused bytes between the sound_id block and the tail stay verbatim.

    The ROM track has a FIXED slot budget (`kf_count`: 9 outer / 17 for-each).
    A keyframes list of any OTHER length raises — over-cap would silently drop
    keyframes on disk (mirror the camera writer's raise-over-cap), under-cap
    would leave stale slot bytes posing as data."""
    keyframes = channel["keyframes"]
    if len(keyframes) != kf_count:
        raise ValueError(
            "sound channel expects exactly %d native keyframe slots, got %d — "
            "refusing to truncate/underfill" % (kf_count, len(keyframes))
        )
    sid_base = base_offset + kf_count * 2
    for i in range(kf_count):
        kf = keyframes[i]
        _write_s16(buf, base_offset + i * 2, int(kf["duration_frames"]))
        _write_u8(buf, sid_base + i, int(kf["sound_id"]))
    _write_s16(buf, base_offset + maxkf_off, int(channel["max_keyframe"]))


# (phase key, base = timeline_ptr(+delta), channel offsets, kf count, max_kf tail)
def _phase_layouts(timeline_ptr: int) -> List[Tuple[str, int, List[int], int, int]]:
    return [
        ("phase1", timeline_ptr, SOUND_PHASE1_OFFSETS, SOUND_OUTER_KF, SOUND_OUTER_MAXKF_OFF),
        ("phase2", timeline_ptr, SOUND_PHASE2_OFFSETS, SOUND_OUTER_KF, SOUND_OUTER_MAXKF_OFF),
        ("for_each", timeline_ptr + 8, SOUND_ANIMATE_OFFSETS, SOUND_FOREACH_KF, SOUND_FOREACH_MAXKF_OFF),
    ]


def patch_sound_into(
    buf: bytearray, sound: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the sound channels of `buf` IN PLACE from `sound` (the parsed,
    possibly edited block). Reusable core shared by the standalone
    `patch_sound_section` and the per-section serializer registry (F1 #264).

    Only the known sound fields (duration_frames, sound_id, max_keyframe) are
    overwritten; all other bytes stay verbatim. Phases absent from `sound`, or a
    channel list shorter than 3, are left untouched. Mirrors parse_sound_keyframes'
    per-phase base math (outer = timeline_ptr; for_each = timeline_ptr + 8)."""
    for phase, base, offsets, kf_count, maxkf_off in _phase_layouts(timeline_ptr):
        channels = sound.get(phase)
        if not isinstance(channels, list):
            continue
        for ci, channel_offset in enumerate(offsets):
            if ci >= len(channels) or not isinstance(channels[ci], dict):
                continue
            serialize_sound_channel(
                buf, base + channel_offset, channels[ci], kf_count, maxkf_off
            )


def patch_sound_section(
    base_bytes: bytes, sound: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the sound channels re-serialized from
    `sound`. A thin copy wrapper over `patch_sound_into` (the in-place core)."""
    buf = bytearray(base_bytes)
    patch_sound_into(buf, sound, timeline_ptr)
    return bytes(buf)
