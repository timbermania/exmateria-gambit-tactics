#!/usr/bin/env python3
"""
TRAP Effect System Parser — BATTLE.BIN + WEP.SPR → Godot JSON

Parses ALL TRAP particle configs baked into BATTLE.BIN — not just the hit
cloud (ThrowStone), but also spell charge shimmer, elemental puffs, summon
orbs, explosions, and beams. Outputs Godot-ready JSON files using the same
conventions as tools/parse_effect.py for E###.BIN files.

17 particle configs serve 5+ charge effect handlers:
  - Handler 2: Hit clouds (configs 0, 1, 9) — melee hits + ThrowStone
  - Handler 1: Spell charge shimmer (configs 3, 7, 8, 11)
  - Handler 3: Elemental charge puffs (configs 2, 6, 13)
  - Handler 4: Summon charge orbs/explosions (configs 4, 5, 10, 14, 15, 16)
  - Handler 5: Summon charge glow (config 12)

Data sources:
  - BATTLE.BIN (ISO-derived). It loads at RAM 0x80067000, so every address
    below is `file_offset = ram - 0x80067000`. This parser used to read a
    PCSX-Redux `SCUS94221_mem_wram.bin` capture off a hardcoded Windows
    AppData path; the capture was never necessary — the tables are on the
    disc. Same convention as parse_dialogue_box_curves.py /
    parse_number_popup.py. Two constants are NOT on the disc; see
    "Boot-written constants" below.
    - Frames section:    RAM 0x801b7690
    - Animation sequences: RAM 0x801b8320
    - Element RGB table: RAM 0x801b84C0
    - Particle configs:  RAM 0x801b8564 (17 × 0x2E bytes)
    - Gravity vector:    .text immediates (0x801b8a40 is .bss — see below)
    - Inertia threshold: .text immediates (0x801b8a4c is .bss — see below)
  - Texture: WEP.SPR
    - TRAP1 palette:     offset 0x10400 (512 bytes)
    - TRAP1 pixel data:  offset 0x10600 (0x4800 bytes)

Constants recovered from code, not data:
  RAM 0x801b8a40 (gravity vector) and 0x801b8a4c (inertia threshold) are ZERO
  in BATTLE.BIN — .bss storage, written at runtime. They are NOT lost: each
  charge handler passes them as immediates to set_gravity_vector@0x801A9984 /
  set_inertia_threshold@0x801A99AC, so parse_particle_header() decodes the
  `ori` at every call site and requires the sites to agree. Still the disc,
  still no emulator — just .text instead of .data. Tagged `gravity_source` /
  `inertia_source` in particle_header.json.

Output: Godot-ready JSON files to assets/effects/TRAP/

Usage:
    uv run python tools/parse_trap_effect.py
    python3 tools/parse_trap_effect.py --output /path/to/output
    python3 tools/parse_trap_effect.py --dump   # Dump all parsed data to stdout
"""

import struct
import json
import sys
import math
import argparse
from pathlib import Path

from _repo_paths import battle_bin as _battle_bin, battle_dir as _battle_dir

# =============================================================================
# Paths — both ISO-derived, host-agnostic via _repo_paths
# =============================================================================

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
BATTLE_BIN = _battle_bin()
WEP_SPR = _battle_dir() / "WEP.SPR"
DEFAULT_OUTPUT = PROJECT_DIR / "assets" / "effects" / "trap"

# =============================================================================
# BATTLE.BIN Addresses (RAM, translated to file offsets by ram_to_file)
# =============================================================================

# BATTLE.BIN loads at RAM 0x80067000 — the same base every other BATTLE.BIN
# parser in tools/ uses. Under the old whole-RAM capture this was 0x80000000.
BATTLE_BIN_RAM_BASE = 0x80067000

# TRAP data addresses in RAM
FRAMES_RAM        = 0x801b7690   # Frames section header (identical to E###.BIN)
ANIM_SEQ_RAM      = 0x801b8320   # Animation offset table (17 sequences)
ELEMENT_RGB_RAM   = 0x801b84C0   # Element RGB color table (9 × 3 bytes)
PARTICLE_CFG_RAM  = 0x801b8564   # Particle config table (17 × 0x2E bytes)
# Gravity / inertia live here at RUNTIME but are zero on disc — see
# parse_particle_header() for how they are recovered from the code instead.
GRAVITY_RAM       = 0x801b8a40   # Gravity vector (3 × i32), .bss
INERTIA_THRESH_RAM = 0x801b8a4c  # Inertia threshold (i32), .bss

# --- Static recovery of the two boot-written globals -------------------------
# 0x801b8a40 / 0x801b8a4c are zero-filled storage on disc (the whole page
# 0x801b8a00..0x801b8b00 is 256/256 zero bytes). Nothing installs them "at
# boot" either: each charge-effect handler sets its OWN pair immediately before
# spawning, via two leaf setters that Ghidra has labelled HIGH confidence:
#
#   set_gravity_vector    @0x801A9984   lui a2,0x801c; addiu a2,a2,-0x75c0
#                                       -> 0x801B8A40; stores a0[0..2]
#   set_inertia_threshold @0x801A99AC   lui at,0x801c; sw a0,-0x75b4(at)
#                                       -> 0x801B8A4C; stores a0
#
# (A plain hex grep for "801b8a40" in battle_disassembly.txt finds nothing:
# the address is formed lui+addiu, so the listing prints the label `=>gravity_x`
# and never the literal. That is why this looked unreachable.)
#
# At every charge-handler call site the argument is an immediate, so the values
# are recoverable from BATTLE.BIN's .text with no emulator in the loop:
#
#   gravity:  ori v0,zero,IMM  then  sw v0,vec+4(sp)  — vec[0] and vec[2] are
#             `sw zero`, so the vector is always (0, IMM, 0).
#   inertia:  ori a0,zero,IMM  in the jal's delay slot.
#
# We decode all of them and require unanimity rather than trusting one site.
GRAVITY_Y_IMM_SITES = [
    0x801B18EC, 0x801B1B6C, 0x801B28D0, 0x801B29F0, 0x801B2B60, 0x801B2C90,
    0x801B2DC8, 0x801B3020, 0x801B32E4, 0x801B38A0, 0x801B4180,
]
INERTIA_IMM_SITES = [
    0x801B18E8, 0x801B1B68, 0x801B21F4, 0x801B28CC, 0x801B29EC, 0x801B2B5C,
    0x801B2C8C, 0x801B2DC4, 0x801B301C, 0x801B32E0, 0x801B389C, 0x801B417C,
]
# A 12th gravity site (0x801A3160) and a 13th inertia site (0x801A3178) take
# their argument from a struct at [0x801BBF88] instead of an immediate — a
# different, non-charge-handler path. Deliberately excluded.

