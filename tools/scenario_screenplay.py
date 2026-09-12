#!/usr/bin/env python3
"""
Scenario screenplay — join event-script disasm + text decoder + ENTD into
a single readable view of an FFT scenario's cinematic.

Inputs:
- A captured event-script chunk (binary) — e.g. the per-scenario RAM blob
  at `0x8004A6BC` after `0xDB Event End` writes the new scenario in.
- A scenario_id (selects the ENTD record for unit lookups).

What it does:
1. Disassembles the bytecode via the shared engine (`_fft_bytecode.disasm`).
2. Locates the string table — it sits immediately after the terminating
   `0xDB Event End` opcode. Walks 0xFE/0xFF-terminated strings from there
   to build a 1-based `message_id → (offset, decoded_text)` table.
3. For every `0x10 Display Message`, resolves:
     - `Message` u16 → the decoded line from the string table
     - `Unit`    u16 → ENTD slot whose `unit_id` low-byte matches the
       Unit param's low byte. Returns the slot's sprite_set name (from
       `tools/data/SpritesheetNames.xml`) and unit_id name (from
       `UnitNames.xml`).
4. Renders either a flat JSON object or a Markdown screenplay; non-dialogue
   opcodes show up as one-line stage directions (camera moves, warps,
   animations) so the cinematic reads top-to-bottom.

Sanity check: scenario 1's chunk produces a Markdown view whose dialogue
lines round-trip the lines in
`research/working_documents/scenario_1_captures/dialogue_pages_decoded.txt`
(modulo the canonical-vs-golden charmap divergences flagged in the handoff).

Usage:
    uv run python tools/scenario_screenplay.py CHUNK.bin --scenario 1
    uv run python tools/scenario_screenplay.py CHUNK.bin --scenario 1 --json
    uv run python tools/scenario_screenplay.py CHUNK.bin --scenario 1 \\
        --chunk-base 0x8004A6BC --out screenplay.md
"""

from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from _fft_bytecode import (
    DATA_DIR, EVENT_CATALOG, OpcodeTable, detect_chunk_base, disasm, load_opcodes,
)
from _fft_strings import (
    EVENT_END_OPCODE, StringTable, find_string_table_base, walk_strings,
)

ASSETS = Path(__file__).parent.parent / "assets"
DEFAULT_SCENARIOS = ASSETS.parent / "addons" / "exmateria_almanac" \
    / "encounters" / "scenarios.json"   # ADR-0251 dec. 2
DEFAULT_ENTD = ASSETS / "scenarios" / "entd.json"
DEFAULT_UNIT_NAMES = DATA_DIR / "UnitNames.xml"
DEFAULT_SPRITE_NAMES = DATA_DIR / "SpritesheetNames.xml"

DISPLAY_MESSAGE_OPCODE = 0x10


def load_name_map(xml_path: Path) -> dict[int, str]:
    """FFTPatcher `<Entries><Entry hex="HH" name="…"/></Entries>` → {int: str}."""
    tree = ET.parse(xml_path)
    out: dict[int, str] = {}
    for e in tree.getroot().findall("Entry"):
        name = e.attrib.get("name")
        if name:
            out[int(e.attrib["hex"], 16)] = name
    return out


@dataclass
class SpeakerInfo:
    unit_byte: int                  # low byte of the Display Message Unit param
    slot_index: int | None          # ENTD slot index (0..15) or None if no match
    sprite_set: int | None          # ENTD slot sprite_set byte
    sprite_name: str | None         # from SpritesheetNames.xml
    unit_id: int | None             # ENTD slot unit_id byte
    unit_name: str | None           # from UnitNames.xml (keyed by unit_id)
    special_name: int | None        # ENTD slot special_name byte

    @property
    def display(self) -> str:
        # Prefer the sprite-set name (matches the dialogue "Female Knight",
        # "Black knight" style) when present; fall back to unit-id name.
        if self.sprite_name:
            return self.sprite_name
        if self.unit_name:
            return self.unit_name
        return f"unit=0x{self.unit_byte:02X}"


