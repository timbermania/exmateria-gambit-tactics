#!/usr/bin/env python3
"""Parse FFT's damage/status **number-popup trending** tables from BATTLE.BIN.

The floating number that pops over a unit when it takes damage (the cream "777")
does not merely appear — it *trends*: each digit scales up small→overshoot→settle,
and the digits reveal right-to-left (ones first). FFT does not synthesize that
motion from a curve at runtime; it reads it from a **Q12 scale-ramp table the ROM
ships**, exactly the way the tile cursor reads its bob from a step-table
(godot-learning ADR-0046). Per root ADR-0001, that table is a *reproducible
extractor output*, not a hand-maintained set of magic Q12 literals in GDScript —
so it is parsed here, byte-verified against the binary.

Provenance (static, `research/working_documents/DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md`
Rounds 4–5): the per-frame draw fn `FUN_800810a4` (@0x800810a4) copies six
transform-template blocks onto the stack and a phase-band switch
(`switchD_80081874`) selects which applies to each digit at the current phase
(the popup's per-frame counter `unit+0x2c2`, +1/frame, grow band = phase 0..20).
Three of the six blocks are the per-digit **scale ramps**; the block index *is*
the `scale[phase]` table. The other three are a paired secondary transform
(position/skew, trig-valued) — preserved raw, semantics not fully RE'd.

Output: assets/sprites/number_popup_trend.json — format-preserving (each ROM block
kept as its raw Q12 halfword list) plus a decoded convenience view and the
phase/pacing/fade constants the trending needs.

Run from tools/:
    uv run python parse_number_popup.py            # writes the JSON
    uv run python parse_number_popup.py --check     # verify only, no write
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _repo_paths import battle_bin as _battle_bin  # noqa: E402

# =============================================================================
# Memory layout (ADR-0046 style) — BATTLE.BIN battle overlay VA 0x80067000 = file 0.
# =============================================================================
BATTLE_BASE = 0x80067000
Q12 = 0x1000  # 1.0 in the ROM's 12-bit fixed point

# The six template blocks the draw fn FUN_800810a4 copies to the stack, in ROM
# order, as (label, virtual address). Each block runs to the next block's base.
BLOCKS = [
    ("secondary_base", 0x80067BB8),   # no stagger, starts at 1.0 — base transform
    ("secondary_digit1", 0x80067BD8),  # staggered secondary (trig-valued)
    ("secondary_digit2", 0x80067C04),  # staggered secondary
    ("scale_ones", 0x80067C30),        # scale ramp, reveal stagger 1  (rightmost digit)
    ("scale_tens", 0x80067C5C),        # scale ramp, reveal stagger 7
    ("scale_hundreds", 0x80067C88),    # scale ramp, reveal stagger 12 (leftmost of 3)
]
REGION_END_VA = 0x80067CB4  # switchD_80081874 (the phase-band jump table) begins here

# The canonical grow curve (Q12), verified to appear in each scale block after its
# per-digit reveal stagger. small → overshoot(1.5) → settle(1.0).
CANONICAL_RAMP_Q12 = [0x04CC, 0x0999, 0x0E65, 0x1331, 0x1800, 0x1331, 0x0E65, 0x0F3C, 0x1000]
SCALE_BLOCKS = ("scale_ones", "scale_tens", "scale_hundreds")

# Lifecycle phase bands (inclusive), from the branch ladder in FUN_800810a4.
PHASE_BANDS = {"grow": [0x00, 0x14], "steady": [0x15, 0x31], "fade": [0x32, 0x3C], "teardown": 0x3D}


def _file_off(va: int) -> int:
    return va - BATTLE_BASE


def _halfwords(buf: bytes, va: int, end_va: int) -> list[int]:
    off, end = _file_off(va), _file_off(end_va)
    return [struct.unpack_from("<H", buf, off + i * 2)[0] for i in range((end - off) // 2)]


def _reveal_stagger(hw: list[int]) -> int:
    """Leading zero count before the ramp's first value (0x04CC) — the reveal delay."""
    return hw.index(CANONICAL_RAMP_Q12[0])


