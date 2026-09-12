#!/usr/bin/env python3
"""
Bulk Effect Audio Capture - captures audio from all FFT effect files.

Prerequisites:
    1. PCSX-Redux running
    2. Effect editor loaded: dofile("...main.lua")
    3. Base session available (e.g., protect_no_sound)

Usage:
    python bulk_capture_audio.py
    python bulk_capture_audio.py --effect-dir "C:/path/to/effects" --output-dir "C:/path/to/output"

Output:
    Creates E###/ subdirectories with phase1.wav, foreach.wav, phase2.wav for each effect.
"""

import argparse
import signal
import sys
import time
from pathlib import Path

# Add this script's directory to path for capture_effect_audio module
sys.path.insert(0, str(Path(__file__).parent))

from capture_effect_audio import capture_isolated

# Global flag for pause request
pause_requested = False

def handle_sigint(signum, frame):
    """Handle Ctrl+C by setting pause flag instead of interrupting."""
    global pause_requested
    pause_requested = True
    print("\n  >>> Pause requested - will pause after current effect completes <<<")

# Install signal handler
signal.signal(signal.SIGINT, handle_sigint)

# Default paths
DEFAULT_EFFECT_DIR = Path("C:/Users/acurr/Documents/fft-extract/EFFECT")
DEFAULT_OUTPUT_DIR = Path("C:/Users/acurr/Documents/GitHub/godot-learning/assets/effects")
DEFAULT_SESSION = "protect_no_sound"

# Effects to skip (no sound data, crashes, or special cases)
SKIP_EFFECTS = {"E000", "E509", "E510"}


def get_effect_files(effect_dir: Path) -> list[Path]:
    """Get list of valid effect files to process."""
    effects = []
    for f in sorted(effect_dir.glob("E*.BIN")):
        # Skip blacklisted
        if f.stem in SKIP_EFFECTS:
            continue
        # Skip 0-byte files
        if f.stat().st_size == 0:
            continue
        effects.append(f)
    return effects


def main():
    parser = argparse.ArgumentParser(
        description="Bulk capture audio from all FFT effect files"
    )
    parser.add_argument(
        "--effect-dir",
        type=Path,
        default=DEFAULT_EFFECT_DIR,
        help=f"Directory containing E###.BIN files (default: {DEFAULT_EFFECT_DIR})"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for captures (default: {DEFAULT_OUTPUT_DIR})"
    )
    parser.add_argument(
        "--session",
        type=str,
        default=DEFAULT_SESSION,
        help=f"Base session name to use (default: {DEFAULT_SESSION})"
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=10.0,
        help="Seconds to wait for effect to complete (default: 10)"
    )
    parser.add_argument(
        "--start-from",
        type=str,
        help="Start from this effect number (e.g., E050)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List effects that would be captured without actually capturing"
    )
    args = parser.parse_args()

    # Get list of effects
    effects = get_effect_files(args.effect_dir)
    print(f"Found {len(effects)} effects to capture")

    # Filter to start from specific effect if requested
    if args.start_from:
        start_idx = None
        for i, f in enumerate(effects):
            if f.stem == args.start_from:
                start_idx = i
                break
        if start_idx is not None:
            effects = effects[start_idx:]
            print(f"Starting from {args.start_from} ({len(effects)} remaining)")
        else:
            print(f"Warning: {args.start_from} not found, processing all")

    if args.dry_run:
        print("\nDry run - would capture:")
        for f in effects:
            output_dir = args.output_dir / f.stem / "sounds"
            exists = (output_dir / "phase1.wav").exists()
            status = "[SKIP - exists]" if exists else "[CAPTURE]"
            print(f"  {f.stem} -> {output_dir} {status}")
        return

    # Process each effect
    global pause_requested
    captured = 0
    skipped = 0
    errors = 0

    for i, effect_file in enumerate(effects):
        effect_name = effect_file.stem  # e.g., "E001"
        output_dir = args.output_dir / effect_name / "sounds"

        # Check if user requested pause (Ctrl+C during previous effect)
        if pause_requested:
            print(f"\n{'='*60}")
            print("PAUSED - Press Enter to continue, or 'q' to quit:")
            print(f"{'='*60}")
            # Temporarily restore default handler for clean input
            signal.signal(signal.SIGINT, signal.default_int_handler)
            try:
                response = input().strip().lower()
            except KeyboardInterrupt:
                print("\nQuitting...")
                break
            # Reinstall our handler
            signal.signal(signal.SIGINT, handle_sigint)
            if response == 'q':
                print("Quitting...")
                break
            pause_requested = False

        print(f"\n{'='*60}")
        print(f"[{i+1}/{len(effects)}] Capturing {effect_name}")
        print(f"  (Press Ctrl+C to pause after this effect)")
        print(f"{'='*60}")

        # Skip if already captured
        if (output_dir / "phase1.wav").exists():
            print(f"  Already captured, skipping")
            skipped += 1
            continue

        try:
            capture_isolated(
                output_dir=output_dir,
                wait_seconds=args.wait,
                session=args.session,
                sound_source=effect_file
            )
            captured += 1

            # Clean up intermediate files
            for pattern in ["*_full.wav", "timestamps.json"]:
                for f in output_dir.glob(pattern):
                    f.unlink()
                    print(f"  Cleaned up: {f.name}")

        except Exception as e:
            print(f"  ERROR: {e}")
            errors += 1
            continue

        # Brief pause between effects
        time.sleep(1)

    print(f"\n{'='*60}")
    print(f"Bulk capture complete!")
    print(f"  Captured: {captured}")
    print(f"  Skipped (already exist): {skipped}")
    print(f"  Errors: {errors}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
