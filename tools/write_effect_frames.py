"""Byte-exact FRAMES/FRAMESET writer for E###.BIN (#278).

The inverse of `parse_effect.parse_frames_section`, restricted to #278's v1
scope: IN-PLACE FIELD EDITS ONLY (no adding/removing/reordering frames,
framesets, or frameset-group membership — see the #278 ticket, locked via
/grill-with-docs 2026-08-17). Given the base bytes, the parsed (possibly
edited) `framesets` block (the SAME flat-array shape `parse_frames_section`
returns / `EffectData.framesets` holds), and the header's `frames_ptr`,
`patch_frames_into` re-serializes each existing 24-byte frame record's
editable fields in place. The group table, per-frameset offset table, frame
counts, and header_flags are NEVER written — they are the very structure this
writer walks to LOCATE each frame, read straight from `buf`, so a v1 edit
can never desync the offsets the parser would recompute.

Editable fields (mirrors `FramesetChannel.gd`'s `_SCALAR_FIELD`/`_UV_FIELD`/
`_VERTEX_FIELD`, the Godot-side encoder this writer is the file-persistence
counterpart of): `palette_id` (byte0 bits 0-3), `semi_trans_mode` (byte0 bits
5-6), `is_8bpp` (byte0 bit 7), `semi_trans_on` (byte1 bit 1), `uv.x/y/width/
height` (bytes +4..+7), and the four signed-s16 `vertices` corners (bytes
+8..+22). texture_page (bytes +2/+3) and the width_signed/height_signed flag
bits (byte1 bits 4/5) are NOT in the v1 editable set and are always preserved
verbatim (read-modify-write on the two flag bytes; every other field's byte(s)
untouched).

uv.x/uv.y need no sign handling — `parse_frame` reads them as plain unsigned
bytes. uv.width/uv.height and the vertices DO get sign-corrected on read (by
the frame's OWN width_signed/height_signed bits, or are natively signed for
vertices), but `value & 0xFF` (Python's bitwise AND on a negative int) always
produces the correct two's-complement byte regardless of which interpretation
is active — so the writer needs no signed/unsigned branch on write; whether a
given value round-trips depends on the frame's (untouched, not authored here)
sign-flag bit, which is exactly `FramesetChannel.gd`'s Faithful advisory's
job to warn about, not this writer's.
"""

from __future__ import annotations

import struct
from typing import Any, Dict, Iterator, List, Tuple

from parse_effect import read_u8, read_u16, FRAME_SIZE, FRAMESET_HEADER_SIZE


def _write_u8(buf: bytearray, offset: int, value: int) -> None:
    buf[offset] = value & 0xFF


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def _iter_frame_offsets(buf: bytes, frames_ptr: int) -> Iterator[Tuple[int, int, int]]:
    """Yield (frameset_index, frame_index, absolute_byte_offset) for every frame
    the base bytes actually contain, walking the SAME group-table / offset-table
    / frameset-header discovery `parse_effect.parse_frames_section` does (so a
    writer using this always targets the exact bytes the parser would read back).
    Read-only over `buf` — this walk never depends on `block`, the (possibly
    edited) JSON block being written."""
    section_size = len(buf) - frames_ptr
    if section_size < 8:
        return

    group_count = read_u8(buf, frames_ptr)
    group_entries_end = 4 + group_count * 2
    if group_entries_end >= section_size:
        return

    first_offset = read_u16(buf, frames_ptr + group_entries_end)
    frame_sets_data_start = first_offset + 4
    max_frame_sets = (frame_sets_data_start - group_entries_end) // 2
    if max_frame_sets <= 0 or max_frame_sets > 500:
        return

    num_frame_sets = 0
    for i in range(max_frame_sets):
        offset_pos = frames_ptr + group_entries_end + i * 2
        if offset_pos + 2 > frames_ptr + section_size:
            break
        raw_offset = read_u16(buf, offset_pos)
        if raw_offset < first_offset:
            break
        num_frame_sets += 1

    for fs_idx in range(num_frame_sets):
        offset_pos = frames_ptr + group_entries_end + fs_idx * 2
        raw_offset = read_u16(buf, offset_pos)
        fs_offset = frames_ptr + raw_offset + 4
        if fs_offset + FRAMESET_HEADER_SIZE > len(buf):
            break
        frame_count = read_u16(buf, fs_offset + 2)
        if frame_count <= 0 or frame_count > 100:
            continue
        for frame_idx in range(frame_count):
            frame_offset = fs_offset + FRAMESET_HEADER_SIZE + frame_idx * FRAME_SIZE
            if frame_offset + FRAME_SIZE > len(buf):
                break
            yield fs_idx, frame_idx, frame_offset


