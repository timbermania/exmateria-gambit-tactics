#!/usr/bin/env python3
"""
FFT Batch Sprite Extractor — ROM-faithful named SPR inputs.

The PSX disc stores per-unit sprites under descriptive filenames
(`RAMUZA.SPR`, `MINA_M.SPR`, `ADORA.SPR`, …) — what FFT's developers
authored. The sprite_id ↔ filename mapping is ROM-derived from
BATTLE.BIN's sprite-LBA table at offset 0x2DCD4 (parsed by
`build_sprite_file_map.py` into `assets/sprites/sprite_files.json`).

Two input categories, dispatched by mapping presence:

1. **Per-unit body sprites** — files listed in `sprite_files.json`.
   Output: `(sprite_id_hex).tga` + `(sprite_id_hex).palette.tga` — keyed
   by FFT sprite_id (0x01..0x9A), per ADR-0022's paletted-at-runtime
   approach. Downstream consumers (JobDatabase, material loader, Godot
   importer) keep their sprite_id-keyed lookups working unchanged.

2. **System SPRs** (`WEP.SPR`, `OTHER.SPR`) — container files with
   multiple sub-regions. The `extract_spr` helper knows about the
   sub-region offsets and emits multiple .tga outputs per container
   (e.g. `WEP1.tga`, `EFF1.tga`, `TRAP1.tga`).

Anything else is an error — no silent fallback (the bug that produced
wrong-aligned textures pre-refactor).

Hand-authored display labels (Male Squire, Chocobo, …) live in
JobDatabase (`src/data/JobDatabase.gd`'s `SPRITE_NAMES`). The principle:
ROM-derived extraction and hand-authored semantic labels never mix at
the extraction boundary.

Usage:
    python extract_all_sprites.py [<fft-extract>] [<output-dir>]
        # defaults: project-assets/fft-extract, ../assets/sprites/textures
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Single-file SPR decoder (palette decode + sub-region emit for WEP/OTHER).
# extract_spr_indexed (ADR-0022) emits indexed.tga + palette.tga for body
# sprites; extract_spr stays for WEP/OTHER (RGBA-baked).
from extract_spr import extract_spr, extract_spr_indexed

# Named system SPRs we know how to handle (container files with sub-regions).
# Anything not in this set and not in sprite_files.json triggers an error.
NAMED_SYSTEM_SPRS = {"WEP", "OTHER"}

# ROM-derived filename → sprite_id index, built by build_sprite_file_map.py.
SPRITE_FILES_JSON = "sprite_files.json"


def load_filename_to_sprite_id(path: Path) -> dict[str, int]:
    """Read sprite_files.json and invert filename → sprite_id (int)."""
    if not path.exists():
        raise SystemExit(
            f"\nERROR: {path} not found.\n"
            f"  Run tools/build_sprite_file_map.py first to derive the "
            f"ROM-faithful sprite_id ↔ filename mapping from BATTLE.BIN."
        )
    data = json.loads(path.read_text())
    return {entry["filename"].upper(): int(sid_hex, 16) for sid_hex, entry in data.items()}


def extract_body_sprite(spr_file: Path, sprite_id: int, output_dir: Path) -> int:
    """Extract one body SPR keyed to one sprite_id. Returns 1/0 for success/fail."""
    indexed_basename = f"{sprite_id:02X}.tga"
    palette_basename = f"{sprite_id:02X}.palette.tga"
    indexed_path = output_dir / indexed_basename
    palette_path = output_dir / palette_basename
    print(f"  {spr_file.name}  →  {indexed_basename} + {palette_basename}  (FFT sprite_id 0x{sprite_id:02X})")
    try:
        extract_spr_indexed(str(spr_file), str(indexed_path), str(palette_path))
        return 1
    except Exception as e:
        print(f"    ERROR: {e}")
        return 0


def extract_one(spr_file: Path, output_dir: Path, filename_to_sid: dict[str, int],
                portrait_palette: int) -> int:
    """Extract a single non-body SPR (system container). Body sprites are
    iterated by mapping in extract_all_sprites — they may be referenced by
    multiple sprite_ids (e.g. MINA_M.SPR backs 8 slots) and need one output
    per sprite_id, which a file-iter loop can't express cleanly.
    """
    stem = spr_file.stem.upper()

    if stem in NAMED_SYSTEM_SPRS:
        # Branch 2: system SPR — extract_spr knows about its sub-regions.
        # For WEP.SPR, extract_spr emits multiple .tga outputs (WEP1/EFF1/TRAP1)
        # from one input.
        output_basename = f"{stem}.tga"
        output_path = output_dir / output_basename
        print(f"  {spr_file.name}  →  {output_basename} (+ system sub-regions)")
        try:
            extract_spr(str(spr_file), str(output_path), portrait_palette=portrait_palette)
            return 1
        except Exception as e:
            print(f"    ERROR: {e}")
            return 0

    # Body sprite (listed in sprite_files.json) — extracted by the per-sprite_id
    # loop in extract_all_sprites, not here. Skip silently.
    if spr_file.name.upper() in filename_to_sid:
        return 1

    # Reject unrecognized formats. ADR-0021 discipline: extraction never silently
    # falls through to "best guess" — produce a clear error so the operator can
    # fix the source rather than ship wrong-aligned assets.
    raise SystemExit(
        f"\nERROR: SPR file {spr_file.name!r} not in sprite_files.json and not a "
        f"known system SPR ({sorted(NAMED_SYSTEM_SPRS)}).\n"
        f"  If this is a real disc file, BATTLE.BIN's sprite-LBA table doesn't "
        f"reference it — likely a system SPR. Add to NAMED_SYSTEM_SPRS and teach "
        f"extract_spr.py how to decode it, or regenerate sprite_files.json."
    )


def extract_all_sprites(fft_path: str, output_dir: str, sprite_files_json: Path,
                        portrait_palette: int = 8) -> None:
    fft_path = Path(fft_path)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    battle_dir = fft_path / "BATTLE"
    if not battle_dir.exists():
        print(f"Error: BATTLE directory not found at {battle_dir}")
        sys.exit(1)

    sprite_map_data = json.loads(sprite_files_json.read_text())
    filename_to_sid = {entry["filename"].upper(): int(sid_hex, 16)
                       for sid_hex, entry in sprite_map_data.items()}

    spr_files = sorted(battle_dir.glob("*.SPR"))
    if not spr_files:
        print(f"Error: No SPR files found in {battle_dir}")
        sys.exit(1)

    print(f"Found {len(spr_files)} SPR files in {battle_dir}")
    print(f"ROM mapping: {sprite_files_json} ({len(sprite_map_data)} sprite_id entries, "
          f"{len(filename_to_sid)} unique files)")
    print(f"Output directory: {output_path}")
    print()

    # Pass 1: body sprites — iterate the ROM-derived mapping. A single SPR file
    # can back multiple sprite_ids (e.g. MINA_M.SPR backs 8), so emit one output
    # per sprite_id. Decode happens once per call; the cost of decoding the same
    # file twice is sub-second so we don't dedupe.
    success = 0
    failed = 0
    for sid_hex, entry in sorted(sprite_map_data.items()):
        spr_path = battle_dir / entry["filename"]
        if not spr_path.exists():
            print(f"  WARN: {entry['filename']} for sprite_id 0x{sid_hex} not found on disk")
            failed += 1
            continue
        ok = extract_body_sprite(spr_path, int(sid_hex, 16), output_path)
        success += ok
        failed += (1 - ok)

    print()

    # Pass 2: system SPRs (WEP, OTHER) — file-keyed, container-with-sub-regions.
    for spr_file in spr_files:
        if spr_file.stem.upper() in NAMED_SYSTEM_SPRS:
            ok = extract_one(spr_file, output_path, filename_to_sid, portrait_palette)
            success += ok
            failed += (1 - ok)
            print()

    # Pass 3: any leftover SPR files not in the mapping and not system SPRs
    # surface as errors via extract_one.
    for spr_file in spr_files:
        fname_upper = spr_file.name.upper()
        stem = spr_file.stem.upper()
        if fname_upper in filename_to_sid or stem in NAMED_SYSTEM_SPRS:
            continue
        extract_one(spr_file, output_path, filename_to_sid, portrait_palette)

    print("=" * 60)
    print(f"Done.  Extracted: {success}  Failed: {failed}")
    print(f"Output: {output_path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    from _repo_paths import fft_extract_root as _fft_extract_root, assets_dir as _assets_dir
    _default_fft = _fft_extract_root()
    _default_out = _assets_dir("sprites/textures")
    _default_map = _assets_dir("sprites") / SPRITE_FILES_JSON
    parser.add_argument(
        "fft_path", nargs="?", default=str(_default_fft),
        help=f"Path to FFT extract directory (default: {_default_fft})",
    )
    parser.add_argument(
        "output_dir", nargs="?", default=str(_default_out),
        help=f"Output directory for TGA files (default: {_default_out})",
    )
    parser.add_argument(
        "--sprite-files-json", type=Path, default=_default_map,
        help=f"ROM-derived sprite_id↔filename map (default: {_default_map}). "
             f"Regenerate with tools/build_sprite_file_map.py.",
    )
    parser.add_argument(
        "--portrait-palette", type=int, default=8, metavar="ROW",
        help="Palette row (0-15) for portrait region. Default 8 = in-game portrait colours.",
    )
    args = parser.parse_args()

    if not Path(args.fft_path).exists():
        print(f"Error: FFT path not found: {args.fft_path}")
        return 1

    extract_all_sprites(args.fft_path, args.output_dir, args.sprite_files_json,
                        args.portrait_palette)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
