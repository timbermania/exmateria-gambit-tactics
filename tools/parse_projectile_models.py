#!/usr/bin/env python3
"""
Projectile Model Parser - Extracts 3D polygon models from BATTLE.BIN

These models are used for projectile effects (arrows, stones, reflect shields).
They use Gouraud-shaded polygons without textures.

Model Locations in BATTLE.BIN:
  Arrow:   0x14F9DC (RAM: 0x801B69DC)
  Stone:   0x14FD00 (RAM: 0x801B6D00)
  Reflect: 0x14FF00 (RAM: 0x801B6F00)
  Unknown: 0x1503B8 (RAM: 0x801B73B8)

Header Format (40 bytes):
  Offset 0x00: uint32 magic (0x41)
  Offset 0x04: uint32 reserved
  Offset 0x08: uint32 type
  Offset 0x0C: uint32 vertex_offset (relative to this field)
  Offset 0x10: uint32 vertex_count
  Offset 0x14: uint32 vertex_data_size
  Offset 0x18: uint32 reserved
  Offset 0x1C: uint32 face_stride (28 for quads, 24 for tris)
  Offset 0x20: uint32 face_count
  Offset 0x24: uint32 reserved

Vertex Format (8 bytes):
  int16 x, int16 y, int16 z, int16 flags

Face Format (24, 28, or 36 bytes):
  Triangle (type 0x06):        24 bytes - 4 header, 3x4 colors, 3x2 indices + 2 pad
  Quad (type 0x08):            28 bytes - 4 header, 4x4 colors, 4x2 indices
  Triangle+Normals (type 0x09): 36 bytes - 4 header, 3x4 normals, 3x4 colors, 3x2 indices + 2 pad

Usage:
    uv run python tools/parse_projectile_models.py [BATTLE.BIN path]
    uv run python tools/parse_projectile_models.py --table  # ASCII table output
    uv run python tools/parse_projectile_models.py -o assets/projectiles/projectile_models.json
"""

import sys
import os
import json
import struct
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Optional

# Model locations in BATTLE.BIN
MODEL_LOCATIONS = {
    'arrow':   {'file_offset': 0x14F9DC, 'ram_address': 0x801B69DC},
    'stone':   {'file_offset': 0x14FD00, 'ram_address': 0x801B6D00},
    'reflect': {'file_offset': 0x14FF00, 'ram_address': 0x801B6F00},
    'unknown': {'file_offset': 0x1503B8, 'ram_address': 0x801B73B8},
}

# Header size
HEADER_SIZE = 40

# Face type codes
FACE_TYPE_TRI = 0x06        # Triangle (3 vertices), 24 bytes
FACE_TYPE_QUAD = 0x08       # Quad (4 vertices), 28 bytes
FACE_TYPE_TRI_NORMAL = 0x09 # Triangle with normals (3 vertices), 36 bytes


@dataclass
class Vertex:
    """3D vertex with position and flags."""
    x: int
    y: int
    z: int
    flags: int = 0

    def to_list(self) -> List[int]:
        return [self.x, self.y, self.z]


@dataclass
class FaceColor:
    """RGB color for a face vertex."""
    r: int
    g: int
    b: int

    def to_list(self) -> List[int]:
        return [self.r, self.g, self.b]


@dataclass
class Face:
    """Polygon face with vertex indices and per-vertex colors."""
    indices: List[int]
    colors: List[FaceColor]
    face_type: int  # 0x06=tri, 0x08=quad

    @property
    def is_quad(self) -> bool:
        return self.face_type == FACE_TYPE_QUAD

    @property
    def is_triangle(self) -> bool:
        return self.face_type in (FACE_TYPE_TRI, FACE_TYPE_TRI_NORMAL)

    @property
    def has_normals(self) -> bool:
        return self.face_type == FACE_TYPE_TRI_NORMAL

    def to_dict(self) -> dict:
        type_name = 'quad' if self.is_quad else ('tri_normal' if self.has_normals else 'tri')
        return {
            'indices': self.indices,
            'colors': [c.to_list() for c in self.colors],
            'type': type_name
        }


