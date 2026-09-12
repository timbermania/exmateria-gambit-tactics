#!/usr/bin/env python3
"""
Dialogue-box OPEN/CLOSE animation curve parser.

Extracts the box grow/shrink tween curves from BATTLE.BIN. When a boxed
Display Message (opcode 0x10, box type 0x1X/0x9X) opens, the engine grows the
box by lerping its textured quad's 4 corners from the speaker-triangle point to
the full rect, advancing one curve entry per frame; on close it shrinks the
same way. The curve is a sequence of Q12 fractions (0x1000 = 4096 = 1.0 = full
size), terminated by the 0x1000 entry.

  - Pointer table  PTR_DAT_80167908 : 5 x u32 -> the 5 curve arrays.
  - OPEN curve index = (Open Type byte, payload +0xE) & 0xf.
  - CLOSE always uses curve index 4.

Curves (as shipped in BATTLE.BIN, verified byte-exact against a live PCSX
capture of the chapel boxes, 2026-07-01):
  c0 ease-out overshoot-bounce (10f), c1 big overshoot 1.125x (11f),
  c2 linear (11f), c3 ease-out (7f), c4 linear (4f) = CLOSE.

Reference living doc:
  research/working_documents/scenario_1_captures/prayer_text_fadeout_and_box_open_close_decode.md
Source: PSX RAM 0x80167908 (BATTLE.BIN offset 0x100908).

Usage:
    uv run python tools/parse_dialogue_box_curves.py
    uv run python tools/parse_dialogue_box_curves.py /path/to/BATTLE.BIN
"""

import json
import struct
import sys
from pathlib import Path
from typing import Dict, List

from _repo_paths import battle_bin as _battle_bin

DEFAULT_BATTLE_PATH = _battle_bin()
DEFAULT_OUTPUT_PATH = Path(__file__).parent.parent / "assets" / "ui" / "dialogue_box_curves.json"

# BATTLE.BIN loads at RAM 0x80067000; pointer table at RAM 0x80167908.
BATTLE_BIN_RAM_BASE = 0x80067000
CURVE_PTR_TABLE_RAM = 0x80167908
NUM_CURVES = 5                    # 5 curves; OPEN uses OpenType&0xf, CLOSE = index 4.
CLOSE_CURVE_INDEX = 4
Q12_ONE = 0x1000                  # full size / terminator
MAX_STEPS = 32                    # safety bound while walking a curve


def _u32(data: bytes, ram: int) -> int:
    return struct.unpack_from("<I", data, ram - BATTLE_BIN_RAM_BASE)[0]


def _u16(data: bytes, ram: int) -> int:
    return struct.unpack_from("<H", data, ram - BATTLE_BIN_RAM_BASE)[0]


def parse_box_curves(battle_bin_path: Path) -> Dict:
    data = battle_bin_path.read_bytes()

    curves: List[Dict] = []
    for i in range(NUM_CURVES):
        ptr = _u32(data, CURVE_PTR_TABLE_RAM + i * 4)
        if not (BATTLE_BIN_RAM_BASE <= ptr < BATTLE_BIN_RAM_BASE + len(data)):
            raise ValueError(f"curve[{i}] pointer 0x{ptr:08X} out of BATTLE.BIN range")
        raw: List[int] = []
        addr = ptr
        for _ in range(MAX_STEPS):
            v = _u16(data, addr)
            raw.append(v)
            addr += 2
            if v == Q12_ONE:
                break
        else:
            raise ValueError(f"curve[{i}] @0x{ptr:08X} never hit the 0x1000 terminator")
        curves.append({
            "index": i,
            "ram": f"0x{ptr:08X}",
            "frames": len(raw),
            "overshoot": max(raw) > Q12_ONE,
            "raw_q12": raw,
            "t": [round(v / Q12_ONE, 6) for v in raw],  # fraction of full size (may exceed 1.0)
        })

    return {
        "_source": "BATTLE.BIN pointer table PTR_DAT_80167908 (RAM 0x80167908) -> 5 curves",
        "_doc": "research/working_documents/scenario_1_captures/prayer_text_fadeout_and_box_open_close_decode.md",
        "unit": "q12_fraction_of_full_box_size (t = raw/4096; 1.0 = full, >1.0 = overshoot)",
        "ram_base": f"0x{BATTLE_BIN_RAM_BASE:08X}",
        "pointer_table_ram": f"0x{CURVE_PTR_TABLE_RAM:08X}",
        "open_curve_index": "OpenType_byte (payload +0xE) & 0xf",
        "close_curve_index": CLOSE_CURVE_INDEX,
        "curves": curves,
    }


def main() -> None:
    battle_bin_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BATTLE_PATH
    if not battle_bin_path.exists():
        print(f"Error: BATTLE.BIN not found at {battle_bin_path}")
        sys.exit(1)

    print(f"Parsing dialogue-box curves from {battle_bin_path}")
    print(f"  pointer table RAM 0x{CURVE_PTR_TABLE_RAM:08X} "
          f"(offset 0x{CURVE_PTR_TABLE_RAM - BATTLE_BIN_RAM_BASE:X})\n")
    result = parse_box_curves(battle_bin_path)
    for c in result["curves"]:
        tag = " CLOSE" if c["index"] == CLOSE_CURVE_INDEX else ""
        os_ = " overshoot" if c["overshoot"] else ""
        print(f"  c{c['index']} @{c['ram']} {c['frames']:2d}f{os_}{tag}: "
              + " ".join(f"{v:04X}" for v in c["raw_q12"]))

    DEFAULT_OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_OUTPUT_PATH.write_text(json.dumps(result, indent=2))
    print(f"\nSaved {len(result['curves'])} curves to {DEFAULT_OUTPUT_PATH}")


if __name__ == "__main__":
    main()
