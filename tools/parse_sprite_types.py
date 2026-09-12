#!/usr/bin/env python3
"""
Sprite Type Parser - Maps sprite IDs to their SHP/SEQ types

The sprite attribute table is stored in BATTLE.BIN at offset 0x2D748.
Each sprite has 4 bytes:
  - Byte 0: SHP type (shape/visual format)
  - Byte 1: SEQ type (animation sequence format)
  - Byte 2: Flying flag (0 or 1)
  - Byte 3: Height

Usage:
    python3 sprite_type_parser.py [BATTLE.BIN path]
    python3 sprite_type_parser.py  # Uses default fft-extract path
"""

import sys
import os
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, Optional

# Sprite type enum (matches ShishiSpriteEditor)
SPRITE_TYPES = {
    0: 'TYPE1',
    1: 'TYPE2',
    2: 'CYOKO',
    3: 'MON',
    4: 'OTHER',
    5: 'RUKA',
    6: 'ARUTE',
    7: 'KANZEN',
    8: 'WEP1',
    9: 'WEP2',
    10: 'EFF1',
    11: 'EFF2',
}

# SEQ file mapping - some types use a different SEQ than their type name
# Reference: TYPE2 uses TYPE2.SHP but TYPE3.SEQ
SEQ_FILE_MAPPING = {
    'TYPE1': 'TYPE1',
    'TYPE2': 'TYPE3',  # TYPE2 sprites use TYPE3.SEQ
    'CYOKO': 'CYOKO',
    'MON': 'MON',
    'OTHER': 'OTHER',
    'RUKA': 'RUKA',
    'ARUTE': 'ARUTE',
    'KANZEN': 'KANZEN',
}

# Reverse lookup
SPRITE_TYPE_VALUES = {v: k for k, v in SPRITE_TYPES.items()}

# Offset in BATTLE.BIN where sprite attributes start
SPRITE_ATTR_OFFSET = 0x2D748

# Number of sprite entries (PSX)
NUM_SPRITES = 159


@dataclass
class SpriteAttributes:
    """Attributes for a single sprite."""
    sprite_id: int
    shp_type: int
    seq_type: int
    flying: bool
    height: int

    @property
    def shp_name(self) -> str:
        """Get SHP type name."""
        return SPRITE_TYPES.get(self.shp_type, f'UNK({self.shp_type})')

    @property
    def seq_name(self) -> str:
        """Get SEQ type name (mapped to actual SEQ file used)."""
        raw_type = SPRITE_TYPES.get(self.seq_type, f'UNK({self.seq_type})')
        # Apply SEQ file mapping (e.g., TYPE2 -> TYPE3)
        return SEQ_FILE_MAPPING.get(raw_type, raw_type)

    @property
    def shp_file(self) -> str:
        """Get the SHP filename this sprite uses."""
        return f'{self.shp_name}.SHP'

    @property
    def seq_file(self) -> str:
        """Get the SEQ filename this sprite uses."""
        return f'{self.seq_name}.SEQ'

    @property
    def spr_file(self) -> str:
        """Get the SPR filename for this sprite."""
        return f'{self.sprite_id:02X}.SPR'

    def __str__(self) -> str:
        fly_str = 'Yes' if self.flying else 'No'
        return (f'Sprite 0x{self.sprite_id:02X}: '
                f'SHP={self.shp_name}, SEQ={self.seq_name}, '
                f'Flying={fly_str}, Height={self.height}')

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            'shp': self.shp_name,
            'seq': self.seq_name,
            'flying': self.flying,
            'height': self.height,
            'shp_file': self.shp_file,
            'seq_file': self.seq_file,
            'spr_file': self.spr_file,
        }


