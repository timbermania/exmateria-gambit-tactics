"""Parse the per-segment Frame Pointers + Block Data of EVENT/EVTCHR.BIN.

Each EVTCHR segment (137 in total, 0x7800 B each) carries a 40-entry
Frame Pointer table at +0x500..+0x59F and the Block Data those pointers
reference at +0x5A0..+0x77F. A cinematic anim's bytecode
(`LoadFrameWait(frame_id, ticks)` — see `parse_cinematic_seq.py`) names a
frame by its raw script byte; the runtime resolves the byte to a list of
blocks (sub-rectangles cut from the segment's 256x200 4bpp pixel page) via:

    block_frame_idx = frame_id - 0xD2        (valid range 0xD2..0xF9 → 0..39)
    block_ptr       = LE32 @ +0x500 + idx*4  (offset into Block Data)
    header @ +0x5A0 + block_ptr              (count_minus_1 u8, pad u8)
    N × 4-byte block descriptors             (identical bit layout to
                                              TYPE1 SHP tiles)

The runtime frame byte sits +7 above the disc-side index (live BP at
`0x80085198` confirmed `displayed_frame = *(short *)(anim_state + 0x14) +
script_byte`; for chapel that offset is 0, so the runtime byte IS the
script byte, but the disc Block-Pointer table is authored for indices
`0xCB..0xF2` — disc index 0 = runtime byte 0xD2). We re-key on the
runtime byte here so consumers (Godot's `load_cinematic_frame`) look up
by the same byte that the bytecode emits.

Per-block descriptor — **same encoding `parse_shp.py` uses**:

    Byte 0    : shift_x        (signed int8, screen-X offset in px)
    Byte 1    : shift_y        (signed int8, screen-Y offset in px)
    Bytes 2-3 : flags          (little-endian u16):
                  bits  0..4  : src tile_x  (×8 → src_x in px)
                  bits  5..9  : src tile_y  (×8 → src_y in px)
                  bits 10..13 : size_index  (lookup in `parse_shp.SIZES`)
                  bit  14     : flip_x
                  bit  15     : flip_y

Output JSON (`evtchr_frames.json`) mirrors `type1_shp.json`'s shape so the
Godot runtime can reuse the existing SHP-tile renderer — the only change
is the outer dict, which keys on segment id first, then frame id:

    {
      "0": {                               # segment 0
        "224": [                           # runtime byte 0xE0 (kneel pose,
                                           # = disc index 7, the same block
                                           # data formerly keyed as 0xD9)
          {
            "rectangle_x": 0,
            "rectangle_y": 80,
            "rectangle_width": 32,
            "rectangle_height": 40,
            "location_x": -17,
            "location_y": -35,
            "rotation": 0.0,
            "revert": false,
            "invert": false
          }
        ],
        ...
      },
      ...
    }

Authority for the per-segment region offsets: `EVTCHR Frame Editor v1.1`
by Xifanie (bundled .xlsm — "EVTCHR Addresses" + "EVTCHR Frames" sheets).
Authority for the block-descriptor bit layout: `parse_shp.py`'s docstring
(the EVTCHR descriptor uses the TYPE1 SHP encoding verbatim).

Usage:
    uv run python tools/parse_evtchr_frames.py            # write JSON
    uv run python tools/parse_evtchr_frames.py --segment 0  # print seg 0
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from _repo_paths import event_dir, assets_dir
from parse_shp import SIZES


NUM_SEGMENTS = 137
SEGMENT_SIZE = 0x7800

FRAME_PTR_TABLE_OFF = 0x0500
FRAMES_PER_SEGMENT = 40
FRAME_PTR_TABLE_LEN = FRAMES_PER_SEGMENT * 4   # 0xA0
BLOCK_DATA_OFF = 0x05A0
BLOCK_DATA_LEN = 0x01E0                         # ends at 0x780

# Runtime frame byte → block-frame-idx base. The cinematic dispatcher
# (`FUN_80083f18` at `0x80083FC8`) routes frame_byte ≥ 0xD2 to the EVTCHR
# atlas; subtracting 0xD2 gives the 40-entry pointer index into the disc
# Block-Pointer table (which is itself authored for raw indices 0..39 —
# disc Xifanie tooling calls these 0xCB..0xF2, +7 below the runtime byte).
# Authority: live BP at `0x80085198` + the disc-to-runtime +7 shift verified
# by re-rendering disc index 7 and matching runtime byte 0xD9 (now keyed
# 0xE0 here). See `cinematic_frame_offset_decode.md` for the full trace.
FRAME_ID_BASE = 0xD2

DEFAULT_EVTCHR_PATH = event_dir() / "EVTCHR.BIN"
DEFAULT_OUTPUT_PATH = (
    assets_dir("sprites/animations") / "evtchr_frames.json"
)


def decode_block(desc: bytes) -> dict:
    """Decode a 4-byte EVTCHR block descriptor to a TYPE1-SHP-shaped tile dict.

    The encoding is identical to `parse_shp.parse_tile` but without the
    sprite-sheet `y_offset` (EVTCHR's pixel page is a single 256x200 image,
    not a stacked TYPE1.SPR sheet) and without per-frame rotation (cinematic
    block lists don't carry the per-frame rotation byte that TYPE1 frames do).
    """
    shift_x = struct.unpack("b", bytes([desc[0]]))[0]
    shift_y = struct.unpack("b", bytes([desc[1]]))[0]
    flags = desc[2] | (desc[3] << 8)

    tile_x = (flags & 0x1F) * 8
    tile_y = ((flags >> 5) & 0x1F) * 8
    size_index = (flags >> 10) & 0xF
    flip_x = bool(flags & 0x4000)
    flip_y = bool(flags & 0x8000)

    width, height = SIZES[size_index] if size_index < len(SIZES) else (8, 8)

    return {
        "rectangle_x": tile_x,
        "rectangle_y": tile_y,
        "rectangle_width": width,
        "rectangle_height": height,
        "location_x": shift_x,
        "location_y": shift_y,
        "rotation": 0.0,
        "revert": flip_x,
        "invert": flip_y,
    }


def decode_frame_block_list(buf: bytes, block_ptr: int) -> list[dict]:
    """Walk one frame's block list at `block_ptr` (offset into Block Data).

    Header is `count_minus_1` u8 followed by a u8 pad (always 0 in segment 0).
    Returns an empty list if the pointer is out of range or count overflows.
    """
    if not (0 <= block_ptr < BLOCK_DATA_LEN):
        return []
    header_off = BLOCK_DATA_OFF + block_ptr
    if header_off + 2 > BLOCK_DATA_OFF + BLOCK_DATA_LEN:
        return []
    count = buf[header_off] + 1
    # Each descriptor is 4 B; the first lives at header_off + 2.
    out: list[dict] = []
    for i in range(count):
        off = header_off + 2 + i * 4
        if off + 4 > BLOCK_DATA_OFF + BLOCK_DATA_LEN:
            break
        out.append(decode_block(buf[off : off + 4]))
    return out


def _parse_segment(buf: bytes) -> dict[int, list[dict]]:
    """Decode all 40 frames in one segment.

    Returns: {frame_id (runtime script byte): [block dict, ...]}. Frame
    ids span 0xD2..0xF9 inclusive.
    """
    out: dict[int, list[dict]] = {}
    ptrs = list(struct.unpack_from(
        f"<{FRAMES_PER_SEGMENT}I", buf, FRAME_PTR_TABLE_OFF
    ))
    for idx in range(FRAMES_PER_SEGMENT):
        frame_id = FRAME_ID_BASE + idx
        out[frame_id] = decode_frame_block_list(buf, ptrs[idx])
    return out


def parse_evtchr_frames(path: str | Path) -> dict[int, dict[int, list[dict]]]:
    """Parse the entire EVTCHR.BIN into per-segment frame tables.

    Returns: {seg_id: {frame_id: [block dict, ...]}} for seg_id in 0..136,
    frame_id in 0xD2..0xF9 (runtime bytecode bytes).
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
        out[seg_id] = _parse_segment(data[base : base + SEGMENT_SIZE])
    return out


def _to_json_keys(table: dict[int, dict[int, list[dict]]]) -> dict:
    """Stringify the integer keys for stable JSON output (matches the
    convention `type1_shp.json` uses for frame_id keys)."""
    return {
        str(seg_id): {str(frame_id): blocks for frame_id, blocks in segs.items()}
        for seg_id, segs in table.items()
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--input", type=Path, default=DEFAULT_EVTCHR_PATH)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    ap.add_argument(
        "--segment", type=int, default=None,
        help="Pretty-print one segment's decoded frames and exit (no write).",
    )
    args = ap.parse_args()

    table = parse_evtchr_frames(args.input)
    if args.segment is not None:
        seg = table[args.segment]
        for frame_id in sorted(seg):
            blocks = seg[frame_id]
            print(f"frame 0x{frame_id:02X} ({len(blocks)} block(s)):")
            for b in blocks:
                print(f"  {b}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(_to_json_keys(table), f, indent=2)
    n_blocks = sum(
        len(blocks) for seg in table.values() for blocks in seg.values()
    )
    print(
        f"Wrote {args.output} "
        f"({NUM_SEGMENTS} segments x {FRAMES_PER_SEGMENT} frames; "
        f"{n_blocks} blocks total)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