ANIM_COUNT = 17
PARTICLE_CFG_SIZE = 0x2E  # 46 bytes per config
EMITTER_COUNT = 17  # 17 valid configs (0-16), configs 17+ are other data structures

# WEP.SPR TRAP1 texture offsets
TRAP1_PALETTE_OFF  = 0x10400
TRAP1_PALETTE_SIZE = 512   # 16 sub-palettes × 16 colors × 2 bytes
TRAP1_PIXEL_OFF    = 0x10600
TRAP1_PIXEL_SIZE   = 0x4800  # 144×256 4bpp

# =============================================================================
# Unit Conversion Constants (same as parse_effect.py)
# =============================================================================

FFT_UNITS_PER_TILE = 28.0
FIXED_POINT_SCALE = 4096.0
POSITION_DIVISOR = FFT_UNITS_PER_TILE         # 28
# TRAP velocity conversion - different fields use different scales:
# - velocity: spawn position ellipsoid (combined with pos_scatter) → position scale
# - vel_range: velocity randomization added AFTER spawn → velocity scale
# - scatter_half_range: also velocity modifier → velocity scale
# PSX formula: pos = (random_dir * velocity / magnitude + pos_scatter) * 0x1000
SPAWN_ELLIPSOID_DIVISOR = FFT_UNITS_PER_TILE   # 28 - velocity defines spawn position
VELOCITY_RANGE_DIVISOR = 14336.0               # For vel_range (actual velocity, same as E###)
SCATTER_DIVISOR = 14336.0                      # For scatter_half_range (same as E###)
ACCEL_DIVISOR = FIXED_POINT_SCALE * FFT_UNITS_PER_TILE  # 114688
ANGLE_TO_RADIANS = math.tau / 4096.0

# Frame binary constants (same as E###.BIN)
FRAME_SIZE = 24
FRAMESET_HEADER_SIZE = 4

# TRAP1 texture is 256×144 pixels. In PSX VRAM, it loads at the BOTTOM of a
# 256×256 texture page, starting at Y=112 (256-144). UV coordinates in the
# frame data are relative to the TPAGE origin (Y=0), so UV Y=120 means VRAM
# row 120, which is TRAP1 row 8 (120-112). The Godot TGA has TRAP1 starting
# at row 0, so we subtract this offset to get correct TGA pixel coordinates.
TRAP1_VRAM_Y_OFFSET = 112  # 256 (TPAGE height) - 144 (TRAP1 height)
TRAP1_TEXTURE_WIDTH = 256
TRAP1_TEXTURE_HEIGHT = 144
# Godot TGA is padded to 488 rows for shader compatibility
TRAP1_TGA_HEIGHT = 488

# =============================================================================
# Memory Read Helpers (from build_trap_effect.py)
# =============================================================================

def ram_to_file(ram_addr):
    """Convert a PSX RAM address to a BATTLE.BIN file offset."""
    return ram_addr - BATTLE_BIN_RAM_BASE

def read_mem(data, ram_addr, size):
    """Read bytes from BATTLE.BIN at a RAM address."""
    offset = ram_to_file(ram_addr)
    if offset < 0 or offset + size > len(data):
        raise ValueError(
            f"RAM 0x{ram_addr:08X} (offset 0x{offset:X}+{size}) is outside "
            f"BATTLE.BIN (0x{BATTLE_BIN_RAM_BASE:08X}..0x{BATTLE_BIN_RAM_BASE + len(data):08X})")
    return data[offset:offset + size]

def read_u8(data, offset):
    return data[offset]

def read_u16(data, offset):
    return struct.unpack_from('<H', data, offset)[0]

def read_s16(data, offset):
    return struct.unpack_from('<h', data, offset)[0]

def read_u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]

def read_s32(data, offset):
    return struct.unpack_from('<i', data, offset)[0]

# =============================================================================
# Conversion Helpers (same as parse_effect.py)
# =============================================================================

def convert_position(xyz):
    """Convert FFT position [x,y,z] to Godot units with Y-flip."""
    return [
        round(xyz[0] / POSITION_DIVISOR, 6),
        round(-xyz[1] / POSITION_DIVISOR, 6),  # Negate Y
        round(xyz[2] / POSITION_DIVISOR, 6),
    ]

def convert_spawn_ellipsoid_component(raw):
    """Convert velocity component for spawn position ellipsoid.

    Velocity field defines the spawn position ellipsoid - uses position scale
    because it's combined with pos_scatter in the PSX formula.
    """
    return round(raw / SPAWN_ELLIPSOID_DIVISOR, 6)

def convert_spawn_ellipsoid_xyz(xyz):
    """Convert spawn ellipsoid velocity [x,y,z] to Godot units with Y-flip."""
    return [
        convert_spawn_ellipsoid_component(xyz[0]),
        -convert_spawn_ellipsoid_component(xyz[1]),  # Negate Y
        convert_spawn_ellipsoid_component(xyz[2]),
    ]

