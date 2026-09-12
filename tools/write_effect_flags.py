"""Byte-exact EFFECT-FLAGS writer for E###.BIN (#272).

The inverse of the flags-byte half of `parse_effect.parse_effect_flags`. Given the
base `E###.BIN` bytes, a flags block (`{flags_byte: int}`, the parsed — possibly
edited — sub-tree), and the header's `effect_flags_ptr`,
`patch_effect_flags_section` returns a NEW byte buffer in which ONLY the single
flags byte is rewritten:

    flags_byte @ effect_flags_ptr + 0x00

Every other byte is preserved verbatim — the dead `spawn_delay_override` @0x04
(ADR-0092: provably never read), the 16 sound-channel bytes @0x08-0x17 (edited in
their own container view, not here), and the whole rest of the file — a partial
patch, mirroring `write_effect_timeline_header`.

The critical invariant (ADR-0092): the engine-ignored bits 0-2 and 7 ride along
untouched, because the whole byte is written from the raw `flags_byte` the author
seeded (from `set_pressed_no_signal` over the live word), not re-derived from the
four decoded bools. The choke-point channel keeps that raw word in sync as the
author toggles the four engine-read bits (3-6), so the low byte here is exactly
the byte to store (`& 0xFF` guards a stray high bit; the parser produced 0..255).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# The flags-byte offset within the effect_flags section (shared with parse_effect_flags).
OFF_FLAGS = 0x00


def patch_effect_flags_into(
    buf: bytearray, block: Dict[str, Any], effect_flags_ptr: int
) -> None:
    """Partial-patch the single flags byte of `buf` IN PLACE from `block` (the
    parsed, possibly edited effect_flags sub-tree — it carries `flags_byte`).
    Reusable core shared by the standalone `patch_effect_flags_section` and the
    per-section serializer registry. Only the one flags byte is overwritten; every
    other byte stays verbatim."""
    buf[effect_flags_ptr + OFF_FLAGS] = int(block["flags_byte"]) & 0xFF


def patch_effect_flags_section(
    base_bytes: bytes, block: Dict[str, Any], effect_flags_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the flags byte rewritten from `block`. A
    thin copy wrapper over `patch_effect_flags_into`."""
    buf = bytearray(base_bytes)
    patch_effect_flags_into(buf, block, effect_flags_ptr)
    return bytes(buf)


# --- game->json->bin CLI --------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's flags byte from an edited flags.json.

    Usage: write_effect_flags.py <base.bin> <flags.json> <header.json> <out.bin>
    `flags.json` supplies `flags_byte`; `header.json` supplies
    `header.effect_flags_ptr`. Every non-flags byte is copied from <base.bin>
    verbatim.
    """
    ap = argparse.ArgumentParser(
        description="Patch an E###.BIN flags byte from flags.json")
    ap.add_argument("base_bin")
    ap.add_argument("flags_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    block = json.loads(Path(args.flags_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    effect_flags_ptr = int(header["header"]["effect_flags_ptr"])

    out = patch_effect_flags_section(base, block, effect_flags_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