def resolve_speaker(
    unit_param: int,
    entd_slots: list[dict],
    sprite_names: dict[int, str],
    unit_names: dict[int, str],
) -> SpeakerInfo:
    """Match the Display Message `Unit` u16's low byte against `slot["unit_id"]`
    in the scenario's ENTD record. Returns a speaker record (slot_index=None
    if no slot matches — empty/0xFF padding slots are skipped)."""
    unit_byte = unit_param & 0xFF
    for i, slot in enumerate(entd_slots):
        if slot["unit_id"] == 0xFF:
            continue        # padding
        if slot["unit_id"] == unit_byte:
            sprite_set = slot["sprite_set"]
            unit_id = slot["unit_id"]
            return SpeakerInfo(
                unit_byte=unit_byte,
                slot_index=i,
                sprite_set=sprite_set,
                sprite_name=sprite_names.get(sprite_set),
                unit_id=unit_id,
                unit_name=unit_names.get(unit_id),
                special_name=slot["special_name"],
            )
    return SpeakerInfo(
        unit_byte=unit_byte, slot_index=None,
        sprite_set=None, sprite_name=None,
        unit_id=None, unit_name=unit_names.get(unit_byte),
        special_name=None,
    )


def load_scenario_record(scenarios_path: Path, scenario_id: int) -> dict:
    payload = json.loads(scenarios_path.read_text(encoding="utf-8"))
    rec = payload["scenarios"].get(str(scenario_id))
    if rec is None:
        raise SystemExit(f"scenario {scenario_id} not found in {scenarios_path}")
    return rec


def load_entd_record(entd_path: Path, entd_idx: int) -> dict:
    payload = json.loads(entd_path.read_text(encoding="utf-8"))
    rec = payload["records"].get(str(entd_idx))
    if rec is None:
        raise SystemExit(f"ENTD record {entd_idx} not found in {entd_path}")
    return rec


# =============================================================================
# Rendering
# =============================================================================

def _inst_param(inst, name: str) -> int | None:
    """Pull a named parameter's value off an instruction; None if absent."""
    for p in inst.params:
        if p["name"] == name:
            return p["value"]
    return None


def _stage_direction(inst) -> str:
    """One-line summary of a non-dialogue opcode — preserve param names but
    drop verbose unknowns so the screenplay stays readable. Unknown opcodes
    show their raw bytes."""
    if inst.unknown and not inst.params:
        return f"?? <0x{inst.opcode:02X}>  raw={inst.raw.hex()}"
    parts: list[str] = []
    for p in inst.params:
        # Skip plain "Unknown" params with value 0 to reduce noise.
        if p["name"] == "Unknown" and p["value"] == 0:
            continue
        parts.append(f"{p['name']}={p['value']:#x}")
    sig = ", ".join(parts) if parts else "—"
    return f"{inst.name}  ({sig})"


def render_markdown(
    insts: list,
    table: OpcodeTable,
    strings: StringTable,
    entd_slots: list[dict],
    sprite_names: dict[int, str],
    unit_names: dict[int, str],
    scenario: dict,
) -> str:
    lines: list[str] = []
    lines.append(f"# {scenario['scenario_name']} (scenario {scenario['scenario_id']})")
    lines.append("")
    lines.append(f"- Map: {scenario.get('map_name', '?')} (MAP{scenario['map_id']:03d})")
    lines.append(f"- ENTD record: {scenario['entd_idx']}")
    lines.append(f"- Music: {scenario.get('music_file_one_id')}/{scenario.get('music_file_two_id')}")
    lines.append("")
    lines.append(f"_String table at chunk offset 0x{strings.base:04X} ({len(strings.entries)} strings)._")
    lines.append("")
    lines.append("---")
    lines.append("")

    for inst in insts:
        addr = f"+{inst.offset:04X}"
        if inst.opcode == DISPLAY_MESSAGE_OPCODE and not inst.unknown:
            msg_id = _inst_param(inst, "Message") or 0
            unit_param = _inst_param(inst, "Unit") or 0
            speaker = resolve_speaker(unit_param, entd_slots, sprite_names, unit_names)
            entry = strings.get(msg_id)
            if entry is None:
                text = f"(msg id #{msg_id} — out of range)"
            else:
                _off, text = entry
            lines.append(f"**`{addr}` {speaker.display}:** {text}")
            lines.append("")
            lines.append(
                f"  > _msg #{msg_id} · unit byte=0x{speaker.unit_byte:02X} "
                f"· slot={speaker.slot_index} · sprite=0x{speaker.sprite_set:02X}_"
                if speaker.slot_index is not None else
                f"  > _msg #{msg_id} · unit byte=0x{speaker.unit_byte:02X} (no ENTD slot match)_"
            )
            lines.append("")
        elif inst.opcode == EVENT_END_OPCODE:
            lines.append(f"`{addr}` **Event End**")
            lines.append("")
            break
        else:
            lines.append(f"`{addr}` _{_stage_direction(inst)}_")
    return "\n".join(lines) + "\n"