def convert_vel_range_component(raw):
    """Convert vel_range component - actual velocity randomization.

    vel_range is added to particle velocity AFTER spawn position calculation,
    so uses velocity scale (same as E### effects).
    """
    return round(raw / VELOCITY_RANGE_DIVISOR, 6)

def convert_vel_range_xyz(xyz):
    """Convert vel_range [x,y,z] to Godot velocity units with Y-flip."""
    return [
        convert_vel_range_component(xyz[0]),
        -convert_vel_range_component(xyz[1]),  # Negate Y
        convert_vel_range_component(xyz[2]),
    ]

def convert_scatter_component(raw):
    """Convert scatter_half_range component using separate divisor."""
    return round(raw / SCATTER_DIVISOR, 6)

def convert_scatter_xyz(xyz):
    """Convert scatter_half_range [x,y,z] to Godot units with Y-flip."""
    return [
        convert_scatter_component(xyz[0]),
        -convert_scatter_component(xyz[1]),  # Negate Y
        convert_scatter_component(xyz[2]),
    ]

# =============================================================================
# Frame Parsing (identical binary format to E###.BIN)
# =============================================================================

def parse_frame(data, offset, frame_index):
    """Parse single 24-byte frame (same as parse_effect.py)."""
    flags_byte0 = read_u8(data, offset)
    flags_byte1 = read_u8(data, offset + 1)
    texture_page = read_u16(data, offset + 2)

    palette_id = flags_byte0 & 0x0F
    semi_trans_mode = (flags_byte0 >> 5) & 0x03
    is_8bpp = bool(flags_byte0 & 0x80)

    semi_trans_on = bool(flags_byte1 & 0x02)
    width_signed = bool(flags_byte1 & 0x10)
    height_signed = bool(flags_byte1 & 0x20)

    # Texture page decoding
    tpage_x_base = texture_page & 0x0F
    tpage_y_base = (texture_page >> 4) & 0x01
    tpage_blend = (texture_page >> 5) & 0x03
    tpage_color_depth = (texture_page >> 7) & 0x03

    # UV coordinates (raw PSX values, relative to TPAGE origin)
    uv_x_raw = read_u8(data, offset + 4)
    uv_y_raw = read_u8(data, offset + 5)
    uv_width = read_u8(data, offset + 6)
    uv_height = read_u8(data, offset + 7)

    # Handle signed UV dimensions (flip)
    if width_signed and uv_width > 127:
        uv_width = uv_width - 256
    if height_signed and uv_height > 127:
        uv_height = uv_height - 256

    # Adjust UV Y for Godot TGA coordinate space:
    # PSX VRAM has TRAP1 at Y=112 within the texture page.
    # Godot TGA has TRAP1 starting at row 0.
    uv_x = uv_x_raw
    uv_y = uv_y_raw - TRAP1_VRAM_Y_OFFSET

    # Vertices (4 corners, signed 16-bit)
    return {
        "index": frame_index,
        "palette_id": palette_id,
        "semi_trans_mode": semi_trans_mode,
        "semi_trans_on": semi_trans_on,
        "is_8bpp": is_8bpp,
        "blend_mode": ["BLEND_50", "ADD", "SUB", "ADD_25"][semi_trans_mode],
        "uv": {
            "x": uv_x,
            "y": uv_y,
            "width": uv_width,
            "height": uv_height,
        },
        "uv_raw": {
            "x": uv_x_raw,
            "y": uv_y_raw,
        },
        "vertices": {
            "top_left": [read_s16(data, offset + 8), read_s16(data, offset + 10)],
            "top_right": [read_s16(data, offset + 12), read_s16(data, offset + 14)],
            "bottom_left": [read_s16(data, offset + 16), read_s16(data, offset + 18)],
            "bottom_right": [read_s16(data, offset + 20), read_s16(data, offset + 22)],
        },
        "texture_page": {
            "x_base": tpage_x_base,
            "y_base": tpage_y_base,
            "blend": tpage_blend,
            "color_depth": tpage_color_depth,
        },
    }


def parse_frames_section(mem):
    """Parse TRAP frames section from BATTLE.BIN.

    Layout at FRAMES_RAM:
      - 4-byte header: group_count (u32)
      - Group entries: group_count × 2 bytes
      - Frameset offset table: N × 2 bytes
      - Frameset data: N × (4-byte header + frame_count × 24 bytes)

    Returns list of frameset dicts (same format as parse_effect.py).
    """
    frames_size = ANIM_SEQ_RAM - FRAMES_RAM  # 0x0C90
    data = read_mem(mem, FRAMES_RAM, frames_size)

    framesets = []
    group_count = read_u8(data, 0)
    group_entries_end = 4 + group_count * 2

    if group_entries_end >= len(data):
        return framesets

    # First frameset offset tells us where frame data starts
    first_offset = read_u16(data, group_entries_end)
    frame_sets_data_start = first_offset + 4
    max_frame_sets = (frame_sets_data_start - group_entries_end) // 2

    if max_frame_sets <= 0 or max_frame_sets > 500:
        return framesets

    # Count valid offset table entries
    num_frame_sets = 0
    for i in range(max_frame_sets):
        offset_pos = group_entries_end + i * 2
        if offset_pos + 2 > len(data):
            break
        raw_offset = read_u16(data, offset_pos)
        if raw_offset < first_offset:
            break
        num_frame_sets += 1

    # Parse each frameset
    for fs_idx in range(num_frame_sets):
        offset_pos = group_entries_end + fs_idx * 2
        raw_offset = read_u16(data, offset_pos)
        fs_offset = raw_offset + 4

        if fs_offset + FRAMESET_HEADER_SIZE > len(data):
            break

        header_flags = read_u16(data, fs_offset)
        frame_count = read_u16(data, fs_offset + 2)

        if frame_count <= 0 or frame_count > 100:
            continue

        frames = []
        for frame_idx in range(frame_count):
            frame_offset = fs_offset + FRAMESET_HEADER_SIZE + frame_idx * FRAME_SIZE
            if frame_offset + FRAME_SIZE > len(data):
                break
            frames.append(parse_frame(data, frame_offset, frame_idx))

        framesets.append({
            "index": fs_idx,
            "header_flags": header_flags,
            "frames": frames,
        })

    return framesets

