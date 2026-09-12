#!/usr/bin/env python3
"""
SEQ Binary Parser

Parses FFT SEQ (sequence) animation files and outputs JSON matching the
existing type1_seq.json format.

SEQ File Structure (from ShishiSpriteEditor):
- Bytes 0-3: Header (unused for parsing)
- Bytes 4-1027: 256 x 4-byte sequence pointers (offset = i * 4 + 4)
- Bytes 1030+ (0x0406): Animation bytecode sequences

Animation Bytecode:
- Regular frame: 2 bytes [frame_id, wait_time] where frame_id < 0xFF
- Special opcode: starts with 0xFF prefix, then opcode byte, then parameters

Reference: ShishiSpriteEditor Sequence.cs

Expected sequence counts (from ShishiSpriteEditor):
- TYPE1: 218, TYPE2: 208, CYOKO: 104, KANZEN: 79, ARUTE: 79
- MON: 194, RUKA: 194, WEP1: 194, WEP2: 194

Usage:
    python tools/parse_seq.py --input TYPE1.SEQ --output type1_seq.json
    python tools/parse_seq.py --all  # Parse all SEQ files
"""

import argparse
import csv
import json
import struct
from pathlib import Path
from typing import Optional

# Default paths
from _repo_paths import battle_dir as _battle_dir, assets_dir as _assets_dir
DEFAULT_SEQ_DIR = _battle_dir()
DEFAULT_OUTPUT_DIR = Path(__file__).parent.parent / "assets/sprites/animations"
# Canonical FFT animation opcode definitions, bundled with the repo.
# Sourced from the fftae project (TacticsEngineG/src/fftae/SeqData/opcodeParameters.txt).
# When this file is present the parser tags every opcode by name; without it
# the fallback `get_default_opcode_definitions()` only knows a subset and
# misses critical ones like MoveUp2 (0xFFCB), causing the runtime to fail
# its `Animation 60 move_start_frame mismatch! Got -1, expected 22` assertion.
OPCODE_PARAMS_FILE = Path(__file__).resolve().parent / "opcodeParameters.txt"

# SEQ file structure constants (from ShishiSpriteEditor)
HEADER_LENGTH = 4               # Bytes 0-3: Header
POINTER_TABLE_LENGTH = 1024     # Bytes 4-1027: 256 x 4-byte pointers
NUM_POINTERS = 256
BYTECODE_START = 0x0406         # Animation bytecode starts at offset 1030


def load_opcode_definitions() -> dict:
    """Load opcode definitions from opcodeParameters.txt.

    Returns: {hex_code: {"name": str, "params": int}}
    """
    opcodes = {}

    if not OPCODE_PARAMS_FILE.exists():
        print(f"Warning: Opcode definitions not found at {OPCODE_PARAMS_FILE}")
        print("Using default opcode definitions")
        return get_default_opcode_definitions()

    with open(OPCODE_PARAMS_FILE, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)  # Skip header

        for row in reader:
            if len(row) < 3:
                continue
            name, params_str, hex_code = row[0], row[1], row[2]
            try:
                code = int(hex_code, 16)
                params = int(params_str)
                opcodes[code] = {"name": name, "params": params}
            except ValueError:
                continue

    return opcodes


def get_default_opcode_definitions() -> dict:
    """Default opcode definitions if file not found."""
    return {
        0xFFBE: {"name": "ffbe", "params": 0},
        0xFFBF: {"name": "ffbf", "params": 0},
        0xFFC0: {"name": "WaitForDistort", "params": 1},
        0xFFC1: {"name": "QueueDistortAnim", "params": 2},
        0xFFC6: {"name": "WaitForInput", "params": 1},
        0xFFD4: {"name": "PlayAttackSound", "params": 1},
        0xFFD5: {"name": "IncrementLoop", "params": 0},
        0xFFD8: {"name": "SetFrameOffset", "params": 1},
        0xFFDB: {"name": "SetSlowdown", "params": 1},
        0xFFDC: {"name": "ReloadAnimation", "params": 0},
        0xFFDD: {"name": "OverrideAnimation", "params": 1},
        0xFFDE: {"name": "PostGenericAttack", "params": 0},
        0xFFDF: {"name": "SetYRotation0", "params": 0},
        0xFFE0: {"name": "ClearShadow", "params": 0},
        0xFFE1: {"name": "SetShadow", "params": 0},
        0xFFE2: {"name": "SetLayerPriority", "params": 1},
        0xFFEB: {"name": "FlipVertical", "params": 0},
        0xFFEC: {"name": "FlipHorizontal", "params": 0},
        0xFFEE: {"name": "MoveUnitFB", "params": 1},
        0xFFEF: {"name": "MoveUnitDU", "params": 1},
        0xFFF0: {"name": "MoveUnitRL", "params": 1},
        0xFFF2: {"name": "QueueSpriteAnim", "params": 2},
        0xFFF6: {"name": "PlaySound", "params": 1},
        0xFFFA: {"name": "MoveUnitRLDUFB", "params": 3},
        0xFFFC: {"name": "Wait", "params": 2},
        0xFFFD: {"name": "HoldWeapon", "params": 1},
        0xFFFE: {"name": "EndAnimation", "params": 0},
        0xFFFF: {"name": "PauseAnimation", "params": 0},
    }


