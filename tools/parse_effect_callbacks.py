#!/usr/bin/env python3
"""Parse callback-specific data tables from CODE-format effect .BIN files.

Each CODE-format effect has bespoke MIPS code with embedded data tables.
This parser extracts those tables into JSON for use by Godot callback scripts.

Usage:
    uv run python tools/parse_effect_callbacks.py E317
    uv run python tools/parse_effect_callbacks.py --all
"""

import argparse
import json
import struct
import sys
from pathlib import Path

from _repo_paths import effect_dir as _effect_dir, assets_dir as _assets_dir

# Paths resolve from the repo via _repo_paths (host-agnostic, CWD-independent).
FFT_EXTRACT = _effect_dir()
ASSETS_DIR = _assets_dir("effects")


def read_int32_array(data: bytes, offset: int, count: int) -> list[int]:
    """Read an array of little-endian int32 values from binary data."""
    values = []
    for i in range(count):
        pos = offset + i * 4
        if pos + 4 > len(data):
            break
        values.append(struct.unpack_from("<i", data, pos)[0])
    return values


def read_int16(data: bytes, offset: int) -> int:
    """Read a single little-endian int16 from binary data."""
    if offset + 2 > len(data):
        return 0
    return struct.unpack_from("<h", data, offset)[0]


def addr_to_offset(psx_addr: int, base_addr: int) -> int:
    """Convert PSX RAM address to file offset."""
    return psx_addr - base_addr


def parse_e317_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E317-specific callback data tables from raw .BIN.

    E317 (Choco Ball) MIPS code loads at PSX address 0x801c2500.

    CB92 data:
    - Brightness table at DAT_801c5c88: per-section bell curve (9 int32s per entry)
      Entry index from emitter vel_spread_start[2] = 4
    - Radius profile at DAT_801c5d60: 5 int32 taper values
    """
    data = bin_path.read_bytes()
    base = 0x801C2500  # PSX load address for E317 MIPS code

    # CB92 brightness table (DAT_801c5c88)
    brightness_table_base = addr_to_offset(0x801C5C88, base)
    entry_index = 4  # vel_spread_start[2] for emitter 4
    entry_size = 36  # 9 int32s = 36 bytes
    entry_offset = brightness_table_base + entry_index * entry_size
    brightness = read_int32_array(data, entry_offset, 9)[:8]

    # CB92 radius profile (DAT_801c5d60)
    radius_offset = addr_to_offset(0x801C5D60, base)
    radius_profile = read_int32_array(data, radius_offset, 5)

    # Write CB92 callback data
    cb92_dir = output_dir / "callbacks" / "CB92"
    cb92_dir.mkdir(parents=True, exist_ok=True)

    cb92_data = {
        "callback_id": 92,
        "brightness_table": brightness,
        "radius_profile": radius_profile,
    }

    out_path = cb92_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb92_data, indent=2) + "\n")
    print(f"  CB92: brightness={brightness}")
    print(f"  CB92: radius_profile={radius_profile}")
    print(f"  -> {out_path}")


def parse_e071_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E071-specific callback data tables from raw .BIN.

    E071 (Bahamut) MIPS code loads at PSX address 0x801c2500.
    CB26/CB27 share FUN_801c2cec — hemisphere/dome mesh callback.

    Data:
    - Brightness table at DAT_801c4000: 9 int32s per row (6 valid rows)
      Brightness row index from emitter's vel_spread_start[2] in raw JSON.
      Values > num_rows use >>8 to derive the row index (PSX fixed-point).
    - spread_start_w at emitter file+0xAC: radius end value (not in standard JSON)
    - curve_indices_raw and raw_position_end_x from emitters.json for curve mapping
    """
    data = bin_path.read_bytes()
    base = 0x801C2500  # PSX load address for E071 MIPS code

    # Brightness table at DAT_801c4000 (file offset 0x1B00)
    brightness_offset = addr_to_offset(0x801C4000, base)
    row_size = 9 * 4  # 9 int32s = 36 bytes per row
    # Read rows until values go out of 0-4096 range (table boundary)
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    # Emitter record layout: base offset 11960, stride 196 bytes (0xC4)
    emitter_base = 11960
    emitter_stride = 196

    # Load emitters.json for curve_indices_raw, raw position_end, vel_spread_start
    emitters_json_path = output_dir / "emitters.json"
    emitters_data = json.loads(emitters_json_path.read_text())

    overrides = {}
    for emitter_idx in [3, 8]:
        em_offset = emitter_base + emitter_idx * emitter_stride
        spread_start_w = read_int16(data, em_offset + 0xAC)

        # Get fields from already-parsed emitters.json
        em_json = emitters_data[emitter_idx]
        curve_raw = em_json.get("curve_indices_raw", [0] * 8)
        raw_pos_end_x = em_json.get("raw", {}).get("position_end", [0, 0, 0])[0]

        # Brightness row index from vel_spread_start[2] (same pattern as E317)
        vel_spread_z = em_json.get("raw", {}).get("vel_spread_start", [0, 0, 0])[2]
        brightness_idx = vel_spread_z
        if brightness_idx >= len(brightness_rows):
            brightness_idx = brightness_idx >> 8  # PSX fixed-point scaling
        if brightness_idx >= len(brightness_rows):
            brightness_idx = 0  # fallback

        overrides[str(emitter_idx)] = {
            "brightness_row_index": brightness_idx,
            "spread_start_w": spread_start_w,
            "curve_indices_raw": curve_raw,
            "raw_position_end_x": raw_pos_end_x,
        }

    # Write to CB26 directory (shared by CB26 and CB27)
    cb_dir = output_dir / "callbacks" / "CB26"
    cb_dir.mkdir(parents=True, exist_ok=True)

    cb_data = {
        "callback_id": 26,
        "brightness_table": brightness_rows,
        "emitter_overrides": overrides,
    }

    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB26: {len(brightness_rows)} brightness rows")
    for idx, ov in overrides.items():
        print(f"  Emitter {idx}: brightness_row={ov['brightness_row_index']}, "
              f"spread_start_w={ov['spread_start_w']}")
    print(f"  -> {out_path}")