# =============================================================================
# Animation Parsing
# =============================================================================

def parse_trap_animations(mem):
    """Parse TRAP animation sequences from BATTLE.BIN.

    TRAP format: offset table (17 × u16), then sequences.
    Each sequence: [total_entries: u16][duration: u8, frame_index: u8]×N

    Returns list of animation dicts converted to E###.BIN opcode format
    (FRAME + LOOP opcodes) for Godot compatibility.
    Also returns raw TRAP sequences for documentation.
    """
    # Read offset table
    offsets = []
    for i in range(ANIM_COUNT):
        off = struct.unpack_from('<H', read_mem(mem, ANIM_SEQ_RAM + i * 2, 2))[0]
        offsets.append(off)

    sequences_raw = []
    sequences_opcodes = []

    for i in range(ANIM_COUNT):
        seq_addr = ANIM_SEQ_RAM + offsets[i]
        total_entries = struct.unpack_from('<H', read_mem(mem, seq_addr, 2))[0]

        entries = []
        for j in range(total_entries):
            entry_data = read_mem(mem, seq_addr + 2 + j * 2, 2)
            duration = entry_data[0]
            frame_index = entry_data[1]
            entries.append({"duration": duration, "frame_index": frame_index})

        # Raw TRAP format (for documentation)
        sequences_raw.append({
            "index": i,
            "offset": offsets[i],
            "total_entries": total_entries,
            "entries": entries,
        })

        # Convert to E###.BIN opcode format for Godot
        opcodes = []
        for entry in entries:
            opcodes.append({
                "type": "FRAME",
                "frameset": entry["frame_index"],
                "duration": entry["duration"],
                "depth_mode": 1,  # PULL_FORWARD_8 (standard for TRAP)
            })
        opcodes.append({"type": "LOOP"})

        sequences_opcodes.append({
            "index": i,
            "opcodes": opcodes,
        })

    return sequences_opcodes, sequences_raw

# =============================================================================
# Particle Config Parsing
# =============================================================================

# Config names based on sprite/animation analysis.
# Configs 0 + 1/9 are used by charge_effect_handler_2 for hit clouds.
# Other configs are used by charge_effect_handlers 1, 3, 4, 5, etc.
# for spell charge shimmer, elemental puffs, summon orbs, etc.
EMITTER_NAMES = {
    0:  "dust",              # Hit cloud dust (anim 0, frames 0-4, 32x32)
    1:  "flash_throwstone",  # ThrowStone sparkle (anim 5, frame 22, 8x8)
    2:  "elemental_puff",    # Rising cloud puffs (anim 4, frames 15-21, 24x24)
    3:  "pulsing_glow",      # Shrink-grow glow orbs (anim 10, pulsing cycle)
    4:  "explosion_burst",   # Large explosion (anim 12, frames 90-100, 48x48)
    5:  "dense_sparkle",     # Dense sparkle field (anim 14, sparkle cycle)
    6:  "cloud_puff_alt",    # Cloud puffs variant (anim 4, frames 15-21)
    7:  "golden_orbs",       # Floating golden orbs (anim 6, frames 23-29)
    8:  "shimmer_glow",      # Spell charge shimmer (anim 2, frames 5-10, 16x16)
    9:  "flash_melee",       # Regular melee sparkle (anim 5, frame 22, 8x8)
    10: "fast_burst",        # Fast shrink sparkles (anim 8, frames 36-41)
    11: "scattered_dots",    # Rising scattered dots (anim 7, frames 30-35, 8x8)
    12: "sparse_sparkle",    # Sparse fast sparkles (anim 5, frame 22)
    13: "small_sparkle",     # Small elemental sparkle (anim 3, frames 11-14)
    14: "pulsing_pair",      # Static pulsing pair (anim 9, frames 48-49)
    15: "medium_puff",       # Medium puff trail (anim 13, frames 72-75, 32x32)
    16: "beam",              # Single static beam (anim 16, frames 101-106, 32x32)
}

# Which handler uses which configs (for documentation/grouping)
HANDLER_CONFIG_MAP = {
    "charge_effect_handler_2 (hit clouds)": {
        "handler_index": 2,
        "address": "0x801b153c",
        "dust_config": 0,
        "flash_config_throwstone": 1,
        "flash_config_melee": 9,
        "notes": "Config 0 (dust) always used. Config 1 vs 9 selected by sub-type byte.",
    },
    "charge_effect_handler_1 (spell shimmer)": {
        "handler_index": 1,
        "address": "0x801b0ffc",
        "configs": [3, 7, 8, 11],
        "notes": "Rising sparkles during spell casting. Element-colored.",
    },
    "charge_effect_handler_3 (elemental charge)": {
        "handler_index": 3,
        "address": "0x801b1990",
        "configs": [2, 6, 13],
        "notes": "Elemental puff clouds during charging.",
    },
    "charge_effect_handler_4 (summon orbs)": {
        "handler_index": 4,
        "address": "0x801b1c04",
        "configs": [4, 5, 10, 14, 15, 16],
        "notes": "Summon charge orbs, explosions, beams.",
    },
    "charge_effect_handler_5 (summon glow)": {
        "handler_index": 5,
        "address": "0x801b27dc",
        "configs": [12],
        "notes": "Summon charge glow sparkles.",
    },
}

