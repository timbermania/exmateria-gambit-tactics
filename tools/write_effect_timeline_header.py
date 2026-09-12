"""Byte-exact TIMELINE-HEADER writer for E###.BIN (#271).

The inverse of the header half of `parse_effect.parse_timeline`. Given the base
`E###.BIN` bytes, a parsed (possibly edited) timeline block (the dict with a
`header` map), and the header's `timeline_section_ptr`,
`patch_timeline_header_section` returns a NEW byte buffer in which ONLY the three
phase-duration u16s are rewritten:

    phase1_duration @ timeline_ptr + 0x04   (frames until for_each starts)
    spawn_delay     @ timeline_ptr + 0x06   (between-spawn delay, multi-target)
    phase2_delay    @ timeline_ptr + 0x0A   (for_each -> phase2 gap)

Every other byte is preserved verbatim — the engine-ignored header words
(0x00-0x03, 0x08-0x09), the particle channels, and the rest of the file — a
partial patch, mirroring `write_effect_particle_timeline`. The durations are a
positive frame count; `parse_timeline` reads them as s16, so writing the low 16
bits (`<H`, value & 0xFFFF) reproduces the stored bytes exactly for any value the
parser produced (round-trip byte-exact). The choke-point channel refuses values
past the positive slot before they reach here.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# The three duration offsets within the timeline header (shared with parse_timeline).
OFF_PHASE1_DURATION = 0x04
OFF_SPAWN_DELAY = 0x06
OFF_PHASE2_DELAY = 0x0A


def _write_u16(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<H", buf, offset, int(value) & 0xFFFF)


def patch_timeline_header_into(
    buf: bytearray, timeline: Dict[str, Any], timeline_ptr: int
) -> None:
    """Partial-patch the three phase durations of `buf` IN PLACE from `timeline`
    (the parsed, possibly edited timeline block). Reusable core shared by the
    standalone `patch_timeline_header_section` and any per-section serializer
    registry. Only the three duration bytes are overwritten; every other byte
    stays verbatim."""
    header = timeline.get("header", {})
    _write_u16(buf, timeline_ptr + OFF_PHASE1_DURATION, header["phase1_duration"])
    _write_u16(buf, timeline_ptr + OFF_SPAWN_DELAY, header["spawn_delay"])
    _write_u16(buf, timeline_ptr + OFF_PHASE2_DELAY, header["phase2_delay"])


def patch_timeline_header_section(
    base_bytes: bytes, timeline: Dict[str, Any], timeline_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the three phase durations rewritten from
    `timeline`. A thin copy wrapper over `patch_timeline_header_into`."""
    buf = bytearray(base_bytes)
    patch_timeline_header_into(buf, timeline, timeline_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's timeline durations from an edited timeline.json.

    Usage: write_effect_timeline_header.py <base.bin> <timeline.json> <header.json> <out.bin>
    `header.json` supplies `header.timeline_section_ptr`. Every non-duration byte
    is copied from <base.bin> verbatim.
    """
    ap = argparse.ArgumentParser(
        description="Patch an E###.BIN timeline-header durations from timeline.json")
    ap.add_argument("base_bin")
    ap.add_argument("timeline_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    timeline = json.loads(Path(args.timeline_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    timeline_ptr = int(header["header"]["timeline_section_ptr"])

    out = patch_timeline_header_section(base, timeline, timeline_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
