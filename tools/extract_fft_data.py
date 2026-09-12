#!/usr/bin/env python3
"""Extract FFT job and stat data from game ISO extract.

This tool parses SCUS_942.21 to extract:
- Job stat modifiers (HP/MP/Speed/PA/MA constants and multipliers)
- Equipment flags
- Elemental affinities
- Status immunities

Data source: the FFT PSX extract, resolved host-agnostically via _repo_paths
(CLI/env/<repo>/project-assets/fft-extract). Offsets from FFTPatcher PsxIso.cs.

Usage:
    python tools/extract_fft_data.py

Output:
    addons/exmateria_almanac/jobs/jobs.json    (OUTPUT_DIR; moved there by extraction #5, #945)
"""

import sys
import json
import struct
from pathlib import Path

# Input path — resolves to <repo>/project-assets/fft-extract via shared helper.
from _repo_paths import scus as _scus
SCUS_FILE = _scus()

# Bit-packed FFT data decodes at the parser boundary (see ADR-0013).
from _fft_decode import (
    ELEMENTS,
    STATUS_NAMES_BY_BYTE,
    EQUIPMENT_FLAG_NAMES,
    decode_set_msb,
    decode_set_msb_bytes,
    decode_flags_msb_multi_byte,
)

# Offsets from FFTPatcher PsxIso.cs
JOBS_OFFSET = 0x518B8
JOBS_SIZE = 0x1E00  # 7680 bytes
JOB_LEVELS_OFFSET = 0x568C4
JOB_LEVELS_SIZE = 0xD0  # 208 bytes

# Output directory (relative to script location)
SCRIPT_DIR = Path(__file__).parent.parent
OUTPUT_DIR = SCRIPT_DIR / "addons" / "exmateria_almanac" / "jobs"

