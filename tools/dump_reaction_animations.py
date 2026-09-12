#!/usr/bin/env python3
"""
Dump FFT Reaction Animation Mappings

Parses SEQ files and creates a mapping from reaction types to animation sequences
for each unit type (TYPE1, TYPE3, MON, etc.)

The chain is:
  Reaction ID (e.g., 0x19 for flinch)
    → animation_ptr_id = reaction_id * 2 (front) or * 2 + 1 (back)
    → sequence_pointers[animation_ptr_id] → sequence_index
    → Animation name from animation_names.txt

Output: data/reaction_animations.json
"""

import csv
import json
import struct
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_paths import almanac_dir as _almanac_dir, battle_dir as _battle_dir  # noqa: E402

# Default paths
DEFAULT_SEQ_DIR = _battle_dir()
DEFAULT_ANIM_NAMES = Path(__file__).resolve().parent / "data" / "animation_names.txt"

# SEQ animation slot IDs from BATTLE.BIN execute_unit_reaction_pose
# These are positions in the 256-slot SEQ animation table (hence the gaps)
REACTION_IDS = {
    "evade": 0x18,              # 24 - Evade/Defend animation
    "taking_damage": 0x19,      # 25 - Flinch/damage animation
    "receive_heal": 0x1b,       # 27 - Receive heal animation (used for healing/raise)
    "shield_block_high": 0x58,  # 88 - Shield block high (hands up right)
    "shield_block_mid": 0x59,   # 89 - Shield block mid (hands up forward)
    "shield_block_low": 0x5a,   # 90 - Shield block low (hands up backward)
}

# Unit type to SEQ file mapping (from TacticsG/Seq.gd)
# Note: type2 and type4 are marked "Unused" in TacticsG but files exist
UNIT_SEQ_FILES = {
    "type1": "TYPE1.SEQ",
    "type2 (Unused)": "TYPE2.SEQ",
    "type3": "TYPE3.SEQ",
    "type4 (Unused)": "TYPE4.SEQ",
    "Monster/mon": "MON.SEQ",
    "Chocobo/cyoko": "CYOKO.SEQ",
    "Lucavi/ruka": "RUKA.SEQ",
    "Altima/arute": "ARUTE.SEQ",
    "Altima2/kanzen": "KANZEN.SEQ",
    "other": "OTHER.SEQ",
}

# SEQ file structure constants
SECTION1_LENGTH = 4      # Header: AA (2 bytes) + BB (2 bytes)
SECTION2_LENGTH = 0x400  # 1024 bytes = 256 x 4-byte pointers


def parse_seq_file(path: Path) -> list[int]:
    """Parse SEQ file and extract sequence_pointers from Section 2.

    SEQ file structure:
    - Section 1 (4 bytes): Header - AA, BB values
    - Section 2 (1024 bytes): sequence_pointers[256] - 4 bytes each
    - Section 3 (variable): Animation bytecode sequences

    Returns list of sequence pointers (indices into Section 3).
    """
    with open(path, 'rb') as f:
        data = f.read()

    if len(data) < SECTION1_LENGTH + SECTION2_LENGTH:
        raise ValueError(f"SEQ file too small: {path}")

    # Read sequence pointers from Section 2
    sequence_pointers = []
    for i in range(256):
        offset = SECTION1_LENGTH + (i * 4)
        ptr = struct.unpack_from('<I', data, offset)[0]
        if i > 0 and ptr == 0xFFFFFFFF:
            break  # End of pointers
        sequence_pointers.append(ptr)

    return sequence_pointers


def load_animation_names(path: Path) -> dict[str, dict[int, str]]:
    """Load animation names from animation_names.txt.

    Format: type,animation_id,animation_name

    Returns: {unit_type: {ptr_id: name}}
    """
    names: dict[str, dict[int, str]] = {}

    with open(path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)  # Skip header row

        for row in reader:
            if len(row) < 3:
                continue
            unit_type, anim_id_str, name = row[0], row[1], row[2]

            try:
                anim_id = int(anim_id_str)
            except ValueError:
                continue

            if unit_type not in names:
                names[unit_type] = {}
            names[unit_type][anim_id] = name

    return names


