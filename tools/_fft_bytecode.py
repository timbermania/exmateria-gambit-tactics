"""
Shared opcode loader + disassembler for FFT bytecode languages.

Two FFT bytecode languages live in the EntryEdit data set, both following
the same catalog shape but with different opcode widths:

- **Event script** (`event_instructions.json`, `_opcode_width=1`): drives
  cutscenes / scenarios. Run by FFT's event-script VM. Lives in Events.bin
  and per-scenario RAM chunks (e.g. `0x8004A6BC`).
- **BattleConditionals** (`battle_conditional_opcodes.json`,
  `_opcode_width=2`): the scripted condition language scenarios use to chain
  into the next scenario, set variables, etc. Lives in BTLEVT.BIN; loaded to
  RAM at `0x80049A18` for set 1.

The catalogs are **OWNED authored data** (sibling to `scenario_names.json`
et al. under `assets/scenarios/`), seeded from FFTPatcher's
`EventCommands.xml` / `BattleConditionalCommands.xml` but corrected + carrying
per-opcode `verified` flags + `handler` cross-refs. They are regenerated /
checked by `gen_opcode_catalog.py`; the vendored XML now lives reference-only
under `tools/data/vendor/` and is no longer on the parser path. This follows
the ISO-derived-data + in-housed-authored pattern (ADR-0001; precedent
`parse_scenarios.py:37-48`).

The owned JSON format is:

    {
      "_provenance": "...",
      "_opcode_width": N,
      "opcodes": {
        "0xHH": {"name": "...", "params": [{"name", "bytes", ["type"], ["mode"]}],
                 "verified": bool, ["handler": "...", "notes": "..."]}
      }
    }

This module supplies:

- `load_opcodes(path)` → parses an owned JSON catalog (or, for the
  generator/reference path, a legacy XML) into an `OpcodeTable` carrying the
  per-instruction opcode-width.
- `disasm(...)` → walks a byte buffer, emits either human-readable lines
  (`format_human`) or structured records (`format_json`) — both exported
  so callers can choose at runtime.

Callers (`disasm_event.py`, `disasm_bc.py`) only configure the default
catalog path; the disassembly engine is identical for both.
"""

from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
ASSETS_SCENARIOS = Path(__file__).parent.parent / "assets" / "scenarios"
# Owned authored catalogs (the parser source of truth). Repo-relative labels
# for baked artifacts come from `catalog_label()` below.
EVENT_CATALOG = ASSETS_SCENARIOS / "event_instructions.json"
BC_CATALOG = ASSETS_SCENARIOS / "battle_conditional_opcodes.json"


@dataclass
class Param:
    name: str
    bytes: int
    type: str | None = None
    mode: str | None = None


@dataclass
class Opcode:
    hex: int
    name: str
    params: list[Param] = field(default_factory=list)

    @property
    def body_bytes(self) -> int:
        return sum(p.bytes for p in self.params)


@dataclass
class OpcodeTable:
    opcode_width: int           # 1 or 2 (bytes of opcode header)
    by_hex: dict[int, Opcode]


def load_opcodes_json(path: Path) -> OpcodeTable:
    """Load an OWNED opcode catalog (`event_instructions.json` shape). The parser
    source of truth; see module docstring for the JSON layout."""
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    width = int(doc.get("_opcode_width", 1))
    by_hex: dict[int, Opcode] = {}
    for hex_str, entry in doc["opcodes"].items():
        op = int(hex_str, 16)
        params = [
            Param(
                name=p.get("name", f"arg{i}"),
                bytes=int(p["bytes"]),
                type=p.get("type"),
                mode=p.get("mode"),
            )
            for i, p in enumerate(entry.get("params", []))
        ]
        by_hex[op] = Opcode(hex=op, name=entry.get("name", "Unknown"), params=params)
    return OpcodeTable(opcode_width=width, by_hex=by_hex)


def load_opcodes_xml(xml_path: Path) -> OpcodeTable:
    """Load a legacy FFTPatcher catalog XML. Reference/generator path only —
    the parser reads the owned JSON via `load_opcodes`. Kept so
    `gen_opcode_catalog.py` and ad-hoc XML inspection still work."""
    tree = ET.parse(xml_path)
    root = tree.getroot()
    width = int(root.attrib.get("bytes", "1"))
    by_hex: dict[int, Opcode] = {}
    for cmd in root.findall("Command"):
        op = int(cmd.attrib["hex"], 16)
        name = cmd.attrib.get("name", "Unknown")
        params = [
            Param(
                name=p.attrib.get("name", f"arg{i}"),
                bytes=int(p.attrib["bytes"]),
                type=p.attrib.get("type"),
                mode=p.attrib.get("mode"),
            )
            for i, p in enumerate(cmd.findall("Parameter"))
        ]
        by_hex[op] = Opcode(hex=op, name=name, params=params)
    return OpcodeTable(opcode_width=width, by_hex=by_hex)


