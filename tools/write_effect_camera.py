"""Byte-exact CAMERA-section writer for E###.BIN (wayfinder #267).

The inverse of `parse_effect.parse_camera_keyframes`. Given the base `E###.BIN`
bytes, a parsed (possibly edited) `camera` block, and the header's
`timeline_section_ptr`, `patch_camera_section` returns a NEW byte buffer in
which the three camera SoA tables (for_each / phase1 / phase2) are re-serialized
from their authoritative raw fields. Every byte outside the written camera
fields is preserved verbatim — a partial patch, mirroring the screen writer
(`write_effect_screen`).

Authoritative raw = `command_raw` (the full u16 command word) plus the raw s16
arrays `end_frame` / `angle` / `position` / `zoom` and the table `max_keyframe`;
the decoded sibling fields (`channel_mask`, `source_mode`, `interpolation`,
`param_index`, `flags`) are DERIVED and ignored here — exactly as the screen
writer ignores `mode`/`blend_mode`. Any editor that changes a decoded field must
fold it back into `command_raw` upstream (the CameraChannel encoder), so the
writer stays a pure raw→bytes projection.

Offset math (per-table SoA offsets, the 21/17 keyframe counts) is imported from
`parse_effect` so reader and writer share exactly ONE ROM layout.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from parse_effect import CAMERA_TRACK_TABLES

# All camera tables use timeline_section_ptr directly as the base (NOT +8 like
# the screen/palette channels — see parse_camera_keyframes).


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def _write_u16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<H", buf, offset, value & 0xFFFF)


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def serialize_camera_table(
    buf: bytearray, base: int, table: Dict[str, Any], offsets: Dict[str, int]
) -> None:
    """Write one camera SoA table's raw arrays into `buf`.

    Byte-exact inverse of `parse_camera_phase_table`: for each of the table's
    `count` keyframes writes end_frame (s16), angle[0..2] / position[0..2] /
    zoom[0..2] (each 3×s16), and command_raw (u16); then max_keyframe (s16) at
    its own offset. Writing all three zoom slots (only [0] is engine-used)
    round-trips the two engine-ignored slots verbatim.
    """
    count = offsets["count"]
    keyframes = table["keyframes"]

    # The camera SoA tables are FIXED native-slot arrays; the add/delete verbs
    # (ADR-0085) express a count change as a moved `max_keyframe` watermark plus
    # shifted slot contents, never a longer list. A table that overflows the
    # native slots — or whose watermark points past them — cannot be
    # section-written (the ROM has no slot to hold it): refuse it loudly rather
    # than silently truncate the tail.
    if len(keyframes) > count:
        raise ValueError(
            "camera table has %d keyframes, over the %d native slots — over-capacity "
            "cannot be section-written (ADR-0085 Faithful capacity)"
            % (len(keyframes), count)
        )
    max_kf = table["max_keyframe"]
    if not (0 <= max_kf < count):
        raise ValueError(
            "camera table max_keyframe %d is outside the native slots [0, %d)"
            % (max_kf, count)
        )

    for i in range(count):
        kf = keyframes[i]
        _write_s16(buf, base + offsets["end_frame"] + i * 2, kf["end_frame"])

        a = kf["angle"]
        for j in range(3):
            _write_s16(buf, base + offsets["angle"] + i * 6 + j * 2, a[j])

        p = kf["position"]
        for j in range(3):
            _write_s16(buf, base + offsets["position"] + i * 6 + j * 2, p[j])

        z = kf["zoom"]
        for j in range(3):
            _write_s16(buf, base + offsets["zoom"] + i * 6 + j * 2, z[j])

        _write_u16(buf, base + offsets["command"] + i * 2, kf["command_raw"])

    _write_s16(buf, base + offsets["max_keyframe"], table["max_keyframe"])


def patch_camera_into(
    buf: bytearray, camera: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the camera SoA tables of `buf` IN PLACE from `camera` (the
    parsed, possibly edited block). Reusable core shared by the standalone
    `patch_camera_section` and the per-section serializer registry (F1 #264).

    Only the known camera fields are overwritten; every other byte — including
    the trailing bytes past the last table and any unknown bytes — stays
    verbatim. Tables absent from `camera` are left untouched.
    """
    for table_name, offsets in CAMERA_TRACK_TABLES.items():
        if table_name in camera:
            serialize_camera_table(buf, timeline_ptr, camera[table_name], offsets)


def patch_camera_section(
    base_bytes: bytes, camera: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the camera SoA tables re-serialized
    from `camera`. A thin copy wrapper over `patch_camera_into` (the in-place
    core)."""
    buf = bytearray(base_bytes)
    patch_camera_into(buf, camera, timeline_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------


def repack(base_bytes: bytes, camera_json: Dict[str, Any], timeline_ptr: int) -> bytes:
    """Patch a base E###.BIN with an (edited) camera.json — the `json -> bin`
    half of the Studio save loop. camera.json IS the parse_camera_keyframes
    shape, so no adapter is needed (unlike screen's flat form)."""
    return patch_camera_section(base_bytes, camera_json, timeline_ptr)


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's camera section from an edited camera.json.

    Usage: write_effect_camera.py <base.bin> <camera.json> <header.json> <out.bin>
    `header.json` supplies `header.timeline_section_ptr`. Every non-camera byte
    is copied from <base.bin> verbatim.
    """
    ap = argparse.ArgumentParser(description="Patch an E###.BIN camera section from camera.json")
    ap.add_argument("base_bin")
    ap.add_argument("camera_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    camera_json = json.loads(Path(args.camera_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    timeline_ptr = int(header["header"]["timeline_section_ptr"])

    out = repack(base, camera_json, timeline_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