# Job names (extracted from FFTPatcher Jobs.xml)
JOB_NAMES = {
    0x01: "Squire",
    0x02: "Squire",
    0x03: "Squire",
    0x04: "Squire",
    0x05: "Holy Knight",
    0x06: "Arc Knight",
    0x07: "Squire",
    0x08: "Arc Knight",
    0x09: "Lune Knight",
    0x0A: "Duke",
    0x0B: "Duke",
    0x0C: "Princess",
    0x0D: "Holy Swordsman",
    0x0E: "High Priest",
    0x0F: "Dragoner",
    0x10: "Holy Priest",
    0x11: "Dark Knight",
    0x12: "Hell Knight",
    0x13: "Bishop",
    0x14: "Cleric",
    0x15: "Astrologist",
    0x16: "Engineer",
    0x17: "Dark Knight",
    0x18: "Cardinal",
    0x19: "Heaven Knight",
    0x1A: "Hell Knight",
    0x1B: "Arc Knight",
    0x1C: "Delita's Sis",
    0x1D: "Arc Duke",
    0x1E: "Holy Knight",
    0x1F: "Temple Knight",
    0x20: "White Knight",
    0x21: "Arc Witch",
    0x22: "Engineer",
    0x23: "Bi-Count",
    0x24: "Divine Knight",
    0x25: "Divine Knight",
    0x26: "Knight Blade",
    0x27: "Sorceror",
    0x28: "White Knight",
    0x29: "Heaven Knight",
    0x2A: "Divine Knight",
    0x2B: "Engineer",
    0x2C: "Cleric",
    0x2D: "Assassin",
    0x2E: "Assassin",
    0x2F: "Divine Knight",
    0x30: "Cleric",
    0x31: "Phony Saint",
    0x32: "Soldier",
    0x33: "Arc Knight",
    0x34: "Holy Knight",
    0x35: "Chemist",
    0x36: "Priest",
    0x37: "Wizard",
    0x38: "Oracle",
    0x3C: "Warlock",
    0x3D: "Knight",
    0x3E: "Angel of Death",
    0x3F: "Archer",
    0x40: "Regulator",
    0x41: "Holy Angel",
    0x42: "Wizard",
    0x43: "Impure King",
    0x44: "Time Mage",
    0x45: "Ghost of Fury",
    0x46: "Oracle",
    0x47: "Summoner",
    0x48: "Holy Dragon",
    0x49: "Arch Angel",
    0x4A: "Squire",
    0x4B: "Chemist",
    0x4C: "Knight",
    0x4D: "Archer",
    0x4E: "Monk",
    0x4F: "Priest",
    0x50: "Wizard",
    0x51: "Time Mage",
    0x52: "Summoner",
    0x53: "Thief",
    0x54: "Mediator",
    0x55: "Oracle",
    0x56: "Geomancer",
    0x57: "Lancer",
    0x58: "Samurai",
    0x59: "Ninja",
    0x5A: "Calculator",
    0x5B: "Bard",
    0x5C: "Dancer",
    0x5D: "Mime",
    0x5E: "Chocobo",
    0x5F: "Black Chocobo",
    0x60: "Red Chocobo",
    0x61: "Goblin",
    0x62: "Black Goblin",
    0x63: "Gobbledeguck",
    0x64: "Bomb",
    0x65: "Grenade",
    0x66: "Explosive",
    0x67: "Red Panther",
    0x68: "Cuar",
    0x69: "Vampire",
    0x6A: "Pisco Demon",
    0x6B: "Squidlarkin",
    0x6C: "Mindflare",
    0x6D: "Skeleton",
    0x6E: "Bone Snatch",
    0x6F: "Living Bone",
    0x70: "Ghoul",
    0x71: "Gust",
    0x72: "Revnant",
    0x73: "Flotiball",
    0x74: "Ahriman",
    0x75: "Plague",
    0x76: "Juravis",
    0x77: "Steel Hawk",
    0x78: "Cocatoris",
    0x79: "Uribo",
    0x7A: "Porky",
    0x7B: "Wildbow",
    0x7C: "Woodman",
    0x7D: "Trent",
    0x7E: "Taiju",
    0x7F: "Bull Demon",
    0x80: "Minitaurus",
    0x81: "Sacred",
    0x82: "Morbol",
    0x83: "Ochu",
    0x84: "Great Morbol",
    0x85: "Behemoth",
    0x86: "King Behemoth",
    0x87: "Dark Behemoth",
    0x88: "Dragon",
    0x89: "Blue Dragon",
    0x8A: "Red Dragon",
    0x8B: "Hyudra",
    0x8C: "Hydra",
    0x8D: "Tiamat",
    0x90: "Byblos",
    0x91: "Steel Giant",
    0x96: "Apanda",
    0x97: "Serpentarius",
    0x98: "Holy Dragon",
    0x99: "Archaic Demon",
    0x9A: "Ultima Demon",
}