# Opcode names whose timing the GPU cinematic orchestrator + animation timing
# loader consume. Keeping them out of the generic opcode_defs table makes the
# walker independent of opcodeParameters.txt formatting drift.
_OPCODE_LOAD_FRAME_WAIT = "LoadFrameWait"
_OPCODE_POST_GENERIC_ATTACK = "PostGenericAttack"
_OPCODE_QUEUE_THROW_ANIMATION = "QueueThrowAnimation"
_OPCODE_QUEUE_SPRITE_ANIM = "QueueSpriteAnim"
_OPCODE_MOVE_UP_2 = "MoveUp2"


def derive_type1_timings(opcodes: list) -> dict:
    """Walk a TYPE1 animation's opcodes and extract the four timing fields
    GPUAnimationTimingLoader._load_type1_timings derives at boot.

    Mirrors the GD loader 1:1 so the migration is byte-identical:
    - damage_frame: tick of the first PostGenericAttack; fallback to
      throw_frame, else total_frames // 2.
    - projectile_frame: tick of the first QueueThrowAnimation, or -1.
    - move_start_frame: tick of MoveUp2 (movement wind-up exit), or -1.
    - total_frames: sum of LoadFrameWait waits up to the EndAnimation/Pause.
    """
    t = 0
    damage_frame = -1
    throw_frame = -1
    move_start_frame = -1

    for op in opcodes:
        name = op.get("op_code_name", "")
        if name == _OPCODE_LOAD_FRAME_WAIT:
            wait = op.get("op_code_param_1", 0) or 0
            t += int(wait)
        elif name == _OPCODE_POST_GENERIC_ATTACK and damage_frame < 0:
            damage_frame = t
        elif name == _OPCODE_QUEUE_THROW_ANIMATION and throw_frame < 0:
            throw_frame = t
        elif name == _OPCODE_MOVE_UP_2 and move_start_frame < 0:
            move_start_frame = t

    if damage_frame < 0:
        damage_frame = throw_frame if throw_frame >= 0 else t // 2

    return {
        "damage_frame": damage_frame,
        "total_frames": t,
        "projectile_frame": throw_frame,
        "move_start_frame": move_start_frame,
    }


def derive_wep1_timings(opcodes: list) -> dict:
    """Walk a WEP1 animation's opcodes and extract the two timing fields
    GPUAnimationTimingLoader._load_wep1_timings derives at boot.

    Mirrors the GD loader: damage_frame is the tick when QueueSpriteAnim fires
    to layer 2 (EFF1 -- the projectile spawn moment, which the orchestrator
    treats as the damage moment for WEP1's projectile-frame analog), falling
    back to total_frames // 2 when no such opcode exists.
    """
    t = 0
    damage_frame = -1

    for op in opcodes:
        name = op.get("op_code_name", "")
        if name == _OPCODE_LOAD_FRAME_WAIT:
            wait = op.get("op_code_param_1", 0) or 0
            t += int(wait)
        elif name == _OPCODE_QUEUE_SPRITE_ANIM and damage_frame < 0:
            layer = op.get("op_code_param_0", 0) or 0
            if int(layer) == 2:
                damage_frame = t

    if damage_frame < 0:
        damage_frame = t // 2

    return {
        "damage_frame": damage_frame,
        "total_frames": t,
    }


