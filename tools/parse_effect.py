#!/usr/bin/env python3
"""
E###.BIN Effect File Parser

Parses Final Fantasy Tactics effect binary files and outputs JSON for Godot.
Based on the Lua parser from tactics_debug/effect_editor.

IMPORTANT: This parser outputs Godot-ready values with ALL unit conversions baked in.
No additional scaling constants should be needed in GDScript.

Conversion Reference (from FFT disassembly):
- Positions: FFT world units (28/tile) -> Godot units (1/tile), Y-flipped
- Velocities: radial * 8 / 4096 / 28 = radial / 14336 (Godot units/frame)
- Acceleration/Drag/Gravity: / 4096 / 28 = / 114688, Y-flipped
- Angles: 0-4096 -> radians (× TAU/4096)
- Inertia/Weight: Keep raw (used directly in physics formulas)
- Homing strength: / 114688 (same as acceleration)
- Target offset: FFT world units / 28, Y-flipped

Usage:
    python parse_effect.py E001.BIN [output_dir]
    python parse_effect.py /path/to/EFFECT/E001.BIN assets/effects/E001
"""

import struct
import json
import sys
import math
import subprocess
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Tuple, Optional, Any

# =============================================================================
# Unit Conversion Constants
# =============================================================================

# FFT uses 28 world units per tile, Godot uses 1.0 unit per tile
FFT_UNITS_PER_TILE = 28.0

# FFT fixed-point scale (20.12 format, 4096 = 1.0)
FIXED_POINT_SCALE = 4096.0

# Position conversion: FFT world units -> Godot units
POSITION_DIVISOR = FFT_UNITS_PER_TILE  # 28

# Velocity conversion: radial_velocity -> Godot units/frame
# FFT: velocity_fixed = radial * 8, then position += velocity / 4096
# So: position_delta = radial * 8 / 4096 FFT units = radial / 512 FFT units
# Godot: radial / 512 / 28 = radial / 14336
VELOCITY_DIVISOR = 14336.0

# Acceleration/Drag/Gravity conversion: raw -> Godot units/frame²
# FFT: velocity += acceleration * 4096 / inertia, then position += velocity / 4096
# Net effect: acceleration affects position by accel / 4096 per frame (simplified)
# Godot: accel / 4096 / 28 = accel / 114688
ACCEL_DIVISOR = FIXED_POINT_SCALE * FFT_UNITS_PER_TILE  # 114688

# Angle conversion: 0-4096 -> radians
ANGLE_TO_RADIANS = math.tau / 4096.0  # TAU / 4096

# =============================================================================
# Conversion Helper Functions
# =============================================================================

def convert_position(xyz: List[int]) -> List[float]:
    """Convert FFT position [x, y, z] to Godot units with Y-flip.

    FFT: -Y is up, 28 units/tile
    Godot: +Y is up, 1.0 units/tile
    """
    return [
        xyz[0] / POSITION_DIVISOR,
        -xyz[1] / POSITION_DIVISOR,  # Negate Y for coordinate flip
        xyz[2] / POSITION_DIVISOR
    ]


def convert_velocity(value: float) -> float:
    """Convert FFT radial velocity to Godot units/frame.

    FFT: velocity_fixed = radial * 8, then position += velocity / 4096
    Godot: velocity directly added to position each frame
    """
    return value / VELOCITY_DIVISOR


def convert_accel(xyz: List[int]) -> List[float]:
    """Convert FFT acceleration/drag [x, y, z] to Godot units with Y-flip.

    FFT: velocity += acceleration * 4096 / inertia
    Godot: velocity += acceleration (pre-scaled)
    """
    return [
        xyz[0] / ACCEL_DIVISOR,
        -xyz[1] / ACCEL_DIVISOR,  # Negate Y for coordinate flip
        xyz[2] / ACCEL_DIVISOR
    ]


def convert_gravity(xyz: List[int]) -> List[float]:
    """Convert FFT gravity to Godot units with Y-flip.

    Same as acceleration conversion.
    """
    return [
        xyz[0] / ACCEL_DIVISOR,
        -xyz[1] / ACCEL_DIVISOR,  # Negate Y for coordinate flip
        xyz[2] / ACCEL_DIVISOR
    ]


def convert_homing_strength(value: float) -> float:
    """Convert FFT homing strength to Godot units.

    Homing affects acceleration, so same scale as acceleration.
    """
    return value / ACCEL_DIVISOR


def convert_angle(value: int) -> float:
    """Convert FFT angle (0-4096 = 0-360°) to radians."""
    return value * ANGLE_TO_RADIANS


def convert_angles(xyz: List[int]) -> List[float]:
    """Convert FFT angle triplet to radians."""
    return [convert_angle(v) for v in xyz]


# =============================================================================
# Binary Constants
# =============================================================================

HEADER_SIZE = 0x28  # 40 bytes
PARTICLE_HEADER_SIZE = 0x14  # 20 bytes
EMITTER_SIZE = 0xC4  # 196 bytes
CURVE_LENGTH = 160
FRAME_SIZE = 24
FRAMESET_HEADER_SIZE = 4

# Authoritative per-effect header-offset table baked into BATTLE.BIN. The game uses
# this to locate each effect's 40-byte header, so it works for every effect regardless
# of file layout — unlike scanning for the MIPS prologue (find_header_offset), which
# misses CODE-format effects whose file does not *start* with the prologue (e.g. E259).
VFX_HEADER_TABLE_OFFSET = 0x14D8D0   # BATTLE.BIN file offset of the table (one u32 per effect)
VFX_LOAD_BASE = 0x801C2500           # PSX RAM address an effect file is loaded at
NUM_VFX = 511                        # number of entries in the table

# Script opcodes (from master_parser.py)
OPCODES = {
    0: ("goto_yield", 4),
    1: ("goto", 4),
    2: ("spawn_child_effect", 4),
    3: ("terminate_child", 2),
    4: ("end", 2),
    5: ("set_texture_page", 2),
    6: ("load_callback", 4),
    7: ("invoke_callback", 4),
    8: ("load_position", 8),
    9: ("store_pos_to_origin", 2),
    10: ("load_pos_from_origin", 2),
    11: ("set_rotation", 8),
    12: ("apply_camera_rotation", 2),
    13: ("load_camera_rotation", 2),
    14: ("set_sprite_scale", 8),
    15: ("apply_sprite_scale", 2),
    16: ("set_script_reg", 4),
    17: ("branch_reg_eq", 6),
    18: ("branch_reg_ge", 6),
    19: ("branch_reg_gt", 6),
    20: ("branch_reg_le", 6),
    21: ("branch_reg_lt", 6),
    22: ("branch_count_eq", 6),
    23: ("branch_count_gt", 6),
    24: ("branch_count_lt", 6),
    25: ("branch_child_count_eq", 6),
    26: ("branch_child_active", 4),
    27: ("branch_child_inactive", 4),
    28: ("branch_reg_ne", 6),
    29: ("branch_anim_done", 4),
    30: ("branch_anim_done_complex", 4),
    31: ("branch_target_type", 4),
    32: ("inc_script_reg", 2),
    33: ("dec_script_reg", 2),
    34: ("add_script_reg", 4),
    35: ("sub_script_reg", 4),
    36: ("reset_sprite_scale", 2),
    37: ("update_all_particles", 2),
    38: ("spawn_emitter", 2),
    39: ("init_physics_params", 2),
    40: ("for_each", 2),
    41: ("process_timeline_frame", 4),
    42: ("clear_timeline_a", 2),
    43: ("clear_timeline_b", 2),
    44: ("nop_44", 2),
    45: ("nop_45", 2),
}

# Animation sequence opcodes
ANIM_OPCODES = {
    0x81: ("loop", 1),
    0x82: ("set_offset", 5),
    0x83: ("add_offset", 3),
}

# Anchor mode names
ANCHOR_MODES = {
    0: "WORLD",
    1: "CURSOR",
    2: "ORIGIN",
    3: "TARGET",
    4: "PARENT",
    5: "CAMERA",
    6: "TRACKED",
}

# TARGET_ANCHOR_MODES is DIFFERENT from ANCHOR_MODES!
# Verified from disassembly at 0x801a7ae8+ (see master_parser.py)
TARGET_ANCHOR_MODES = {
    0x00: "WORLD",   # No anchor, just use target_offset
    0x20: "WORLD",   # Same as 0x00 (both branch to same code)
    0x40: "CAMERA",  # Camera position (NOT ORIGIN!)
    0x60: "ORIGIN",  # Effect origin point
    0x80: "TARGET",  # Effect target point (NOT PARENT!)
    0xA0: "PARENT",  # Parent particle position (for child emitters)
    0xC0: "UNKNOWN_C0",
    0xE0: "UNKNOWN_E0",
}


def read_u8(data: bytes, offset: int) -> int:
    return data[offset]


def read_u16(data: bytes, offset: int) -> int:
    return struct.unpack_from('<H', data, offset)[0]


def read_s16(data: bytes, offset: int) -> int:
    return struct.unpack_from('<h', data, offset)[0]


def read_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from('<I', data, offset)[0]


def read_s32(data: bytes, offset: int) -> int:
    return struct.unpack_from('<i', data, offset)[0]


# =============================================================================
# CODE Format Detection (MIPS executable effects)
# =============================================================================

def find_header_offset(data: bytes) -> int:
    """Detect CODE format effects and find the embedded header offset.

    107 of 398 FFT effects are CODE format - they contain MIPS executable code
    prepended before the standard 40-byte header. DATA format effects have the
    header at offset 0.

    Detection: first word matches MIPS prologue signature (addiu sp, sp, -N).
    Header location: scan for frames_ptr=0x28 with ascending valid pointers.

    Returns 0 for DATA format, >0 for CODE format.
    """
    if len(data) < 40:
        return 0

    first_word = read_u32(data, 0)

    # Check for MIPS prologue: addiu sp, sp, -N  (opcode 0x27BD????)
    if (first_word & 0xFFFF0000) != 0x27BD0000:
        return 0

    # CODE format detected - scan for embedded header
    # The header's first field (frames_ptr) is always 0x28 (40 bytes = header size)
    file_size = len(data)
    for offset in range(4, file_size - 40, 4):
        candidate_frames_ptr = read_u32(data, offset)
        if candidate_frames_ptr != 0x28:
            continue

        # Verify: all 10 pointers should be ascending and within bounds
        ptrs = []
        valid = True
        for i in range(10):
            ptr = read_u32(data, offset + i * 4)
            # Pointers are relative to header position
            abs_ptr = offset + ptr
            if abs_ptr > file_size:
                valid = False
                break
            ptrs.append(ptr)

        if not valid:
            continue

        # Check that pointers are non-decreasing (sections are sequential)
        # Skip time_scale_ptr (index 5) which can be 0
        check_ptrs = ptrs[:5] + ptrs[6:]  # skip time_scale_ptr
        if all(check_ptrs[i] <= check_ptrs[i + 1] for i in range(len(check_ptrs) - 1)):
            return offset

    # Fallback: couldn't find header in CODE format file
    print(f"  WARNING: CODE format detected but header not found, treating as offset 0")
    return 0


def vfx_id_from_filename(name: str) -> Optional[int]:
    """Extract the numeric effect id from a filename like 'E259.BIN' -> 259."""
    stem = Path(name).stem  # 'E259'
    if not stem or stem[0].upper() != "E":
        return None
    try:
        return int(stem[1:])
    except ValueError:
        return None


def load_vfx_header_offset(battle_bin_path: str, vfx_id: int) -> Optional[int]:
    """Look up an effect's header offset from the BATTLE.BIN table.

    Returns the file-relative byte offset of the 40-byte header (0 for DATA-format
    effects, >0 for CODE-format), or None if the table can't be read for this id so
    the caller can fall back to find_header_offset().
    """
    if vfx_id is None or vfx_id < 0 or vfx_id >= NUM_VFX:
        return None
    try:
        battle = Path(battle_bin_path).read_bytes()
    except OSError:
        return None
    entry = VFX_HEADER_TABLE_OFFSET + vfx_id * 4
    if entry + 4 > len(battle):
        return None
    offset = read_u32(battle, entry) - VFX_LOAD_BASE
    if offset < 0:
        return None
    return offset


# =============================================================================
# Header Parsing
# =============================================================================

def parse_header(data: bytes, base_offset: int = 0) -> Dict[str, Any]:
    """Parse 40-byte file header.

    For CODE format effects, base_offset is the position of the header within
    the file. All section pointers in the header are relative to the header
    position, so we add base_offset to get absolute file offsets.
    """
    return {
        "frames_ptr": base_offset + read_u32(data, base_offset + 0x00),
        "animation_ptr": base_offset + read_u32(data, base_offset + 0x04),
        "script_data_ptr": base_offset + read_u32(data, base_offset + 0x08),
        "effect_data_ptr": base_offset + read_u32(data, base_offset + 0x0C),
        "anim_table_ptr": base_offset + read_u32(data, base_offset + 0x10),
        "time_scale_ptr": (base_offset + read_u32(data, base_offset + 0x14)) if read_u32(data, base_offset + 0x14) != 0 else 0,
        "effect_flags_ptr": base_offset + read_u32(data, base_offset + 0x18),
        "timeline_section_ptr": base_offset + read_u32(data, base_offset + 0x1C),
        "sound_def_ptr": base_offset + read_u32(data, base_offset + 0x20),
        "texture_ptr": base_offset + read_u32(data, base_offset + 0x24),
        "file_size": len(data),
    }