def parse_e065_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E065-specific callback data tables from raw .BIN.

    E065 MIPS code loads at PSX address 0x801c2500.
    CB17 (FUN_801c2c74) — spiral/helix mesh callback.

    Data:
    - Brightness table at DAT_801c5974 (file offset 0x3474):
      6 int32s per row (24 bytes), indexed by emitter+0x4E.
    - Raw emitter bytes at offsets 0x38-0x48 etc. not in standard emitters.json.
    """
    data = bin_path.read_bytes()
    base = 0x801C2500

    # CB17 brightness table at DAT_801c5974 (file offset 0x3474)
    brightness_offset = addr_to_offset(0x801C5974, base)
    row_size = 6 * 4  # 6 int32s = 24 bytes per row
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 6)
        if len(values) < 6 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    # Emitter record layout from header.json: ParticleSystem at offset 19056,
    # header is 20 bytes, so first emitter at 19056 + 20 = 19076
    emitter_base = 19076
    emitter_stride = 196  # 0xC4

    # Extract raw bytes not in standard emitters.json for callback emitters
    # CB17 uses emitter 14 (timeline action_flags=2 → slot 1, emitter_id=15 → index 14)
    # CB16 uses emitter 10 (action_flags=1 → slot 0, emitter_id=11 → index 10)
    overrides = {}
    for emitter_idx in [10, 14]:
        em_offset = emitter_base + emitter_idx * emitter_stride
        overrides[str(emitter_idx)] = {
            # Size/rotation fields (0x38-0x48) — not in emitters.json raw_data
            "size_start": read_int16(data, em_offset + 0x38),
            "size_end": read_int16(data, em_offset + 0x3A),
            "size_spread_start": read_int16(data, em_offset + 0x3C),
            "size_spread_end": read_int16(data, em_offset + 0x3E),
            "rotation_start": read_int16(data, em_offset + 0x40),
            "rotation_end": read_int16(data, em_offset + 0x42),
            "rot_vel_start": read_int16(data, em_offset + 0x44),
            "rot_vel_end": read_int16(data, em_offset + 0x46),
            # 0x48 is color_r_start/end read as s16 by callback (bag of bytes)
            "color_as_s16_0x48": read_int16(data, em_offset + 0x48),
            # Depth/render priority byte at 0x54
            "depth_0x54": read_int16(data, em_offset + 0x54),
            # Reserved radial fields used as rotation acceleration
            "radial_reserved_1": read_int16(data, em_offset + 0x9C),
            "radial_reserved_2": read_int16(data, em_offset + 0xA2),
            # Curve index nibbles from second dword (bytes 0x0C-0x0F)
            "curve_nibbles_0c": [
                (data[em_offset + 0x0C]) & 0xF,
                (data[em_offset + 0x0C] >> 4) & 0xF,
                (data[em_offset + 0x0D]) & 0xF,
                (data[em_offset + 0x0D] >> 4) & 0xF,
                (data[em_offset + 0x0E]) & 0xF,
                (data[em_offset + 0x0E] >> 4) & 0xF,
                (data[em_offset + 0x0F]) & 0xF,
                (data[em_offset + 0x0F] >> 4) & 0xF,
            ],
        }

    # Write CB17 callback data
    cb_dir = output_dir / "callbacks" / "CB17"
    cb_dir.mkdir(parents=True, exist_ok=True)

    cb_data = {
        "callback_id": 17,
        "brightness_table": brightness_rows,
        "emitter_overrides": overrides,
    }

    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB17: {len(brightness_rows)} brightness rows")
    for idx, ov in overrides.items():
        print(f"  Emitter {idx}: size_start={ov['size_start']}, "
              f"rot_vel_start={ov['rot_vel_start']}, depth={ov['depth_0x54']}")
    print(f"  -> {out_path}")

    # CB16 brightness table at DAT_801c58e8 (file offset 0x33E8)
    cb16_brightness_offset = addr_to_offset(0x801C58E8, base)
    cb16_row_size = 5 * 4  # 5 int32s = 20 bytes per row
    cb16_brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, cb16_brightness_offset + row * cb16_row_size, 5)
        if len(values) < 5 or any(v < 0 or v > 4096 for v in values):
            break
        cb16_brightness_rows.append(values)

    cb16_dir = output_dir / "callbacks" / "CB16"
    cb16_dir.mkdir(parents=True, exist_ok=True)
    cb16_data = {
        "callback_id": 16,
        "brightness_table": cb16_brightness_rows,
    }
    cb16_out = cb16_dir / "callback_data.json"
    cb16_out.write_text(json.dumps(cb16_data, indent=2) + "\n")
    print(f"  CB16: {len(cb16_brightness_rows)} brightness rows -> {cb16_out}")

    # CB18 brightness table at DAT_801c5a1c (file offset 0x351C)
    cb18_brightness_offset = addr_to_offset(0x801C5A1C, base)
    cb18_row_size = 9 * 4  # 9 int32s = 36 bytes per row
    cb18_brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, cb18_brightness_offset + row * cb18_row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        cb18_brightness_rows.append(values)

    cb18_dir = output_dir / "callbacks" / "CB18"
    cb18_dir.mkdir(parents=True, exist_ok=True)
    cb18_data = {
        "callback_id": 18,
        "brightness_table": cb18_brightness_rows,
    }
    cb18_out = cb18_dir / "callback_data.json"
    cb18_out.write_text(json.dumps(cb18_data, indent=2) + "\n")
    print(f"  CB18: {len(cb18_brightness_rows)} brightness rows -> {cb18_out}")


def parse_world_tube_callbacks(bin_path: Path, output_dir: Path, effect_name: str,
                                cb_id: int) -> None:
    """Generic parser for effects using the WorldTube callback (CB4/CB18/etc).

    The WorldTube function (FUN at offset 0x14F8 or 0x0000) references a brightness
    table at DAT_801c5a1c (base + 0x351C). Same structure across all effects that
    use this callback: 9 int32s per row (36 bytes).
    """
    data = bin_path.read_bytes()
    base = 0x801C2500

    brightness_offset = addr_to_offset(0x801C5A1C, base)
    row_size = 9 * 4  # 9 int32s = 36 bytes per row
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    cb_dir = output_dir / "callbacks" / f"CB{cb_id:02d}"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {
        "callback_id": cb_id,
        "brightness_table": brightness_rows,
    }
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB{cb_id:02d}: {len(brightness_rows)} brightness rows -> {out_path}")


def parse_e005_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E005 callback data. Uses WorldTube callback (CB4).

    E005's brightness table is at file offset 0x14F8 (NOT 0x351C like E065).
    The code section is smaller, so the data table is at a different offset.
    """
    data = bin_path.read_bytes()
    base = 0x801C2500

    # Brightness table at offset 0x14F8 (found by scanning for valid 9×int32 rows)
    brightness_offset = 0x14F8
    row_size = 9 * 4
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    cb_dir = output_dir / "callbacks" / "CB04"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {
        "callback_id": 4,
        "brightness_table": brightness_rows,
    }
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB04: {len(brightness_rows)} brightness rows -> {out_path}")