def parse_trap_config(mem, config_index):
    """Parse a 0x2E-byte TRAP particle config into flat emitter JSON.

    Returns Godot-ready emitter dict with converted units.
    """
    cfg_addr = PARTICLE_CFG_RAM + config_index * PARTICLE_CFG_SIZE
    raw = read_mem(mem, cfg_addr, PARTICLE_CFG_SIZE)

    # Parse raw fields
    frame_table_index = raw[0x00]
    spawn_check_lo    = raw[0x02]
    spawn_check_hi    = raw[0x03]
    max_particles     = raw[0x04]
    direction_flags   = read_u16(raw, 0x06)
    velocity_mode     = read_u16(raw, 0x08)
    pos_scatter_x     = read_s16(raw, 0x0A)
    # +0x0C of config 5 (RAM 0x801B8656) is the one field in this table the game
    # MUTATES at runtime: Ghidra XREF[3] = 801b2d88(W) 801b2da8(R) 801b2db4(W) —
    # 0x801b2d74 stores -8 into it, and 0x801b2da8..db4 does
    # `lhu; addiu v0,v0,-3; sh` (a per-pass decrement). So a RAM capture reads
    # whatever the last charge left behind; the disc value FF84 (-124) is the
    # initialiser. Extraction takes the disc. An older committed emitters.json
    # had -125 here, captured mid-animation — do not "restore" it.
    pos_scatter_y     = read_s16(raw, 0x0C)
    pos_scatter_z     = read_s16(raw, 0x0E)
    vel_x             = read_s16(raw, 0x10)
    vel_y             = read_s16(raw, 0x12)
    vel_z             = read_s16(raw, 0x14)
    vel_range_x       = read_s16(raw, 0x16)
    vel_range_y       = read_s16(raw, 0x18)
    vel_range_z       = read_s16(raw, 0x1A)
    scatter_half_x    = read_u16(raw, 0x1C)
    scatter_half_y    = read_u16(raw, 0x1E)
    scatter_half_z    = read_u16(raw, 0x20)
    weight_min        = read_s16(raw, 0x22)
    weight_max        = read_s16(raw, 0x24)
    # radius is SIGNED - negative values mean particles fly away from target
    radius_min        = read_s16(raw, 0x26)
    radius_max        = read_s16(raw, 0x28)
    spawn_rate        = raw[0x2A]
    spawn_count       = raw[0x2B]
    lifetime_min      = struct.unpack_from('<b', raw, 0x2C)[0]  # signed
    lifetime_max      = struct.unpack_from('<b', raw, 0x2D)[0]  # signed

    # Decode direction/velocity mode flags
    dir_mode = "NONE"
    if direction_flags & 0x410 == 0x410:
        dir_mode = "FACING"
    elif direction_flags & 0x400:
        dir_mode = "DIRECTIONAL"

    vel_mode = "SPHERICAL_RANDOM"
    if velocity_mode & 0x1000:
        vel_mode = "ZERO"
    elif velocity_mode & 0x410 == 0x410:
        vel_mode = "FACING_DIRECTIONAL"
    elif velocity_mode & 0x400:
        vel_mode = "DIRECTIONAL"
    elif velocity_mode & 0x010:
        vel_mode = "SCATTER"
    elif velocity_mode == 0:
        vel_mode = "SPHERICAL_RANDOM"  # fallthrough in disassembly

    # RGB modulation is set by the handler after FUN_801b0c88, not in the config.
    # Known values from decompilation:
    #   Config 0 (dust): (128,128,128) = 1.0× normal
    #   Config 1, 9 (flash sparkles): (255,255,255) = 2.0× overbright white
    #   Other configs: handler-dependent, default to (128,128,128)
    if config_index in (1, 9):
        rgb_mod = [255, 255, 255]  # Overbright flash sparkles
    else:
        rgb_mod = [128, 128, 128]  # Normal modulation (handler may override)

    # Build Godot-ready emitter dict
    emitter = {
        "index": config_index,
        "name": EMITTER_NAMES.get(config_index, f"config_{config_index}"),
        "anim_index": frame_table_index,
        "max_particles": max_particles,

        # Position scatter (Godot units, Y-flipped)
        "position_scatter": convert_position([pos_scatter_x, pos_scatter_y, pos_scatter_z]),

        # For DIRECTIONAL mode: scatter_half_range = cone angle randomization (radians)
        # For SCATTER mode: unused (dust has [0,0,0])
        # FFT uses 4096 = 2π, so raw/4096 * 2π = radians
        "scatter_half_range": [
            round(scatter_half_x * ANGLE_TO_RADIANS, 6),
            round(scatter_half_y * ANGLE_TO_RADIANS, 6),
            round(scatter_half_z * ANGLE_TO_RADIANS, 6),
        ],

        # Per-component velocity defines spawn position ellipsoid (position scale)
        "velocity": convert_spawn_ellipsoid_xyz([vel_x, vel_y, vel_z]),

        # For DIRECTIONAL mode: vel_range = base cone direction angles (radians)
        # For SCATTER mode: unused (dust has [0,0,0])
        "vel_range": [
            round(vel_range_x * ANGLE_TO_RADIANS, 6),
            round(vel_range_y * ANGLE_TO_RADIANS, 6),
            round(vel_range_z * ANGLE_TO_RADIANS, 6),
        ],

        # Weight (raw, used in physics formula)
        "weight": weight_min if weight_min == weight_max else [weight_min, weight_max],

        # Inertia (hardcoded in init)
        "inertia": 4096,

        # Lifetime (-1 = animation-driven)
        "lifetime": lifetime_min if lifetime_min == lifetime_max else [lifetime_min, lifetime_max],

        # Spawn control
        "spawn_rate": spawn_rate,
        "spawn_count": spawn_count,
        "spawn_window": [spawn_check_lo, spawn_check_hi],

        # Radius
        "radius": [radius_min, radius_max] if radius_min != radius_max else radius_min,

        # Visual
        "rgb_modulation": rgb_mod,
        "blend_mode": "ADD",  # Both use PSX semi-trans mode 1
        "palette_id": 0,       # Element-dependent for dust; hardcoded for flash

        # Flags
        "flags": {
            "direction_mode": dir_mode,
            "velocity_mode": vel_mode,
        },

        # Raw values for reference
        "raw": {
            "config_addr": f"0x{cfg_addr:08X}",
            "direction_flags": f"0x{direction_flags:04X}",
            "velocity_mode": f"0x{velocity_mode:04X}",
            "position_scatter": [pos_scatter_x, pos_scatter_y, pos_scatter_z],
            "velocity": [vel_x, vel_y, vel_z],
            "vel_range": [vel_range_x, vel_range_y, vel_range_z],
            "scatter_half_range": [scatter_half_x, scatter_half_y, scatter_half_z],
            "weight": [weight_min, weight_max],
            "radius": [radius_min, radius_max],
            "lifetime": [lifetime_min, lifetime_max],
            "hex": raw.hex(),
        },
    }

    return emitter