def parse(buf: bytes) -> dict:
    bases = [va for _, va in BLOCKS] + [REGION_END_VA]
    blocks = {}
    for i, (label, va) in enumerate(BLOCKS):
        blocks[label] = _halfwords(buf, va, bases[i + 1])

    # Verify: each scale block contains the canonical ramp at its reveal stagger.
    stagger = {}
    for label in SCALE_BLOCKS:
        hw = blocks[label]
        s = _reveal_stagger(hw)
        got = hw[s:s + len(CANONICAL_RAMP_Q12)]
        if got != CANONICAL_RAMP_Q12:
            raise ValueError(
                f"{label} ramp mismatch at stagger {s}: {[hex(x) for x in got]} "
                f"!= {[hex(x) for x in CANONICAL_RAMP_Q12]} — BATTLE.BIN not reproducing "
                "the trending table (ADR-0001: a committed asset that does not reproduce is a bug)."
            )
        stagger[label] = s

    # scale_by_phase[digit] = the raw block truncated to the grow band (phase 0..20),
    # i.e. the phase→scale table the engine indexes directly. Padded/held at 1.0.
    grow_len = PHASE_BANDS["grow"][1] + 1  # 21 phases (0..20 inclusive)
    scale_by_phase = {
        digit: [blocks[label][p] if p < len(blocks[label]) else Q12 for p in range(grow_len)]
        for digit, label in zip(("ones", "tens", "hundreds"), SCALE_BLOCKS)
    }

    return {
        "format": "number_popup_trend",
        "_doc": "Per-digit grow/reveal scale ramp + lifecycle constants for the "
                "damage/status number popup. See DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md.",
        "source": {
            "binary": "BATTLE.BIN",
            "base_va": hex(BATTLE_BASE),
            "draw_fn": "FUN_800810a4 @0x800810a4",
            "table_region_va": [hex(BLOCKS[0][1]), hex(REGION_END_VA)],
            "phase_switch_va": "0x80081874",
        },
        "q12_one": Q12,
        "phase_counter": "unit+0x2c2",
        "phase_bands": PHASE_BANDS,
        "pacing": {
            "per_frame_delta_global": "DAT_80045980",
            "value": 1,
            "hz": 60,
            "note": "same vblanks-per-tick divider as the cursor bob (ADR-0046); "
                    "==2 is the ROM's fast-forward.",
        },
        "fade": {
            "engine": "FUN_8008f710",
            "per_channel_delta": -0x1F,
            "target_rgb": [0, 0, 0],
            "blend": {
                "grow_steady": {"gp0_code": "0x2C", "mode": "opaque", "tpage_abr": 0},
                "fade": {"gp0_code": "0x2E", "mode": "semi_transparent", "tpage_abr": 1,
                         "abr_equation": "B + F (additive)"},
                "switch_at_phase": "0x32",
            },
            "note": "TWO things happen together in the fade band: (1) the primitive "
                    "switches opaque(0x2C)->additive-semitransparent(0x2E, ABR=1) at "
                    "phase 0x32, and (2) FUN_8008f710 ramps the palette RGB toward black "
                    "(-0x1f/channel/frame). Under additive blend, palette->black = adds "
                    "nothing = fade-to-nothing. Live-verified (see Round 5.2). Port: "
                    "render opaque during grow+steady, ADDITIVE during fade, driving the "
                    "digit colour to black. CLUT 0x79CB = *(unit+0x10)+0x100.",
        },
        "grow": {
            "canonical_ramp_q12": CANONICAL_RAMP_Q12,
            "canonical_ramp_f": [round(x / Q12, 4) for x in CANONICAL_RAMP_Q12],
            "reveal_stagger_phase": {d: stagger[l] for d, l in
                                     zip(("ones", "tens", "hundreds"), SCALE_BLOCKS)},
            "scale_by_phase_q12": scale_by_phase,
            "anchor": "shared_point_at_number_right_edge",
            "apply": "SUB_80042b1c builds a diagonal scale matrix per digit; SUB_80044a60 "
                     "transforms the digit record; each digit is an OFFSET (8x16 cell, 7px "
                     "pitch, common baseline) from a SINGLE shared anchor at the number's "
                     "right edge, scaled about that anchor. At scale 0 all digits collapse "
                     "to the anchor (live-verified). Anchor is placed over the target unit's "
                     "projected screen position, so scale each digit about the shared right "
                     "anchor (NOT its own center), and anchor that point to the unit.",
            "note": "digit 'ones' = rightmost; leading-zero pad before each ramp IS "
                    "the right-to-left reveal. All three reach 1.0 by phase 0x14. Growing "
                    "outward-LEFT from the right anchor reinforces the ones-first reveal.",
        },
        "raw_blocks_q12": blocks,
        "secondary_transform_note": "Blocks secondary_base/digit1/digit2 (bb8/bd8/c04) "
                                    "are a paired position/skew transform, trig-valued "
                                    "(0x0800=0.5, 0x0b50=0.707, 0x0f74=0.966), also "
                                    "per-digit staggered. Preserved raw; full matrix "
                                    "semantics not yet RE'd.",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--battle", type=Path, default=_battle_bin(), help="Path to BATTLE.BIN")
    ap.add_argument("--output", type=Path,
                    default=Path(__file__).parent.parent / "assets" / "sprites" / "number_popup_trend.json")
    ap.add_argument("--check", action="store_true", help="Verify + print summary; do not write")
    args = ap.parse_args()

    if not args.battle.exists():
        print(f"Error: BATTLE.BIN not found: {args.battle}", file=sys.stderr)
        return 1
    data = parse(args.battle.read_bytes())

    g = data["grow"]
    print("number-popup trending — parsed + verified")
    print(f"  ramp (Q12): {[hex(x) for x in g['canonical_ramp_q12']]}")
    print(f"  ramp (f):   {g['canonical_ramp_f']}")
    print(f"  reveal stagger (phase): {g['reveal_stagger_phase']}")
    print(f"  phase bands: {data['phase_bands']}")
    if args.check:
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