@dataclass
class ProjectileModel:
    """Complete 3D model for a projectile."""
    name: str
    file_offset: int
    ram_address: int
    vertices: List[Vertex] = field(default_factory=list)
    faces: List[Face] = field(default_factory=list)

    @property
    def vertex_count(self) -> int:
        return len(self.vertices)

    @property
    def face_count(self) -> int:
        return len(self.faces)

    @property
    def tri_count(self) -> int:
        return sum(1 for f in self.faces if f.is_triangle)

    @property
    def quad_count(self) -> int:
        return sum(1 for f in self.faces if f.is_quad)

    def to_dict(self) -> dict:
        return {
            'file_offset': f'0x{self.file_offset:X}',
            'ram_address': f'0x{self.ram_address:X}',
            'vertex_count': self.vertex_count,
            'face_count': self.face_count,
            'vertices': [v.to_list() for v in self.vertices],
            'faces': [f.to_dict() for f in self.faces]
        }


def parse_model(data: bytes, offset: int, name: str, ram_address: int) -> ProjectileModel:
    """Parse a single 3D model from BATTLE.BIN data."""
    model = ProjectileModel(
        name=name,
        file_offset=offset,
        ram_address=ram_address
    )

    # Read header
    header = data[offset:offset + HEADER_SIZE]
    magic = struct.unpack_from('<I', header, 0)[0]

    # Vertex offset is at byte 12, relative to that field position
    vertex_offset_rel = struct.unpack_from('<I', header, 12)[0]
    vertex_count = struct.unpack_from('<I', header, 16)[0]

    # Calculate absolute vertex position
    vertex_offset_abs = offset + 12 + vertex_offset_rel

    # Parse vertices (8 bytes each: int16 x, y, z, flags)
    for i in range(vertex_count):
        v_off = vertex_offset_abs + (i * 8)
        x, y, z, flags = struct.unpack_from('<hhhh', data, v_off)
        model.vertices.append(Vertex(x, y, z, flags))

    # Parse faces - they start after the header
    face_offset = offset + HEADER_SIZE

    # Parse faces until we reach vertex data
    while face_offset < vertex_offset_abs - 8:
        # Read face type from first byte
        face_type = data[face_offset]

        if face_type == FACE_TYPE_QUAD:
            # Quad: 28 bytes
            # 4 bytes header, 4x4 bytes colors, 4x2 bytes indices
            colors = []
            for c in range(4):
                color_off = face_offset + 4 + (c * 4)
                r, g, b = data[color_off], data[color_off + 1], data[color_off + 2]
                colors.append(FaceColor(r, g, b))

            indices = []
            for idx in range(4):
                idx_off = face_offset + 20 + (idx * 2)
                indices.append(struct.unpack_from('<H', data, idx_off)[0])

            model.faces.append(Face(indices, colors, face_type))
            face_offset += 28

        elif face_type == FACE_TYPE_TRI:
            # Triangle: 24 bytes
            # 4 bytes header, 3x4 bytes colors, 3x2 bytes indices + 2 pad
            colors = []
            for c in range(3):
                color_off = face_offset + 4 + (c * 4)
                r, g, b = data[color_off], data[color_off + 1], data[color_off + 2]
                colors.append(FaceColor(r, g, b))

            indices = []
            for idx in range(3):
                idx_off = face_offset + 16 + (idx * 2)
                indices.append(struct.unpack_from('<H', data, idx_off)[0])

            model.faces.append(Face(indices, colors, face_type))
            face_offset += 24

        elif face_type == FACE_TYPE_TRI_NORMAL:
            # Triangle with normals: 36 bytes
            # 4 bytes header, 3x4 bytes normals (skipped), 3x4 bytes colors, 3x2 bytes indices + 2 pad
            colors = []
            for c in range(3):
                # Colors start after header (4) + normals (12) = offset 16
                color_off = face_offset + 16 + (c * 4)
                r, g, b = data[color_off], data[color_off + 1], data[color_off + 2]
                colors.append(FaceColor(r, g, b))

            indices = []
            for idx in range(3):
                # Indices start after header (4) + normals (12) + colors (12) = offset 28
                idx_off = face_offset + 28 + (idx * 2)
                indices.append(struct.unpack_from('<H', data, idx_off)[0])

            model.faces.append(Face(indices, colors, face_type))
            face_offset += 36

        else:
            # Unknown face type, stop parsing
            break

    return model