def build_reaction_mapping(
    sequence_pointers: list[int],
    animation_names: dict[int, str],
    unit_type: str
) -> dict:
    """Build reaction type to animation mapping for a unit type.

    For each SEQ animation ID:
    - front seq_ptr_index = seq_animation_id * 2
    - back seq_ptr_index = seq_animation_id * 2 + 1
    - seq_offset = sequence_pointers[seq_ptr_index]
    - name = animation_names[seq_ptr_index]
    """
    mapping = {}

    for reaction_name, seq_animation_id in REACTION_IDS.items():
        front_ptr_index = seq_animation_id * 2
        back_ptr_index = seq_animation_id * 2 + 1

        # Check if pointers are valid
        front_seq_offset = None
        back_seq_offset = None

        if front_ptr_index < len(sequence_pointers):
            front_seq_offset = sequence_pointers[front_ptr_index]
        if back_ptr_index < len(sequence_pointers):
            back_seq_offset = sequence_pointers[back_ptr_index]

        # Get names
        front_name = animation_names.get(front_ptr_index, "")
        back_name = animation_names.get(back_ptr_index, "")

        mapping[reaction_name] = {
            "seq_animation_id": seq_animation_id,
            "seq_animation_id_hex": f"0x{seq_animation_id:02X}",
            "front": {
                "seq_ptr_index": front_ptr_index,
                "seq_offset": front_seq_offset,
                "name": front_name,
            },
            "back": {
                "seq_ptr_index": back_ptr_index,
                "seq_offset": back_seq_offset,
                "name": back_name,
            }
        }

    return mapping


def dump_all(seq_dir: Path, anim_names_path: Path, output_dir: Path):
    """Dump reaction animation mappings for all unit types."""

    # Load animation names
    print(f"Loading animation names from {anim_names_path}...")
    all_anim_names = load_animation_names(anim_names_path)
    print(f"  Loaded names for {len(all_anim_names)} unit types")

    # Process each unit type
    result = {}

    for unit_type, seq_filename in UNIT_SEQ_FILES.items():
        seq_path = seq_dir / seq_filename

        if not seq_path.exists():
            print(f"  Warning: {seq_filename} not found, skipping {unit_type}")
            continue

        print(f"Processing {unit_type} ({seq_filename})...")

        # Parse SEQ file
        try:
            sequence_pointers = parse_seq_file(seq_path)
            print(f"  Found {len(sequence_pointers)} sequence pointers")
        except Exception as e:
            print(f"  Error parsing {seq_filename}: {e}")
            continue

        # Get animation names for this unit type
        anim_names = all_anim_names.get(unit_type, {})
        if not anim_names:
            print(f"  Warning: No animation names found for {unit_type}")

        # Build mapping
        mapping = build_reaction_mapping(sequence_pointers, anim_names, unit_type)

        result[unit_type] = {
            "seq_file": seq_filename,
            "total_pointers": len(sequence_pointers),
            "reactions": mapping,
        }

    # Write output
    output_path = output_dir / "reaction_animations.json"
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"\nWrote {output_path}")

    # Print summary
    print("\nSummary:")
    for unit_type, data in result.items():
        print(f"\n  {unit_type} ({data['seq_file']}):")
        for reaction_name, reaction_data in data['reactions'].items():
            front = reaction_data['front']
            print(f"    {reaction_name}: seq_ptr_index={front['seq_ptr_index']} -> \"{front['name']}\"")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Dump FFT reaction animation mappings")
    parser.add_argument("--seq-dir", type=Path, default=DEFAULT_SEQ_DIR,
                        help=f"Directory containing SEQ files (default: {DEFAULT_SEQ_DIR})")
    parser.add_argument("--anim-names", type=Path, default=DEFAULT_ANIM_NAMES,
                        help=f"Path to animation_names.txt (default: {DEFAULT_ANIM_NAMES})")
    parser.add_argument("--output", type=Path, default=_almanac_dir("sprites"),
                        help="Output directory for JSON files")
    args = parser.parse_args()

    if not args.seq_dir.exists():
        print(f"Error: SEQ directory not found: {args.seq_dir}")
        return 1

    if not args.anim_names.exists():
        print(f"Error: animation_names.txt not found: {args.anim_names}")
        return 1

    args.output.mkdir(parents=True, exist_ok=True)
    dump_all(args.seq_dir, args.anim_names, args.output)
    return 0


if __name__ == "__main__":
    exit(main())
