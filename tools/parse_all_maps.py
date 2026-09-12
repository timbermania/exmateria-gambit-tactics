#!/usr/bin/env python3
"""
FFT Map Batch Parser - Parse all maps from a source directory.

Scans a directory for .GNS files and parses each one to the maps folder.

Usage:
    python tools/parse_all_maps.py /path/to/fft-extract/MAP/
    python tools/parse_all_maps.py /path/to/fft-extract/MAP/ --force
"""

import argparse
import sys
import time
from pathlib import Path

# Add tools directory to path for imports
TOOLS_DIR = Path(__file__).parent
sys.path.insert(0, str(TOOLS_DIR))

from parse_map import parse_map, DEFAULT_OUTPUT_BASE


def parse_all_maps(
    source_dir: Path,
    output_base: Path = None,
    force: bool = False,
    verbose: bool = False,
) -> dict:
    """
    Parse all .GNS files in source directory.

    Args:
        source_dir: Directory containing .GNS files
        output_base: Base directory for output (default: assets/maps)
        force: Re-parse even if output already exists
        verbose: Enable verbose logging

    Returns:
        Dict with success/failure counts and details
    """
    if output_base is None:
        output_base = DEFAULT_OUTPUT_BASE

    # Find all .GNS files
    gns_files = sorted(source_dir.glob("*.GNS"))

    if not gns_files:
        # Try lowercase
        gns_files = sorted(source_dir.glob("*.gns"))

    if not gns_files:
        print(f"ERROR: No .GNS files found in {source_dir}")
        return {"success": [], "failed": [], "skipped": []}

    print(f"\n{'=' * 60}")
    print(f"FFT MAP BATCH PARSER")
    print(f"{'=' * 60}")
    print(f"\nSource: {source_dir}")
    print(f"Output: {output_base}")
    print(f"Maps found: {len(gns_files)}")
    print(f"Force: {force}")
    print()

    results = {
        "success": [],
        "failed": [],
        "skipped": [],
    }

    start_time = time.time()

    for i, gns_file in enumerate(gns_files, 1):
        map_name = gns_file.stem.upper()
        output_dir = output_base / map_name

        print(f"\n[{i}/{len(gns_files)}] {map_name}")

        # Check if already generated
        if output_dir.exists() and not force:
            # Check if it has the required files
            required_files = [
                "terrain.json",
                "geometry_linked.json",
                "palettes.json",
                "manifest.json",
                "texture_indexed.tga",
            ]
            all_present = all((output_dir / f).exists() for f in required_files)

            if all_present:
                print(f"  Skipped: Already generated (use --force to re-parse)")
                results["skipped"].append(map_name)
                continue

        # Parse the map
        try:
            success = parse_map(gns_file, output_dir, verbose)
            if success:
                results["success"].append(map_name)
            else:
                results["failed"].append(map_name)
        except Exception as e:
            print(f"  ERROR: {e}")
            results["failed"].append(map_name)

    elapsed = time.time() - start_time

    # Summary
    print(f"\n{'=' * 60}")
    print(f"BATCH PARSING COMPLETE")
    print(f"{'=' * 60}")
    print(f"\nTotal time: {elapsed:.1f}s")
    print(f"Success: {len(results['success'])}")
    print(f"Failed: {len(results['failed'])}")
    print(f"Skipped: {len(results['skipped'])}")

    if results["failed"]:
        print(f"\nFailed maps:")
        for name in results["failed"]:
            print(f"  - {name}")

    if results["success"]:
        print(f"\nOutput directory: {output_base}")

    print()

    return results


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Parse all FFT map files (.GNS) from a directory",
        prog="parse_all_maps",
    )
    parser.add_argument(
        "source_dir",
        type=Path,
        help="Directory containing .GNS map files",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output base directory (default: assets/maps)",
    )
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Re-parse maps even if output already exists",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output",
    )

    args = parser.parse_args()

    # Validate source directory
    if not args.source_dir.exists():
        print(f"ERROR: Directory not found: {args.source_dir}")
        sys.exit(1)

    if not args.source_dir.is_dir():
        print(f"ERROR: Not a directory: {args.source_dir}")
        sys.exit(1)

    # Run batch processing
    results = parse_all_maps(
        args.source_dir,
        args.output,
        args.force,
        args.verbose,
    )

    # Exit with error if any failed
    if results["failed"]:
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