def parse_job_binary(data: bytes, offset: int) -> dict:
    """Parse a single job entry (48 bytes) from Jobs.bin.

    Binary structure (PSX):
        Offset 0:     skill_set_id (1 byte)
        Offset 1-8:   innate_abilities (4 × 2 bytes)
        Offset 9-12:  equipment_flags (4 bytes = 32 bits)
        Offset 13:    hp_constant
        Offset 14:    hp_multiplier
        Offset 15:    mp_constant
        Offset 16:    mp_multiplier
        Offset 17:    speed_constant
        Offset 18:    speed_multiplier
        Offset 19:    pa_constant
        Offset 20:    pa_multiplier
        Offset 21:    ma_constant
        Offset 22:    ma_multiplier
        Offset 23:    move
        Offset 24:    jump
        Offset 25:    c_evade
        Offset 26-30: permanent_status (5 bytes)
        Offset 31-35: status_immunity (5 bytes)
        Offset 36-40: starting_status (5 bytes)
        Offset 41:    absorb_element
        Offset 42:    cancel_element
        Offset 43:    half_element
        Offset 44:    weak_element
        Offset 45:    male_portrait
        Offset 46:    male_palette
        Offset 47:    male_graphic
    """
    # Unpack all fields
    (
        skill_set_id,
        innate1, innate2, innate3, innate4,
        equip_flags,
        hp_constant, hp_multiplier,
        mp_constant, mp_multiplier,
        speed_constant, speed_multiplier,
        pa_constant, pa_multiplier,
        ma_constant, ma_multiplier,
        move, jump, c_evade,
        perm_status_1, perm_status_2, perm_status_3, perm_status_4, perm_status_5,
        status_imm_1, status_imm_2, status_imm_3, status_imm_4, status_imm_5,
        start_status_1, start_status_2, start_status_3, start_status_4, start_status_5,
        absorb_element, cancel_element, half_element, weak_element,
        male_portrait, male_palette, male_graphic
    ) = struct.unpack_from(
        "<B HHHH I BBBBBBBBBB BBB BBBBB BBBBB BBBBB BBBB BBB",
        data, offset
    )

    permanent_status_bytes = [
        perm_status_1, perm_status_2, perm_status_3, perm_status_4, perm_status_5,
    ]
    status_immunity_bytes = [
        status_imm_1, status_imm_2, status_imm_3, status_imm_4, status_imm_5,
    ]
    starting_status_bytes = [
        start_status_1, start_status_2, start_status_3, start_status_4, start_status_5,
    ]

    return {
        "skill_set_id": skill_set_id,
        "innate_abilities": [innate1, innate2, innate3, innate4],
        # equipment_flags decodes named-bool form per ADR-0013, 32 bits
        # = 4 bytes (little-endian) with FFT's MSB-first layout within each
        # byte (FFTPatcher Job/Equipment.cs `psxNames`).
        "equipment_flags": decode_flags_msb_multi_byte(equip_flags, EQUIPMENT_FLAG_NAMES, 4),
        "hp_constant": hp_constant,
        "hp_multiplier": hp_multiplier,
        "mp_constant": mp_constant,
        "mp_multiplier": mp_multiplier,
        "speed_constant": speed_constant,
        "speed_multiplier": speed_multiplier,
        "pa_constant": pa_constant,
        "pa_multiplier": pa_multiplier,
        "ma_constant": ma_constant,
        "ma_multiplier": ma_multiplier,
        "move": move,
        "jump": jump,
        "c_evade": c_evade,
        "permanent_status": decode_set_msb_bytes(permanent_status_bytes, STATUS_NAMES_BY_BYTE),
        "status_immunity": decode_set_msb_bytes(status_immunity_bytes, STATUS_NAMES_BY_BYTE),
        "starting_status": decode_set_msb_bytes(starting_status_bytes, STATUS_NAMES_BY_BYTE),
        "absorb_elements": decode_set_msb(absorb_element, ELEMENTS),
        "cancel_elements": decode_set_msb(cancel_element, ELEMENTS),
        "half_elements": decode_set_msb(half_element, ELEMENTS),
        "weak_elements": decode_set_msb(weak_element, ELEMENTS),
        # ADR-0022 vocabulary: these per-job byte fields are about the BODY
        # sprite, not specifically about males. The "male_" prefix is legacy
        # from when only the male humanoid path was modeled. For monster jobs
        # (where these fields actually drive behavior), they hold the monster's
        # portrait sprite_id + palette row + monster_type byte respectively.
        "body_portrait_sprite_id": male_portrait,
        "body_palette_row": male_palette,
        "body_graphic": male_graphic,
    }


def parse_job_levels(data: bytes) -> list[int]:
    """Parse JP requirements from JobLevels.bin.

    The file contains JP thresholds for job levels 1-8.
    First 8 values are multipliers, remaining are thresholds.
    """
    # JobLevels.bin structure: 26 entries × 8 bytes each = 208 bytes
    # For now, extract the first set of JP requirements (base requirements)
    jp_requirements = []

    # Read 8 JP threshold values (2 bytes each, little-endian)
    for i in range(8):
        jp = struct.unpack_from("<H", data, i * 2)[0]
        jp_requirements.append(jp)

    return jp_requirements


