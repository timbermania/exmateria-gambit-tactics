#!/usr/bin/env python3
"""
Fire-and-forget: extract every E###.BIN into assets/effects/E###/.

Single pass per effect — JSON sections + texture.tga — using the authoritative
BATTLE.BIN header-offset table (handles DATA and CODE-format effects alike).

Usage:
    uv run python tools/parse_all_effects_py.py [--force] [--effect-dir PATH]

    --force            re-extract effects that already have output
    --effect-dir PATH  EFFECT/ directory inside the FFT extract. If omitted, uses
                       $FFT_EXTRACT/EFFECT, or falls back to the symlinked
                       project-assets/fft-extract/EFFECT relative to this script,
                       or finally to the legacy WSL default.
"""

import os
import sys
from pathlib import Path

# Import the shared single-effect extractor.
sys.path.insert(0, str(Path(__file__).parent))
from parse_effect import extract_effect


def _resolve_effect_dir() -> Path:
    """Locate the EFFECT/ directory.

    Priority: --effect-dir <path>  →  $FFT_EXTRACT/EFFECT  →
              <repo>/project-assets/fft-extract/EFFECT (via _repo_paths).
    """
    if "--effect-dir" in sys.argv:
        return Path(sys.argv[sys.argv.index("--effect-dir") + 1])
    from _repo_paths import effect_dir
    return effect_dir()


def main():
    force = "--force" in sys.argv

    effect_dir = _resolve_effect_dir()
    output_base = Path(__file__).resolve().parent.parent / "assets" / "effects"
    battle_bin = effect_dir.parent / "BATTLE.BIN"

    bin_files = sorted(effect_dir.glob("*.BIN"))
    total = len(bin_files)
    print(f"Found {total} effect files to parse")
    print()

    success = 0
    failed = 0
    skipped = 0
    empty = 0

    for i, bin_file in enumerate(bin_files, 1):
        effect_name = bin_file.stem
        output_dir = output_base / effect_name

        if not force and (output_dir / "emitters.json").exists():
            print(f"[{i}/{total}] {effect_name} - skipped (exists)")
            skipped += 1
            continue

        # Many slots are empty placeholder BINs (no effect assigned) — nothing to parse.
        if bin_file.stat().st_size == 0:
            print(f"[{i}/{total}] {effect_name} - empty (no data)")
            empty += 1
            continue

        print(f"[{i}/{total}] Parsing {effect_name}...", end=" ", flush=True)

        try:
            parsed = extract_effect(bin_file, output_dir, battle_bin=battle_bin)
            print(f"OK ({len(parsed['emitters'])} emitters)")
            success += 1
        except Exception as e:
            print(f"FAILED: {e}")
            failed += 1

    print()
    print(f"Done! Success: {success}, Failed: {failed}, Empty: {empty}, Skipped: {skipped}")


if __name__ == "__main__":
    main()
