#!/usr/bin/env python3
"""Derive the canonical sprite_id ↔ SPR filename mapping from BATTLE.BIN + ISO.

Authority (Shishi's SpriteFileLocations.cs):
    BATTLE.BIN @ 0x2DCD4: 159 records × 8 bytes each
        bytes [0..3]  → sector (u24, LSB first) — absolute LBA on disc
        bytes [4..7]  → size (u32, LSB first) — file size in bytes

Each record corresponds to one sprite_id (0-indexed). We join sector against
the ISO9660 directory walk for /BATTLE/, which gives (filename, lba) for
every SPR file. The result is the ROM-faithful mapping — no Shishi naming
table, no FFTPatcher XML.

A sector value of 0 means "no sprite at this id" (a few gaps in the table).

Usage:
    python3 build_sprite_file_map.py
    (every path defaults through `_repo_paths`; pass --iso / --battle-bin /
    --out only to override)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _repo_paths  # noqa: E402

# The ISO9660 walk comes from `fft-iso-patcher`, which is a SIBLING package in
# the monorepo and a vendored copy in the standalone repo. Prefer the sibling so
# a monorepo edit is picked up immediately; fall back to `vendor/`, which
# tools/check_vendor_sync.py holds byte-identical to it.
_SIBLING = Path(__file__).resolve().parent.parent.parent / "fft-iso-patcher"
_VENDOR = Path(__file__).resolve().parent.parent / "vendor"
sys.path.insert(0, str(_SIBLING if (_SIBLING / "fft_iso_patcher").is_dir() else _VENDOR))
from fft_iso_patcher.iso9660 import _list_dir, root_dir_record
from fft_iso_patcher.iso_sectors import PsxDisc

SPRITE_TABLE_OFFSET = 0x2DCD4
NUM_SPRITES = 159
RECORD_SIZE = 8


def parse_battle_bin_sprite_table(battle_bin: Path) -> list[tuple[int, int]]:
    """Read 159 (sector, size) records from BATTLE.BIN."""
    data = battle_bin.read_bytes()
    records: list[tuple[int, int]] = []
    for i in range(NUM_SPRITES):
        off = SPRITE_TABLE_OFFSET + i * RECORD_SIZE
        sector = int.from_bytes(data[off : off + 3], "little")
        size = int.from_bytes(data[off + 4 : off + 8], "little")
        records.append((sector, size))
    return records


def list_battle_files(iso: Path) -> dict[int, tuple[str, int]]:
    """Walk the ISO's /BATTLE directory, return {lba: (filename, size)}."""
    disc = PsxDisc(iso)
    root = root_dir_record(disc)
    battle = None
    for rec in _list_dir(disc, root.lba, root.size_bytes):
        if rec.name in ("\x00", "\x01"):
            continue
        if rec.is_dir and rec.name.upper().startswith("BATTLE"):
            battle = rec
            break
    if not battle:
        raise SystemExit("No /BATTLE directory found on disc")

    files: dict[int, tuple[str, int]] = {}
    for rec in _list_dir(disc, battle.lba, battle.size_bytes):
        if rec.name in ("\x00", "\x01"):
            continue
        clean_name = rec.name.rstrip(";1") if rec.name.endswith(";1") else rec.name
        files[rec.lba] = (clean_name, rec.size_bytes)
    return files


def build_mapping(iso: Path, battle_bin: Path) -> dict[str, dict]:
    """Join BATTLE.BIN's sprite table with the ISO directory."""
    sprite_records = parse_battle_bin_sprite_table(battle_bin)
    lba_to_file = list_battle_files(iso)

    out: dict[str, dict] = {}
    misses: list[int] = []
    for sprite_id, (sector, size) in enumerate(sprite_records):
        if sector == 0:
            # Table gap — no sprite at this id.
            continue
        if sector not in lba_to_file:
            misses.append(sprite_id)
            continue
        fname, fsize = lba_to_file[sector]
        out[f"{sprite_id:02X}"] = {
            "filename": fname,
            "sector": sector,
            "size": size,
        }
    if misses:
        sys.stderr.write(
            f"warning: {len(misses)} sprite_id(s) had sectors not in ISO directory: "
            f"{[f'0x{m:02X}' for m in misses]}\n"
        )
    return out


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--iso", type=Path, default=None,
                   help="FFT PSX ISO (default: $FFT_ISO or project-assets/)")
    p.add_argument("--battle-bin", type=Path, default=None,
                   help="extracted BATTLE.BIN (default: the resolved extract)")
    p.add_argument("--out", type=Path,
                   default=_repo_paths.assets_dir("sprites") / "sprite_files.json",
                   help="Output JSON path")
    args = p.parse_args()

    mapping = build_mapping(_repo_paths.iso(args.iso),
                            _repo_paths.battle_bin(args.battle_bin))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(mapping, indent=2) + "\n")
    print(f"wrote {args.out} ({len(mapping)} entries)")

    # Spot-check known sprites for sanity.
    checkpoints = {"01": "RAMUZA", "60": "MINA_M", "41": "ARUTE"}
    print("checkpoints:")
    for sid, expected_stem in checkpoints.items():
        entry = mapping.get(sid)
        actual = entry["filename"] if entry else "(missing)"
        marker = "✓" if entry and actual.upper().startswith(expected_stem) else "✗"
        print(f"  {marker} sprite_id 0x{sid}: expected {expected_stem}.SPR, got {actual}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
