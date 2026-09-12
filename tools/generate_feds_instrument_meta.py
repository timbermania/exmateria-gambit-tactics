#!/usr/bin/env python3
"""Regenerate assets/feds_instrument_meta.json from the ROM waveset (WAVESET.WD).

The FEDS Instrument opcode (0xAC) picks a waveset sample by raw id; the SPU then
decides, on a held note, whether that sample SUSTAINS (loops a tail) or is a
ONE-SHOT — a property of the sample's ADPCM block-loop flags, not the opcode. The
studio wants to surface that on the instrument-chip click (ADR-0085 amendment).
This table carries the raw facts; FedsInstrumentMeta.gd humanizes them.

Keyed by raw 0xAC id. The runtime maps opcode id N → waveset entry N+1
(instrument.gd `_load_inst_into_channel(byte_val + 1, …)`), so this applies the
+1 internally: meta[id] describes waveset[id + 1].

Mirrors the ADPCM block-flag scan in
addons/exmateria_sound/runtime/waveset_parser.gd::_decode_adpcm (the code path the
game plays) — the two must agree. Paired drift guard:
tools/test_feds_instrument_meta_drift.py.

Run from the package root:  uv run python tools/generate_feds_instrument_meta.py
(needs project-assets/fft-extract/SOUND/WAVESET.WD — ROM-derived, gitignored.)
"""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE.parent / "assets" / "feds_instrument_meta.json"

BLOCK_SIZE = 16
FLAG_LOOP_END = 0x01
FLAG_LOOP_REPEAT = 0x02
FLAG_LOOP_START = 0x04


def _u16(data: bytes, off: int) -> int:
    return data[off] | (data[off + 1] << 8)


def _u32(data: bytes, off: int) -> int:
    return data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24)


def _scan_loop_flags(sample: bytes) -> dict:
    """Mirror waveset_parser._decode_adpcm's loop-flag walk over one sample's
    ADPCM blocks. Stops at the first LOOP_END block (as the SPU does)."""
    has_explicit_loop_start = False
    has_loop_repeat = False
    loop_offset_bytes = -1
    num_blocks = len(sample) // BLOCK_SIZE
    for block_idx in range(num_blocks):
        offset = block_idx * BLOCK_SIZE
        flags = sample[offset + 1]
        if flags & FLAG_LOOP_START:
            has_explicit_loop_start = True
            loop_offset_bytes = offset
        if flags & FLAG_LOOP_REPEAT:
            has_loop_repeat = True
        if flags & FLAG_LOOP_END:
            break
    return {
        "has_explicit_loop_start": has_explicit_loop_start,
        "has_loop_repeat": has_loop_repeat,
        "loop_offset_bytes": loop_offset_bytes,
    }


def parse_waveset(data: bytes) -> dict:
    """WAVESET.WD bytes → {opcode_id: {sample_size, has_loop_repeat,
    has_explicit_loop_start, loop_offset_bytes, is_null}}.

    Keyed by 0xAC opcode id = waveset entry index − 1. Waveset entry 0 is never
    addressable by any opcode (would be id −1) and is dropped. Returns {} when the
    blob is not a `dwds` waveset."""
    if len(data) < 0x20 or data[0:4] != b"dwds":
        return {}
    data_offset = _u32(data, 0x10)
    num_entries = (data_offset - 0x20) // 16

    out: dict[int, dict] = {}
    for idx in range(num_entries):
        opcode_id = idx - 1
        if opcode_id < 0:
            continue  # waveset[0] has no opcode
        ent_off = 0x20 + idx * 16
        sample_offset = _u32(data, ent_off)
        sample_size = _u16(data, ent_off + 4)
        if sample_offset == 0 and sample_size == 0:
            out[opcode_id] = {
                "sample_size": 0,
                "has_loop_repeat": False,
                "has_explicit_loop_start": False,
                "loop_offset_bytes": -1,
                "is_null": True,
            }
            continue
        adpcm_start = data_offset + sample_offset
        adpcm_end = min(adpcm_start + sample_size, len(data))
        flags = _scan_loop_flags(data[adpcm_start:adpcm_end])
        out[opcode_id] = {
            "sample_size": sample_size,
            "has_loop_repeat": flags["has_loop_repeat"],
            "has_explicit_loop_start": flags["has_explicit_loop_start"],
            "loop_offset_bytes": flags["loop_offset_bytes"],
            "is_null": False,
        }
    return out


def waveset_path() -> Path:
    return (HERE.parent.parent / "project-assets" / "fft-extract" / "SOUND" / "WAVESET.WD")


def render(meta: dict) -> str:
    return json.dumps({"meta": {str(k): meta[k] for k in sorted(meta)}}, indent=1) + "\n"


def main() -> None:
    path = waveset_path()
    if not path.exists():
        raise SystemExit(f"WAVESET.WD not found at {path} (ROM-derived, populate project-assets)")
    meta = parse_waveset(path.read_bytes())
    TARGET.write_text(render(meta))
    print(f"wrote {TARGET} ({len(meta)} instruments)")


if __name__ == "__main__":
    main()