def parse_all_models(battle_bin_path: str) -> Dict[str, ProjectileModel]:
    """Parse all projectile models from BATTLE.BIN."""
    with open(battle_bin_path, 'rb') as f:
        data = f.read()

    models = {}
    for name, loc in MODEL_LOCATIONS.items():
        model = parse_model(data, loc['file_offset'], name, loc['ram_address'])
        models[name] = model

    return models


def models_to_json(models: Dict[str, ProjectileModel], indent: int = 2) -> str:
    """Convert models to JSON string."""
    output = {
        'format_notes': {
            'description': 'PSX 3D polygon models for projectiles (Gouraud shaded, no textures)',
            'source': 'BATTLE.BIN',
            'vertex_format': '8 bytes: int16 x, int16 y, int16 z, int16 flags',
            'face_format': 'Tri (24 bytes) or Quad (28 bytes): header + RGB colors + vertex indices',
            'color_note': 'Colors are per-vertex for Gouraud interpolation across face'
        },
        'models': {name: model.to_dict() for name, model in models.items()}
    }
    return json.dumps(output, indent=indent)


def print_table(models: Dict[str, ProjectileModel], file=None):
    """Print models as ASCII table."""
    print('┌──────────┬────────────┬────────────────┬──────────┬────────┬──────┬───────┐', file=file)
    print('│ Model    │ Offset     │ RAM Address    │ Vertices │ Faces  │ Tris │ Quads │', file=file)
    print('├──────────┼────────────┼────────────────┼──────────┼────────┼──────┼───────┤', file=file)

    for name, model in models.items():
        print(f'│ {name:8} │ 0x{model.file_offset:06X}  │ 0x{model.ram_address:08X}  │ {model.vertex_count:8} │ {model.face_count:6} │ {model.tri_count:4} │ {model.quad_count:5} │', file=file)

    print('└──────────┴────────────┴────────────────┴──────────┴────────┴──────┴───────┘', file=file)

    # Print each model's details
    for name, model in models.items():
        print(f'\n=== {name.upper()} Model ===\n', file=file)

        print('Vertices:', file=file)
        for i, v in enumerate(model.vertices):
            print(f'  {i:2}: ({v.x:5}, {v.y:5}, {v.z:5})', file=file)

        print('\nFaces:', file=file)
        for i, f in enumerate(model.faces):
            type_str = 'Q' if f.is_quad else 'T'
            indices_str = ', '.join(str(idx) for idx in f.indices)
            colors_str = ' | '.join(f'({c.r:3},{c.g:3},{c.b:3})' for c in f.colors)
            print(f'  {i:2} [{type_str}]: indices=[{indices_str}] colors=[{colors_str}]', file=file)


def get_default_battle_bin_path() -> str:
    """Default BATTLE.BIN — resolves to <repo>/project-assets/fft-extract via
    _repo_paths (CLI/env/repo), host-agnostic."""
    from _repo_paths import battle_bin as _battle_bin
    return str(_battle_bin())


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Parse projectile 3D models from BATTLE.BIN')
    parser.add_argument('battle_bin', nargs='?', default=None, help='Path to BATTLE.BIN')
    parser.add_argument('--table', action='store_true', help='Output as ASCII table instead of JSON')
    parser.add_argument('-o', '--output', default=None,
                        help='Output file path (default: the package asset; '
                             'pass "-" for stdout)')
    args = parser.parse_args()

    battle_bin_path = args.battle_bin or get_default_battle_bin_path()

    try:
        models = parse_all_models(battle_bin_path)
    except FileNotFoundError:
        print(f'Error: Could not find {battle_bin_path}', file=sys.stderr)
        sys.exit(1)

    # Default to the artifact the game loads. It used to default to STDOUT, so
    # `parse_projectile_models.py` with no -o printed 40 KB of JSON, exited 0 and
    # wrote nothing — a bootstrap line that reads `ok` while producing no asset.
    if args.output is None:
        from _repo_paths import assets_dir as _assets_dir
        args.output = str(_assets_dir('projectiles') / 'projectile_models.json')
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    elif args.output == '-':
        args.output = None

    if args.table:
        if args.output:
            with open(args.output, 'w') as f:
                print_table(models, file=f)
        else:
            print_table(models)
    else:
        output = models_to_json(models)
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output)
        else:
            print(output)


if __name__ == '__main__':
    main()