def extract_jobs() -> dict:
    """Extract all job data from SCUS_942.21.

    Returns:
        dict with job data ready for JSON serialization
    """
    # Load binary data from SCUS file
    with open(SCUS_FILE, "rb") as f:
        f.seek(JOBS_OFFSET)
        jobs_data = f.read(JOBS_SIZE)
        f.seek(JOB_LEVELS_OFFSET)
        levels_data = f.read(JOB_LEVELS_SIZE)

    print(f"  Read {len(jobs_data)} bytes of job data")
    print(f"  Read {len(levels_data)} bytes of job level data")

    # Parse JP requirements
    jp_requirements = parse_job_levels(levels_data)

    # Parse each job (160 jobs × 48 bytes = 7680 bytes)
    JOB_SIZE = 48
    num_jobs = len(jobs_data) // JOB_SIZE

    jobs = {}
    for i in range(num_jobs):
        offset = i * JOB_SIZE
        job_data = parse_job_binary(jobs_data, offset)

        # Get name from lookup (offset is 1-indexed in XML, 0-indexed here)
        name = JOB_NAMES.get(i, f"Unknown_{i:02X}")

        # Create job ID from offset
        job_id = f"{i:02x}"

        # Add name to job data
        job_data["name"] = name
        job_data["offset"] = i
        # ADR-0013: classify by job_id at parse time so runtime never
        # compares the raw byte to 0x4A/0x5E.
        job_data["kind"] = (
            "monster" if i >= 0x5E
            else "generic_human" if 0x4A <= i <= 0x5D
            else "special"
        )
        # ADR-0013: body sprite IDs per gender, computed at parse time.
        # Layout per FFTPatcher SpriteFiles.xml:
        #   - Special units 0x00-0x49: sprite_id == job_id, no gender split
        #   - Generic humans 0x4A-0x5A (Squire..Calculator): M = 0x60 +
        #     2*(i - 0x4A), F = M + 1
        #   - Bard 0x5B (male-only) and Dancer 0x5C (female-only): each
        #     has a single shared sprite (0x82 / 0x83); the gender arg
        #     is moot, both keys return the same value
        #   - Mime 0x5D: M = 0x84, F = 0x85
        #   - Monsters 0x5E+: both genders return body_portrait_sprite_id
        #     (gender is meaningless for non-human units)
        if i <= 0x49:
            male_sprite = i
            female_sprite = i
        elif 0x4A <= i <= 0x5A:
            male_sprite = 0x60 + 2 * (i - 0x4A)
            female_sprite = male_sprite + 1
        elif i == 0x5B:
            male_sprite = 0x82
            female_sprite = 0x82
        elif i == 0x5C:
            male_sprite = 0x83
            female_sprite = 0x83
        elif i == 0x5D:
            male_sprite = 0x84
            female_sprite = 0x85
        else:
            male_sprite = job_data["body_portrait_sprite_id"]
            female_sprite = male_sprite
        job_data["body_sprite_id_male"] = male_sprite
        job_data["body_sprite_id_female"] = female_sprite

        jobs[job_id] = job_data

    return {
        "metadata": {
            "source": SCUS_FILE.name,
            "job_count": num_jobs,
            "jp_requirements": jp_requirements,
        },
        "jobs": jobs,
    }


def main():
    """Main entry point."""
    print("Extracting FFT job data from SCUS_942.21...")

    # Verify source file exists
    if not SCUS_FILE.exists():
        print(f"ERROR: Source file not found: {SCUS_FILE}")
        sys.exit(1)

    # Extract data
    data = extract_jobs()

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Write output
    output_path = OUTPUT_DIR / "jobs.json"
    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    print(f"Wrote {len(data['jobs'])} jobs to {output_path}")

    # Print some sample data
    print("\nSample job data:")
    for job_id in ["4a", "4b", "4c"]:  # Squire, Chemist, Knight
        job = data["jobs"][job_id]
        print(f"  {job['name']} (0x{job_id.upper()}):")
        print(f"    HP: const={job['hp_constant']}, mult={job['hp_multiplier']}")
        print(f"    PA: const={job['pa_constant']}, mult={job['pa_multiplier']}")
        print(f"    Move={job['move']}, Jump={job['jump']}")


if __name__ == "__main__":
    main()
