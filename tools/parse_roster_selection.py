#!/usr/bin/env python3
"""Decode the 3 roster/formation sprite-selection tables from WORLD/WORLD.BIN.

The party/formation "sort list" screen (FORMATION_SCREEN.md §13) picks each
cell's *pose* (a 24x40 cell in the UNIT.BIN atlas) and *palette* from three
static tables baked into the world-map overlay. `FUN_801256c8` resolves a unit's
display struct -> a descriptor index `idx`, reads the 12-byte descriptor for the
atlas rect, and resolves a palette id from a selector byte. This extractor pulls
those tables straight from the ROM overlay (ADR-0001 -- never a savestate/VRAM
dump) and re-implements the pure `descriptor_index` rule so the Godot port bakes
faithful data instead of re-RE-ing it.

ROM source (byte-verified vs the live pcsx dump in
research/working_documents/roster_catalogue_captures/roster_selection_tables.txt):

    overlay file : EVENT-adjacent WORLD/WORLD.BIN, loaded at 0x800E0000
    file_off(a)  = a - 0x800E0000

    DESC  0x8018DA44  84 x 12B   sprite descriptors (atlas U,V,W,H + tail)
    REMAP 0x8018DE34  256 B      class/job byte -> descriptor idx
    PAL   0x8018A168  256 x u16  CLUT selector -> palette id

(The snapshot named `roster_menu_overlay_800F0000_256kb.bin` does NOT contain
these -- they sit at overlay +0x9xxxx, past that 256KB window; WORLD.BIN is the
real, ADR-0001-clean source. See ticket #169.)

Output (assets/ui/formation/):
    ROSTER_SELECTION.json  the 3 tables + the resolver constants, as data the
                           port's roster_unit_to_sprite() consumes.

Usage:
    uv run python tools/parse_roster_selection.py [fft-extract-path]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

from _repo_paths import assets_dir, world_bin

# --- overlay geometry -------------------------------------------------------
OVERLAY_BASE = 0x800E0000

DESC_ADDR = 0x8018DA44
NUM_DESCRIPTORS = 84            # 0x3F0 bytes -> exactly REMAP_ADDR
DESC_ENTRY_BYTES = 12
DESC_BYTES = NUM_DESCRIPTORS * DESC_ENTRY_BYTES  # 0x3F0

REMAP_ADDR = 0x8018DE34
REMAP_BYTES = 256              # indexed by a class/job byte (0..0xFF)

PAL_ADDR = 0x8018A168
PAL_ENTRIES = 256              # u16 each, indexed by the CLUT selector (+0x2c)
PAL_BYTES = PAL_ENTRIES * 2

# --- descriptor_index resolver constants (FUN_801256c8 @0x801256C8) ---------
# Hard-coded job overrides that bypass the class/remap path.
SPECIAL_JOB_IDX = {
    0x90: 0x4E, 0x96: 0x4E, 0x91: 0x52, 0x97: 0x4F,
    0x99: 0x51, 0x9A: 0x51, 0x48: 0x4C,
}
GENERIC_CLASS_MIN = 0x4A        # +0x72 >= this -> generic path
MONSTER_CLASS = 0x82            # +0x72 == this -> monster: idx = spc(+0x11e)+0x3D
MONSTER_IDX_BASE = 0x3D
GENERIC_JOB_REMAP_MAX = 0x35    # generic job < this -> REMAP[job]
GENERIC_SPECIAL = {0x5B: 0x3A, 0x5C: 0x3B, 0x5D: 0x3C}
GENERIC_FORMULA_SUB = 0x7C      # else idx = job*2 - 0x7C  (+1 if female)
FEMALE_BIT = 0x40               # +0x70 & 0x40


def file_offset(addr: int) -> int:
    """Byte offset of an overlay-space address inside WORLD.BIN."""
    return addr - OVERLAY_BASE


def read_descriptors(data: bytes) -> list[dict]:
    """The 84 sprite descriptors at DESC_ADDR.

    Each 12-byte entry is `<HHHH BBBB>`: u,v,w,h then a 4-byte tail (tex u/v,
    tpage, pad). For human cells u,v == (idx%10)*24, (idx//10)*40 -- but the
    table is authoritative (monsters break the formula with 48x48 rects), so
    the port must read u,v,w,h from here, not recompute them."""
    base = file_offset(DESC_ADDR)
    out = []
    for idx in range(NUM_DESCRIPTORS):
        u, v, w, h, t0, t1, t2, t3 = struct.unpack_from(
            "<HHHHBBBB", data, base + idx * DESC_ENTRY_BYTES)
        out.append({
            "idx": idx, "u": u, "v": v, "w": w, "h": h,
            "tail": [t0, t1, t2, t3],
        })
    return out


def read_remap(data: bytes) -> list[int]:
    """The 256-byte class/job -> descriptor-index remap at REMAP_ADDR."""
    base = file_offset(REMAP_ADDR)
    return list(data[base:base + REMAP_BYTES])


def read_palette_table(data: bytes) -> list[int]:
    """The 256 u16 CLUT-selector -> palette-id entries at PAL_ADDR."""
    base = file_offset(PAL_ADDR)
    return list(struct.unpack_from("<%dH" % PAL_ENTRIES, data, base))


def descriptor_index(job: int, cls: int, female: bool, spc: int,
                     remap: list[int]) -> int:
    """Reproduce FUN_801256c8's pose selection (FORMATION_SCREEN.md §13.3).

    job = +0x24, cls = +0x72 class byte, female = bool(+0x70 & 0x40),
    spc = +0x11e special sub-index (used only on the monster class path)."""
    if job in SPECIAL_JOB_IDX:
        return SPECIAL_JOB_IDX[job]
    if cls == MONSTER_CLASS:
        return spc + MONSTER_IDX_BASE
    if cls >= GENERIC_CLASS_MIN:                      # generic human path
        if job < GENERIC_JOB_REMAP_MAX:
            return remap[job]
        if job in GENERIC_SPECIAL:
            return GENERIC_SPECIAL[job]
        idx = job * 2 - GENERIC_FORMULA_SUB
        if female:
            idx += 1
        return idx
    return remap[cls]                                 # story / special


def parse(world_path: Path, out_dir: Path) -> dict:
    data = world_path.read_bytes()
    need = file_offset(REMAP_ADDR) + REMAP_BYTES
    if len(data) < need:
        raise ValueError(f"WORLD.BIN is {len(data)} bytes, need >= {need}")

    descriptors = read_descriptors(data)
    remap = read_remap(data)
    palette_table = read_palette_table(data)

    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "_comment": (
            "Roster/formation sprite-SELECTION tables from WORLD/WORLD.BIN "
            "(overlay @0x800E0000), byte-verified vs the live dump. The port's "
            "roster_unit_to_sprite() reads descriptors[idx] for the UNIT.BIN "
            "atlas rect and palette_table[selector] for the CLUT; idx comes "
            "from the resolver constants below. See FORMATION_SCREEN.md §13."
        ),
        "source": "WORLD/WORLD.BIN",
        "overlay_base": OVERLAY_BASE,
        "tables": {
            "descriptors": {"addr": DESC_ADDR, "count": NUM_DESCRIPTORS,
                            "entry_bytes": DESC_ENTRY_BYTES},
            "remap": {"addr": REMAP_ADDR, "bytes": REMAP_BYTES},
            "palette": {"addr": PAL_ADDR, "entries": PAL_ENTRIES},
        },
        "descriptors": descriptors,
        "remap": remap,
        "palette_table": palette_table,
        "resolver": {
            "special_job_idx": {str(k): v for k, v in SPECIAL_JOB_IDX.items()},
            "generic_class_min": GENERIC_CLASS_MIN,
            "monster_class": MONSTER_CLASS,
            "monster_idx_base": MONSTER_IDX_BASE,
            "generic_job_remap_max": GENERIC_JOB_REMAP_MAX,
            "generic_special": {str(k): v for k, v in GENERIC_SPECIAL.items()},
            "generic_formula_sub": GENERIC_FORMULA_SUB,
            "female_bit": FEMALE_BIT,
        },
    }
    with open(out_dir / "ROSTER_SELECTION.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract the 3 roster/formation sprite-selection tables "
                    "from WORLD/WORLD.BIN")
    parser.add_argument("fft_path", nargs="?", default=None,
                        help="FFT extract directory (default: project-assets)")
    args = parser.parse_args()

    input_path = world_bin(args.fft_path)
    if not input_path.exists():
        print(f"Error: WORLD.BIN not found at {input_path}")
        sys.exit(1)

    out_dir = assets_dir() / "ui" / "formation"
    manifest = parse(input_path, out_dir)
    print(f"Extracting roster-selection tables from {input_path.name}")
    print(f"  descriptors : {len(manifest['descriptors'])} @ {DESC_ADDR:#010x}")
    print(f"  remap       : {len(manifest['remap'])} B @ {REMAP_ADDR:#010x}")
    print(f"  palette     : {len(manifest['palette_table'])} u16 @ {PAL_ADDR:#010x}")
    print(f"  manifest -> {out_dir / 'ROSTER_SELECTION.json'}")


if __name__ == "__main__":
    main()
