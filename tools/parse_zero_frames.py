#!/usr/bin/env python3
"""Parse the per-weapon-family `zero_frames` arrays from WEP1.SHP, WEP2.SHP,
and EFF1.SHP section 1.

Each WEP/EFF SHP file packs a 32-entry uint16 LE array at section 1, starting
at byte 0x4. The array gives the SHP-frame base index for each weapon family:

    SHP frame for an attack = zero_frames[item_type_array_index] + (anim frame)

Combined with weapon_graphic_data[graphic].wep1_v_offset_pixels (which picks
the texture-row of WEP1.tga for the specific graphic), this is the full
"which pixels to sample for this attack frame" pipeline.

FFT loads each array into RAM at 0x800bdf0c at boot (per ffhacktics wiki), but
the on-disk source is the SHP file's section 1, which we read straight off
disk.

item_type_id → array_index quirk: the SHP array packs item_types 0..19 at
indices 0..19 contiguously, then item_types 32 (Shuriken) / 33 (Ball / wiki's
"Bombs") at indices 20 / 21. item_type 34 (Consumable) has no SHP entry.

We bake the remap into the emitted JSON so consumers can key by item_type_id
directly with no special-casing at the call site.

Authority: ffhacktics wiki Weapon Zero Frames table (matches the ROM bytes
byte-for-byte across WEP1, WEP2, EFF1).

Output: assets/sprites/wep_zero_frames.json — Dictionary keyed by sheet name
("wep1" / "wep2" / "eff1"), each entry a Dictionary keyed by item_type_id
string with the SHP-frame base index as the value.

Consumed by WeaponZeroFrames.gd.
"""
import argparse
import json
from pathlib import Path

# Allow `import _repo_paths` when run from anywhere.
import sys
sys.path.insert(0, str(Path(__file__).parent))
from _repo_paths import almanac_dir as _almanac_dir  # noqa: E402
from _repo_paths import battle_dir as _battle_dir  # noqa: E402

SECTION1_OFFSET = 0x4
NUM_ENTRIES = 22  # 0..21 — the meaningful entries (0..19 plus the 20/21 remap slots).

# item_type_id → SHP zero_frames array index. Item types not in this map have
# no WEP/EFF sprite entry (Consumable=34 and the unused 20..31 range).
ITEM_TYPE_TO_ARRAY_INDEX = {**{i: i for i in range(20)},
                            32: 20,   # Shuriken
                            33: 21}   # Ball / wiki's "Bombs"


def parse_zero_frames(shp_path: Path) -> dict[str, int]:
    """Read NUM_ENTRIES uint16 LE from section 1, remap to item_type_id keys."""
    data = shp_path.read_bytes()
    raw = [int.from_bytes(data[SECTION1_OFFSET + i * 2:SECTION1_OFFSET + (i + 1) * 2], "little")
           for i in range(NUM_ENTRIES)]
    return {str(item_type): raw[idx] for item_type, idx in ITEM_TYPE_TO_ARRAY_INDEX.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shp-dir", type=Path, default=_battle_dir(),
                    help="Directory containing WEP1.SHP, WEP2.SHP, EFF1.SHP (default: fft-extract/BATTLE).")
    ap.add_argument("-o", "--output", type=Path,
                    default=_almanac_dir("sprites/wep_zero_frames.json"))
    args = ap.parse_args()

    out = {
        "wep1": parse_zero_frames(args.shp_dir / "WEP1.SHP"),
        "wep2": parse_zero_frames(args.shp_dir / "WEP2.SHP"),
        "eff1": parse_zero_frames(args.shp_dir / "EFF1.SHP"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        json.dump(out, f, indent="\t", sort_keys=False)
        f.write("\n")
    print(f"Wrote {args.output} ({NUM_ENTRIES} item_types × 3 sheets)")


if __name__ == "__main__":
    main()
