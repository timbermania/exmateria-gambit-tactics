"""Byte-exact EFFECT-SCRIPT pattern-swap writer for E###.BIN (#273, ADR-0094).

The Effect Studio surfaces an effect's *script pattern* — `3-phase`
(phase-1 + for-each + phase-2; opcode 41 outer + opcode 40 for-each) or
`1-phase` (for-each only; opcode 40) — and lets the author **swap** it. Unlike
the fixed-size flags / timeline-header patchers, a swap **resizes** the script
section (header offset 0x08), so every downstream section shifts.

A swap is a *structure-preserving, variable-length section rewrite* (ADR-0094):

1. **Preserve the real prologue verbatim.** Every script opens with a per-effect
   prologue: `set_texture_page` (its flags byte is the texture page, never 0),
   then 0-4 `load_callback` registrations, then — on 1-phase only — a
   `clear_timeline_a` marker, then `init_physics_params`. `parse_prologue` reads
   `(texture_page, callbacks[])` out of it; a swap keeps them and regenerates
   only the control-flow body.
2. **Regenerate the canonical body.** `regenerate_section` synthesizes the whole
   canonical section (root + for-each child + trailing pad) from
   `(pattern, texture_page, callbacks)`. The bodies are derived from real effects
   (E001 3-phase incl. child; E043 1-phase incl. `clear_timeline_a`), NOT the
   lossy Lua templates. Branch offsets are absolute-within-section and shift with
   the callback count; the section is padded up to a 4-byte multiple.
3. **Strict-canonical + DATA gate.** `regenerate_section(detect, *prologue) == sec`
   IS the canonical definition, so `is_swappable` offers the swap only when the
   effect regenerates its own section byte-exactly AND the file is DATA-format.
   Everything else (Custom, CODE-format, the 2 non-canonical 1-phase outliers)
   is read-only.
4. **Save = regenerate + splice + tail-shift + header fix-up.** `swap_effect_script`
   splices the new section in, shifts the entire tail by `delta = new - old`, and
   adds `delta` to the eight downstream header pointers (0x0C-0x24), skipping any
   that are 0 (e.g. an absent `time_scale_ptr`). Sections are located ONLY through
   the 40-byte header (no interior absolute cross-section pointers exist), so this
   is sufficient — no interior relocation needed.

The round-trip is then provably lossless and reversible. `test_write_effect_script`
pins it on the real BINs E001/E019 (3-phase) and E043 (1-phase).
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import parse_effect as pe

# Opcode ids (shared vocabulary with parse_effect.OPCODES / the runtime).
OP_GOTO_YIELD = 0
OP_END = 4
OP_SET_TEXTURE_PAGE = 5
OP_LOAD_CALLBACK = 6
OP_BRANCH_COUNT_EQ = 22
OP_BRANCH_ANIM_DONE = 29
OP_BRANCH_ANIM_DONE_COMPLEX = 30
OP_BRANCH_TARGET_TYPE = 31
OP_UPDATE_ALL_PARTICLES = 37
OP_INIT_PHYSICS_PARAMS = 39
OP_FOR_EACH = 40
OP_PROCESS_TIMELINE_FRAME = 41
OP_CLEAR_TIMELINE_A = 42

# Instruction byte sizes, sourced from parse_effect (single source of truth).
_OPSIZE = {oid: size for oid, (_name, size) in pe.OPCODES.items()}

PATTERN_3PHASE = "3-phase"
PATTERN_1PHASE = "1-phase"
PATTERN_CUSTOM = "Custom"

# Downstream header pointers that shift when the script section resizes: every
# pointer strictly after script_ptr (0x08). frames/animation/script (0x00-0x08)
# sit at or before the section and never move.
_DOWNSTREAM_PTR_OFFSETS = (0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24)


# --- low-level emission -------------------------------------------------------


def _w16(value: int) -> bytes:
    return struct.pack("<H", value & 0xFFFF)


def _opword(opcode: int, flags: int = 0) -> bytes:
    """A script instruction word: opcode in bits 0-8, flags in bits 9-15."""
    return _w16(opcode + (flags << 9))


# --- canonical bodies (label-relative; offsets resolved at emit time) ---------
#
# Each entry is (label, opcode, [args]) where an arg is either a literal int or a
# label name (resolved to its absolute-within-section offset). This mirrors the
# real E001 (3-phase root+child) and E043 (1-phase) byte layouts exactly.

_BODY_1PHASE = [
    ("btt", OP_BRANCH_TARGET_TYPE, ["end"]),
    ("bad", OP_BRANCH_ANIM_DONE, ["wait"]),
    ("fe", OP_FOR_EACH, []),
    ("up1", OP_UPDATE_ALL_PARTICLES, []),
    ("gy1", OP_GOTO_YIELD, ["bad"]),
    ("wait", OP_UPDATE_ALL_PARTICLES, []),
    ("bce", OP_BRANCH_COUNT_EQ, [0, "end"]),
    ("gy2", OP_GOTO_YIELD, ["wait"]),
    ("end", OP_END, []),
]

_BODY_3PHASE = [
    # ROOT
    ("btt", OP_BRANCH_TARGET_TYPE, ["endroot"]),
    ("bad", OP_BRANCH_ANIM_DONE_COMPLEX, ["wait"]),
    ("ptf", OP_PROCESS_TIMELINE_FRAME, ["child"]),
    ("up1", OP_UPDATE_ALL_PARTICLES, []),
    ("gy1", OP_GOTO_YIELD, ["bad"]),
    ("wait", OP_UPDATE_ALL_PARTICLES, []),
    ("bce", OP_BRANCH_COUNT_EQ, [0, "endroot"]),
    ("gy2", OP_GOTO_YIELD, ["wait"]),
    ("endroot", OP_END, []),
    # FOR-EACH CHILD (structurally the 1-phase loop)
    ("child", OP_BRANCH_ANIM_DONE, ["cwait"]),
    ("cfe", OP_FOR_EACH, []),
    ("cup1", OP_UPDATE_ALL_PARTICLES, []),
    ("cgy1", OP_GOTO_YIELD, ["child"]),
    ("cwait", OP_UPDATE_ALL_PARTICLES, []),
    ("cbce", OP_BRANCH_COUNT_EQ, [0, "cend"]),
    ("cgy2", OP_GOTO_YIELD, ["cwait"]),
    ("cend", OP_END, []),
]


def _build_prologue(pattern: str, texture_page: int,
                    callbacks: List[Tuple[int, int]]) -> bytes:
    """`set_texture_page` + [`load_callback` x N] + (`clear_timeline_a` if 1-phase)
    + `init_physics_params` — the per-effect prologue, verbatim."""
    out = bytearray()
    out += _opword(OP_SET_TEXTURE_PAGE, texture_page)
    for slot, cb_id in callbacks:
        out += _opword(OP_LOAD_CALLBACK, slot)
        out += _w16(cb_id)
    if pattern == PATTERN_1PHASE:
        out += _opword(OP_CLEAR_TIMELINE_A)
    out += _opword(OP_INIT_PHYSICS_PARAMS)
    return bytes(out)


def regenerate_section(pattern: str, texture_page: int,
                       callbacks: List[Tuple[int, int]]) -> bytes:
    """Synthesize the whole canonical script section for `pattern`, preserving the
    prologue `(texture_page, callbacks)`. Branch offsets are absolute-within-section
    and shift with the callback count; the section is padded up to a 4-byte multiple
    (a 2-byte tail pad on 3-phase, none on callback-free 1-phase)."""
    if pattern not in (PATTERN_1PHASE, PATTERN_3PHASE):
        raise ValueError("cannot regenerate non-canonical pattern %r" % pattern)
    prologue = _build_prologue(pattern, texture_page, callbacks)
    body_seq = _BODY_1PHASE if pattern == PATTERN_1PHASE else _BODY_3PHASE

    # First pass: assign each instruction an absolute offset (prologue is fixed).
    labels: Dict[str, int] = {}
    offset = len(prologue)
    for label, opcode, _args in body_seq:
        labels[label] = offset
        offset += _OPSIZE[opcode]

    # Second pass: emit, resolving label args to their offsets.
    out = bytearray(prologue)
    for _label, opcode, args in body_seq:
        out += _opword(opcode)
        for arg in args:
            out += _w16(labels[arg] if isinstance(arg, str) else arg)

    # Pad to a 4-byte boundary (keeps the next section 4-aligned).
    while len(out) % 4 != 0:
        out += b"\x00"
    return bytes(out)


# --- reading the current section ----------------------------------------------


def parse_prologue(section: bytes) -> Optional[Tuple[int, List[Tuple[int, int]]]]:
    """Read `(texture_page, callbacks[])` from a section's prologue, or None if the
    prologue is not the canonical shape (`set_texture_page`, 0-4 `load_callback`,
    optional `clear_timeline_a`, `init_physics_params`)."""
    if len(section) < 4:
        return None
    word = struct.unpack_from("<H", section, 0)[0]
    if (word & 0x1FF) != OP_SET_TEXTURE_PAGE:
        return None
    texture_page = (word >> 9) & 0x7F
    pos = 2
    callbacks: List[Tuple[int, int]] = []
    while pos + 2 <= len(section):
        word = struct.unpack_from("<H", section, pos)[0]
        if (word & 0x1FF) != OP_LOAD_CALLBACK:
            break
        if pos + 4 > len(section):
            return None
        slot = (word >> 9) & 0x7F
        cb_id = struct.unpack_from("<h", section, pos + 2)[0]
        callbacks.append((slot, cb_id))
        pos += 4
    if pos + 2 > len(section):
        return None
    if (struct.unpack_from("<H", section, pos)[0] & 0x1FF) == OP_CLEAR_TIMELINE_A:
        pos += 2
    if pos + 2 > len(section):
        return None
    if (struct.unpack_from("<H", section, pos)[0] & 0x1FF) != OP_INIT_PHYSICS_PARAMS:
        return None
    return texture_page, callbacks


def detect_pattern(section: bytes) -> str:
    """`3-phase` (opcode 41 outer + opcode 31 branch_target_type), `1-phase`
    (opcode 40 for-each, no opcode 41), else `Custom`. Ports the Lua
    `detect_script_pattern` and runs on the root (parse stops at the first `end`)."""
    ids = []
    pos = 0
    while pos + 2 <= len(section):
        oid = struct.unpack_from("<H", section, pos)[0] & 0x1FF
        ids.append(oid)
        pos += _OPSIZE.get(oid, 2)
        if oid == OP_END:
            break
    has_outer = OP_PROCESS_TIMELINE_FRAME in ids
    has_for_each = OP_FOR_EACH in ids
    has_target_type = OP_BRANCH_TARGET_TYPE in ids
    if has_outer and has_target_type:
        return PATTERN_3PHASE
    if has_for_each and not has_outer:
        return PATTERN_1PHASE
    return PATTERN_CUSTOM


def is_code_format(data: bytes) -> bool:
    """CODE-format effects start with a MIPS prologue `addiu sp, sp, -N`
    (0x27BD????); their header pointers are garbage-as-DATA and the writer is
    DATA-only."""
    if len(data) < 4:
        return True
    return (struct.unpack_from("<I", data, 0)[0] & 0xFFFF0000) == 0x27BD0000


def _script_bounds(data: bytes) -> Optional[Tuple[int, int]]:
    """(script_ptr, effect_data_ptr) from the DATA header, or None if implausible."""
    if len(data) < 40:
        return None
    script_ptr = struct.unpack_from("<I", data, 0x08)[0]
    effect_data_ptr = struct.unpack_from("<I", data, 0x0C)[0]
    if script_ptr < 40 or effect_data_ptr <= script_ptr or effect_data_ptr > len(data):
        return None
    return script_ptr, effect_data_ptr


def is_swappable(data: bytes) -> Tuple[bool, str]:
    """Whether the script pattern is editable (swappable) for this file, and if not,
    a read-only reason. The gate (ADR-0094 decision 3): DATA-format AND the section
    regenerates itself byte-exactly from its own `(pattern, prologue)`."""
    if is_code_format(data):
        return False, "CODE-format effect (script is MIPS executable, not editable)"
    bounds = _script_bounds(data)
    if bounds is None:
        return False, "unreadable script section header"
    section = data[bounds[0]:bounds[1]]
    pattern = detect_pattern(section)
    if pattern == PATTERN_CUSTOM:
        return False, "Custom script (not a recognized 1-phase / 3-phase pattern)"
    prologue = parse_prologue(section)
    if prologue is None:
        return False, "non-canonical prologue"
    texture_page, callbacks = prologue
    if regenerate_section(pattern, texture_page, callbacks) != section:
        return False, "non-canonical script body (does not match the canonical %s template)" % pattern
    return True, ""


# --- the swap: regenerate + splice + tail-shift + header fix-up ----------------


def swap_effect_script(base_bytes: bytes, target_pattern: str) -> bytes:
    """Return a NEW file with the script section rewritten to `target_pattern`,
    preserving the effect's prologue. If the effect is not swappable (CODE / Custom
    / non-canonical) or `target_pattern` isn't canonical, the base is returned
    unchanged. Regenerating to the *current* pattern reproduces the section
    byte-identically (a no-op)."""
    swappable, _reason = is_swappable(base_bytes)
    if not swappable or target_pattern not in (PATTERN_1PHASE, PATTERN_3PHASE):
        return base_bytes

    script_ptr, effect_data_ptr = _script_bounds(base_bytes)  # type: ignore[misc]
    section = base_bytes[script_ptr:effect_data_ptr]
    texture_page, callbacks = parse_prologue(section)  # type: ignore[misc]

    new_section = regenerate_section(target_pattern, texture_page, callbacks)
    delta = len(new_section) - len(section)

    out = bytearray(base_bytes[:script_ptr])
    out += new_section
    out += base_bytes[effect_data_ptr:]

    # Shift every non-zero downstream header pointer by delta.
    for off in _DOWNSTREAM_PTR_OFFSETS:
        ptr = struct.unpack_from("<I", out, off)[0]
        if ptr != 0:
            struct.pack_into("<I", out, off, ptr + delta)
    return bytes(out)


# --- game->json->bin CLI ------------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: swap a base E###.BIN's script pattern from a script.json target.

    Usage: write_effect_script.py <base.bin> <script.json> <header.json> <out.bin>
    `script.json` supplies `{"pattern": "3-phase" | "1-phase"}` (the target — the
    studio detects it from the live, possibly-swapped script). `header.json` is
    accepted for saver-chain convention but the pointers are read straight from the
    base bytes (robust to any prior in-place patches). A non-swappable base is
    copied through unchanged.
    """
    ap = argparse.ArgumentParser(
        description="Swap an E###.BIN script pattern (3-phase <-> 1-phase)")
    ap.add_argument("base_bin")
    ap.add_argument("script_json")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    args = ap.parse_args(argv)

    base = Path(args.base_bin).read_bytes()
    block: Dict[str, Any] = json.loads(Path(args.script_json).read_text())
    target = str(block.get("pattern", ""))

    out = swap_effect_script(base, target)
    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