def parse_e006_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E006 callback data. Uses WorldTube callback (CB5).
    Identical code to E005, brightness table at same offset 0x14F8.
    """
    data = bin_path.read_bytes()
    brightness_offset = 0x14F8
    row_size = 9 * 4
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    cb_dir = output_dir / "callbacks" / "CB05"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {
        "callback_id": 5,
        "brightness_table": brightness_rows,
    }
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB05: {len(brightness_rows)} brightness rows -> {out_path}")


def parse_e007_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E007 callback data. Uses WorldTube callback (CB6).
    Identical code to E005/E006, brightness table at same offset 0x14F8.
    """
    data = bin_path.read_bytes()
    brightness_offset = 0x14F8
    row_size = 9 * 4
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    cb_dir = output_dir / "callbacks" / "CB06"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {
        "callback_id": 6,
        "brightness_table": brightness_rows,
    }
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB06: {len(brightness_rows)} brightness rows -> {out_path}")


def parse_e015_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E015 callback data.

    E015 has two callbacks:
    - CB08 (WorldTube) at offset 0x14F8 — brightness table at 0x3238
    - CB09 (ScreenGrid) at offset 0x2AC8 — no separate brightness table found
    """
    data = bin_path.read_bytes()

    # WorldTube brightness at 0x3238 (found by scanning)
    brightness_offset = 0x3238
    row_size = 9 * 4
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    cb_dir = output_dir / "callbacks" / "CB08"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {"callback_id": 8, "brightness_table": brightness_rows}
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB08: {len(brightness_rows)} brightness rows -> {out_path}")

    # ScreenGrid (CB09) — empty brightness table (uses vertex colors only)
    cb_dir = output_dir / "callbacks" / "CB09"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {"callback_id": 9, "brightness_table": []}
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB09: empty brightness -> {out_path}")


def parse_e033_callbacks(bin_path: Path, output_dir: Path) -> None:
    """Parse E033 callback data. WarpedGrid callback (CB10/CB11).
    Brightness table at offset 0x2390 (DAT_801c4890).
    """
    data = bin_path.read_bytes()
    brightness_offset = 0x2390
    row_size = 9 * 4
    brightness_rows = []
    for row in range(16):
        values = read_int32_array(data, brightness_offset + row * row_size, 9)
        if len(values) < 9 or any(v < 0 or v > 4096 for v in values):
            break
        brightness_rows.append(values)

    # CB11 is the primary ID from offset table (0x177C | 11, 13, 36)
    cb_dir = output_dir / "callbacks" / "CB11"
    cb_dir.mkdir(parents=True, exist_ok=True)
    cb_data = {"callback_id": 11, "brightness_table": brightness_rows}
    out_path = cb_dir / "callback_data.json"
    out_path.write_text(json.dumps(cb_data, indent=2) + "\n")
    print(f"  CB11: {len(brightness_rows)} brightness rows -> {out_path}")


# Registry of per-effect parsers
EFFECT_PARSERS = {
    "E005": parse_e005_callbacks,
    "E006": parse_e006_callbacks,
    "E007": parse_e007_callbacks,
    "E015": parse_e015_callbacks,
    "E033": parse_e033_callbacks,
    "E065": parse_e065_callbacks,
    "E071": parse_e071_callbacks,
    "E317": parse_e317_callbacks,
}


def main():
    parser = argparse.ArgumentParser(description="Parse callback data from effect .BIN files")
    parser.add_argument("effect", nargs="?", help="Effect name (e.g., E317)")
    parser.add_argument("--all", action="store_true", help="Parse all known effects")
    args = parser.parse_args()

    if args.all:
        effects = list(EFFECT_PARSERS.keys())
    elif args.effect:
        effects = [args.effect]
    else:
        parser.print_help()
        sys.exit(1)

    for effect_name in effects:
        if effect_name not in EFFECT_PARSERS:
            print(f"No parser registered for {effect_name}, skipping")
            continue

        bin_path = FFT_EXTRACT / f"{effect_name}.BIN"
        if not bin_path.exists():
            print(f"BIN file not found: {bin_path}")
            continue

        output_dir = ASSETS_DIR / effect_name
        print(f"Parsing {effect_name} from {bin_path}...")
        EFFECT_PARSERS[effect_name](bin_path, output_dir)

    print("Done.")


if __name__ == "__main__":
    main()
