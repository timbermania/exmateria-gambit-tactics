"""Parse the cinematic SEQ tables embedded in EVENT/EVTCHR.BIN.

Each EVTCHR segment (137 in total, 0x7800 B each) carries a 64-entry
cinematic-animation table at the START of the segment — the bytes
`parse_evtchr.py` ignored as "header / unused" before this decode landed.
The event-script opcode `0x58 Load EVTCHR` (handler at
`BATTLE.BIN:0x80145414`) queues a slot id; an async worker
(per-frame at `BATTLE.BIN:0x80143930`) reads it, fetches the segment from
disc, and copies the 64-entry table into RAM at either:

    Block 1 -> 0x800A77D8  (anim_id 0x01F4..0x0233)
    Block 2 -> 0x800AED3C  (anim_id 0x0258..0x0297)

The two RAM tables alias the SAME 64 cinematic anims at different anim_id
ranges, so the event script can choose which block to use without
re-loading. (Source: FFT wiki "EVTCHR Animations" table; the dispatcher
selects between Block 1 / Block 2 via the band check at
`BATTLE.BIN:0x800848C0`.)

Per-segment layout (offsets all repeat every 0x7800 B):
    +0x0000 .. +0x00FF   64 u32 LE anim_offset entries
                         (relative to the anim-data region @ +0x0100)
    +0x0100 .. +0x04FF   variable-length bytecode (FF FF / FF FE terminators)
    +0x0500 .. +0x059F   block pointers (frame-composition)
    +0x05A0 .. +0x077F   block data
    +0x0780 ..           palettes + image (`parse_evtchr.py` covers this)

Authority for the segment offset table: `EVTCHR Frame Editor v1.1` by
Xifanie (the "EVTCHR Addresses" sheet of the bundled .xlsm).

Output shape (`cinematic_seq.json`):
    {
        "0": {"0": [<opcode dict>, ...], "1": [...], ..., "63": [...]},
        "1": {...},
        ...
        "136": {...}
    }

Each opcode dict mirrors the per-instruction shape of `parse_seq.py`'s
output so the Godot side can re-use the same walker.

Usage:
    uv run python tools/parse_cinematic_seq.py            # write JSON
    uv run python tools/parse_cinematic_seq.py --segment 0  # print seg 0
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import parse_seq  # opcode definitions live there — single source of truth
from _repo_paths import event_dir, assets_dir


NUM_SEGMENTS = 137
SEGMENT_SIZE = 0x7800

ANIM_PTR_TABLE_OFF = 0x0000
ANIMS_PER_SEGMENT = 64
ANIM_PTR_TABLE_LEN = ANIMS_PER_SEGMENT * 4   # 0x100

ANIM_DATA_OFF = 0x0100
ANIM_DATA_LEN = 0x0400                       # ends at 0x500

DEFAULT_EVTCHR_PATH = event_dir() / "EVTCHR.BIN"
DEFAULT_OUTPUT_PATH = (
    assets_dir("sprites/animations") / "cinematic_seq.json"
)


def decode_bytecode(buf: bytes, seq_no: int) -> list[dict]:
    """Decode one cinematic anim's bytecode into the per-instruction shape
    used by `parse_seq.py`'s SEQ output.

    Bytecode format (identical to TYPE1.SEQ etc., authored against the same
    walker):
        - first byte != 0xFF: a `LoadFrameWait` -> [frame_id, wait_ticks]
        - first byte == 0xFF: a parametric opcode encoded as 0xFFxx, with
          parameter count from `opcodeParameters.txt`. The cinematic
          terminators we see in EVTCHR are `0xFFFF` (PauseAnimation, holds
          the last frame) and `0xFFFE` (EndAnimation, full stop).

    Mirrors `parse_seq.SEQParser._parse_sequence` deliberately — a future
    consolidation could share the routine, but keeping it explicit here
    documents which subset of the opcode table is in scope for cinematic
    bytecode (no animation-walker-only opcodes like MoveUp2 appear).
    """
    opcode_defs = parse_seq.load_opcode_definitions()
    instructions: list[dict] = []
    pos = 0
    instruction_num = 0
    while pos < len(buf):
        b0 = buf[pos]
        if b0 == 0xFF:
            if pos + 1 >= len(buf):
                break
            b1 = buf[pos + 1]
            opcode = 0xFF00 | b1
            info = opcode_defs.get(opcode, {"name": f"ff{b1:02x}", "params": 0})
            params: list[int] = []
            for i in range(info["params"]):
                params.append(buf[pos + 2 + i] if pos + 2 + i < len(buf) else 0)
            instructions.append({
                "seq_no": seq_no,
                "op_code_hex": f"0x{opcode:04X}",
                "op_code_param_0": params[0] if len(params) > 0 else None,
                "op_code_param_1": params[1] if len(params) > 1 else None,
                "op_code_param_2": params[2] if len(params) > 2 else None,
                "op_code_name": info["name"],
                "instruction_num": instruction_num,
            })
            pos += 2 + info["params"]
            instruction_num += 1
            if opcode in (0xFFFE, 0xFFFF):
                break
        else:
            if pos + 1 >= len(buf):
                break
            instructions.append({
                "seq_no": seq_no,
                "op_code_hex": None,
                "op_code_param_0": b0,
                "op_code_param_1": buf[pos + 1],
                "op_code_param_2": None,
                "op_code_name": "LoadFrameWait",
                "instruction_num": instruction_num,
            })
            pos += 2
            instruction_num += 1
    return instructions


def _parse_segment(buf: bytes, seg_id: int) -> dict[int, list[dict]]:
    """Walk the 64 anim pointers and decode each one's bytecode.

    Returns: {anim_idx: [<opcode dict>, ...]} for anim_idx in 0..63.
    """
    out: dict[int, list[dict]] = {}
    ptrs = list(struct.unpack_from(
        f"<{ANIMS_PER_SEGMENT}I", buf, ANIM_PTR_TABLE_OFF
    ))
    # An anim's data runs from its pointer up to the next anim's pointer in the
    # data region. Unused slots carry pointer 0, so we must NOT bound by
    # ptrs[anim_idx + 1] directly: a real anim immediately followed by an unused
    # (0) slot would get end=0 and be wrongly dropped. This is exactly the bug
    # that lost segment 0 local 18 (the female-knight walk-in, anim 0x26A) —
    # local 19's pointer is 0 — and the last used anim of every segment whose
    # successor slot is zero. Bound instead by the smallest pointer strictly
    # greater than `start`; if none exists the anim runs to the end of the data
    # region. decode_bytecode stops at the FFFE/FFFF terminator regardless, so
    # the wider bound never over-reads a well-formed anim.
    for anim_idx in range(ANIMS_PER_SEGMENT):
        start = ptrs[anim_idx]
        # Pointer 0 marks an unused slot for every anim except anim 0, whose
        # data legitimately begins at data-region offset 0.
        if start == 0 and anim_idx != 0:
            out[anim_idx] = []
            continue
        if not (0 <= start < ANIM_DATA_LEN):
            out[anim_idx] = []
            continue
        later = [p for p in ptrs if p > start]
        end = min(later) if later else ANIM_DATA_LEN
        bc = buf[ANIM_DATA_OFF + start : ANIM_DATA_OFF + end]
        out[anim_idx] = decode_bytecode(bc, seq_no=seg_id * ANIMS_PER_SEGMENT + anim_idx)
    return out


def parse_cinematic_seq(path: str | Path) -> dict[int, dict[int, list[dict]]]:
    """Parse the entire EVTCHR.BIN into a per-segment cinematic SEQ table.

    Returns: {seg_id: {anim_idx: [opcode dict, ...]}} for seg_id in 0..136,
    anim_idx in 0..63.
    """
    data = Path(path).read_bytes()
    expected = NUM_SEGMENTS * SEGMENT_SIZE
    if len(data) != expected:
        raise ValueError(
            f"EVTCHR.BIN size mismatch: got {len(data)}, expected {expected}"
        )
    out: dict[int, dict[int, list[dict]]] = {}
    for seg_id in range(NUM_SEGMENTS):
        base = seg_id * SEGMENT_SIZE
        out[seg_id] = _parse_segment(data[base : base + SEGMENT_SIZE], seg_id)
    return out


def _to_json_keys(table: dict[int, dict[int, list[dict]]]) -> dict:
    """Stringify the integer keys for stable JSON output (matches the
    convention `type1_seq.json` uses for anim_id keys)."""
    return {
        str(seg_id): {str(anim_idx): anims for anim_idx, anims in segs.items()}
        for seg_id, segs in table.items()
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--input", type=Path, default=DEFAULT_EVTCHR_PATH)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    ap.add_argument(
        "--segment", type=int, default=None,
        help="Pretty-print one segment's decoded anims and exit (no write).",
    )
    args = ap.parse_args()

    table = parse_cinematic_seq(args.input)
    if args.segment is not None:
        seg = table[args.segment]
        for anim_idx in sorted(seg):
            print(f"anim {anim_idx}:")
            for ins in seg[anim_idx]:
                print(f"  {ins}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(_to_json_keys(table), f, indent=2)
    n_anims = sum(len(s) for s in table.values())
    print(
        f"Wrote {args.output} "
        f"({NUM_SEGMENTS} segments x {ANIMS_PER_SEGMENT} anims = {n_anims})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
