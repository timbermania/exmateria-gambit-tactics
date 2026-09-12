"""Byte-exact ANIMATION/SEQUENCE writer for E###.BIN (#275).

The inverse of `parse_effect.parse_animations_section`, restricted to #275's v1
scope: IN-PLACE PARAMETER EDITS ONLY (no inserting/deleting/reordering opcodes,
no changing an opcode's TYPE, no adding/removing sequences — locked with the
user 2026-08-18). Given the base bytes, the parsed (possibly edited)
`animations` block (the SAME shape `parse_animations_section` returns /
`EffectData.animations` holds), the header's `animation_ptr` and the section
size, `patch_animation_into` re-serializes each existing opcode's parameters in
place.

The sequence count and the per-sequence offset table are NEVER written — they
are the very structure this writer walks to LOCATE each opcode, read straight
from `buf`, so a v1 edit can never desync the offsets the parser would recompute.

Why this matters more than it did for frames (#278): frame records are
fixed-size (24 B), so no frame edit can shift a neighbour. Sequence opcodes are
VARIABLE-size (FRAME 3 B, LOOP 1 B, SET_OFFSET 5 B, ADD_OFFSET 3 B), so writing
an opcode's TYPE byte would re-length it and desync every following opcode AND
the offset table. Only one parameter lands on a type byte at all: a FRAME's
`frameset` index IS its opcode byte (values 0x00-0x7F). It is therefore masked
to 0x7F on write, so an out-of-range authored value degrades to a wrong-but-
structurally-valid frameset rather than silently re-encoding the opcode as
LOOP (0x81) / SET_OFFSET (0x82) / ADD_OFFSET (0x83). `SequenceChannel.gd`'s
Faithful advisory is what warns the author before it gets here.

Opcode completeness is settled: a section-bounded corpus audit (2026-08-18)
walked all 2428 sequences across all 401 non-empty effects in
`project-assets/fft-extract/EFFECT/` and found ZERO undocumented opcodes, zero
opcodes straddling a sequence bound, and zero non-zero unconsumed tail bytes.
The four opcodes below are exhaustive for the shipped corpus.

The walk below mirrors `parse_effect.parse_animation_sequence`'s termination
rules EXACTLY (LOOP ends a sequence; an all-zero FRAME ends a sequence; an
unrecognized byte ends a sequence), because opcode INDEX must mean the same
thing to the writer as it did to the parser that produced the model — the
`test_write_effect_animation` corpus round-trip is what holds those two in sync.
"""

from __future__ import annotations

import struct
from typing import Any, Dict, Iterator, List, Tuple

from parse_effect import read_u8, read_u16, read_u32

LOOP = 0x81
SET_OFFSET = 0x82
ADD_OFFSET = 0x83

# opcode byte -> (type name, size in bytes)
_SIZED_OPCODES = {
    LOOP: ("LOOP", 1),
    SET_OFFSET: ("SET_OFFSET", 5),
    ADD_OFFSET: ("ADD_OFFSET", 3),
}
_FRAME_SIZE = 3


def _write_u8(buf: bytearray, offset: int, value: int) -> None:
    buf[offset] = value & 0xFF


def _write_s16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<h", buf, offset, _as_s16(value))


