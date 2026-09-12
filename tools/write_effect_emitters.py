"""Byte-exact EMITTER-block writer for E###.BIN (ADR-0089, slice 4).

The inverse of `parse_effect.parse_all_emitters`. Given the base `E###.BIN`
bytes, the parsed (possibly edited) emitter list, and the header's
`effect_data_ptr`, `patch_emitters_section` returns a NEW buffer in which each
196-byte emitter record's KNOWN fields are re-serialized from their raw values.

A partial patch at two grains:
  * Per DICT KEY — a key absent from an emitter dict leaves its bytes untouched
    (the saver may emit sparse dicts; older emitters.json may lack newer keys).
  * Per BYTE — bytes the parser does not surface are never written: unknown_12/13,
    the unparsed halves at 0x4D/0x50-0x53, the 0x11 high nibble (nibble-patched),
    and reserved_C2/C3. Reserved-but-parsed bytes (byte_00 / byte_05) round-trip
    through their keys.

Record math (effect_data_ptr + particle header + index stride) and sizes are
imported from `parse_effect` so reader and writer share ONE ROM layout.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from parse_effect import EMITTER_SIZE, PARTICLE_HEADER_SIZE

# --- field tables (offsets within one 196-byte record; mirror parse_emitter) ---

# Top-level u8 keys.
_U8_FIELDS = {
    "byte_00": 0x00, "anim_index": 0x01, "motion_type_flag": 0x02,
    "animation_target_flag": 0x03, "anim_param": 0x04, "byte_05": 0x05,
    "emitter_flags_lo": 0x06, "emitter_flags_hi": 0x07,
    "child_emitter_on_death": 0xC0, "child_emitter_mid_life": 0xC1,
}

# `raw` sub-dict: s16 vec3 triplets — key -> [x, y, z] offsets. Contiguous for the
# position-family; min/max interleaved per component for accel/drag.
_RAW_VEC3 = {
    "position_start": (0x14, 0x16, 0x18), "position_end": (0x1A, 0x1C, 0x1E),
    "spread_start": (0x20, 0x22, 0x24), "spread_end": (0x26, 0x28, 0x2A),
    "angle_start": (0x2C, 0x2E, 0x30), "angle_end": (0x32, 0x34, 0x36),
    "vel_spread_start": (0x38, 0x3A, 0x3C), "vel_spread_end": (0x3E, 0x40, 0x42),
    "accel_min_start": (0x64, 0x68, 0x6C), "accel_max_start": (0x66, 0x6A, 0x6E),
    "accel_min_end": (0x70, 0x74, 0x78), "accel_max_end": (0x72, 0x76, 0x7A),
    "drag_min_start": (0x7C, 0x80, 0x84), "drag_max_start": (0x7E, 0x82, 0x86),
    "drag_min_end": (0x88, 0x8C, 0x90), "drag_max_end": (0x8A, 0x8E, 0x92),
    "target_start": (0x9C, 0x9E, 0xA0), "target_end": (0xA2, 0xA4, 0xA6),
}

# `raw` sub-dict: s16 scalars.
_RAW_S16 = {
    "radial_min_start": 0x5C, "radial_max_start": 0x5E,
    "radial_min_end": 0x60, "radial_max_end": 0x62,
    "homing_min_start": 0xB8, "homing_max_start": 0xBA,
    "homing_min_end": 0xBC, "homing_max_end": 0xBE,
}

# Named sub-dicts whose values ARE the raw bytes: (dict key, value key) -> (offset, fmt).
_DICT_FIELDS = {
    ("inertia", "min_start"): (0x44, "<h"), ("inertia", "max_start"): (0x46, "<h"),
    ("inertia", "min_end"): (0x48, "<h"), ("inertia", "max_end"): (0x4A, "<h"),
    ("weight", "min_start"): (0x54, "<h"), ("weight", "max_start"): (0x56, "<h"),
    ("weight", "min_end"): (0x58, "<h"), ("weight", "max_end"): (0x5A, "<h"),
    ("lifetime", "min_start"): (0x94, "<H"), ("lifetime", "max_start"): (0x96, "<H"),
    ("lifetime", "min_end"): (0x98, "<H"), ("lifetime", "max_end"): (0x9A, "<H"),
    ("spawn", "particle_count_start"): (0xB0, "<H"), ("spawn", "particle_count_end"): (0xB2, "<H"),
    ("spawn", "interval_start"): (0xB4, "<H"), ("spawn", "interval_end"): (0xB6, "<H"),
    ("callback_params", "param_4C"): (0x4C, "u8"), ("callback_params", "param_4E"): (0x4E, "u8"),
    ("callback_params", "param_A8"): (0xA8, "<h"), ("callback_params", "param_AA"): (0xAA, "<h"),
    ("callback_params", "param_AC"): (0xAC, "<h"), ("callback_params", "param_AE"): (0xAE, "<h"),
}


def emitter_offset(effect_data_ptr: int, index: int) -> int:
    """The record base of emitter `index` (mirror parse_all_emitters)."""
    return effect_data_ptr + PARTICLE_HEADER_SIZE + index * EMITTER_SIZE


def _write(buf: bytearray, offset: int, fmt: str, value: Any) -> None:
    """Write one field's bytes. 16-bit fields are masked and written unsigned —
    signedness is interpretation, not bytes — so both encodings of the same
    halfword round-trip (e.g. lifetime 0xFFFF parses as 65535 from the current
    u16 reader but as the -1 animation-driven sentinel in older emitters.json)."""
    v = int(value)
    if fmt == "u8":
        buf[offset] = v & 0xFF
    else:
        struct.pack_into("<H", buf, offset, v & 0xFFFF)


def serialize_emitter_into(buf: bytearray, base: int, em: Dict[str, Any]) -> None:
    """Partial-patch ONE emitter record at `base` from the keys present in `em`."""
    for key, off in _U8_FIELDS.items():
        if key in em:
            _write(buf, base + off, "u8", em[key])

    ci = em.get("curve_indices_raw")
    if ci:
        for i, b in enumerate(ci[:8]):
            _write(buf, base + 0x08 + i, "u8", b)

    cc = em.get("color_curves")
    if cc is not None:
        # Nibble-patch: r/g pack byte 0x10; b is the LOW nibble of 0x11 (the high
        # nibble is unparsed — preserved from the base).
        if "r" in cc or "g" in cc:
            cur = buf[base + 0x10]
            r = int(cc.get("r", cur & 0x0F)) & 0x0F
            g = int(cc.get("g", (cur >> 4) & 0x0F)) & 0x0F
            buf[base + 0x10] = r | (g << 4)
        if "b" in cc:
            buf[base + 0x11] = (buf[base + 0x11] & 0xF0) | (int(cc["b"]) & 0x0F)

    raw = em.get("raw", {})
    for key, offs in _RAW_VEC3.items():
        if key in raw:
            vec = raw[key]
            for comp in range(3):
                _write(buf, base + offs[comp], "<h", vec[comp])
    for key, off in _RAW_S16.items():
        if key in raw:
            _write(buf, base + off, "<h", raw[key])

    for (dict_key, value_key), (off, fmt) in _DICT_FIELDS.items():
        sub = em.get(dict_key)
        if sub is not None and value_key in sub:
            _write(buf, base + off, fmt, sub[value_key])


def patch_emitters_into(buf: bytearray, emitters: List[Dict[str, Any]], effect_data_ptr: int) -> None:
    """Partial-patch every emitter record IN PLACE. Records are addressed by each
    dict's `index` (the same stride math as parse_all_emitters), so a sparse edit
    set may name any subset of emitters."""
    for em in emitters:
        serialize_emitter_into(buf, emitter_offset(effect_data_ptr, int(em["index"])), em)


def patch_emitters_section(
    base_bytes: bytes, emitters: List[Dict[str, Any]], effect_data_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the emitter records re-serialized from
    `emitters`. A thin copy wrapper over `patch_emitters_into` (the in-place core)."""
    buf = bytearray(base_bytes)
    patch_emitters_into(buf, emitters, effect_data_ptr)
    return bytes(buf)


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: patch a base E###.BIN's emitter block from an edited emitters.json.

    Usage: write_effect_emitters.py <base.bin> <emitters.json> <header.json> <out.bin>
    `header.json` supplies `header.effect_data_ptr`. Every byte outside the known
    emitter fields is copied from <base.bin> verbatim (a partial patch). The Studio
    layers this on top of the other section writers' output BIN.
    """
    ap = argparse.ArgumentParser(description="Patch an E###.BIN emitter block from emitters.json")
    ap.add_argument("base_bin")
    ap.add_argument("emitters_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    emitters = json.loads(Path(args.emitters_json).read_text())
    header = json.loads(Path(args.header_json).read_text())
    effect_data_ptr = int(header["header"]["effect_data_ptr"])

    out = patch_emitters_section(base, emitters, effect_data_ptr)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