# =============================================================================
# Particle Header Parsing
# =============================================================================

def decode_immediate_to_reg(mem, ram_addr, want_rt):
    """Decode `ori/addiu <want_rt>, zero, IMM` at a RAM address -> IMM.

    Raises if the word at that address is not that instruction, so a ROM
    revision that moved the code fails loudly instead of emitting a wrong
    constant.
    """
    word = read_u32(mem, ram_to_file(ram_addr))
    op, rs, rt, imm = word >> 26, (word >> 21) & 31, (word >> 16) & 31, word & 0xFFFF
    if op not in (0x0D, 0x09) or rs != 0 or rt != want_rt:
        raise ValueError(
            f"0x{ram_addr:08X}: expected `ori/addiu r{want_rt},zero,imm`, "
            f"got word 0x{word:08X} (op=0x{op:02X} rs={rs} rt={rt})")
    return imm


def _unanimous(mem, sites, want_rt, what):
    """Decode an immediate at every site; require they all agree."""
    vals = {}
    for site in sites:
        vals.setdefault(decode_immediate_to_reg(mem, site, want_rt), []).append(site)
    if len(vals) != 1:
        detail = "; ".join(
            f"{v} at " + ",".join(f"0x{a:08X}" for a in addrs)
            for v, addrs in sorted(vals.items()))
        raise ValueError(f"{what} disagrees across call sites: {detail}")
    return next(iter(vals))


def parse_particle_header(mem):
    """TRAP particle system globals (gravity, inertia threshold).

    Both are recovered from the CODE, not from 0x801b8a40/0x801b8a4c — those
    are zero on disc. See GRAVITY_Y_IMM_SITES above.
    """
    # Assert the premise rather than assume it: if a future extract DOES carry
    # non-zero data here, we want to know, not silently prefer the code.
    stored = (read_s32(read_mem(mem, GRAVITY_RAM, 4), 0),
              read_s32(read_mem(mem, GRAVITY_RAM + 4, 4), 0),
              read_s32(read_mem(mem, GRAVITY_RAM + 8, 4), 0),
              read_s32(read_mem(mem, INERTIA_THRESH_RAM, 4), 0))
    if any(stored):
        raise ValueError(
            f"0x{GRAVITY_RAM:08X}/0x{INERTIA_THRESH_RAM:08X} are non-zero on "
            f"disc ({stored}) — they were .bss when this was written. Re-check "
            "whether the static decode below is still the right source.")

    gx, gz = 0, 0                                   # both `sw zero` at every site
    gy = _unanimous(mem, GRAVITY_Y_IMM_SITES, 2, "gravity_y")      # -> v0
    threshold = _unanimous(mem, INERTIA_IMM_SITES, 4, "inertia")   # -> a0

    return {
        "constant": 2,  # Matches E###.BIN convention
        "emitter_count": EMITTER_COUNT,
        "gravity": [
            round(gx / ACCEL_DIVISOR, 6),
            round(-gy / ACCEL_DIVISOR, 6),
            round(gz / ACCEL_DIVISOR, 6),
        ],
        "gravity_raw": [gx, gy, gz],
        "inertia_threshold": threshold,
        # Provenance: these two are the only fields in this parser's output not
        # read from a data table. Recovered from BATTLE.BIN .text — see
        # GRAVITY_Y_IMM_SITES / INERTIA_IMM_SITES.
        "gravity_source": f"code: ori v0,zero,imm at {len(GRAVITY_Y_IMM_SITES)} charge-handler call sites of set_gravity_vector@0x801A9984",
        "inertia_source": f"code: ori a0,zero,imm at {len(INERTIA_IMM_SITES)} call sites of set_inertia_threshold@0x801A99AC",
    }

# =============================================================================
# Palette Extraction (from WEP.SPR)
# =============================================================================

def parse_palette(wep_data):
    """Extract 16 sub-palettes × 16 colors from WEP.SPR TRAP1 section.

    Returns list of 16 sub-palettes, each a list of 16 [r, g, b, stp] colors.
    BGR555 format: BBBBB_GGGGG_RRRRR with STP bit 15.
    """
    palette_data = wep_data[TRAP1_PALETTE_OFF:TRAP1_PALETTE_OFF + TRAP1_PALETTE_SIZE]
    sub_palettes = []

    for sub in range(16):
        colors = []
        for c in range(16):
            offset = (sub * 16 + c) * 2
            word = struct.unpack_from('<H', palette_data, offset)[0]

            r5 = word & 0x1F
            g5 = (word >> 5) & 0x1F
            b5 = (word >> 10) & 0x1F
            stp = (word >> 15) & 1

            # Convert 5-bit to 8-bit
            r8 = (r5 << 3) | (r5 >> 2)
            g8 = (g5 << 3) | (g5 >> 2)
            b8 = (b5 << 3) | (b5 >> 2)

            colors.append([r8, g8, b8, stp])
        sub_palettes.append(colors)

    return sub_palettes

