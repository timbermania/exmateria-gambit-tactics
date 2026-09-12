#!/usr/bin/env python3
"""Per-PC static decode of scenario_1_chunk.json for the chapel cinematic.

Walks the opcode list and emits a TSV summarising:
  - which unit(s) each opcode targets
  - what each opcode is asking the engine to change (facing, animation,
    visibility, palette, position …)

Output is the static "expected" column used in the side-by-side diff under
research/working_documents/chapel_opcode_trace/static_chunk.tsv.

This is a *static* decode — no engine state. The Godot and PCSX dynamic
captures fill in what each side actually did.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHUNK_JSON = REPO / "godot-learning/assets/scenarios/scenario_1_chunk.json"
ENTD_JSON = REPO / "godot-learning/assets/scenarios/entd.json"
DEFAULT_OUT = REPO / "research/working_documents/chapel_opcode_trace/static_chunk.tsv"
DEFAULT_PC_END = 200
SCENARIO_ENTD_RECORD = "256"

# 0=S 1=W 2=N 3=E in FFT's convention (parse_entd.py).
FFT_FACING_LABEL = {0: "S", 1: "W", 2: "N", 3: "E"}


def load_entd_slots() -> dict[int, dict]:
    with open(ENTD_JSON) as f:
        data = json.load(f)
    rec = data["records"][SCENARIO_ENTD_RECORD]
    out: dict[int, dict] = {}
    for slot in rec["slots"]:
        uid = int(slot["unit_id"])
        if uid == 0xFF:
            continue
        out[uid] = slot
    return out


def params_dict(inst: dict) -> dict[str, int]:
    out: dict[str, int] = {}
    for p in inst.get("params", []):
        out[str(p["name"])] = int(p["value"])
    return out


def target_units(inst: dict) -> list[int]:
    """Pull the chunk_unit_id(s) an opcode acts on, if any.

    `Units` (low byte) + `Multi` (high byte) are how the disassembler splits
    the u16 chunk_unit_id; `Unit` is the single-byte form. Scenario 1 has no
    Multi != 0 unit refs in the chapel slice so we treat Multi as a passthrough
    here.
    """
    p = params_dict(inst)
    if "Unit" in p:
        return [p["Unit"] & 0xFF]
    if "Units" in p:
        return [p["Units"] & 0xFF]
    return []


def expected_facing_str(facing_raw: int) -> str:
    """Facing value from `Rotate Unit` / `Warp Unit`.

    Rotate Unit's `Facing` is the per-handler raw value (0..4 observed in the
    chunk; 4 is "preserve current facing", see `event_unit_anim_decode.md`
    "later 2"). We just surface the raw byte here — the dynamic captures
    show whether it landed.
    """
    if facing_raw in FFT_FACING_LABEL:
        return f"{FFT_FACING_LABEL[facing_raw]} ({facing_raw})"
    if facing_raw == 4:
        return "preserve (4)"
    return f"raw=0x{facing_raw:02X}"


def expected_anim_str(anim_id: int) -> str:
    if 0x1F4 <= anim_id < 0x234:
        return f"cinematic block1 local=0x{anim_id - 0x1F4:02X} (anim=0x{anim_id:03X})"
    if 0x258 <= anim_id < 0x298:
        return f"cinematic block2 local=0x{anim_id - 0x258:02X} (anim=0x{anim_id:03X})"
    return f"type1 anim_id=0x{anim_id:X}"


def decode_opcode(inst: dict) -> tuple[str, str, str]:
    """Return (targets, expected_change, summary) for one opcode.

    targets: comma-separated chunk_unit_ids the opcode mutates
    expected_change: one-line description of the state delta the engine should apply
    summary: condensed param dump for the human reader
    """
    name = inst.get("name", "?")
    p = params_dict(inst)
    targets = ", ".join(f"0x{u:02X}" for u in target_units(inst)) or "-"

    if name == "Rotate Unit":
        change = (
            f"facing→{expected_facing_str(p.get('Facing', -1))}, "
            f"dir={p.get('Direction','?')}, speed={p.get('Speed','?')}, delay={p.get('Delay','?')}"
        )
    elif name == "Unit Anim":
        change = f"play {expected_anim_str(p.get('Animation', -1))} flag={p.get('Unknown','?')}"
    elif name == "Warp Unit":
        change = (
            f"warp tile=({p.get('X','?')},{p.get('Y','?')}) "
            f"facing→{expected_facing_str(p.get('Facing', -1))}"
        )
    elif name == "Walk To":
        change = (
            f"walk→({p.get('X','?')},{p.get('Y','?')}) speed={p.get('Speed','?')}"
        )
    elif name == "Walk To Anim":
        change = f"set walk anim→0x{p.get('Animation', 0):X}"
    elif name == "Sprite Move":
        change = (
            f"sprite_offset Δ=({p.get('+X','?')},{p.get('+Y','?')},{p.get('+Z','?')}) "
            f"type={p.get('Type','?')}"
        )
    elif name == "Wait Sprite Move":
        change = "block until sprite_move done"
    elif name == "Wait Walk":
        change = "block until walk done"
    elif name == "Color Unit":
        change = (
            f"palette tint color={p.get('Color','?')} "
            f"rgb=({p.get('Red','?')},{p.get('Green','?')},{p.get('Blue','?')})"
        )
    elif name == "Reset Palette":
        change = f"reset palette of unit 0x{p.get('Unit', 0):02X}"
    elif name == "Draw Unit":
        change = f"make unit 0x{p.get('Unit', 0):02X} VISIBLE"
    elif name == "Add Unit":
        change = f"add unit 0x{p.get('Unit', 0):02X} (visible + active)"
    elif name == "Camera":
        change = (
            f"camera pose X={p.get('X','?')} Z={p.get('Z','?')} Y={p.get('Y','?')} "
            f"angle={p.get('Angle','?')} map_rot={p.get('Map Rotation','?')}"
        )
    elif name == "Wait":
        change = f"hold {p.get('Time','?')} ticks"
    elif name == "Wait For Instruction":
        change = f"hold until task {p.get('Task','?')} done"
    elif name == "Display Message":
        change = (
            f"dialog={p.get('Dialog','?')} msg={p.get('Message','?')} "
            f"speaker=0x{p.get('Unit', 0):02X}"
        )
    elif name == "Sound Effect":
        change = f"sfx sound={p.get('Sound','?')}"
    elif name == "Block Start":
        change = "parallel block begin"
    elif name == "Block End":
        change = "parallel block end"
    elif name == "Reveal":
        change = "screen-fade reveal"
    elif name == "Event Speed":
        change = f"event-script speed×{p.get('Speed','?')}"
    elif name == "Load EVTCHR":
        change = f"map EVTCHR slot={p.get('Slot','?')} → block={p.get('Block','?')}"
    elif name == "Unknown":
        change = f"unknown opcode (Unknown={p.get('Unknown','?')})"
    else:
        change = ", ".join(f"{k}={v}" for k, v in p.items())

    summary_parts = []
    for pname in ("Units", "Unit", "Multi", "Animation", "Facing", "Direction",
                  "Time", "Dialog", "Message", "X", "Y", "Z", "+X", "+Y", "+Z",
                  "Color", "Red", "Green", "Blue", "Speed", "Delay", "Task",
                  "Sound", "Angle", "Map Rotation", "Camera Rotation", "Slot",
                  "Block", "Unknown"):
        if pname in p:
            summary_parts.append(f"{pname}={p[pname]}")
    summary = " ".join(summary_parts)

    return targets, change, summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pc-start", type=int, default=0)
    ap.add_argument("--pc-end", type=int, default=DEFAULT_PC_END)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    with open(CHUNK_JSON) as f:
        chunk = json.load(f)
    insts = chunk["instructions"]
    entd_slots = load_entd_slots()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    cols = ["pc", "offset", "opcode", "target_units", "expected_change", "params"]
    with open(args.out, "w") as f:
        f.write("\t".join(cols) + "\n")
        for i in range(args.pc_start, min(args.pc_end, len(insts))):
            inst = insts[i]
            targets, change, summary = decode_opcode(inst)
            row = [
                str(i),
                f"0x{int(inst.get('offset', 0)):04X}",
                inst.get("name", "?"),
                targets,
                change,
                summary,
            ]
            f.write("\t".join(row) + "\n")

    print(f"wrote {args.out}", file=sys.stderr)
    print(f"  pc {args.pc_start}..{args.pc_end - 1} ({args.pc_end - args.pc_start} opcodes)",
          file=sys.stderr)
    print(f"  ENTD slots seen: {sorted(entd_slots)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
