#!/usr/bin/env python3
"""
Layer Priority Table Parser

Extracts the animation layer priority table from BATTLE.BIN.

The layer priority table is stored at RAM address 0x80094548 (BATTLE.BIN offset 0x2D548).
Each entry consists of 4 x 32-bit words (16 bytes total), where only the low byte of
each word contains the layer index value (0-3).

Layer indices:
  - 0: Unit graphic
  - 1: Weapon graphic
  - 2: Effect graphic
  - 3: Status/damage text graphic

The array position indicates draw order (first = back/bottom, last = front/top).

There are 24 valid entries (indices 0-23). Entries 24-26 are documented as "erroneous"
and are not used by the game.

Reference: FFHacktics wiki "Animation layer priority"
Source: PSX RAM address 0x80094548

Usage:
    python tools/parse_layer_priority.py
    python tools/parse_layer_priority.py /path/to/BATTLE.BIN
"""

import json
import sys
from pathlib import Path
from typing import List, Dict

# =============================================================================
# Configuration
# =============================================================================

# Default input path — resolves to project-assets/fft-extract/BATTLE.BIN.
from _repo_paths import battle_bin as _battle_bin
DEFAULT_BATTLE_PATH = _battle_bin()

# Default output path
DEFAULT_OUTPUT_PATH = Path(__file__).parent.parent / "assets" / "sprites" / "layer_priority.json"

# =============================================================================
# Memory Layout Constants
# =============================================================================

# BATTLE.BIN loads at RAM 0x80067000
# Layer priority table at RAM 0x80094548
# Offset = 0x80094548 - 0x80067000 = 0x2D548
BATTLE_BIN_RAM_BASE = 0x80067000
LAYER_PRIORITY_RAM = 0x80094548
LAYER_PRIORITY_OFFSET = LAYER_PRIORITY_RAM - BATTLE_BIN_RAM_BASE  # 0x2D548

# Number of valid entries (0-23)
NUM_ENTRIES = 24

# Each entry is 4 x 32-bit words = 16 bytes
ENTRY_SIZE = 16


# =============================================================================
# Parser
# =============================================================================

def parse_layer_priority_table(battle_bin_path: Path) -> Dict[str, List[int]]:
    """
    Parse the layer priority table from BATTLE.BIN.

    Args:
        battle_bin_path: Path to BATTLE.BIN file

    Returns:
        Dictionary mapping entry index (as string) to list of 4 layer indices
    """
    with open(battle_bin_path, 'rb') as f:
        f.seek(LAYER_PRIORITY_OFFSET)
        data = f.read(NUM_ENTRIES * ENTRY_SIZE)

    table = {}
    for entry_idx in range(NUM_ENTRIES):
        entry_offset = entry_idx * ENTRY_SIZE
        # Read low byte of each 32-bit word
        values = [
            data[entry_offset + i * 4]
            for i in range(4)
        ]
        table[str(entry_idx)] = values

    return table


def save_json(table: Dict[str, List[int]], output_path: Path) -> None:
    """Save table to JSON file with proper formatting."""
    with open(output_path, 'w') as f:
        json.dump(table, f, indent=4)
    print(f"Saved {len(table)} entries to {output_path}")


def main():
    # Parse command line arguments
    if len(sys.argv) > 1:
        battle_bin_path = Path(sys.argv[1])
    else:
        battle_bin_path = DEFAULT_BATTLE_PATH

    if not battle_bin_path.exists():
        print(f"Error: BATTLE.BIN not found at {battle_bin_path}")
        sys.exit(1)

    print(f"Parsing layer priority table from {battle_bin_path}")
    print(f"  RAM address: 0x{LAYER_PRIORITY_RAM:08X}")
    print(f"  File offset: 0x{LAYER_PRIORITY_OFFSET:X}")
    print()

    # Parse the table
    table = parse_layer_priority_table(battle_bin_path)

    # Display the table
    print("Layer Priority Table:")
    print("  Index | Values [unit, weapon, effect, text]")
    print("  ------+-------------------------------------")
    for i in range(NUM_ENTRIES):
        values = table[str(i)]
        print(f"  {i:5d} | {values}")
    print()

    # Save to JSON
    save_json(table, DEFAULT_OUTPUT_PATH)


if __name__ == "__main__":
    main()
