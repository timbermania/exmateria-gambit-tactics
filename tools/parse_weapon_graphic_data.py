#!/usr/bin/env python3
"""Parse the per-item battle-graphic table from BATTLE.BIN at 0x2d3e4.

This table is **keyed by item id** (0..0x7F for weapons + 0x80..0x8F for
shields = 144 entries), NOT by the FFTPatcher `graphic` field in items.json.
The `graphic` field is the menu-icon sprite index — a completely separate
concept. Mixing them up samples the wrong row of WEP1.tga at runtime
(authority: ffhacktics wiki "Item Graphics in Battle").

Each item has a 2-byte entry (XY ZZ in the wiki's notation):
  - byte 0 = XY:
      X (high nibble) = palette for the held-weapon overlay (WEP1.tga sampling)
      Y (low nibble)  = palette for the EFF1 overlay (swoosh / weapon gleam /
                        swing blur). The ffhacktics wiki labels this nibble as
                        "swoosh palette in WEP2.SPR", but (a) no WEP2.SPR file
                        exists in WEP.SPR (Shishi confirms WEP1/WEP2 alias the
                        same bytes) and (b) the empirical X-vs-Y palette
                        correlation across 128 weapons shows ZERO matching
                        non-zero pairs, with Y zero in 84% of entries — the
                        shape of "default overlay unless this weapon has a
                        custom effect color", not "alternate-angle palette of
                        the same held weapon". So the nibble drives EFF1.
  - byte 1 = ZZ:
      vertical pixel offset into WEP1.tga, in units of 8 px (v_off = byte * 8).
      ZZ values are scoped per-item-type: a knife with ZZ=00 displays a
      DIFFERENT sprite than a sword with ZZ=00, because the SHP zero_frame
      for each item_type points the rectangle at a different base. The
      combined sample y = shp.rect_y + (item.ZZ * 8).

Without this lookup keyed correctly, every weapon samples from the wrong
row of WEP1.tga — e.g. Rod (item_id 51) was reading Excalibur's entry
(item_id 35) because items.json[51].graphic == 35.

Authority for byte layout: ffhacktics wiki "Item Graphics in Battle"; cross-
check TacticsEngineG `battle_bin_data.gd` `weapon_graphic_data_start` (which
labels Y as "WEP2 palette" — matches the wiki).

Output: assets/sprites/weapon_graphic_data.json — Dictionary keyed by
**item id** (string), each entry { wep1_palette, eff1_palette, wep1_v_offset_pixels }.
Consumed by SpriteLayerManager.load_weapon_texture via item_id.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_paths import almanac_dir as _almanac_dir, battle_bin as _battle_bin  # noqa: E402

TABLE_OFFSET = 0x2d3e4
NUM_ENTRIES = 0x90  # 128 weapons (0x00..0x7F) + 16 shields (0x80..0x8F)
ENTRY_SIZE = 2


def parse(battle_bin_path: Path) -> dict:
    with battle_bin_path.open("rb") as f:
        data = f.read()
    out = {}
    for item_id in range(NUM_ENTRIES):
        off = TABLE_OFFSET + item_id * ENTRY_SIZE
        b0 = data[off]
        b1 = data[off + 1]
        out[str(item_id)] = {
            "wep1_palette": (b0 & 0xf0) >> 4,
            "eff1_palette": b0 & 0x0f,
            "wep1_v_offset_pixels": b1 * 8,
        }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--battle-bin",
        type=Path,
        default=_battle_bin(),
    )
    ap.add_argument(
        "-o", "--output",
        type=Path,
        default=_almanac_dir("sprites/weapon_graphic_data.json"),
    )
    args = ap.parse_args()
    out = parse(args.battle_bin)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        json.dump(out, f, indent="\t", sort_keys=False)
        f.write("\n")
    print(f"Wrote {args.output} ({len(out)} entries)")


if __name__ == "__main__":
    main()