def render_json(
    insts: list,
    strings: StringTable,
    entd_slots: list[dict],
    sprite_names: dict[int, str],
    unit_names: dict[int, str],
    scenario: dict,
) -> dict:
    out_insts: list[dict] = []
    for inst in insts:
        rec: dict = {
            "offset": inst.offset,
            "ram_addr": inst.ram_addr,
            "opcode": inst.opcode,
            "name": inst.name,
            "unknown": inst.unknown,
            "params": inst.params,
        }
        if inst.opcode == DISPLAY_MESSAGE_OPCODE and not inst.unknown:
            msg_id = _inst_param(inst, "Message") or 0
            unit_param = _inst_param(inst, "Unit") or 0
            speaker = resolve_speaker(unit_param, entd_slots, sprite_names, unit_names)
            entry = strings.get(msg_id)
            rec["dialogue"] = {
                "message_id": msg_id,
                "string_offset": entry[0] if entry else None,
                "text": entry[1] if entry else None,
                "speaker": {
                    "unit_byte": speaker.unit_byte,
                    "slot_index": speaker.slot_index,
                    "sprite_set": speaker.sprite_set,
                    "sprite_name": speaker.sprite_name,
                    "unit_id": speaker.unit_id,
                    "unit_name": speaker.unit_name,
                    "special_name": speaker.special_name,
                    "display": speaker.display,
                },
            }
        out_insts.append(rec)
        if inst.opcode == EVENT_END_OPCODE:
            break
    return {
        "scenario": scenario,
        "string_table": {
            "base": strings.base,
            "count": len(strings.entries),
            "entries": [{"id": i + 1, "offset": off, "text": text}
                        for i, (off, text) in enumerate(strings.entries)],
        },
        "instructions": out_insts,
    }


# =============================================================================
# CLI
# =============================================================================

def main() -> None:
    ap = argparse.ArgumentParser(description="Render an FFT scenario as a screenplay")
    ap.add_argument("file", type=Path, help="captured event-script chunk")
    ap.add_argument("--scenario", type=int, required=True,
                    help="scenario_id (selects the ENTD record for unit lookups)")
    ap.add_argument("--chunk-base", type=lambda s: int(s, 0), default=None,
                    help="RAM base; default: detected from filename _0xHHHHHHHH suffix")
    ap.add_argument("--scenarios", type=Path, default=DEFAULT_SCENARIOS)
    ap.add_argument("--entd", type=Path, default=DEFAULT_ENTD)
    ap.add_argument("--unit-names", type=Path, default=DEFAULT_UNIT_NAMES)
    ap.add_argument("--sprite-names", type=Path, default=DEFAULT_SPRITE_NAMES)
    ap.add_argument("--catalog", "--xml", dest="catalog", type=Path,
                    default=EVENT_CATALOG)
    ap.add_argument("--json", action="store_true", help="emit JSON instead of Markdown")
    ap.add_argument("--out", type=Path, default=None,
                    help="write to file instead of stdout")
    args = ap.parse_args()

    table = load_opcodes(args.catalog)
    buf = args.file.read_bytes()
    base = args.chunk_base
    if base is None:
        base = detect_chunk_base(args.file) or 0

    str_base = find_string_table_base(buf, table)
    strings = StringTable(base=str_base, entries=walk_strings(buf, str_base))
    insts = disasm(buf, table, chunk_base=base)

    scenario = load_scenario_record(args.scenarios, args.scenario)
    entd = load_entd_record(args.entd, scenario["entd_idx"])
    sprite_names = load_name_map(args.sprite_names)
    unit_names = load_name_map(args.unit_names)

    if args.json:
        payload = render_json(
            insts, strings, entd["slots"], sprite_names, unit_names, scenario,
        )
        text = json.dumps(payload, indent="\t")
    else:
        text = render_markdown(
            insts, table, strings, entd["slots"], sprite_names, unit_names, scenario,
        )

    if args.out:
        args.out.write_text(text)
        print(f"wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