# =============================================================================
# Element Config
# =============================================================================

ELEMENT_NAMES = [
    "None", "Fire", "Lightning", "Ice", "Wind",
    "Earth", "Water", "Holy", "Dark"
]

def parse_element_config(mem):
    """Parse element RGB color table + CLUT values.

    9 elements at 0x801b84C0 (9 × 3 bytes RGB).
    CLUT values: dust = element_index + 0x7AC0, flash = 0x7ACA.
    """
    rgb_data = read_mem(mem, ELEMENT_RGB_RAM, 27)
    elements = []

    for i in range(9):
        r = rgb_data[i * 3]
        g = rgb_data[i * 3 + 1]
        b = rgb_data[i * 3 + 2]
        dust_clut = 0x7AC0 + i
        flash_clut = 0x7ACA

        # Decode CLUT to VRAM coordinates
        clut_x = (dust_clut & 0x3F) << 4
        clut_y = dust_clut >> 6

        elements.append({
            "index": i,
            "name": ELEMENT_NAMES[i],
            "rgb": [r, g, b],
            "dust_clut": f"0x{dust_clut:04X}",
            "flash_clut": f"0x{flash_clut:04X}",
            "dust_palette_index": i,  # sub-palette index in TRAP1 palette
            "vram_location": [clut_x, clut_y],
        })

    return elements

# =============================================================================
# Palette Tracks (White Flash — hardcoded from FUN_8008a924)
# =============================================================================

def generate_palette_keyframes():
    """Generate palette.json (palette-subsystem keyframes) from FUN_8008a924 state machine.

    Maps the white flash state machine phases to keyframed palette
    modifications, matching the E###.BIN palette track format.

    FUN_8008a924 (disasm ~line 305556): 8-phase state machine.
    Uses apply_unit_palette_effect(mode, sub_mode, unit, r, g, b).

    Modes: 4 = SET (replace), 8 = REMOVE (clear)
    Sub-modes: 2 = apply to unit, 4 = add to existing, 0 = terrain-aware
    """
    return {
        "target": {
            "max_keyframe": 4,
            "function": "FUN_8008a924",
            "function_addr": "0x8008a924",
            "disasm_line": "~305556",
            "keyframes": [
                {
                    "tick": 0,
                    "phase": 0,
                    "rgb": [31, 31, 31],
                    "mode": 4,
                    "sub_mode": 2,
                    "mode_name": "SET",
                    "comment": "White flash ON (play sound 0x6A)",
                },
                {
                    "tick": 17,
                    "phase": 2,
                    "rgb": [-31, -31, -31],
                    "mode": 4,
                    "sub_mode": 4,
                    "mode_name": "ADD",
                    "comment": "Return to normal (add -31 to existing +31 shift = 0)",
                },
                {
                    "tick": 17,
                    "phase": 3,
                    "rgb": [-31, -31, -31],
                    "mode": 4,
                    "sub_mode": 0,
                    "mode_name": "SET_TERRAIN",
                    "comment": "Terrain shadow (darkens terrain under unit, not the unit sprite)",
                },
                {
                    "tick": 34,
                    "phase": 5,
                    "rgb": [31, 31, 31],
                    "mode": 4,
                    "sub_mode": 4,
                    "mode_name": "ADD",
                    "comment": "Second white flash (add +31 to 0 shift = white again)",
                },
                {
                    "tick": 50,
                    "phase": 6,
                    "rgb": [0, 0, 0],
                    "mode": 8,
                    "sub_mode": 2,
                    "mode_name": "REMOVE",
                    "comment": "Remove palette effect (restore original)",
                },
            ],
        },
    }

# =============================================================================
# Sounds (hardcoded from handler functions)
# =============================================================================

def generate_sounds():
    """Generate sounds.json from hardcoded sound triggers.

    Sound IDs from FUN_8008a924 and related handlers.
    """
    return [
        {
            "id": "0x6A",
            "id_dec": 106,
            "trigger": "impact",
            "tick": 0,
            "source": "FUN_8008a924 phase 0 (FUN_8008a800)",
            "comment": "Physical hit impact sound",
        },
        {
            "id": "0xDB",
            "id_dec": 219,
            "trigger": "attack_hit_first",
            "tick": 0,
            "source": "FUN_8008a924 phase 1 (attack/item sync)",
            "comment": "First hit sound for Attack/Item abilities",
        },
        {
            "id": "0xDC",
            "id_dec": 220,
            "trigger": "attack_hit_first_alt",
            "tick": 0,
            "source": "FUN_8008a924 phase 1 (attack/item sync)",
            "comment": "First hit alt sound for Attack/Item abilities",
        },
        {
            "id": "0xB8",
            "id_dec": 184,
            "trigger": "attack_hit_second",
            "tick": 17,
            "source": "FUN_8008a924 phase 4 (attack/item sync)",
            "comment": "Second hit sound for Attack/Item abilities",
        },
        {
            "id": "0x28",
            "id_dec": 40,
            "trigger": "attack_hit_second_alt",
            "tick": 17,
            "source": "FUN_8008a924 phase 4 (attack/item sync)",
            "comment": "Second hit alt sound for Attack/Item abilities",
        },
    ]

# =============================================================================
# Timeline (simplified spawn windows)
# =============================================================================