def _as_s16(value: int) -> int:
    v = value & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def _iter_opcode_offsets(
    buf: bytes, animation_ptr: int, section_size: int
) -> Iterator[Tuple[int, int, int, str]]:
    """Yield (sequence_index, opcode_index, absolute_byte_offset, type_name) for
    every opcode the base bytes actually contain, walking the SAME count /
    offset-table / per-sequence discovery `parse_effect.parse_animations_section`
    does — so a writer using this always targets the exact bytes the parser read
    back. Read-only over `buf`: this walk never depends on the (possibly edited)
    `animations` block being written."""
    if section_size < 4:
        return
    seq_count = read_u32(buf, animation_ptr)
    if seq_count == 0 or seq_count > 256:
        return

    section_end = animation_ptr + section_size
    for seq_idx in range(seq_count):
        table_pos = animation_ptr + 4 + seq_idx * 2
        if table_pos + 2 > section_end:
            break
        seq_start = animation_ptr + 4 + read_u16(buf, table_pos)
        if seq_start >= len(buf):
            break

        # Safety limit mirrors parse_animation_sequence's own `offset + 1000`.
        max_pos = min(seq_start + 1000, len(buf))
        pos = seq_start
        op_idx = 0
        while pos < max_pos:
            opcode = read_u8(buf, pos)
            if opcode <= 0x7F:
                if pos + _FRAME_SIZE > max_pos:
                    break
                duration = read_u8(buf, pos + 1)
                depth_mode = read_u8(buf, pos + 2)
                yield seq_idx, op_idx, pos, "FRAME"
                op_idx += 1
                pos += _FRAME_SIZE
                # parse_animation_sequence treats an all-zero FRAME as terminal.
                if duration == 0 and opcode == 0 and depth_mode == 0:
                    break
            elif opcode in _SIZED_OPCODES:
                name, size = _SIZED_OPCODES[opcode]
                if pos + size > max_pos:
                    break
                yield seq_idx, op_idx, pos, name
                op_idx += 1
                pos += size
                if opcode == LOOP:
                    break
            else:
                # Unrecognized byte ends the sequence (parser parity). The corpus
                # audit found none of these, so this is a defensive path.
                break


def serialize_opcode(buf: bytearray, offset: int, op_type: str, op: Dict[str, Any]) -> None:
    """Write one opcode's editable PARAMETERS into `buf` at `offset`. The
    opcode's size and type are fixed by the base bytes and never rewritten —
    except a FRAME's index, which IS the type byte and is masked to 0x7F so it
    stays a FRAME (see the module docstring)."""
    if op_type == "FRAME":
        _write_u8(buf, offset, int(op.get("frameset", 0)) & 0x7F)
        _write_u8(buf, offset + 1, int(op.get("duration", 0)))
        _write_u8(buf, offset + 2, int(op.get("depth_mode", 0)))
    elif op_type == "SET_OFFSET":
        _write_s16(buf, offset + 1, int(op.get("x", 0)))
        _write_s16(buf, offset + 3, int(op.get("y", 0)))
    elif op_type == "ADD_OFFSET":
        _write_u8(buf, offset + 1, int(op.get("dx", 0)))
        _write_u8(buf, offset + 2, int(op.get("dy", 0)))
    # LOOP carries no parameters — nothing to write.


def patch_animation_into(
    buf: bytearray,
    animations: List[Dict[str, Any]],
    animation_ptr: int,
    section_size: int,
) -> None:
    """Partial-patch every opcode's parameters into `buf` IN PLACE from
    `animations` (the parsed, possibly edited sequence array — SAME shape
    `parse_animations_section` returns). Opcode offsets are located by walking
    the EXISTING (untouched) count / offset-table structure in `buf`, never from
    `animations` itself, so a v1 edit can only ever touch a real opcode's own
    parameter bytes.

    An `animations` shorter than the base (or a sequence's `opcodes` shorter
    than the base's) leaves the missing opcodes' bytes untouched rather than
    raising — the choke point (`EffectEditSession`) never removes entries in v1,
    so this is a defensive no-op path, not the expected case. An opcode whose
    model TYPE disagrees with the base bytes is skipped for the same reason:
    v1 cannot change a type, so a disagreement means a stale/foreign block, and
    writing it would corrupt the stream."""
    for seq_idx, op_idx, offset, op_type in _iter_opcode_offsets(
        buf, animation_ptr, section_size
    ):
        if seq_idx >= len(animations) or not isinstance(animations[seq_idx], dict):
            continue
        opcodes = animations[seq_idx].get("opcodes", [])
        if op_idx >= len(opcodes) or not isinstance(opcodes[op_idx], dict):
            continue
        op = opcodes[op_idx]
        if str(op.get("type", "")) != op_type:
            continue
        serialize_opcode(buf, offset, op_type, op)


def patch_animation_section(
    base_bytes: bytes,
    animations: List[Dict[str, Any]],
    animation_ptr: int,
    section_size: int,
) -> bytes:
    """Return a copy of `base_bytes` with every opcode's parameters
    re-serialized from `animations`. A thin copy wrapper over
    `patch_animation_into` (the in-place core), mirroring write_effect_frames."""
    buf = bytearray(base_bytes)
    patch_animation_into(buf, animations, animation_ptr, section_size)
    return bytes(buf)