def load_opcodes(path: Path) -> OpcodeTable:
    """Parse an opcode catalog into an `OpcodeTable`. Dispatches on suffix:
    `.json` → owned catalog (the parser default); `.xml` → legacy FFTPatcher
    reference (generator/inspection only)."""
    return load_opcodes_xml(path) if Path(path).suffix == ".xml" \
        else load_opcodes_json(path)


def catalog_label(path: Path) -> str:
    """Repo-relative label for a catalog path, for baking into chunk JSON
    `_catalog` (no host-tailored absolute paths — ADR-0001)."""
    p = Path(path)
    try:
        return str(p.relative_to(Path(__file__).parent.parent))
    except ValueError:
        return p.name


# Pull a `0x8004A6BC`-style suffix out of a filename so callers can omit
# `--chunk-base` for capture artifacts named with their RAM address.
_BASE_RE = re.compile(r"_0x([0-9A-Fa-f]{6,8})\b")


def detect_chunk_base(path: Path) -> int | None:
    m = _BASE_RE.search(path.stem)
    return int(m.group(1), 16) if m else None


@dataclass
class Instruction:
    offset: int                 # byte offset into the buffer
    ram_addr: int               # offset + chunk_base
    opcode: int                 # raw opcode value (1 or 2 bytes wide)
    name: str                   # opcode mnemonic
    params: list[dict]          # decoded params: [{name, type, value, bytes}]
    raw: bytes                  # full instruction bytes
    unknown: bool = False       # true if opcode not in table (no params decoded)


def disasm(buf: bytes, table: OpcodeTable, chunk_base: int = 0,
           start: int = 0, end: int | None = None,
           stop_opcode: int | None = None) -> list[Instruction]:
    """Disassemble `buf[start:end]` (or full buffer) into Instruction records.

    Unknown opcodes are emitted as 1-or-2-byte stubs (matching the opcode
    width) so the walk can continue; the `unknown` flag is set so callers
    can highlight them. If the trailing instruction would overrun the
    buffer, it is truncated and `unknown=True`.

    `stop_opcode`: when set (e.g. the event language's `0xDB` Event End), the
    walk terminates right AFTER emitting the first instruction with that opcode
    — matching the runtime, which halts on the first Event End (parser.lua /
    ScenarioVM). Without it, callers past a real terminator would walk the
    trailing string table / zero padding as spurious opcodes."""
    if end is None:
        end = len(buf)
    width = table.opcode_width
    pc = start
    out: list[Instruction] = []
    while pc + width <= end:
        op = int.from_bytes(buf[pc:pc + width], "little")
        cmd = table.by_hex.get(op)
        if cmd is None:
            out.append(Instruction(
                offset=pc, ram_addr=chunk_base + pc, opcode=op,
                name="Unknown", params=[], raw=buf[pc:pc + width], unknown=True,
            ))
            pc += width
            if op == stop_opcode:
                break
            continue
        body_len = cmd.body_bytes
        if pc + width + body_len > end:
            # Truncated: emit as unknown so we don't fabricate values.
            out.append(Instruction(
                offset=pc, ram_addr=chunk_base + pc, opcode=op,
                name=cmd.name, params=[], raw=buf[pc:end], unknown=True,
            ))
            break
        params: list[dict] = []
        o = pc + width
        for p in cmd.params:
            v = int.from_bytes(buf[o:o + p.bytes], "little")
            params.append({
                "name": p.name, "type": p.type,
                "value": v, "bytes": p.bytes,
            })
            o += p.bytes
        out.append(Instruction(
            offset=pc, ram_addr=chunk_base + pc, opcode=op,
            name=cmd.name, params=params, raw=buf[pc:pc + width + body_len],
        ))
        pc += width + body_len
        if op == stop_opcode:
            break
    return out


def format_human(inst: Instruction, opcode_width: int) -> str:
    """Render an Instruction as a one-line disassembly string (matches the
    legacy `event_disasm.py` / `bc_disasm.py` output format)."""
    op_fmt = f"0x{inst.opcode:0{opcode_width * 2}X}"
    raw = inst.raw.hex(" ")
    if inst.unknown and not inst.params:
        return (f"  +{inst.offset:04X} {inst.ram_addr:#010x}  "
                f"?? <{op_fmt}>  {inst.name:s}  [{raw}]")
    parts = [f"{p['name']}={p['value']:#x}" for p in inst.params]
    return (f"  +{inst.offset:04X} {inst.ram_addr:#010x}  "
            f"{op_fmt} {inst.name:24s}  {', '.join(parts):60s}  [{raw}]")


def format_json(inst: Instruction) -> dict:
    """JSON-safe dict for the structured output mode."""
    return {
        "offset": inst.offset,
        "ram_addr": inst.ram_addr,
        "opcode": inst.opcode,
        "name": inst.name,
        "unknown": inst.unknown,
        "params": inst.params,
        "raw": inst.raw.hex(),
    }
