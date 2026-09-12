"""Byte-exact TIME-SCALE writer for E###.BIN (#270).

The inverse of `parse_effect.parse_time_scale`'s two curve regions. Given the
base `E###.BIN` bytes, a time_scale block (`{outer_phases: [600 ints],
for_each: [600 ints]}`, the parsed — possibly edited — sub-tree), and the
header's `time_scale_ptr`, `patch_time_scale_section` returns a NEW byte buffer
in which ONLY the two 300-byte nibble-packed regions are rewritten:

    outer_phases ("Phase 1 pacing") @ time_scale_ptr + 0x000
    for_each     ("For-each pacing") @ time_scale_ptr + 0x12C  (300)

Each region packs 600 values into 300 bytes, two per byte: even frame in the low
nibble, odd frame in the high nibble (the inverse of the parser's `unpack_region`).
Every other byte is preserved verbatim — the effect_flags byte that physically
carries the two enable bits (5/6) is edited in its own `effect_flags` channel,
NOT here — a partial patch, mirroring `write_effect_flags`.

The pacing values are the raw 0..15 nibble alphabet (the corpus uses only 2..10);
`& 0x0F` guards a stray high bit so a value never spills into its neighbour's
nibble.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Region layout within the time_scale section (shared with parse_time_scale).
REGION_FRAMES = 600
REGION_BYTES = REGION_FRAMES // 2  # 300 (2 nibbles/byte)
OFF_OUTER = 0x000
OFF_FOR_EACH = REGION_BYTES  # 0x12C


def _pack_region_into(buf: bytearray, region_start: int, values: List[int]) -> None:
    """Nibble-pack `values` (600 ints) into 300 bytes at `region_start`: even
    frame -> low nibble, odd frame -> high nibble. Both nibbles of each byte are
    written, so the region is fully overwritten (no read-modify needed)."""
    for frame in range(REGION_FRAMES):
        v = int(values[frame]) & 0x0F
        byte_offset = region_start + frame // 2
        if (frame & 1) == 0:
            buf[byte_offset] = (buf[byte_offset] & 0xF0) | v
        else:
            buf[byte_offset] = (buf[byte_offset] & 0x0F) | (v << 4)


def patch_time_scale_into(
    buf: bytearray, block: Dict[str, Any], time_scale_ptr: int
) -> None:
    """Partial-patch the two curve regions of `buf` IN PLACE from `block` (the
    parsed, possibly edited time_scale sub-tree — `outer_phases` + `for_each`).
    Reusable core shared by the standalone `patch_time_scale_section` and the
    per-section serializer registry. Only the two 300-byte regions are
    overwritten; every other byte stays verbatim."""
    _pack_region_into(buf, time_scale_ptr + OFF_OUTER, block["outer_phases"])
    _pack_region_into(buf, time_scale_ptr + OFF_FOR_EACH, block["for_each"])


def patch_time_scale_section(
    base_bytes: bytes, block: Dict[str, Any], time_scale_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the two pacing regions rewritten from
    `block`. A thin copy wrapper over `patch_time_scale_into`."""
    buf = bytearray(base_bytes)
    patch_time_scale_into(buf, block, time_scale_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's pacing curves from an edited time_scale.json.

    Usage: write_effect_time_scale.py <base.bin> <time_scale.json> <header.json> <out.bin>
    `time_scale.json` supplies `outer_phases`/`for_each`; `header.json` supplies
    `header.time_scale_ptr`. Every non-curve byte is copied from <base.bin>
    verbatim.
    """
    ap = argparse.ArgumentParser(
        description="Patch an E###.BIN pacing curves from time_scale.json")
    ap.add_argument("base_bin")
    ap.add_argument("time_scale_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    block = json.loads(Path(args.time_scale_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    time_scale_ptr = int(header["header"]["time_scale_ptr"])

    out = patch_time_scale_section(base, block, time_scale_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