def generate_timeline(emitters):
    """Generate timeline.json from emitter spawn windows.

    Maps spawn_check_lo/hi from each emitter config to timeline keyframes.
    """
    channels = []
    for em in emitters:
        lo = em["spawn_window"][0]
        hi = em["spawn_window"][1]
        channels.append({
            "emitter_index": em["index"],
            "emitter_name": em["name"],
            "spawn_start_tick": lo,
            "spawn_end_tick": hi,
            "spawn_rate": em["spawn_rate"],
            "max_particles": em["max_particles"],
        })

    return {
        "handler": "charge_effect_handler_2",
        "handler_addr": "0x801b153c",
        "total_duration_comment": "Effect runs until all particles dead + handler ticks expire",
        "channels": channels,
    }

# =============================================================================
# Main Parser
# =============================================================================

def parse_trap_effect(mem, wep_data, dump=False):
    """Parse all TRAP effect data and return dict of output files."""
    results = {}

    # 1. Particle header
    particle_header = parse_particle_header(mem)
    results["particle_header"] = particle_header
    print(f"  particle_header: gravity={particle_header['gravity_raw']}, "
          f"inertia_threshold={particle_header['inertia_threshold']}")

    # 2. Emitters (17 configs)
    emitters = [parse_trap_config(mem, i) for i in range(EMITTER_COUNT)]
    results["emitters"] = emitters
    results["handler_config_map"] = HANDLER_CONFIG_MAP
    for em in emitters:
        print(f"  emitter {em['index']:2d} ({em['name']:20s}): "
              f"anim={em['anim_index']:2d}, max={em['max_particles']:2d}, "
              f"spawn={em['spawn_rate']}/tick, "
              f"lifetime={em['lifetime']}")

    # 3. Frames (identical to E###.BIN format)
    framesets = parse_frames_section(mem)
    results["frames"] = framesets
    print(f"  frames: {len(framesets)} framesets")

    # 4. Animations (converted to opcode format)
    animations, animations_raw = parse_trap_animations(mem)
    results["animations"] = animations
    results["_animations_raw"] = animations_raw
    print(f"  animations: {len(animations)} sequences")

    # 5. Texture palette (16 sub-palettes from WEP.SPR — static color table)
    texture_palette = parse_palette(wep_data)
    results["texture_palette"] = texture_palette
    print(f"  texture_palette: {len(texture_palette)} sub-palettes × {len(texture_palette[0])} colors")

    # 6. Palette-subsystem keyframes (white flash animation)
    palette = generate_palette_keyframes()
    results["palette"] = palette
    print(f"  palette: {len(palette['target']['keyframes'])} keyframes")

    # 7. Sounds
    sounds = generate_sounds()
    results["sounds"] = sounds
    print(f"  sounds: {len(sounds)} entries")

    # 8. Element config
    element_config = parse_element_config(mem)
    results["element_config"] = element_config
    print(f"  element_config: {len(element_config)} elements")

    # 9. Timeline
    timeline = generate_timeline(emitters)
    results["timeline"] = timeline
    print(f"  timeline: {len(timeline['channels'])} channels")

    return results


def save_results(results, output_dir):
    """Write all parsed data to JSON files."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    files = {
        "particle_header.json": results["particle_header"],
        "emitters.json": results["emitters"],
        "handler_config_map.json": results["handler_config_map"],
        "frames.json": results["frames"],
        "animations.json": results["animations"],
        "texture_palette.json": results["texture_palette"],
        "palette.json": results["palette"],
        "sounds.json": results["sounds"],
        "element_config.json": results["element_config"],
        "timeline.json": results["timeline"],
    }

    for filename, data in files.items():
        filepath = out / filename
        with open(filepath, "w") as f:
            json.dump(data, f, indent=2)
        print(f"  {filename}: {filepath.stat().st_size:,} bytes")

    print(f"\nOutput directory: {out}")
    print(f"Total files: {len(files)}")


def main():
    parser = argparse.ArgumentParser(
        description="Parse the TRAP particle effect system from BATTLE.BIN + WEP.SPR")
    parser.add_argument("--output", "-o", type=str, default=str(DEFAULT_OUTPUT),
                        help=f"Output directory (default: {DEFAULT_OUTPUT})")
    parser.add_argument("--dump", action="store_true",
                        help="Dump all parsed data to stdout as JSON")
    parser.add_argument("--battle-bin", type=str, default=str(BATTLE_BIN),
                        help=f"BATTLE.BIN path (default: {BATTLE_BIN})")
    parser.add_argument("--wep-spr", type=str, default=str(WEP_SPR),
                        help=f"WEP.SPR path (default: {WEP_SPR})")
    args = parser.parse_args()

    print("=== TRAP Effect System Parser (17 configs) ===\n")

    battle_path = Path(args.battle_bin)
    wep_path = Path(args.wep_spr)

    if not battle_path.exists():
        print(f"ERROR: BATTLE.BIN not found: {battle_path}")
        return 1
    if not wep_path.exists():
        print(f"ERROR: WEP.SPR not found: {wep_path}")
        return 1

    print(f"Reading BATTLE.BIN: {battle_path}")
    mem = battle_path.read_bytes()
    print(f"  Size: {len(mem):,} bytes (RAM base 0x{BATTLE_BIN_RAM_BASE:08X})")

    print(f"Reading WEP.SPR: {wep_path}")
    wep_data = wep_path.read_bytes()
    print(f"  Size: {len(wep_data):,} bytes\n")

    # Validate
    if len(wep_data) < TRAP1_PIXEL_OFF + TRAP1_PIXEL_SIZE:
        print("ERROR: WEP.SPR too small for TRAP1 data")
        return 1

    print("Parsing...")
    results = parse_trap_effect(mem, wep_data)

    if args.dump:
        # Remove internal keys
        dump_data = {k: v for k, v in results.items() if not k.startswith("_")}
        print("\n" + json.dumps(dump_data, indent=2))
    else:
        print(f"\nWriting output files...")
        save_results(results, args.output)

    return 0


if __name__ == "__main__":
    sys.exit(main())