# Per-SEQ-file mapping: name -> per-animation timing-derivation function.
# Only TYPE1 and WEP1 carry GPU-consumed timings today; the others (TYPE2/3/4,
# MON, CYOKO, RUKA, ARUTE, KANZEN, OTHER, WEP2, EFF1, EFF2) get no _timings
# sidecar, matching the GD loader's coverage.
_TIMING_DERIVERS = {
    "type1_seq.json": derive_type1_timings,
    "wep1_seq.json": derive_wep1_timings,
}


class SEQParser:
    """Parser for FFT SEQ animation files."""

    def __init__(self, opcode_defs: dict):
        self.opcode_defs = opcode_defs

    def parse_file(self, filepath: Path) -> dict:
        """Parse a SEQ file and return JSON-compatible dict.

        Matches ShishiSpriteEditor's Sequence.BuildSequences() logic:
        - Read pointers from offset (i * 4 + 4) until 0xFFFFFFFF
        - Skip consecutive duplicate pointers
        - Bytecode starts at 0x0406

        Returns: Dict keyed by animation index (as string), each containing
                 a list of instruction dicts.
        """
        with open(filepath, 'rb') as f:
            data = f.read()

        if len(data) < BYTECODE_START:
            raise ValueError(f"SEQ file too small: {filepath}")

        # Read sequence pointers until 0xFFFFFFFF (like ShishiSpriteEditor)
        offsets = []
        for i in range(NUM_POINTERS):
            ptr_offset = i * 4 + 4  # ShishiSpriteEditor: bytes.Sub(i * 4 + 4, ...)
            ptr = struct.unpack_from('<I', data, ptr_offset)[0]

            if ptr == 0xFFFFFFFF:
                break  # End marker

            offsets.append(ptr)

        # Parse sequences, skipping consecutive duplicates (like ShishiSpriteEditor)
        # IMPORTANT: Use pointer table index 'i' as the key, NOT a sequential counter.
        # This preserves the game's original animation numbering for AnimationStateController.
        result = {}

        for i in range(len(offsets) - 1):
            # Skip consecutive duplicates
            if offsets[i] == offsets[i + 1]:
                continue

            # Parse this sequence's bytecode
            start = BYTECODE_START + offsets[i]
            end = BYTECODE_START + offsets[i + 1]

            # Use pointer table index 'i' as seq_no and as the dictionary key
            instructions = self._parse_sequence(data, start, end, i)
            if instructions:
                result[str(i)] = instructions

        # Parse the last sequence (from last offset to end of file)
        if offsets:
            last_idx = len(offsets) - 1
            start = BYTECODE_START + offsets[-1]
            instructions = self._parse_sequence(data, start, len(data), last_idx)
            if instructions:
                result[str(last_idx)] = instructions

        return result

    def _parse_sequence(self, data: bytes, start: int, end: int, seq_no: int) -> list:
        """Parse a single animation sequence's bytecode.

        Args:
            data: Full file data
            start: Start offset of this sequence's bytecode
            end: End offset (exclusive)
            seq_no: Sequence number for output

        Returns: List of instruction dicts
        """
        instructions = []
        pos = start
        instruction_num = 0

        # Prevent infinite loops - set a reasonable max
        max_instructions = 1000

        while pos < end and instruction_num < max_instructions:
            if pos >= len(data):
                break

            byte1 = data[pos]

            # Check for special opcode (0xFF prefix)
            if byte1 == 0xFF:
                if pos + 1 >= len(data):
                    break

                byte2 = data[pos + 1]
                opcode = 0xFF00 | byte2

                # Look up opcode definition
                opcode_info = self.opcode_defs.get(opcode, {"name": f"ff{byte2:02x}", "params": 0})
                opcode_name = opcode_info["name"]
                num_params = opcode_info["params"]

                # Read parameters
                params = []
                for i in range(num_params):
                    param_pos = pos + 2 + i
                    if param_pos < len(data):
                        params.append(data[param_pos])
                    else:
                        params.append(0)

                instruction = {
                    "seq_no": seq_no,
                    "op_code_hex": f"0x{opcode:04X}",
                    "op_code_param_0": params[0] if len(params) > 0 else None,
                    "op_code_param_1": params[1] if len(params) > 1 else None,
                    "op_code_param_2": params[2] if len(params) > 2 else None,
                    "op_code_name": opcode_name,
                    "instruction_num": instruction_num
                }
                instructions.append(instruction)

                pos += 2 + num_params  # opcode (2 bytes) + params
                instruction_num += 1

                # End on EndAnimation or PauseAnimation
                if opcode in (0xFFFE, 0xFFFF):
                    break
            else:
                # Regular frame load: [frame_id, wait_time]
                if pos + 1 >= len(data):
                    break

                frame_id = byte1
                wait_time = data[pos + 1]

                instruction = {
                    "seq_no": seq_no,
                    "op_code_hex": None,
                    "op_code_param_0": frame_id,
                    "op_code_param_1": wait_time,
                    "op_code_param_2": None,
                    "op_code_name": "LoadFrameWait",
                    "instruction_num": instruction_num
                }
                instructions.append(instruction)

                pos += 2
                instruction_num += 1

        return instructions