class SpriteTypeTable:
    """Table mapping sprite IDs to their attributes."""

    def __init__(self):
        self.sprites: Dict[int, SpriteAttributes] = {}

    def __getitem__(self, sprite_id: int) -> SpriteAttributes:
        """Get sprite by ID (supports both int and hex string)."""
        if isinstance(sprite_id, str):
            sprite_id = int(sprite_id, 16)
        return self.sprites[sprite_id]

    def __contains__(self, sprite_id: int) -> bool:
        if isinstance(sprite_id, str):
            sprite_id = int(sprite_id, 16)
        return sprite_id in self.sprites

    def __iter__(self):
        return iter(self.sprites.values())

    def __len__(self):
        return len(self.sprites)

    def get(self, sprite_id: int, default=None) -> Optional[SpriteAttributes]:
        """Get sprite by ID with optional default."""
        if isinstance(sprite_id, str):
            sprite_id = int(sprite_id, 16)
        return self.sprites.get(sprite_id, default)

    def by_shp_type(self, shp_type: str) -> list:
        """Get all sprites with a specific SHP type."""
        return [s for s in self.sprites.values() if s.shp_name == shp_type]

    def by_seq_type(self, seq_type: str) -> list:
        """Get all sprites with a specific SEQ type."""
        return [s for s in self.sprites.values() if s.seq_name == seq_type]

    def flying_sprites(self) -> list:
        """Get all sprites with flying=True."""
        return [s for s in self.sprites.values() if s.flying]

    def to_dict(self) -> dict:
        """Convert to dictionary with hex string keys."""
        return {
            f'{sprite_id:02X}': attrs.to_dict()
            for sprite_id, attrs in self.sprites.items()
        }

    def to_json(self, indent: int = 2) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict(), indent=indent)

    def save_json(self, filepath: str):
        """Save to JSON file."""
        with open(filepath, 'w') as f:
            f.write(self.to_json())

    @classmethod
    def from_battle_bin(cls, battle_bin_path: str) -> 'SpriteTypeTable':
        """Parse sprite attributes from BATTLE.BIN."""
        table = cls()

        with open(battle_bin_path, 'rb') as f:
            f.seek(SPRITE_ATTR_OFFSET)
            data = f.read(NUM_SPRITES * 4)

        for i in range(NUM_SPRITES):
            offset = i * 4
            attrs = SpriteAttributes(
                sprite_id=i,
                shp_type=data[offset],
                seq_type=data[offset + 1],
                flying=bool(data[offset + 2]),
                height=data[offset + 3],
            )
            table.sprites[i] = attrs

        return table

    def print_table(self, file=None):
        """Print the full table."""
        print('┌──────┬──────────┬──────────┬─────────┬────────┬─────────────┬─────────────┐', file=file)
        print('│  ID  │ SHP      │ SEQ      │ Flying  │ Height │ SHP File    │ SEQ File    │', file=file)
        print('├──────┼──────────┼──────────┼─────────┼────────┼─────────────┼─────────────┤', file=file)

        for sprite in self.sprites.values():
            fly_str = 'Yes' if sprite.flying else 'No'
            print(f'│ 0x{sprite.sprite_id:02X} │ {sprite.shp_name:8} │ {sprite.seq_name:8} │ {fly_str:7} │ {sprite.height:6} │ {sprite.shp_file:11} │ {sprite.seq_file:11} │', file=file)

        print('└──────┴──────────┴──────────┴─────────┴────────┴─────────────┴─────────────┘', file=file)

    def print_summary(self, file=None):
        """Print a summary of sprite types."""
        print('\n=== Sprite Type Summary ===\n', file=file)

        # Count by SHP type
        shp_counts = {}
        for sprite in self.sprites.values():
            name = sprite.shp_name
            shp_counts[name] = shp_counts.get(name, 0) + 1

        print('SHP Type Distribution:', file=file)
        for name, count in sorted(shp_counts.items(), key=lambda x: -x[1]):
            print(f'  {name:8}: {count:3} sprites', file=file)

        # Flying sprites
        flying = self.flying_sprites()
        print(f'\nFlying Sprites ({len(flying)}):', file=file)
        for s in flying:
            print(f'  0x{s.sprite_id:02X} ({s.shp_name}/{s.seq_name})', file=file)


def get_default_battle_bin_path() -> str:
    """Get default path to BATTLE.BIN — resolves via _repo_paths helper."""
    from _repo_paths import battle_bin as _battle_bin
    return str(_battle_bin())


#: Where the table belongs. Register step 15 / root ADR-0001: this artifact is
#: ISO DATA — `0x2D748` of the reader's own BATTLE.BIN — and was committed and
#: classified `hand-authored` for as long as it has existed, because this parser
#: defaulted to STDOUT and nothing wired it to the path the game loads. A
#: derivation nobody can re-derive in place reads as authored no matter what its
#: docstring says. Same shape as `parse_layer_priority.py`'s DEFAULT_OUTPUT_PATH.
DEFAULT_OUTPUT_PATH = (Path(__file__).parent.parent / "addons" / "exmateria_almanac"
                       / "sprites" / "sprite_types.json")


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Parse sprite type attributes from BATTLE.BIN')
    parser.add_argument('battle_bin', nargs='?', default=None, help='Path to BATTLE.BIN')
    parser.add_argument('--table', action='store_true', help='Output as ASCII table instead of JSON')
    parser.add_argument('-o', '--output',
                        help=f'Output file path (default: {DEFAULT_OUTPUT_PATH})')
    parser.add_argument('--stdout', action='store_true',
                        help='Print the JSON instead of writing the artifact')
    args = parser.parse_args()

    battle_bin_path = args.battle_bin or get_default_battle_bin_path()

    try:
        table = SpriteTypeTable.from_battle_bin(battle_bin_path)
    except FileNotFoundError:
        print(f'Error: Could not find {battle_bin_path}', file=sys.stderr)
        sys.exit(1)

    if args.table:
        if args.output:
            with open(args.output, 'w') as f:
                table.print_table(file=f)
                table.print_summary(file=f)
        else:
            table.print_table()
            table.print_summary()
    else:
        output = table.to_json()
        dest = Path(args.output) if args.output else DEFAULT_OUTPUT_PATH
        if args.stdout:
            print(output)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            # A trailing newline, which the committed file did NOT have. That one
            # byte is the whole difference between the old committed copy and a
            # fresh parse: `diff` reported "\ No newline at end of file" and
            # nothing else over 1,433 lines.
            dest.write_text(output + "\n")
            print(f'parse_sprite_types: {len(table.sprites)} sprites -> {dest}')


if __name__ == '__main__':
    main()