_VERTEX_CORNERS = ["top_left", "top_right", "bottom_left", "bottom_right"]


def serialize_frame(buf: bytearray, offset: int, frame: Dict[str, Any]) -> None:
    """Write one frame's editable fields into `buf` at `offset` (24 bytes),
    read-modify-write on the two flag bytes so every unread/unauthored bit
    (bit4 of byte0, width_signed/height_signed of byte1, all of texture_page)
    survives untouched."""
    byte0 = buf[offset]
    palette_id = int(frame.get("palette_id", 0)) & 0x0F
    semi_trans_mode = int(frame.get("semi_trans_mode", 0)) & 0x03
    is_8bpp = 1 if frame.get("is_8bpp", False) else 0
    byte0 = (byte0 & 0x10) | palette_id | (semi_trans_mode << 5) | (is_8bpp << 7)
    _write_u8(buf, offset, byte0)

    byte1 = buf[offset + 1]
    semi_trans_on = 1 if frame.get("semi_trans_on", False) else 0
    byte1 = (byte1 & ~0x02) | (semi_trans_on << 1)
    _write_u8(buf, offset + 1, byte1)

    # +2/+3 (texture_page, packed u16) intentionally untouched — not v1-editable.

    uv: Dict[str, Any] = frame.get("uv", {}) or {}
    _write_u8(buf, offset + 4, int(uv.get("x", 0)))
    _write_u8(buf, offset + 5, int(uv.get("y", 0)))
    _write_u8(buf, offset + 6, int(uv.get("width", 0)))
    _write_u8(buf, offset + 7, int(uv.get("height", 0)))

    vertices: Dict[str, Any] = frame.get("vertices", {}) or {}
    for i, corner in enumerate(_VERTEX_CORNERS):
        pair = vertices.get(corner, [0, 0])
        _write_s16(buf, offset + 8 + i * 4, int(pair[0]))
        _write_s16(buf, offset + 8 + i * 4 + 2, int(pair[1]))


def patch_frames_into(buf: bytearray, framesets: List[Dict[str, Any]], frames_ptr: int) -> None:
    """Partial-patch every frame's editable fields into `buf` IN PLACE from
    `framesets` (the parsed, possibly edited flat frameset array — SAME shape
    `parse_frames_section` returns). Frame offsets are located by walking the
    EXISTING (untouched) group/offset-table structure in `buf`, never from
    `framesets` itself, so a v1 edit can only ever touch a real frame's own 24
    bytes. A `framesets` shorter than the base (or a frameset's `frames`
    shorter than its base frame_count) leaves the missing frames' bytes
    untouched, rather than raising — the choke point (`EffectEditSession`)
    never removes entries in v1, so this is a defensive no-op path, not the
    expected case."""
    for fs_idx, frame_idx, offset in _iter_frame_offsets(buf, frames_ptr):
        if fs_idx >= len(framesets) or not isinstance(framesets[fs_idx], dict):
            continue
        frames = framesets[fs_idx].get("frames", [])
        if frame_idx >= len(frames) or not isinstance(frames[frame_idx], dict):
            continue
        serialize_frame(buf, offset, frames[frame_idx])


def patch_frames_section(base_bytes: bytes, framesets: List[Dict[str, Any]], frames_ptr: int) -> bytes:
    """Return a copy of `base_bytes` with every frame's editable fields
    re-serialized from `framesets`. A thin copy wrapper over
    `patch_frames_into` (the in-place core), mirroring write_effect_sound."""
    buf = bytearray(base_bytes)
    patch_frames_into(buf, framesets, frames_ptr)
    return bytes(buf)