def _add_timings_sidecar(result: dict, output_name: str) -> None:
    """Attach a `_timings` sidecar dict for SEQ files the GPU consumes.

    Issue #53 / Phase 1: GPUAnimationTimingLoader migrates from boot-time
    opcode walking to direct reads of per-animation timing fields. The
    sidecar key is `_timings` (an underscore-prefixed sentinel that cannot
    collide with an integer anim_id key) so existing array-shaped consumers
    keep working unchanged.
    """
    derive = _TIMING_DERIVERS.get(output_name)
    if derive is None:
        return
    timings = {}
    for anim_id_str, opcodes in result.items():
        if not isinstance(opcodes, list):
            continue
        timings[anim_id_str] = derive(opcodes)
    result["_timings"] = timings


def parse_all_seq_files(seq_dir: Path, output_dir: Path):
    """Parse all SEQ files in directory."""
    seq_files = [
        ("TYPE1.SEQ", "type1_seq.json"),
        ("TYPE2.SEQ", "type2_seq.json"),
        ("TYPE3.SEQ", "type3_seq.json"),
        ("TYPE4.SEQ", "type4_seq.json"),
        ("MON.SEQ", "mon_seq.json"),
        ("CYOKO.SEQ", "cyoko_seq.json"),
        ("RUKA.SEQ", "ruka_seq.json"),
        ("ARUTE.SEQ", "arute_seq.json"),
        ("KANZEN.SEQ", "kanzen_seq.json"),
        ("OTHER.SEQ", "other_seq.json"),
        ("WEP1.SEQ", "wep1_seq.json"),
        ("WEP2.SEQ", "wep2_seq.json"),
        ("EFF1.SEQ", "eff1_seq.json"),
        ("EFF2.SEQ", "eff2_seq.json"),
    ]

    opcode_defs = load_opcode_definitions()
    parser = SEQParser(opcode_defs)

    for input_name, output_name in seq_files:
        input_path = seq_dir / input_name
        output_path = output_dir / output_name

        if not input_path.exists():
            print(f"  Skipping {input_name} (not found)")
            continue

        print(f"Parsing {input_name}...")
        try:
            result = parser.parse_file(input_path)
            _add_timings_sidecar(result, output_name)

            with open(output_path, 'w') as f:
                json.dump(result, f, indent=4)

            seq_count = sum(1 for k in result if k != "_timings")
            print(f"  -> {output_name} ({seq_count} sequences)")
        except Exception as e:
            print(f"  Error: {e}")


def main():
    parser = argparse.ArgumentParser(description="Parse FFT SEQ animation files")
    parser.add_argument("--input", type=Path, help="Input SEQ file")
    parser.add_argument("--output", type=Path, help="Output JSON file")
    parser.add_argument("--all", action="store_true", help="Parse all SEQ files")
    parser.add_argument("--seq-dir", type=Path, default=DEFAULT_SEQ_DIR,
                       help=f"SEQ files directory (default: {DEFAULT_SEQ_DIR})")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                       help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})")
    args = parser.parse_args()

    if args.all:
        parse_all_seq_files(args.seq_dir, args.output_dir)
    elif args.input and args.output:
        opcode_defs = load_opcode_definitions()
        parser = SEQParser(opcode_defs)
        result = parser.parse_file(args.input)
        _add_timings_sidecar(result, args.output.name)

        with open(args.output, 'w') as f:
            json.dump(result, f, indent=4)

        seq_count = sum(1 for k in result if k != "_timings")
        print(f"Wrote {args.output} ({seq_count} sequences)")
    else:
        parser.print_help()
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