def calculate_sections(header: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Calculate section boundaries from header pointers"""
    sections = []

    sections.append({
        "name": "Frames",
        "offset": header["frames_ptr"],
        "size": header["animation_ptr"] - header["frames_ptr"]
    })
    sections.append({
        "name": "Animation",
        "offset": header["animation_ptr"],
        "size": header["script_data_ptr"] - header["animation_ptr"]
    })
    sections.append({
        "name": "Script",
        "offset": header["script_data_ptr"],
        "size": header["effect_data_ptr"] - header["script_data_ptr"]
    })
    sections.append({
        "name": "ParticleSystem",
        "offset": header["effect_data_ptr"],
        "size": header["anim_table_ptr"] - header["effect_data_ptr"]
    })

    if header["time_scale_ptr"] != 0:
        sections.append({
            "name": "AnimCurves",
            "offset": header["anim_table_ptr"],
            "size": header["time_scale_ptr"] - header["anim_table_ptr"]
        })
        sections.append({
            "name": "TimeScales",
            "offset": header["time_scale_ptr"],
            "size": header["effect_flags_ptr"] - header["time_scale_ptr"]
        })
    else:
        sections.append({
            "name": "AnimCurves",
            "offset": header["anim_table_ptr"],
            "size": header["effect_flags_ptr"] - header["anim_table_ptr"]
        })

    sections.append({
        "name": "EffectFlags",
        "offset": header["effect_flags_ptr"],
        "size": header["timeline_section_ptr"] - header["effect_flags_ptr"]
    })
    sections.append({
        "name": "Timeline",
        "offset": header["timeline_section_ptr"],
        "size": header["sound_def_ptr"] - header["timeline_section_ptr"]
    })
    sections.append({
        "name": "SoundDef",
        "offset": header["sound_def_ptr"],
        "size": header["texture_ptr"] - header["sound_def_ptr"]
    })
    sections.append({
        "name": "Texture",
        "offset": header["texture_ptr"],
        "size": header["file_size"] - header["texture_ptr"]
    })

    return sections


def parse_effect_flags(data: bytes, effect_flags_offset: int) -> Dict[str, Any]:
    """Parse the flags byte @0x00 of the effect_flags section (#272, ADR-0092).

    The RAW byte is the round-trip source of truth — bits 0-2/7 are loaded but
    AND-masked away by the engine, yet effect files still set them (E001=0x03),
    so the writer must reproduce the whole byte, not re-derive it from the four
    decoded bools. Only bits 3-6 are engine-read (proven at 0x801A1530 /
    0x801A61E0 / 0x801A3BF8 / 0x801A4A5C):
        bit3 (0x08) terrain_height_adjust
        bit4 (0x10) audio_fade
        bit5 (0x20) time_scale_pattern1  (3-phase slow-mo enable)
        bit6 (0x40) time_scale_pattern2  (1-phase slow-mo enable)
    """
    flags_byte = read_u8(data, effect_flags_offset)
    return {
        "flags_byte": flags_byte,
        "terrain_height_adjust": bool(flags_byte & 0x08),
        "audio_fade": bool(flags_byte & 0x10),
        "time_scale_pattern1": bool(flags_byte & 0x20),
        "time_scale_pattern2": bool(flags_byte & 0x40),
    }


def parse_time_scale(data: bytes, time_scale_offset: int, effect_flags_offset: int) -> Dict[str, Any]:
    """Parse 600-byte time scale data and effect flags byte 0.

    Time scale controls VBlank wait between game loop iterations.
    Higher values = fewer fixed steps per real second = everything slows down.
    Data is stored as packed nibbles (2 values per byte), 600 frames per region.
    """
    flags_byte = read_u8(data, effect_flags_offset)

    def unpack_region(region_start: int) -> List[int]:
        values = []
        for frame in range(600):
            byte_offset = region_start + frame // 2
            byte_val = read_u8(data, byte_offset)
            if (frame & 1) == 0:
                values.append(byte_val & 0x0F)
            else:
                values.append(byte_val >> 4)
        return values

    return {
        "flags": {
            "time_scale_pattern1": bool(flags_byte & 0x20),
            "time_scale_pattern2": bool(flags_byte & 0x40)
        },
        "outer_phases": unpack_region(time_scale_offset),
        "for_each": unpack_region(time_scale_offset + 300)
    }


# =============================================================================
# Particle System Parsing
# =============================================================================

def parse_particle_header(data: bytes, offset: int) -> Dict[str, Any]:
    """Parse 20-byte particle system header with Godot-ready conversions"""
    # Raw values
    raw_gx = read_s32(data, offset + 0x04)
    raw_gy = read_s32(data, offset + 0x08)
    raw_gz = read_s32(data, offset + 0x0C)

    # Convert gravity to Godot units with Y-flip
    gravity = convert_gravity([raw_gx, raw_gy, raw_gz])

    return {
        "constant": read_u16(data, offset + 0x00),
        "emitter_count": read_u16(data, offset + 0x02),
        # Gravity in Godot units (Y-flipped)
        "gravity": gravity,
        # Keep raw values for reference/debugging
        "gravity_raw": [raw_gx, raw_gy, raw_gz],
        # Inertia threshold - keep raw, used in physics formula
        "inertia_threshold": read_u32(data, offset + 0x10),
    }


def decode_curve_index(raw: int) -> int:
    """Decode nibble-packed curve index. 0 = none (-1), N = curve N-1"""
    return raw - 1 if raw > 0 else -1


def parse_emitter(data: bytes, offset: int, index: int) -> Dict[str, Any]:
    """Parse 196-byte emitter structure with Godot-ready conversions"""
    # Read curve indices (nibble-packed)
    curve_bytes = [read_u8(data, offset + 0x08 + i) for i in range(8)]

    # Read raw position values
    raw_pos_start = [read_s16(data, offset + 0x14), read_s16(data, offset + 0x16), read_s16(data, offset + 0x18)]
    raw_pos_end = [read_s16(data, offset + 0x1A), read_s16(data, offset + 0x1C), read_s16(data, offset + 0x1E)]

    # Read raw spread values
    raw_spread_start = [read_s16(data, offset + 0x20), read_s16(data, offset + 0x22), read_s16(data, offset + 0x24)]
    raw_spread_end = [read_s16(data, offset + 0x26), read_s16(data, offset + 0x28), read_s16(data, offset + 0x2A)]

    # Read raw angle values
    raw_angle_start = [read_s16(data, offset + 0x2C), read_s16(data, offset + 0x2E), read_s16(data, offset + 0x30)]
    raw_angle_end = [read_s16(data, offset + 0x32), read_s16(data, offset + 0x34), read_s16(data, offset + 0x36)]

    # Read raw velocity spread values
    raw_vel_spread_start = [read_s16(data, offset + 0x38), read_s16(data, offset + 0x3A), read_s16(data, offset + 0x3C)]
    raw_vel_spread_end = [read_s16(data, offset + 0x3E), read_s16(data, offset + 0x40), read_s16(data, offset + 0x42)]

    # Read raw acceleration values
    raw_accel_min_start = [read_s16(data, offset + 0x64), read_s16(data, offset + 0x68), read_s16(data, offset + 0x6C)]
    raw_accel_max_start = [read_s16(data, offset + 0x66), read_s16(data, offset + 0x6A), read_s16(data, offset + 0x6E)]
    raw_accel_min_end = [read_s16(data, offset + 0x70), read_s16(data, offset + 0x74), read_s16(data, offset + 0x78)]
    raw_accel_max_end = [read_s16(data, offset + 0x72), read_s16(data, offset + 0x76), read_s16(data, offset + 0x7A)]

    # Read raw drag values
    raw_drag_min_start = [read_s16(data, offset + 0x7C), read_s16(data, offset + 0x80), read_s16(data, offset + 0x84)]
    raw_drag_max_start = [read_s16(data, offset + 0x7E), read_s16(data, offset + 0x82), read_s16(data, offset + 0x86)]
    raw_drag_min_end = [read_s16(data, offset + 0x88), read_s16(data, offset + 0x8C), read_s16(data, offset + 0x90)]
    raw_drag_max_end = [read_s16(data, offset + 0x8A), read_s16(data, offset + 0x8E), read_s16(data, offset + 0x92)]

    # Read raw target offset values
    raw_target_start = [read_s16(data, offset + 0x9C), read_s16(data, offset + 0x9E), read_s16(data, offset + 0xA0)]
    raw_target_end = [read_s16(data, offset + 0xA2), read_s16(data, offset + 0xA4), read_s16(data, offset + 0xA6)]

    # Read raw radial velocity values (SIGNED - can be negative for inward motion)
    raw_radial_min_start = read_s16(data, offset + 0x5C)
    raw_radial_max_start = read_s16(data, offset + 0x5E)
    raw_radial_min_end = read_s16(data, offset + 0x60)
    raw_radial_max_end = read_s16(data, offset + 0x62)

    # Read raw homing strength values (SIGNED - PSX uses `lh` signed halfword load)
    raw_homing_min_start = read_s16(data, offset + 0xB8)
    raw_homing_max_start = read_s16(data, offset + 0xBA)
    raw_homing_min_end = read_s16(data, offset + 0xBC)
    raw_homing_max_end = read_s16(data, offset + 0xBE)

    emitter = {
        "index": index,
        "file_offset": offset,

        # Core control (0x00-0x07)
        "byte_00": read_u8(data, offset + 0x00),
        "anim_index": read_u8(data, offset + 0x01),
        "motion_type_flag": read_u8(data, offset + 0x02),
        "animation_target_flag": read_u8(data, offset + 0x03),
        "anim_param": read_u8(data, offset + 0x04),
        "byte_05": read_u8(data, offset + 0x05),
        "emitter_flags_lo": read_u8(data, offset + 0x06),
        "emitter_flags_hi": read_u8(data, offset + 0x07),

        # Curve indices raw bytes for reference
        "curve_indices_raw": curve_bytes,

        # Decoded curve indices
        "curves": {
            "position": decode_curve_index(curve_bytes[0] & 0x0F),
            "spread": decode_curve_index((curve_bytes[0] >> 4) & 0x0F),
            "velocity_base_angle": decode_curve_index(curve_bytes[1] & 0x0F),
            "velocity_dir_spread": decode_curve_index((curve_bytes[1] >> 4) & 0x0F),
            "inertia": decode_curve_index(curve_bytes[2] & 0x0F),
            "weight": decode_curve_index(curve_bytes[3] & 0x0F),
            "radial_velocity": decode_curve_index((curve_bytes[3] >> 4) & 0x0F),
            "acceleration": decode_curve_index(curve_bytes[4] & 0x0F),
            "drag": decode_curve_index((curve_bytes[4] >> 4) & 0x0F),
            "lifetime": decode_curve_index(curve_bytes[5] & 0x0F),
            "target_offset": decode_curve_index((curve_bytes[5] >> 4) & 0x0F),
            "particle_count": decode_curve_index((curve_bytes[6] >> 4) & 0x0F),
            "spawn_interval": decode_curve_index(curve_bytes[7] & 0x0F),
            "homing_strength": decode_curve_index((curve_bytes[7] >> 4) & 0x03),
            "homing_blend": decode_curve_index((curve_bytes[7] >> 6) & 0x03),
        },

        # Color curves (0x10-0x11)
        "color_curves": {
            "r": read_u8(data, offset + 0x10) & 0x0F,
            "g": (read_u8(data, offset + 0x10) >> 4) & 0x0F,
            "b": read_u8(data, offset + 0x11) & 0x0F,
        },

        # =========================================================
        # CONVERTED VALUES - Godot-ready units
        # =========================================================

        # Position - converted to Godot units, Y-flipped
        "position": {
            "start": convert_position(raw_pos_start),
            "end": convert_position(raw_pos_end),
        },

        # Spread - converted to Godot units, Y-flipped
        "spread": {
            "start": convert_position(raw_spread_start),
            "end": convert_position(raw_spread_end),
        },

        # Velocity base angles - converted to radians
        "velocity_base_angle": {
            "start": convert_angles(raw_angle_start),
            "end": convert_angles(raw_angle_end),
        },

        # Velocity direction spread - converted to radians
        "velocity_direction_spread": {
            "start": convert_angles(raw_vel_spread_start),
            "end": convert_angles(raw_vel_spread_end),
        },

        # Inertia - keep raw (used directly in physics formula)
        # FFT: new_vel = ((inertia - threshold) * old_vel + accel * 4096) / inertia
        "inertia": {
            "min_start": read_s16(data, offset + 0x44),
            "max_start": read_s16(data, offset + 0x46),
            "min_end": read_s16(data, offset + 0x48),
            "max_end": read_s16(data, offset + 0x4A),
        },

        # Weight - keep raw (used as gravity multiplier, divided by 4096 in formula)
        # FFT: gravity_effect = gravity * weight >> 12
        "weight": {
            "min_start": read_s16(data, offset + 0x54),
            "max_start": read_s16(data, offset + 0x56),
            "min_end": read_s16(data, offset + 0x58),
            "max_end": read_s16(data, offset + 0x5A),
        },

        # Radial velocity - converted to Godot units/frame
        "radial_velocity": {
            "min_start": convert_velocity(raw_radial_min_start),
            "max_start": convert_velocity(raw_radial_max_start),
            "min_end": convert_velocity(raw_radial_min_end),
            "max_end": convert_velocity(raw_radial_max_end),
        },

        # Acceleration - converted to Godot units, Y-flipped
        "acceleration": {
            "min_start": convert_accel(raw_accel_min_start),
            "max_start": convert_accel(raw_accel_max_start),
            "min_end": convert_accel(raw_accel_min_end),
            "max_end": convert_accel(raw_accel_max_end),
        },

        # Drag - converted to Godot units, Y-flipped
        "drag": {
            "min_start": convert_accel(raw_drag_min_start),
            "max_start": convert_accel(raw_drag_max_start),
            "min_end": convert_accel(raw_drag_min_end),
            "max_end": convert_accel(raw_drag_max_end),
        },

        # Lifetime - keep as frames (no conversion needed)
        "lifetime": {
            "min_start": read_u16(data, offset + 0x94),
            "max_start": read_u16(data, offset + 0x96),
            "min_end": read_u16(data, offset + 0x98),
            "max_end": read_u16(data, offset + 0x9A),
        },

        # Target offset - converted to Godot units, Y-flipped
        "target_offset": {
            "start": convert_position(raw_target_start),
            "end": convert_position(raw_target_end),
        },

        # Spawn control - no conversion (frames/counts)
        "spawn": {
            "particle_count_start": read_u16(data, offset + 0xB0),
            "particle_count_end": read_u16(data, offset + 0xB2),
            "interval_start": read_u16(data, offset + 0xB4),
            "interval_end": read_u16(data, offset + 0xB6),
        },

        # Homing strength - converted to Godot units (same as acceleration scale)
        "homing_strength": {
            "min_start": convert_homing_strength(raw_homing_min_start),
            "max_start": convert_homing_strength(raw_homing_max_start),
            "min_end": convert_homing_strength(raw_homing_min_end),
            "max_end": convert_homing_strength(raw_homing_max_end),
        },

        # Child emitters - no conversion (indices)
        "child_emitter_on_death": read_u8(data, offset + 0xC0),
        "child_emitter_mid_life": read_u8(data, offset + 0xC1),

        # Callback params (meaning varies per callback ID, not used by normal particles)
        "callback_params": {
            "param_4C": read_u8(data, offset + 0x4C),
            "param_4E": read_u8(data, offset + 0x4E),
            "param_A8": read_s16(data, offset + 0xA8),
            "param_AA": read_s16(data, offset + 0xAA),
            "param_AC": read_s16(data, offset + 0xAC),
            "param_AE": read_s16(data, offset + 0xAE),
        },

        # =========================================================
        # RAW VALUES - for reference/debugging
        # =========================================================
        "raw": {
            "position_start": raw_pos_start,
            "position_end": raw_pos_end,
            "spread_start": raw_spread_start,
            "spread_end": raw_spread_end,
            "angle_start": raw_angle_start,
            "angle_end": raw_angle_end,
            "vel_spread_start": raw_vel_spread_start,
            "vel_spread_end": raw_vel_spread_end,
            "radial_min_start": raw_radial_min_start,
            "radial_max_start": raw_radial_max_start,
            "radial_min_end": raw_radial_min_end,
            "radial_max_end": raw_radial_max_end,
            "accel_min_start": raw_accel_min_start,
            "accel_max_start": raw_accel_max_start,
            "accel_min_end": raw_accel_min_end,
            "accel_max_end": raw_accel_max_end,
            "drag_min_start": raw_drag_min_start,
            "drag_max_start": raw_drag_max_start,
            "drag_min_end": raw_drag_min_end,
            "drag_max_end": raw_drag_max_end,
            "target_start": raw_target_start,
            "target_end": raw_target_end,
            "homing_min_start": raw_homing_min_start,
            "homing_max_start": raw_homing_max_start,
            "homing_min_end": raw_homing_min_end,
            "homing_max_end": raw_homing_max_end,
        },
    }

    # Decode flags
    motion_type = emitter["motion_type_flag"]
    anim_target = emitter["animation_target_flag"]
    flags_lo = emitter["emitter_flags_lo"]
    flags_hi = emitter["emitter_flags_hi"]

    emitter["flags"] = {
        "align_to_velocity": bool(motion_type & 0x02),
        "target_anchor_mode": TARGET_ANCHOR_MODES.get(motion_type & 0xE0, f"UNKNOWN_{motion_type & 0xE0:02X}"),
        "spread_mode": "BOX" if (anim_target & 0x01) else "SPHERICAL",
        "emitter_anchor_mode": ANCHOR_MODES.get((anim_target >> 1) & 0x07, "UNKNOWN"),
        "color_curve_enabled": bool(flags_lo & 0x40),
        "velocity_inward": bool(flags_lo & 0x10),
        "child_death_enabled": bool(flags_lo & 0x03),
        "child_midlife_enabled": bool(flags_lo & 0x0C),
        "align_to_facing": bool(flags_hi & 0x04),
        "homing_arrival_threshold": flags_hi & 0x03,
    }

    return emitter


def parse_all_emitters(data: bytes, effect_data_ptr: int, emitter_count: int) -> List[Dict[str, Any]]:
    """Parse all emitters from effect data section"""
    emitters = []
    for i in range(emitter_count):
        offset = effect_data_ptr + PARTICLE_HEADER_SIZE + (i * EMITTER_SIZE)
        emitters.append(parse_emitter(data, offset, i))
    return emitters


# =============================================================================
# Curve Parsing
# =============================================================================

def parse_curves(data: bytes, anim_table_ptr: int, section_size: int) -> List[Dict[str, Any]]:
    """Parse animation curves (160 bytes each)"""
    if section_size < 4:
        return []

    curve_count = read_u32(data, anim_table_ptr)
    curves = []

    for i in range(curve_count):
        offset = anim_table_ptr + 4 + (i * CURVE_LENGTH)
        if offset + CURVE_LENGTH > len(data):
            break

        values = [read_u8(data, offset + j) for j in range(CURVE_LENGTH)]
        curves.append({
            "index": i,
            "values": values,
        })

    return curves


# =============================================================================
# Frame Parsing
# =============================================================================

def parse_frame(data: bytes, offset: int, frame_index: int) -> Dict[str, Any]:
    """Parse single 24-byte frame"""
    flags_byte0 = read_u8(data, offset)
    flags_byte1 = read_u8(data, offset + 1)
    texture_page = read_u16(data, offset + 2)

    # Decode flags
    palette_id = flags_byte0 & 0x0F
    # Bit 4 selects which CLUT LINE the sub-palette is read from: clear = palette 1
    # (VRAM 0x7B00), set = palette 2 (0x7B40). Verified in the sprite renderer at
    # 0x801a5664. A static per-sprite choice, not animated.
    uses_palette_2 = bool(flags_byte0 & 0x10)
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

    # UV coordinates
    uv_x = read_u8(data, offset + 4)
    uv_y = read_u8(data, offset + 5)
    uv_width = read_u8(data, offset + 6)
    uv_height = read_u8(data, offset + 7)

    # Handle signed UV dimensions
    if width_signed and uv_width > 127:
        uv_width = uv_width - 256
    if height_signed and uv_height > 127:
        uv_height = uv_height - 256

    # Vertices (4 corners, signed 16-bit)
    return {
        "index": frame_index,
        "palette_id": palette_id,
        "uses_palette_2": uses_palette_2,
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


def parse_frames_section(data: bytes, frames_ptr: int, section_size: int):
    """Parse frames section (complex structure with groups and framesets).

    Returns (framesets, group_sizes) where group_sizes is a list of per-group
    frameset counts. The flat framesets array contains group 0's framesets first,
    then group 1's, etc. group_sizes lets the runtime compute cumulative offsets
    so each emitter can index into its own group's framesets starting at 0.
    """
    framesets = []
    group_sizes = []

    if section_size < 8:
        return framesets, group_sizes

    # Header: byte 0 = group_count
    group_count = read_u8(data, frames_ptr)
    group_entries_end = 4 + group_count * 2

    if group_entries_end >= section_size:
        return framesets, group_sizes

    # Read group entry offsets (each points to that group's frameset offset table)
    group_entry_offsets = []
    for g in range(group_count):
        entry_offset = read_u16(data, frames_ptr + 4 + g * 2)
        group_entry_offsets.append(entry_offset)

    # First frameset offset tells us where frame data starts
    first_offset = read_u16(data, frames_ptr + group_entries_end)
    frame_sets_data_start = first_offset + 4
    max_frame_sets = (frame_sets_data_start - group_entries_end) // 2

    if max_frame_sets <= 0 or max_frame_sets > 500:
        return framesets, group_sizes

    # Compute per-group frameset counts from gaps between group entry offsets
    # Each group's offset table starts at group_entry_offsets[g] and ends at the
    # next group's start (or at frame_sets_data_start for the last group).
    # Each entry in the offset table is 2 bytes (u16).
    for g in range(group_count):
        start = group_entry_offsets[g]
        if g + 1 < group_count:
            end = group_entry_offsets[g + 1]
        else:
            # Last group ends where frameset data begins
            end = first_offset
        group_sizes.append((end - start) // 2)

    # Count valid offset table entries
    num_frame_sets = 0
    for i in range(max_frame_sets):
        offset_pos = frames_ptr + group_entries_end + i * 2
        if offset_pos + 2 > frames_ptr + section_size:
            break
        raw_offset = read_u16(data, offset_pos)
        if raw_offset < first_offset:
            break
        num_frame_sets += 1

    # Parse each frameset
    for fs_idx in range(num_frame_sets):
        offset_pos = frames_ptr + group_entries_end + fs_idx * 2
        raw_offset = read_u16(data, offset_pos)
        fs_offset = frames_ptr + raw_offset + 4

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

    return framesets, group_sizes


# =============================================================================
# Animation Sequence Parsing
# =============================================================================

def parse_animation_sequence(data: bytes, offset: int, seq_idx: int) -> Dict[str, Any]:
    """Parse single animation sequence"""
    sequence = {
        "index": seq_idx,
        "opcodes": [],
    }

    pos = offset
    max_pos = min(offset + 1000, len(data))  # Safety limit

    while pos < max_pos:
        opcode = read_u8(data, pos)

        if opcode <= 0x7F:
            # FRAME: display frameset
            if pos + 3 > max_pos:
                break
            duration = read_u8(data, pos + 1)
            depth_mode = read_u8(data, pos + 2)
            sequence["opcodes"].append({
                "type": "FRAME",
                "frameset": opcode,
                "duration": duration,
                "depth_mode": depth_mode,
            })
            pos += 3

            # duration 0 often signals end
            if duration == 0 and opcode == 0 and depth_mode == 0:
                break

        elif opcode == 0x81:
            # LOOP
            sequence["opcodes"].append({"type": "LOOP"})
            pos += 1
            break  # Loop is always end of sequence

        elif opcode == 0x82:
            # SET_OFFSET
            if pos + 5 > max_pos:
                break
            offset_x = read_s16(data, pos + 1)
            offset_y = read_s16(data, pos + 3)
            sequence["opcodes"].append({
                "type": "SET_OFFSET",
                "x": offset_x,
                "y": offset_y,
            })
            pos += 5

        elif opcode == 0x83:
            # ADD_OFFSET
            if pos + 3 > max_pos:
                break
            delta_x = data[pos + 1]
            delta_y = data[pos + 2]
            # Sign extend
            if delta_x > 127:
                delta_x -= 256
            if delta_y > 127:
                delta_y -= 256
            sequence["opcodes"].append({
                "type": "ADD_OFFSET",
                "dx": delta_x,
                "dy": delta_y,
            })
            pos += 3

        else:
            # Unknown, skip
            pos += 1
            break

    return sequence


def parse_animations_section(data: bytes, animation_ptr: int, section_size: int) -> List[Dict[str, Any]]:
    """Parse animation sequences section"""
    if section_size < 4:
        return []

    seq_count = read_u32(data, animation_ptr)
    if seq_count > 256 or seq_count == 0:
        return []

    sequences = []

    # Read offset table
    for i in range(seq_count):
        offset_table_pos = animation_ptr + 4 + i * 2
        if offset_table_pos + 2 > animation_ptr + section_size:
            break

        seq_offset = read_u16(data, offset_table_pos)
        seq_data_offset = animation_ptr + 4 + seq_offset

        if seq_data_offset >= len(data):
            break

        sequences.append(parse_animation_sequence(data, seq_data_offset, i))

    return sequences


def calculate_animation_duration(animation: Dict[str, Any]) -> int:
    """Calculate total duration of an animation in frames.

    Sums FRAME opcode durations. Stops at LOOP opcode (animation would repeat).
    Returns 60 as default if no FRAME opcodes found.
    """
    total = 0
    for opcode in animation.get("opcodes", []):
        op_type = opcode.get("type", "")
        if op_type == "FRAME":
            total += opcode.get("duration", 0)
        elif op_type == "LOOP":
            # LOOP means animation repeats - duration is frames before loop
            break

    return total if total > 0 else 60  # Default to 60 if no frames


def get_animation_durations(animations: List[Dict[str, Any]]) -> Dict[int, int]:
    """Build dict of animation index -> duration in frames."""
    durations = {}
    for anim in animations:
        idx = anim.get("index", 0)
        durations[idx] = calculate_animation_duration(anim)
    return durations


# =============================================================================
# Script Parsing
# =============================================================================

def parse_script(data: bytes, script_ptr: int, section_size: int) -> List[Dict[str, Any]]:
    """Parse effect script bytecode"""
    instructions = []
    pos = script_ptr
    end_pos = script_ptr + section_size

    while pos < end_pos:
        if pos + 2 > len(data):
            break

        opcode_word = read_u16(data, pos)
        opcode_id = opcode_word & 0x1FF
        flags = (opcode_word >> 9) & 0x7F

        if opcode_id in OPCODES:
            name, size = OPCODES[opcode_id]
        else:
            name, size = f"unknown_{opcode_id}", 2

        instr = {
            "offset": pos - script_ptr,
            "opcode": opcode_id,
            "name": name,
            "flags": flags,
            "size": size,
        }

        # Read arguments based on size
        if size >= 4 and pos + 4 <= len(data):
            instr["arg1"] = read_s16(data, pos + 2)
        if size >= 6 and pos + 6 <= len(data):
            instr["arg2"] = read_s16(data, pos + 4)
        if size >= 8 and pos + 8 <= len(data):
            instr["arg3"] = read_s16(data, pos + 6)

        instructions.append(instr)
        pos += size

        # Stop at end opcode
        if opcode_id == 4:
            break

    return instructions


# =============================================================================
# Timeline Parsing
# =============================================================================

# --- Particle-timeline channel layout (single source of truth: reader + writer) ---
# A particle channel is a fixed 128-byte, 25-slot structure-of-arrays.
PARTICLE_CHANNEL_SIZE = 128
PARTICLE_SLOTS = 25
# SoA field offsets within the 128-byte channel. NOTE the time[]/emitter_id[]
# OVERLAP: time[] is 25 s16 spanning bytes 0x00..0x31 (its last byte, time[24].hi,
# is at 0x31), and emitter_id[] starts at 0x31 — so byte 0x31 is PHYSICALLY SHARED.
# In real data max_keyframe never reaches 24 (time[24] is a phantom slot), and
# emitter_id[0] is the semantic owner of 0x31 (the parser reads it AS emitter_id[0]).
# A byte-exact writer must therefore write time[] BEFORE emitter_id[] so emitter_id
# wins byte 0x31 — see write_effect_particle_timeline.
PARTICLE_OFF_TIME = 0x00          # time[i]         s16 at +i*2
PARTICLE_OFF_EMITTER_ID = 0x31    # emitter_id[i]   u8  at +i
PARTICLE_OFF_ACTION_FLAGS = 0x4A  # action_flags[i] u16 at +i*2
PARTICLE_OFF_MAX_KEYFRAME = 0x7E  # max_keyframe    s16

# Per-context channel base offsets (from the Lua parser). for_each channels are
# based at timeline_ptr + 8; phase1/phase2 at timeline_ptr directly.
PARTICLE_FOR_EACH_OFFSETS = [0x0004, 0x0084, 0x0104, 0x0184, 0x0204]
PARTICLE_PHASE1_OFFSETS = [0x082A, 0x08AA, 0x092A, 0x09AA, 0x0A2A]
PARTICLE_PHASE2_OFFSETS = [0x0AAA, 0x0B2A, 0x0BAA, 0x0C2A, 0x0CAA]
PARTICLE_FOR_EACH_BASE_BIAS = 8   # for_each base = timeline_ptr + 8


def particle_channel_offset(timeline_ptr: int, context: str, channel_index: int) -> int:
    """File offset of a particle channel from its context + lane index. The ONE
    layout source shared by the reader (parse_timeline) and the writer
    (write_effect_particle_timeline), so they can never disagree on geometry."""
    if context == "for_each":
        return timeline_ptr + PARTICLE_FOR_EACH_BASE_BIAS + PARTICLE_FOR_EACH_OFFSETS[channel_index]
    if context == "phase1":
        return timeline_ptr + PARTICLE_PHASE1_OFFSETS[channel_index]
    if context == "phase2":
        return timeline_ptr + PARTICLE_PHASE2_OFFSETS[channel_index]
    raise ValueError("unknown particle context %r" % context)


def parse_particle_channel(data: bytes, offset: int, context: str, channel_idx: int) -> Dict[str, Any]:
    """Parse 128-byte particle channel"""
    channel = {
        "context": context,
        "channel_index": channel_idx,
        "keyframes": [],
    }

    max_keyframe = read_s16(data, offset + PARTICLE_OFF_MAX_KEYFRAME)
    channel["max_keyframe"] = max_keyframe

    for i in range(PARTICLE_SLOTS):
        time = read_s16(data, offset + PARTICLE_OFF_TIME + i * 2)
        emitter_id = read_u8(data, offset + PARTICLE_OFF_EMITTER_ID + i)
        action_flags = read_u16(data, offset + PARTICLE_OFF_ACTION_FLAGS + i * 2)

        channel["keyframes"].append({
            "time": time,
            "emitter_id": emitter_id,
            "action_flags": action_flags,
        })

    return channel


HIT_REACT_FLAG = 0x10  # action_flags bit identifying a HIT_REACT keyframe


def _simulate_for_each_phase_block(
    particle_channels: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Walk every for_each channel using the runtime PhaseBlock model
    (`addons/exmateria_effects/subsystem/PhaseBlock.gd`) and return when its keyframe action_flags
    actually fire. The runtime treats `kf[N].time` as *cumulative*: a channel
    sits in keyframe N for `kf[N].time - kf[N-1].time` 30 Hz frames (zero-
    duration transitions still take one frame, matching the runtime's
    `dur 0 -> -1 -> advance` step), then emits kf[N+1].action_flags as it
    advances. Initial dur = kf[1].time, decremented from frame 0 — so a
    channel with kf[1].time = T advances out of kf[1] at PhaseBlock cf =
    max(0, T - 1). kf[1].action_flags fires at cf = 0 in initialize().

    Returns a dict with:
      - hit_cfs: sorted list of PhaseBlock cf values where HIT_REACT
        (action_flags & 0x10) fires across all for_each channels.
      - last_active_cf: the largest cf at which any for_each channel was
        still running (i.e. the for_each PhaseBlock-end frame, relative to
        the for_each-open edge at effect_frame = phase1_duration).

    Both numbers are in **CPU effect_frame units relative to the for_each
    open edge**; add phase1_duration to convert to absolute effect_frame.
    """
    hit_cfs: List[int] = []
    last_active_cf = 0

    for ch in particle_channels:
        if ch.get("context") != "for_each":
            continue
        max_kf = int(ch.get("max_keyframe", 0))
        if max_kf < 1:
            continue
        kfs = ch.get("keyframes", []) or []
        if len(kfs) <= max_kf:
            continue

        # initialize(): emit kf[1].action_flags at cf=0 if non-zero.
        if (int(kfs[1].get("action_flags", 0)) & HIT_REACT_FLAG) != 0:
            hit_cfs.append(0)

        current_kf = 1
        dur = int(kfs[1].get("time", 0))
        cf = 0
        # advance_frame loop: decrement; on dur<=0 advance and emit next kf's
        # action_flags at current cf, then increment cf at end-of-call.
        # Safety bound prevents infinite loop on malformed data.
        guard = 0
        while current_kf <= max_kf:
            guard += 1
            if guard > 100_000:
                break
            dur -= 1
            if dur <= 0:
                current_kf += 1
                if current_kf > max_kf:
                    if cf > last_active_cf:
                        last_active_cf = cf
                    break
                new_kf = kfs[current_kf]
                prev_kf = kfs[current_kf - 1]
                dur = int(new_kf.get("time", 0)) - int(prev_kf.get("time", 0))
                if (int(new_kf.get("action_flags", 0)) & HIT_REACT_FLAG) != 0:
                    hit_cfs.append(cf)
            cf += 1

    hit_cfs.sort()
    return {"hit_cfs": hit_cfs, "last_active_cf": last_active_cf}


def _derive_cinematic_timing(
    header: Dict[str, Any],
    particle_channels: List[Dict[str, Any]],
    camera: Optional[Dict[str, Any]] = None,
) -> Dict[str, int]:
    """Compute the cinematic-orchestrator timing fields.

    Consumed by the GPU cinematic-spell orchestrator (issue #53). All three
    fields are absolute frames from the orchestrator's U_CINEMATIC_TIMER == 0
    reference (the cinematic-enter edge).

    - first_hit_frame: absolute effect_frame at which the runtime PhaseBlock
      would fire HIT_REACT (action_flags & 0x10), or 0 if no for_each
      HIT_REACT exists. Computed by simulating the cumulative-duration
      walk (see _simulate_for_each_phase_block) and adding phase1_duration
      (the effect_frame at which the for_each phase opens).
    - for_each_delay: stride between consecutive HIT_REACT fires in the
      runtime model, clamped max(1, raw). Defaults to 1 when fewer than
      2 HIT_REACTs exist.
    - total_frames: the absolute effect_frame at which the *visible*
      cinematic ends. Picks the larger of:
        (a) the camera-walker phase2 last keyframe (camera holds at
            strategy-view position once this passes), and
        (b) the latest AoE HIT_REACT fire frame across a worst-case
            UNITS_PER_BATTLE - 1 target sweep (otherwise multi-target
            damage on the last target would never land).
      Falls back to the for_each PhaseBlock's last active frame for
      effects with no walkable phase2 camera animation.

    All values returned are in **CPU effect_frame units (30 Hz)**. The GPU
    orchestrator ticks BH_CINEMATIC_TIMER at host frame rate (~60 Hz);
    GPUEffectTimingLoader applies the 30 → host-tick scale on upload to the
    SSBO so the on-disk JSON stays in the runtime PhaseBlock unit.

    Earlier this returned the largest *for_each particle keyframe* time
    using the absolute-time interpretation (`base + kf.time`), which
    disagreed with the runtime PhaseBlock by hundreds of frames per
    effect. The runtime is authoritative — EffectViewer plays the
    keyframes back via PhaseBlock's cumulative-duration semantics — so the
    parser now mirrors that walk verbatim.

    Empirical grilling note (issue #53): scanning all 401 effects respecting
    max_keyframe, 223 real HIT_REACT keyframes were found — every one in
    for_each context, 0 in phase1/phase2. So scanning for_each only is sound
    for the HIT_REACT-derived fields.
    """
    phase1_duration = header.get("phase1_duration", 0) or 0
    phase2_delay = header.get("phase2_delay", 0) or 0

    sim = _simulate_for_each_phase_block(particle_channels)
    hit_cfs: List[int] = sim["hit_cfs"]
    last_active_cf: int = sim["last_active_cf"]

    if hit_cfs:
        first_hit_frame = phase1_duration + hit_cfs[0]
    else:
        first_hit_frame = 0

    if len(hit_cfs) >= 2:
        for_each_delay = max(1, hit_cfs[1] - hit_cfs[0])
    else:
        for_each_delay = 1

    # Camera-walker-derived visible-cinematic end. Phase 2 of the camera is
    # the return-to-strategy-view leg; once its last walkable keyframe's
    # end_frame is passed, the camera holds at its destination — that's the
    # natural "the cinematic is visually done" marker for most spells (e.g.
    # E016 Fire). Falls back to the particle-derived bound when no phase2
    # camera animation is present.
    phase2_visible_end = -1
    if camera is not None:
        phase2 = camera.get("phase2")
        if isinstance(phase2, dict):
            max_kf = int(phase2.get("max_keyframe", 0))
            kfs = phase2.get("keyframes", []) or []
            for i, kf in enumerate(kfs):
                if i > max_kf:
                    break
                ef = int(kf.get("end_frame", 0))
                if ef > phase2_visible_end:
                    phase2_visible_end = ef

    camera_visible_end = (
        phase1_duration + phase2_delay + phase2_visible_end
        if phase2_visible_end > 0 else -1
    )

    # Even for camera-bound cinematics, total_frames must reach the latest
    # AoE HIT_REACT fire — orchestrator stamps fire_frame = first_hit_frame
    # + N * for_each_delay per target, and the cinematic-end check ALWAYS
    # gates on `new_timer >= total_frames`. If we tear down before the last
    # target's fire_frame, that target's damage / status never lands.
    # Worst case is the full battle minus the caster (UNITS_PER_BATTLE - 1).
    # Some spells (e.g. E032 Haste) place their lone HIT_REACT keyframe deep
    # past the camera-return — for those, this branch dominates the bound.
    UNITS_PER_BATTLE_FALLBACK = 8
    last_fire_frame = (
        first_hit_frame + (UNITS_PER_BATTLE_FALLBACK - 1) * for_each_delay
        if first_hit_frame > 0 else 0
    )

    # for_each PhaseBlock's natural end frame in absolute effect_frame units.
    # Used as the no-camera fallback: it tracks when the last for_each channel's
    # max_keyframe is consumed, the same instant the runtime PhaseBlock reports
    # is_finished(). For most effects this trails the camera return; for
    # cinematic-less spells (no walkable phase2) it's the only bound.
    for_each_block_end = phase1_duration + last_active_cf

    if camera_visible_end > 0:
        total_frames = max(camera_visible_end, last_fire_frame)
    else:
        total_frames = max(for_each_block_end, last_fire_frame)

    return {
        "first_hit_frame": first_hit_frame,
        "for_each_delay": for_each_delay,
        "total_frames": total_frames,
    }


def parse_timeline(data: bytes, timeline_ptr: int, section_size: int) -> Dict[str, Any]:
    """Parse timeline section"""
    timeline = {
        "header": {},
        "particle_channels": [],
    }

    if section_size < 12:
        return timeline

    # Parse header (12 bytes)
    timeline["header"] = {
        "unknown_00": read_s16(data, timeline_ptr + 0x00),
        "unknown_02": read_s16(data, timeline_ptr + 0x02),
        "phase1_duration": read_s16(data, timeline_ptr + 0x04),
        "spawn_delay": read_s16(data, timeline_ptr + 0x06),
        "unknown_08": read_s16(data, timeline_ptr + 0x08),
        "phase2_delay": read_s16(data, timeline_ptr + 0x0A),
    }

    # Channel offsets shared with the writer (see particle_channel_offset).
    for context, offsets in (
        ("for_each", PARTICLE_FOR_EACH_OFFSETS),
        ("phase1", PARTICLE_PHASE1_OFFSETS),
        ("phase2", PARTICLE_PHASE2_OFFSETS),
    ):
        for i in range(len(offsets)):
            offset = particle_channel_offset(timeline_ptr, context, i)
            if offset + PARTICLE_CHANNEL_SIZE <= len(data):
                timeline["particle_channels"].append(
                    parse_particle_channel(data, offset, context, i)
                )

    # Cinematic timing fields are derived in extract_effect() once the camera
    # tables are also parsed — the visible-cinematic end_frame depends on the
    # camera walker's phase2 keyframes, which aren't part of this section.
    # A best-effort particle-only seed lands here so callers that only invoke
    # parse_timeline (tests, ad-hoc tooling) still get sane defaults.
    timeline["header"].update(
        _derive_cinematic_timing(timeline["header"], timeline["particle_channels"], camera=None)
    )

    return timeline


# =============================================================================
# Screen-subsystem keyframe parsing (background color animation)
# =============================================================================

# Screen-subsystem keyframe offsets from timeline section (from LUA parser)
# for_each uses timeline_section_offset + 8 as base
# phase1/phase2 use timeline_section_offset as base
SCREEN_TRACK_OFFSETS = {
    "for_each": {"data": 0x057E, "max_keyframe": 0x06A8},  # Base = timeline + 8
    "phase1": {"data": 0x1036, "max_keyframe": None},  # max_kf at end (offset 298)
    "phase2": {"data": 0x13BA, "max_keyframe": None},  # max_kf at end (offset 298)
}

MAX_SCREEN_KEYFRAMES = 33


def parse_screen_channel(data: bytes, base_offset: int, context: str, max_kf_offset: Optional[int] = None) -> Dict[str, Any]:
    """Parse the screen subsystem's single channel for one phase (298 bytes of
    keyframes + 2 bytes max_keyframe).

    Screen channel keyframe layout (per LUA parser):
    - time values: offset 0x00 + i*2 (signed 16-bit)
    - start RGB: offset 0x42 + i*3
    - end RGB: offset 0xA5 + i*3
    - ctrl byte: offset 0x108 + i
    - max_keyframe: offset 298 (or specified)
    """
    channel = {
        "context": context,
        "keyframes": [],
    }

    # Read max_keyframe
    if max_kf_offset is not None:
        channel["max_keyframe"] = read_s16(data, max_kf_offset)
    else:
        # Default: at end of channel (offset 298)
        channel["max_keyframe"] = read_s16(data, base_offset + 298)

    # Parse all 33 keyframes
    for i in range(MAX_SCREEN_KEYFRAMES):
        # Time value (signed 16-bit)
        time_value = read_s16(data, base_offset + i * 2)

        # Start RGB (gradient top / tint color)
        start_r = read_u8(data, base_offset + 0x42 + i * 3)
        start_g = read_u8(data, base_offset + 0x43 + i * 3)
        start_b = read_u8(data, base_offset + 0x44 + i * 3)

        # End RGB (gradient bottom)
        end_r = read_u8(data, base_offset + 0xA5 + i * 3)
        end_g = read_u8(data, base_offset + 0xA6 + i * 3)
        end_b = read_u8(data, base_offset + 0xA7 + i * 3)

        # Control byte
        ctrl = read_u8(data, base_offset + 0x108 + i)

        # Decode ctrl byte for screen-channel keyframes:
        # bit 7 = TINT mode (ctrl >= 128), bits 0-6 = blend mode
        is_tint = ctrl >= 128
        blend_mode = ctrl % 128
        mode = "TINT" if is_tint else "FADE"

        # Calculate duration: time_value << 3 (multiply by 8) per PSX decompilation
        duration_frames = time_value * 8 if time_value > 0 else 1

        channel["keyframes"].append({
            "index": i,
            "time_value": time_value,
            "duration_frames": duration_frames,
            "start_r": start_r,
            "start_g": start_g,
            "start_b": start_b,
            "end_r": end_r,
            "end_g": end_g,
            "end_b": end_b,
            "ctrl": ctrl,
            "mode": mode,
            "blend_mode": blend_mode,
            # Authoritative PSX-domain bytes (#254 slice 4). This is the source
            # of truth the byte-exact writer (#255 slice 5) serializes from; the
            # sibling fields above (duration_frames, mode, blend_mode) are a
            # derived cache. A screen keyframe = one screen tween / lane event.
            "raw": {
                "time_value": time_value,
                "start_r": start_r,
                "start_g": start_g,
                "start_b": start_b,
                "end_r": end_r,
                "end_g": end_g,
                "end_b": end_b,
                "ctrl": ctrl,
            },
        })

    return channel


def parse_all_screen_keyframes(data: bytes, timeline_ptr: int) -> Dict[str, Any]:
    """Parse all screen-subsystem channels (one per phase: for_each,
    phase1, phase2)."""
    screen = {}

    # for_each: base is timeline_ptr + 8
    for_each_base = timeline_ptr + 8
    offsets = SCREEN_TRACK_OFFSETS["for_each"]
    channel_offset = for_each_base + offsets["data"]
    max_kf_offset = for_each_base + offsets["max_keyframe"]

    if channel_offset + 300 <= len(data):
        screen["for_each"] = parse_screen_channel(
            data, channel_offset, "for_each", max_kf_offset
        )

    # phase1: base is timeline_ptr
    offsets = SCREEN_TRACK_OFFSETS["phase1"]
    channel_offset = timeline_ptr + offsets["data"]

    if channel_offset + 300 <= len(data):
        screen["phase1"] = parse_screen_channel(
            data, channel_offset, "phase1", None
        )

    # phase2: base is timeline_ptr
    offsets = SCREEN_TRACK_OFFSETS["phase2"]
    channel_offset = timeline_ptr + offsets["data"]

    if channel_offset + 300 <= len(data):
        screen["phase2"] = parse_screen_channel(
            data, channel_offset, "phase2", None
        )

    return screen


# =============================================================================
# Palette-subsystem keyframe parsing (3 channels: affected_units, caster, target)
# =============================================================================

# Palette-subsystem keyframe offsets from timeline section
# Channel 0 = Affected Units (affects both units AND map/terrain)
# Channel 1 = Caster only
# Channel 2 = Target only
# Each channel is 198 bytes: 66 time + 99 RGB + 33 ctrl
PALETTE_TRACK_OFFSETS = {
    "for_each": {
        "affected_units": 0x0326,
        "caster": 0x03EE,
        "target": 0x04B6,
    },
    "phase1": {
        "affected_units": 0x0DDE,
        "caster": 0x0EA6,
        "target": 0x0F6E,
    },
    "phase2": {
        "affected_units": 0x1162,
        "caster": 0x122A,
        "target": 0x12F2,
    },
}

PALETTE_TRACK_SIZE = 198
MAX_PALETTE_KEYFRAMES = 33


def parse_palette_channel(data: bytes, base_offset: int, context: str, channel_name: str) -> Dict[str, Any]:
    """Parse a single palette-subsystem channel (198 bytes) for one phase.

    Palette channel keyframe layout:
    - time values: offset 0x00 + i*2 (signed 16-bit)
    - RGB triplets: offset 0x42 + i*3 (interleaved R, G, B)
    - ctrl byte: offset 0xA5 + i
    """
    channel = {
        "context": context,
        "channel_name": channel_name,
        "keyframes": [],
        "max_keyframe": 0,
    }

    # Read max_keyframe from the dedicated 16-bit field at base + 0xC6
    # (each palette channel is 198 bytes of data followed by a 2-byte max_keyframe field)
    max_kf_offset = base_offset + PALETTE_TRACK_SIZE
    if max_kf_offset + 2 <= len(data):
        max_kf = read_s16(data, max_kf_offset)
        # Clamp to valid range
        if max_kf < 0 or max_kf >= MAX_PALETTE_KEYFRAMES:
            max_kf = 0
    else:
        max_kf = 0
    channel["max_keyframe"] = max_kf

    # Parse all keyframes
    for i in range(MAX_PALETTE_KEYFRAMES):
        # Time value (signed 16-bit)
        time_value = read_s16(data, base_offset + i * 2)

        # RGB triplet (interleaved)
        r = read_u8(data, base_offset + 0x42 + i * 3)
        g = read_u8(data, base_offset + 0x43 + i * 3)
        b = read_u8(data, base_offset + 0x44 + i * 3)

        # Signed interpretation (two's complement) for human readability
        r_signed = r if r < 128 else r - 256
        g_signed = g if g < 128 else g - 256
        b_signed = b if b < 128 else b - 256

        # Control byte
        ctrl = read_u8(data, base_offset + 0xA5 + i)

        # Decode ctrl byte for palette-channel keyframes:
        # bit 7 = enabled (ctrl >= 128)
        # bits 0-6 = blend mode (0-10)
        enabled = ctrl >= 128
        blend_mode = ctrl & 0x7F

        # Calculate duration: time_value << 3 (multiply by 8) per PSX decompilation
        # If time_value == 0, duration is 1 (instant)
        duration_frames = time_value * 8 if time_value > 0 else 1

        channel["keyframes"].append({
            "index": i,
            "time_value": time_value,
            "duration_frames": duration_frames,
            "rgb": [r, g, b],
            "rgb_signed": [r_signed, g_signed, b_signed],
            "ctrl": ctrl,
            "enabled": enabled,
            "blend_mode": blend_mode,
        })

    return channel


# =============================================================================
# Camera-subsystem keyframe parsing (angle/position/zoom)
# =============================================================================

# Camera phase tables: 3 tables (phase1, for_each, phase2), each with 5 parallel arrays
# Per-keyframe: end_frame=2 bytes, angle/position/zoom=6 bytes (3×int16), command=2 bytes
CAMERA_TRACK_TABLES = {
    "phase1":   {"end_frame": 0x14E6, "angle": 0x1510, "position": 0x158E, "zoom": 0x160C, "command": 0x168A, "max_keyframe": 0x16B4, "count": 21},
    "for_each": {"end_frame": 0x06B2, "angle": 0x06D4, "position": 0x073A, "zoom": 0x07A0, "command": 0x0806, "max_keyframe": 0x0828, "count": 17},
    "phase2":   {"end_frame": 0x16B6, "angle": 0x16E0, "position": 0x175E, "zoom": 0x17DC, "command": 0x185A, "max_keyframe": 0x1884, "count": 21},
}

# Source mode decoding (bits 5-8 of command word)
CAMERA_SOURCE_MODES = {
    0x000: "TARGET",
    0x020: "OFFSET",
    0x040: "DIRECT",
    0x060: "ORIGIN",
    0x080: "EFFECT_CTR",
    0x0C0: "MAP",
    0x100: "SLOT_COPY",
    0x140: "CASTER",
    0x180: "ALL_TARGETS",
    0x1C0: "CURSOR",
}

# Interpolation decoding (bits 9-12 of command word)
CAMERA_INTERPOLATIONS = {
    0x0200: "IMMEDIATE",
    0x0400: "COSINE_A",
    0x0600: "COSINE_B",
    0x0800: "LINEAR",
    0x0A00: "COSINE_C",
    0x0C00: "ADDITIVE",
    0x0E00: "ADDITIVE_B",
    0x1000: "SHAKE_DAMPED",
    0x1200: "SHAKE_DIRECT",
    0x1400: "SHAKE_DAMPED_B",
}


def parse_camera_phase_table(data: bytes, base: int, table_name: str, offsets: Dict) -> Dict[str, Any]:
    """Parse a single camera phase table (one of phase1/for_each/phase2)."""
    count = offsets["count"]
    max_kf_offset = base + offsets["max_keyframe"]

    # Read max_keyframe
    max_kf = 0
    if max_kf_offset + 2 <= len(data):
        max_kf = read_s16(data, max_kf_offset)
        if max_kf < 0 or max_kf >= count:
            max_kf = 0

    keyframes = []
    for i in range(count):
        # end_frame (int16)
        ef_off = base + offsets["end_frame"] + i * 2
        end_frame = read_s16(data, ef_off) if ef_off + 2 <= len(data) else 0

        # angle (3 × int16)
        a_off = base + offsets["angle"] + i * 6
        if a_off + 6 <= len(data):
            angle = [read_s16(data, a_off), read_s16(data, a_off + 2), read_s16(data, a_off + 4)]
        else:
            angle = [0, 0, 0]

        # position (3 × int16)
        p_off = base + offsets["position"] + i * 6
        if p_off + 6 <= len(data):
            position = [read_s16(data, p_off), read_s16(data, p_off + 2), read_s16(data, p_off + 4)]
        else:
            position = [0, 0, 0]

        # zoom (3 × int16)
        z_off = base + offsets["zoom"] + i * 6
        if z_off + 6 <= len(data):
            zoom = [read_s16(data, z_off), read_s16(data, z_off + 2), read_s16(data, z_off + 4)]
        else:
            zoom = [0, 0, 0]

        # command (uint16)
        c_off = base + offsets["command"] + i * 2
        cmd = read_u16(data, c_off) if c_off + 2 <= len(data) else 0

        # Decode command word
        channel_mask = cmd & 0x0007
        param_index = (cmd >> 3) & 0x03
        source_bits = cmd & 0x01E0
        interp_bits = cmd & 0x1E00
        flags = (cmd >> 13) & 0x07

        source_mode = CAMERA_SOURCE_MODES.get(source_bits, "UNKNOWN_0x%03X" % source_bits)
        interpolation = CAMERA_INTERPOLATIONS.get(interp_bits, "UNKNOWN_0x%04X" % interp_bits)

        keyframes.append({
            "index": i,
            "end_frame": end_frame,
            "angle": angle,
            "position": position,
            "zoom": zoom,
            "command_raw": cmd,
            "channel_mask": channel_mask,
            "source_mode": source_mode,
            "interpolation": interpolation,
            "param_index": param_index,
            "flags": flags,
        })

    return {
        "max_keyframe": max_kf,
        "keyframes": keyframes,
    }


def parse_camera_keyframes(data: bytes, timeline_ptr: int) -> Dict[str, Any]:
    """Parse the camera subsystem's keyframes (3 phase tables: phase1,
    for_each, phase2). Each keyframe carries angle/position/zoom values gated
    by a `channel_mask` bitmask that selects which of those three channels
    the keyframe activates."""
    camera = {}

    for table_name, offsets in CAMERA_TRACK_TABLES.items():
        # All camera tables use timeline_section_ptr directly (not +8 like
        # screen/palette channels).
        base = timeline_ptr

        # Check bounds
        max_offset = max(offsets["end_frame"], offsets["angle"], offsets["position"],
                        offsets["zoom"], offsets["command"], offsets["max_keyframe"])
        if base + max_offset + 2 <= len(data):
            camera[table_name] = parse_camera_phase_table(data, base, table_name, offsets)

    return camera


def parse_all_palette_keyframes(data: bytes, timeline_ptr: int) -> Dict[str, Any]:
    """Parse the palette subsystem's keyframes (3 channels per phase:
    affected_units, caster, target)."""
    palette = {}

    for context, offsets in PALETTE_TRACK_OFFSETS.items():
        palette[context] = {}

        # Determine base pointer
        if context == "for_each":
            base = timeline_ptr + 8  # for_each uses timeline_channel_base
        else:
            base = timeline_ptr  # phase1/phase2 use timeline_section_ptr directly

        for channel_name, channel_offset in offsets.items():
            offset = base + channel_offset

            if offset + PALETTE_TRACK_SIZE <= len(data):
                palette[context][channel_name] = parse_palette_channel(
                    data, offset, context, channel_name
                )

    return palette


def print_palette_channels(palette: Dict[str, Any]) -> None:
    """Print human-readable keyframe table for all active palette channels.

    Shows signed RGB interpretation so positive/negative deltas are immediately
    clear (e.g., +16/-10/-13 instead of 16/246/243).
    """
    for context, channels in palette.items():
        for channel_name, ch in channels.items():
            max_kf = ch["max_keyframe"]
            active_kfs = [kf for kf in ch["keyframes"] if kf["index"] <= max_kf]
            if not active_kfs or all(kf["time_value"] == 0 and not kf["enabled"] for kf in active_kfs):
                continue

            print(f"\n  Palette channel: {context}/{channel_name} (max_keyframe={max_kf})")
            print(f"  {'KF':>3}  {'time':>4}  {'dur':>4}  {'R':>4} {'G':>4} {'B':>4}  {'R±':>4} {'G±':>4} {'B±':>4}  {'ctrl':>4}  {'en':>2}  {'mode':>4}")
            print(f"  {'---':>3}  {'----':>4}  {'----':>4}  {'----':>4} {'----':>4} {'----':>4}  {'----':>4} {'----':>4} {'----':>4}  {'----':>4}  {'--':>2}  {'----':>4}")

            for kf in active_kfs:
                rs, gs, bs = kf["rgb_signed"]
                r, g, b = kf["rgb"]
                print(f"  {kf['index']:3d}  {kf['time_value']:4d}  {kf['duration_frames']:4d}  "
                      f"{r:4d} {g:4d} {b:4d}  {rs:+4d} {gs:+4d} {bs:+4d}  "
                      f"0x{kf['ctrl']:02X}  {'Y' if kf['enabled'] else 'N':>2}  {kf['blend_mode']:4d}")


# =============================================================================
# Texture/Palette Extraction
# =============================================================================

def parse_texture_meta(data: bytes, texture_ptr: int) -> Dict[str, Any]:
    """The texture section's 4-byte VRAM upload header at texture_ptr + 0x400.

    Layout, per the engine's init at 0x801a0e80 / 0x801a0ed8:

      +0x400..+0x402  u24  PIXEL DATA SIZE in bytes
      +0x403          u8   row-stride selector: 0 -> 128 bytes, non-0 -> 256

    The 24-bit value is a **size**, not a coordinate: measured across all 401
    non-empty effects it equals the pixel plane's byte count exactly, and the
    engine divides it by the stride to recover the upload height.
    (`TEXTURE_AND_PALETTE_FORMAT.md` previously called it a "VRAM Y coordinate";
    corrected.) The upload X is the fixed 0x180; the Y is not encoded here, so
    `vram_y` is reported as None rather than invented.

    No texel WIDTH is reported: a row is `row_bytes` wide in bytes, but that is
    `row_bytes` texels at 8bpp and twice that at 4bpp — and depth is a per-FRAME
    property (`flags_byte0 & 0x80`), not this header's. The caller knows the
    depth and derives width; guessing it here would be right only half the time.
    `height` is in rows and is depth-independent.
    """
    base = texture_ptr
    size = read_u8(data, base + 0x400) | (read_u8(data, base + 0x401) << 8) \
        | (read_u8(data, base + 0x402) << 16)
    stride_flag = read_u8(data, base + 0x403)
    row_bytes = 256 if stride_flag else 128
    height = size // row_bytes if row_bytes else 0

    pal1 = data[base:base + 0x200]
    pal2 = data[base + 0x200:base + 0x400]

    return {
        "pixel_data_size": size,
        "stride_flag": stride_flag,
        "row_bytes": row_bytes,
        "height": height,
        "vram_x": 0x180,
        "vram_y": None,
        "palette_1_nonzero": any(pal1),
        "palette_2_nonzero": any(pal2),
    }


def extract_palette(data: bytes, texture_ptr: int) -> List[List[int]]:
    """Extract BGR555 palette (512 bytes = 256 colors)"""
    palette = []

    for i in range(256):
        offset = texture_ptr + i * 2
        if offset + 2 > len(data):
            break

        color_word = read_u16(data, offset)

        # BGR555 format
        b = (color_word & 0x7C00) >> 10
        g = (color_word & 0x03E0) >> 5
        r = color_word & 0x001F
        stp = (color_word >> 15) & 1  # Semi-transparency permission

        # Convert 5-bit to 8-bit
        r8 = (r << 3) | (r >> 2)
        g8 = (g << 3) | (g >> 2)
        b8 = (b << 3) | (b >> 2)

        palette.append([r8, g8, b8, stp])

    return palette


# =============================================================================
# Main Parser
# =============================================================================

# --- FEDS effect-sound section (header[0x20]..header[0x24]) ---------------
# The FEDS blob uses the same opcode encoding as SMD music. Decode is ported
# from research/tools/extract_feds.py. feds.bin (the raw slice) is the playback
# source the exmateria_sound addon consumes; feds.json is the human-readable
# parse, parallel to the other effect sections.

_FEDS_DELTA_TIME_TABLE = [0, 192, 144, 96, 72, 64, 48, 36, 32, 24, 18, 16, 12, 9, 8, 6, 4, 3, 2]
_FEDS_NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'cont', 'rest']

# opcode -> (name, param_count). MIRRORS the runtime decoder's tables in
# addons/exmateria_sound/runtime/sound_opcodes.gd (OPCODE_INFO names + counts;
# _EXTRA_OPCODES entries carry counts only and keep the Unknown_XX convention).
# That runtime table is the one that PLAYS feds.bin — a param-count drift here
# desyncs feds.json mid-track (ADR-0085 amendment 2026-08-11). Mechanized by
# test_feds_opcode_drift.py; edit sound_opcodes.gd first, then this.
_FEDS_OPCODE_INFO = {
    # 0x80-0x9F: control flow + structure
    0x80: ("Rest", 1), 0x81: ("Fermata", 1), 0x82: ("NOP", 0),
    0x90: ("EndBar", 0), 0x91: ("Loop", 0),
    0x94: ("Octave", 1), 0x95: ("RaiseOctave", 0), 0x96: ("LowerOctave", 0),
    0x97: ("TimeSignature", 2),
    0x98: ("Repeat", 1), 0x99: ("Coda", 0), 0x9A: ("RepeatBreak", 0),
    0x9B: ("NOP_Sled", 0),
    # 0xA0-0xAF: tempo + instrument
    0xA0: ("Tempo", 1), 0xA2: ("TempoSlide", 2),
    0xA9: ("FormulaSelector", 1),
    0xAC: ("Instrument", 1),
    0xAD: ("Byte76_Adjust", 1),
    0xAE: ("PercussionOn", 0), 0xAF: ("PercussionOff", 0),
    # 0xB0-0xBF: slur, FMod, noise, reverb
    0xB0: ("SlurOn", 0), 0xB1: ("SlurOff", 0),
    0xB2: ("FMod_Enable", 0), 0xB3: ("FMod_Disable", 0),
    0xB4: ("Noise_EnableAndClock", 1), 0xB5: ("Noise_ClockAdd", 1),
    0xB6: ("Noise_EnableNoArm", 0), 0xB7: ("Noise_Disable", 0),
    0xBA: ("ReverbOn", 0), 0xBB: ("ReverbOff", 0),
    # 0xC0-0xCF: ADSR
    0xC0: ("ADSR_Reset", 0), 0xC2: ("ADSR_Attack", 1),
    0xC3: ("ADSR_DecayRate", 1),
    0xC4: ("ADSR_SustainRate", 1), 0xC5: ("ADSR_Release", 1),
    0xC6: ("ADSR1_LowNibble_SlideTarget", 1),
    0xC7: ("ADSR_DecayAndSustainLevel", 2),
    0xC8: ("ADSR_AttackMode", 1),
    0xC9: ("ADSR_Decay", 1), 0xCA: ("ADSR_SustainLevel", 1),
    # 0xD0-0xDF: pitch bend, portamento, LFO sub-slot 0
    0xD0: ("SetPitchBend", 1),
    0xD1: ("AddPitchBend", 1),
    0xD2: ("PitchBendRel", 1),
    0xD3: ("PitchBend_Add_16bit", 2),
    0xD4: ("Portamento_Init", 2),
    0xD5: ("Chan6_Bit2_Toggle", 0),
    0xD6: ("Detune", 1),
    0xD7: ("PitchLFO_Depth", 1), 0xD8: ("PitchLFO_Init", 3),
    0xD9: ("PitchLFO_Init_Signed", 3),
    0xDA: ("FlagSet_0xFE", 0), 0xDB: ("FlagClear_0xFE", 0),
    0xDC: ("Portamento_Stop", 0),
    # 0xE0-0xEF: dynamics, expression, LFO sub-slot 1
    0xE0: ("Dynamics", 1),
    0xE1: ("Dynamics_Add", 1),
    0xE2: ("Expression_VolBurst", 2),
    0xE3: ("VolumeLFO_Depth", 1),
    0xE4: ("VolumeLFO_Init", 3),
    0xE5: ("VolLFO_Init_SubSlot1", 3),
    0xE6: ("LFO_SubSlot1_Activate", 0),
    0xE7: ("LFO_SubSlot1_Disable", 0),
    0xE8: ("Pan", 1),
    0xEB: ("PanLFO_Depth", 1),
    0xEC: ("PanLFO_Arm_SubSlot2", 3),
    0xED: ("PanLFO_Init_SubSlot2", 3),
    0xEF: ("LFO_SubSlot2_Disable", 0),
    # 0xF0-0xFF: dynamic LFO sub-slot machinery
    0xF0: ("LFO_SubSlot_Select_Init", 3),
    0xF1: ("LFO_SubSlot_Update", 3),
    0xF2: ("LFO_SubSlot_DynamicDepth", 2),
    0xF6: ("LFO_SubSlot_Activate", 1),
    0xF7: ("LFO_SubSlot_DynamicDisable", 1),
    0xFE: ("BankSelect", 1),
    # sound_opcodes.gd _EXTRA_OPCODES: known param counts, unimplemented at the
    # dispatcher (names unknown) — consumed so the stream doesn't desync.
    0x8A: ("Unknown_8A", 0), 0x8D: ("Unknown_8D", 1), 0x8E: ("Unknown_8E", 3),
    0x8F: ("Unknown_8F", 0),
    0x9C: ("Unknown_9C", 3), 0x9D: ("Unknown_9D", 3), 0x9E: ("Unknown_9E", 3),
    0xA1: ("Unknown_A1", 1), 0xA3: ("Unknown_A3", 2), 0xA4: ("Unknown_A4", 1),
    0xA5: ("Unknown_A5", 1), 0xA6: ("Unknown_A6", 1), 0xA7: ("Unknown_A7", 2),
    0xAA: ("Unknown_AA", 1),
    0xB8: ("Unknown_B8", 3), 0xB9: ("Unknown_B9", 1),
    0xC1: ("Unknown_C1", 3), 0xCF: ("Unknown_CF", 0),
    0xE9: ("Unknown_E9", 1), 0xEA: ("Unknown_EA", 2), 0xEE: ("Unknown_EE", 0),
    0xF4: ("Unknown_F4", 1), 0xF5: ("Unknown_F5", 1),
    0xF8: ("Unknown_F8", 3), 0xF9: ("Unknown_F9", 2), 0xFB: ("Unknown_FB", 1),
    0xFC: ("Unknown_FC", 2), 0xFD: ("Unknown_FD", 1), 0xFF: ("Unknown_FF", 0),
}


def _decode_feds_track(track: bytes) -> List[Dict[str, Any]]:
    """Decode one track's opcode stream into JSON-friendly dicts."""
    events: List[Dict[str, Any]] = []
    pos = 0
    n = len(track)
    while pos < n:
        opcode = track[pos]
        pos += 1
        if opcode < 0x80:
            # Note: opcode = velocity, next byte encodes key + duration index.
            if pos >= n:
                break
            data_byte = track[pos]
            pos += 1
            relative_key = data_byte // 19
            delta_time = _FEDS_DELTA_TIME_TABLE[data_byte % 19]
            if delta_time == 0 and pos < n:  # 0 => explicit duration byte follows
                delta_time = track[pos]
                pos += 1
            note = _FEDS_NOTE_NAMES[relative_key] if relative_key < len(_FEDS_NOTE_NAMES) else "?%d" % relative_key
            events.append({
                "type": "Note", "velocity": opcode, "key": relative_key,
                "note": note, "duration": delta_time,
            })
        else:
            name, param_count = _FEDS_OPCODE_INFO.get(opcode, ("Unknown_%02X" % opcode, 0))
            params: List[int] = []
            for _ in range(param_count):
                if pos >= n:
                    break
                params.append(track[pos])
                pos += 1
            ev: Dict[str, Any] = {"type": name, "opcode": opcode}
            if len(params) == 1:
                ev["value"] = params[0]
            elif params:
                ev["params"] = params
            events.append(ev)
            if opcode == 0x90:  # EndBar terminates the track
                break
    return events


def parse_feds_blob(feds: bytes) -> Optional[Dict[str, Any]]:
    """Decode a raw FEDS blob (the feds.bin content) into the feds.json doc.

    Returns None when the blob isn't a decodable feds section. Shared by
    parse_feds (fresh extract) and regen_feds_json (re-decode in place)."""
    if len(feds) < 24 or feds[0:4] != b"feds":
        return None
    try:
        data_size = read_u32(feds, 0x04)
        pair_count_plus1 = read_u16(feds, 0x08)
        resource_id = read_u16(feds, 0x0A)
        data_offset = read_u32(feds, 0x0C)
        num_tracks = max(0, (pair_count_plus1 - 1) * 2)
        offsets = [read_u16(feds, 0x18 + i * 2) for i in range(num_tracks)]
        tracks = []
        for i, off in enumerate(offsets):
            tr_end = offsets[i + 1] if i + 1 < len(offsets) else data_size
            tr_end = min(tr_end, len(feds))
            off = min(off, len(feds))
            tracks.append({
                "index": i,
                "pair": i // 2,
                "offset": off,
                "size": max(0, tr_end - off),
                "opcodes": _decode_feds_track(feds[off:tr_end]),
            })
        return {
            "resource_id": resource_id,
            "pair_count": pair_count_plus1 - 1,
            "data_offset": data_offset,
            "tracks": tracks,
        }
    except Exception:
        return None


def parse_feds(data: bytes, header: Dict[str, Any]) -> Tuple[Optional[Dict[str, Any]], Optional[bytes]]:
    """Slice and decode the FEDS effect-sound section.

    Returns (feds_json_dict, raw_feds_bytes), or (None, None) when the effect
    has no sound section (zero-size or non-feds content).
    """
    start = header["sound_def_ptr"]
    end = header["texture_ptr"]
    if end > len(data):
        end = len(data)
    if start <= 0 or end <= start:
        return None, None
    feds = data[start:end]
    doc = parse_feds_blob(feds)
    if doc is None:
        return None, None
    return doc, feds


# =============================================================================
# Sound-subsystem timeline data (TIER 1) + effect-flags sound config (TIER 2)
# =============================================================================
#
# Consumed by the addon's EffectJSONLoader / EffectSoundController to drive
# FFT-faithful, timeline-scheduled FEDS playback. Ported from the parity tool
# exmateria-sound/workspace/orchestrator/extract_timeline_data.py — keep the JSON
# field names in lockstep with effect_json_loader.gd + effect_sound_controller.gd
# (mode/id_a/id_b/id_c for config; channel_index/max_keyframe/keyframes[].{
# duration_frames,sound_id} for channels). Offsets are RELATIVE to the section
# pointers; callers pass the already base-adjusted absolute header pointers
# (header["effect_flags_ptr"] / header["timeline_section_ptr"]) so CODE-format
# effects (E259/E338/E464) resolve correctly.

# Public shared ROM layout for the Sound Timeline SFX-trigger tracks (#268) — the
# byte-exact writer (write_effect_sound) imports these so reader and writer never
# keep two drifting copies (the F1 discipline; mirrors PALETTE_TRACK_OFFSETS).
# Offsets are RELATIVE to the section pointer the caller passes: outer channels
# (phase1/phase2) are based at timeline_ptr; for_each channels at timeline_ptr + 8.
#
# Semantics (see the FEDS 3-tier map): a keyframe's sound_id is NOT a raw SFX id —
# 0/1 = skip, N>=2 indexes SoundContainer[N-2] (TIER-2, effect-flags section) which
# resolves via a mode to a FEDS pair (TIER-3, header[0x20]). duration_frames is the
# per-keyframe frames-left COUNTDOWN (gap until the next trigger fires), NOT a total.
# We edit only the raw TIER-1 bytes here; TIER-2/TIER-3 stay untouched.
SOUND_PHASE1_OFFSETS = [0xD2A + i * 30 for i in range(3)]        # phase1 outer, base=timeline_ptr
SOUND_PHASE2_OFFSETS = [0xD2A + 90 + i * 30 for i in range(3)]   # phase2 outer, base=timeline_ptr
SOUND_ANIMATE_OFFSETS = [0x284 + i * 54 for i in range(3)]       # for_each foreach, base=timeline_ptr+8
SOUND_OUTER_KF = 9      # keyframes per outer (phase1/phase2) channel (30-byte track)
SOUND_FOREACH_KF = 17   # keyframes per for-each (for_each) channel (54-byte track)
SOUND_OUTER_SIZE = 30   # bytes per outer channel
SOUND_FOREACH_SIZE = 54  # bytes per for-each channel
SOUND_OUTER_MAXKF_OFF = 28    # s16 max_keyframe within an outer channel
SOUND_FOREACH_MAXKF_OFF = 52  # s16 max_keyframe within a for-each channel

# Back-compat private aliases (existing readers below reference these names).
_SOUND_PHASE1_OFFSETS = SOUND_PHASE1_OFFSETS
_SOUND_PHASE2_OFFSETS = SOUND_PHASE2_OFFSETS
_SOUND_ANIMATE_OFFSETS = SOUND_ANIMATE_OFFSETS
_SOUND_OUTER_KF = SOUND_OUTER_KF
_SOUND_FOREACH_KF = SOUND_FOREACH_KF


def parse_sound_containers(data: bytes, effect_flags_ptr: int) -> Optional[Dict[str, Any]]:
    """The 4 per-effect SoundContainers (TIER-2 resolver entries).

    Each container is 4 bytes [mode, id_a, id_b, id_c] at
    effect_flags_ptr + 8 + ci*4. See CONTEXT.md "Audio" → SoundContainer.
    """
    base = effect_flags_ptr + 8
    if base < 0 or base + 4 * 4 > len(data):
        return None
    containers = []
    for ci in range(4):
        o = base + ci * 4
        containers.append({
            "mode": read_u8(data, o),
            "id_a": read_u8(data, o + 1),
            "id_b": read_u8(data, o + 2),
            "id_c": read_u8(data, o + 3),
            "index": ci,
        })
    return {"containers": containers}


def _build_sound_channel(channel_index: int, max_kf: int,
                       time_values: List[int], sound_ids: List[int]) -> Dict[str, Any]:
    keyframes = [
        {"duration_frames": int(dur), "sound_id": int(sid)}
        for dur, sid in zip(time_values, sound_ids)
    ]
    return {
        "channel_index": channel_index,
        "max_keyframe": int(max_kf),
        "keyframes": keyframes,
    }


def _parse_outer_sound_channel(data: bytes, off: int, channel_index: int) -> Dict[str, Any]:
    # 9 × int16 time_values, then 9 × u8 sound_ids, then int16 max_keyframe @ +28.
    time_values = [read_s16(data, off + i * 2) for i in range(_SOUND_OUTER_KF)]
    sid_base = off + _SOUND_OUTER_KF * 2
    sound_ids = [read_u8(data, sid_base + i) for i in range(_SOUND_OUTER_KF)]
    return _build_sound_channel(channel_index, read_s16(data, off + 28), time_values, sound_ids)


def _parse_foreach_sound_channel(data: bytes, off: int, channel_index: int) -> Dict[str, Any]:
    # 17 × int16 time_values, then 17 × u8 sound_ids, then int16 max_keyframe @ +52.
    time_values = [read_s16(data, off + i * 2) for i in range(_SOUND_FOREACH_KF)]
    sid_base = off + _SOUND_FOREACH_KF * 2
    sound_ids = [read_u8(data, sid_base + i) for i in range(_SOUND_FOREACH_KF)]
    return _build_sound_channel(channel_index, read_s16(data, off + 52), time_values, sound_ids)


def parse_sound_keyframes(data: bytes, timeline_ptr: int) -> Optional[Dict[str, Any]]:
    """Sound-subsystem keyframes (TIER 1): 3 phase1 + 3 phase2 outer channels
    (30 bytes each) plus 3 for_each for-each channels (54 bytes each, based
    at timeline_ptr + 8). Always emits all 3 channels per phase so the
    controller's three_phase detection (phase1 non-empty) matches the parity
    harness.
    """
    channel_base = timeline_ptr + 8
    last_outer = timeline_ptr + _SOUND_PHASE2_OFFSETS[-1] + 30
    last_foreach = channel_base + _SOUND_ANIMATE_OFFSETS[-1] + 54
    if timeline_ptr < 0 or max(last_outer, last_foreach) > len(data):
        return None
    phase1 = [_parse_outer_sound_channel(data, timeline_ptr + _SOUND_PHASE1_OFFSETS[i], i) for i in range(3)]
    phase2 = [_parse_outer_sound_channel(data, timeline_ptr + _SOUND_PHASE2_OFFSETS[i], i) for i in range(3)]
    animate = [_parse_foreach_sound_channel(data, channel_base + _SOUND_ANIMATE_OFFSETS[i], i) for i in range(3)]
    return {"phase1": phase1, "phase2": phase2, "for_each": animate}


def parse_effect_file(filepath: str, header_offset: Optional[int] = None) -> Dict[str, Any]:
    """Parse complete effect file.

    If header_offset is provided (e.g. looked up from the BATTLE.BIN table via
    load_vfx_header_offset), it is used as the authoritative header position.
    Otherwise we fall back to scanning for the MIPS prologue (find_header_offset),
    which only handles CODE-format effects whose file starts with the prologue.
    """
    path = Path(filepath)
    data = path.read_bytes()

    # Locate the 40-byte header. Prefer the authoritative table offset; the heuristic
    # scan is a fallback for when BATTLE.BIN is unavailable.
    if header_offset is not None:
        base_offset = header_offset
    else:
        base_offset = find_header_offset(data)
    is_code_format = base_offset > 0

    # Parse header (pointers already adjusted to absolute file offsets)
    header = parse_header(data, base_offset)
    sections = calculate_sections(header)

    # Find section sizes
    curves_section = next((s for s in sections if s["name"] == "AnimCurves"), None)
    frames_section = next((s for s in sections if s["name"] == "Frames"), None)
    animation_section = next((s for s in sections if s["name"] == "Animation"), None)
    script_section = next((s for s in sections if s["name"] == "Script"), None)
    timeline_section = next((s for s in sections if s["name"] == "Timeline"), None)

    # Parse animations FIRST (needed for lifetime calculation)
    animations = parse_animations_section(data, header["animation_ptr"], animation_section["size"] if animation_section else 0)
    anim_durations = get_animation_durations(animations)

    # Parse particle system
    particle_header = parse_particle_header(data, header["effect_data_ptr"])
    emitters = parse_all_emitters(data, header["effect_data_ptr"], particle_header["emitter_count"])

    # Preserve animation-driven lifetime indicator (65535 = -1 = animation-driven)
    # In FFT, lifetime = -1 means particle dies when animation completes
    # We convert the unsigned 65535 to signed -1 for clearer semantics
    for emitter in emitters:
        lifetime = emitter.get("lifetime", {})
        for key in ["min_start", "max_start", "min_end", "max_end"]:
            if lifetime.get(key, 0) >= 65535:
                lifetime[key] = -1

    # Parse curves
    curves = parse_curves(data, header["anim_table_ptr"], curves_section["size"] if curves_section else 0)

    # Parse frames
    framesets, frameset_group_sizes = parse_frames_section(data, header["frames_ptr"], frames_section["size"] if frames_section else 0)

    # Parse script
    script = parse_script(data, header["script_data_ptr"], script_section["size"] if script_section else 0)

    # Parse timeline
    timeline = parse_timeline(data, header["timeline_section_ptr"], timeline_section["size"] if timeline_section else 0)

    # Parse screen-subsystem keyframes (background-color animation)
    screen = parse_all_screen_keyframes(data, header["timeline_section_ptr"])

    # Parse palette-subsystem keyframes (unit/map color animation)
    palette = parse_all_palette_keyframes(data, header["timeline_section_ptr"])

    # Parse camera-subsystem keyframes (angle/position/zoom animation)
    camera = parse_camera_keyframes(data, header["timeline_section_ptr"])

    # Re-derive cinematic timing now that camera is available. parse_timeline
    # seeds the fields from particle channels only (camera=None); the visible-
    # cinematic end_frame requires the phase2 camera keyframes — see
    # _derive_cinematic_timing's docstring for the rationale.
    timeline["header"].update(
        _derive_cinematic_timing(timeline["header"], timeline["particle_channels"], camera=camera)
    )

    # Parse the effect flags byte (#272, ADR-0092). Present in every effect (unlike the
    # conditional time_scale), so the two time-scale enables can't be sourced from time_scale.json.
    effect_flags = parse_effect_flags(data, header["effect_flags_ptr"])

    # Parse time scale data (optional - for dramatic slowdown effects)
    time_scale = None
    if header["time_scale_ptr"] != 0:
        time_scale = parse_time_scale(data, header["time_scale_ptr"], header["effect_flags_ptr"])

    # Extract the static BGR555 color palette (256 colors for sprite display)
    texture_palette = extract_palette(data, header["texture_ptr"])
    texture_meta = parse_texture_meta(data, header["texture_ptr"])

    # Parse FEDS effect-sound section (raw slice + decoded opcodes)
    feds_doc, feds_bin = parse_feds(data, header)

    # Sound-subsystem keyframes (TIER 1) + per-effect SoundContainers (TIER 2)
    # for the addon's EffectSoundController. Only emitted for sound-bearing
    # effects (gated on feds presence at save time).
    sound_containers = parse_sound_containers(data, header["effect_flags_ptr"])
    sound = parse_sound_keyframes(data, header["timeline_section_ptr"])

    return {
        "filename": path.name,
        "feds": feds_doc,
        "feds_bin": feds_bin,
        "sound_containers": sound_containers,
        "sound": sound,
        "is_code_format": is_code_format,
        "header_offset": base_offset,
        "header": header,
        "sections": sections,
        "particle_header": particle_header,
        "emitters": emitters,
        "curves": curves,
        "framesets": framesets,
        "frameset_group_sizes": frameset_group_sizes,
        "animations": animations,
        "script": script,
        "timeline": timeline,
        "screen": screen,
        "palette": palette,
        "camera": camera,
        "time_scale": time_scale,
        "effect_flags": effect_flags,
        "texture_palette": texture_palette,
        "texture_meta": texture_meta,
    }


# Files older pipelines wrote that this parser no longer emits. Removed on
# (re)parse so effect folders stay clean. sound_def.json is superseded by
# feds.json; texture_indexed.bin is superseded by the generated texture.tga.
# The *_tracks.json names are pre-#31 outputs superseded by the Subsystem-aligned
# {screen,palette,camera,sound}.json names. sound_config.json is superseded by
# sound_containers.json (the per-effect SoundContainers).
STALE_OUTPUTS = (
    "sound_def.json",
    "texture_indexed.bin",
    "screen_tracks.json",
    "palette_tracks.json",
    "camera_tracks.json",
    "sound_tracks.json",
    "sound_config.json",
)

# (filename, key in the parsed dict) for the JSON sections written unconditionally.
_JSON_OUTPUTS = [
    ("particle_header.json", "particle_header"),
    ("emitters.json", "emitters"),
    ("curves.json", "curves"),
    ("frames.json", "framesets"),
    ("animations.json", "animations"),
    ("script.json", "script"),
    ("timeline.json", "timeline"),
    ("screen.json", "screen"),
    ("palette.json", "palette"),
    ("camera.json", "camera"),
    ("effect_flags.json", "effect_flags"),
    ("texture_palette.json", "texture_palette"),
    ("texture_meta.json", "texture_meta"),
]


def generate_texture(input_file, out_path: Path, header_offset: Optional[int]) -> None:
    """Generate texture.tga via the Lua extractor.

    header_offset (when > 0) is forwarded so CODE-format effects read their texture from
    the correct embedded offset instead of the extractor's own prologue scan.
    """
    lua_script = Path(__file__).parent / "extract_effect_texture.lua"
    if not lua_script.exists():
        print(f"  ! texture extractor not found: {lua_script}")
        return
    cmd = ["lua", str(lua_script), str(input_file), str(out_path / "texture.tga")]
    if header_offset and header_offset > 0:
        cmd.append(str(header_offset))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ! texture generation failed: {result.stderr.strip()}")


def save_effect(parsed: Dict[str, Any], output_dir) -> None:
    """Write all parsed JSON for one effect and remove stale outputs from older pipelines."""
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    header_doc = {
        "filename": parsed["filename"],
        "header": parsed["header"],
        "sections": parsed["sections"],
    }
    if parsed.get("is_code_format"):
        header_doc["is_code_format"] = True
        header_doc["header_offset"] = parsed["header_offset"]
    with open(out_path / "header.json", "w") as f:
        json.dump(header_doc, f, indent=2)

    for name, key in _JSON_OUTPUTS:
        with open(out_path / name, "w") as f:
            json.dump(parsed[key], f, indent=2)

    if parsed.get("frameset_group_sizes"):
        with open(out_path / "frameset_groups.json", "w") as f:
            json.dump(parsed["frameset_group_sizes"], f, indent=2)

    if parsed.get("time_scale"):
        with open(out_path / "time_scale.json", "w") as f:
            json.dump(parsed["time_scale"], f, indent=2)

    # FEDS effect sound: feds.bin (raw slice, the addon's playback source) +
    # feds.json (decoded opcodes), plus sound_containers.json / sound.json
    # (the EffectSoundController's TIER-2 resolver config + TIER-1 sound-subsystem
    # channels). All are emitted together only for sound-bearing effects;
    # soundless effects get any stale copies removed.
    feds_present = parsed.get("feds") is not None and bool(parsed.get("feds_bin"))
    if feds_present:
        (out_path / "feds.bin").write_bytes(parsed["feds_bin"])
        with open(out_path / "feds.json", "w") as f:
            json.dump(parsed["feds"], f, indent=2)
    sound_extra = {
        "sound_containers.json": parsed.get("sound_containers") if feds_present else None,
        "sound.json": parsed.get("sound") if feds_present else None,
    }
    for name, doc in sound_extra.items():
        p = out_path / name
        if doc is not None:
            with open(p, "w") as f:
                json.dump(doc, f, indent=2)
        elif p.exists():
            p.unlink()
    if not feds_present:
        for leftover in ("feds.bin", "feds.json"):
            p = out_path / leftover
            if p.exists():
                p.unlink()

    for stale in STALE_OUTPUTS:
        stale_path = out_path / stale
        if stale_path.exists():
            stale_path.unlink()


def extract_effect(bin_path, output_dir, battle_bin=None) -> Dict[str, Any]:
    """Fully extract one effect in a single pass: JSON + texture (+ callback tables for
    the handful of effects that have bespoke MIPS callbacks).

    The header offset comes from the BATTLE.BIN per-effect table (authoritative for
    CODE-format effects); battle_bin defaults to the BATTLE.BIN sibling of the EFFECT dir.
    """
    bin_path = Path(bin_path)
    out_path = Path(output_dir)
    if battle_bin is None:
        battle_bin = bin_path.parent.parent / "BATTLE.BIN"

    vfx_id = vfx_id_from_filename(bin_path.name)
    header_offset = load_vfx_header_offset(str(battle_bin), vfx_id) if vfx_id is not None else None

    parsed = parse_effect_file(str(bin_path), header_offset=header_offset)
    save_effect(parsed, out_path)
    generate_texture(bin_path, out_path, parsed["header_offset"])

    # Bespoke per-effect callback tables (only the CODE-format effects registered in
    # parse_effect_callbacks). Runs after save_effect so emitters.json is available.
    try:
        from parse_effect_callbacks import EFFECT_PARSERS
        if bin_path.stem in EFFECT_PARSERS:
            EFFECT_PARSERS[bin_path.stem](bin_path, out_path)
    except Exception as e:
        print(f"  ! callback parse failed for {bin_path.stem}: {e}")

    return parsed


def main():
    """Extract a single effect (JSON + texture + callbacks). To extract every effect,
    use parse_all_effects_py.py."""
    if len(sys.argv) < 2:
        print("Usage: python parse_effect.py /path/to/EFFECT/E001.BIN [output_dir]")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if not input_file.exists():
        print(f"Error: {input_file} not found")
        sys.exit(1)

    output_dir = Path(sys.argv[2] if len(sys.argv) > 2 else f"assets/effects/{input_file.stem}")
    parsed = extract_effect(input_file, output_dir)
    print(f"Saved {input_file.stem} -> {output_dir} "
          f"({len(parsed['emitters'])} emitters, {len(parsed['framesets'])} framesets, "
          f"{len(parsed['curves'])} curves)")


if __name__ == "__main__":
    main()
