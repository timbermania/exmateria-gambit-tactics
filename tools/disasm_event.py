#!/usr/bin/env python3
"""
Disassemble FFT event-script bytecode (1-byte opcodes).

Event script is the cutscene/scenario instruction language run by FFT's
event VM. Found in `Events.bin` (per-event scripts), in BTLEVT.BIN, and in
the per-scenario RAM chunk overwritten by each `0xDB Event End` transition
(canonical RAM addr `0x8004A6BC`).

Opcode catalog: the OWNED `assets/scenarios/event_instructions.json` (seeded from
FFTPatcher's `EventCommands.xml`, now reference-only under
`tools/data/vendor/`; regenerated/checked by `gen_opcode_catalog.py`). Shared
loader/walker lives in `tools/_fft_bytecode.py` (see also `disasm_bc.py` for
the 2-byte BattleConditionals dialect).

Usage:
    # Human-readable disasm of a captured chunk:
    uv run python tools/disasm_event.py CHUNK.bin

    # Override RAM base (default: detected from filename suffix _0xHHHHHHHH;
    # absent → 0):
    uv run python tools/disasm_event.py --chunk-base 0x8004A6BC CHUNK.bin

    # Structured JSON (one record per instruction):
    uv run python tools/disasm_event.py --json CHUNK.bin

    # Bound the walk (start/end byte offsets):
    uv run python tools/disasm_event.py --start 0 --end 0x944 CHUNK.bin
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from _fft_bytecode import (
    EVENT_CATALOG, catalog_label, detect_chunk_base, disasm, format_human,
    format_json, load_opcodes,
)
from _fft_strings import (
    StringTable, find_string_table_base, tokenize, walk_strings,
)

DISPLAY_MESSAGE_OPCODE = 0x10


def _param_value(params: list[dict], name: str) -> int | None:
    for p in params:
        if p["name"] == name:
            return p["value"]
    return None


def _attach_dialogue(records: list[dict], strings: StringTable) -> None:
    """Mutates each ``0x10 Display Message`` record in-place, adding a
    ``dialogue`` sub-dict with the resolved string + structured tokens."""
    for rec in records:
        if rec["opcode"] != DISPLAY_MESSAGE_OPCODE or rec["unknown"]:
            continue
        msg_id = _param_value(rec["params"], "Message") or 0
        unit = _param_value(rec["params"], "Unit") or 0
        entry = strings.get(msg_id)
        raw = entry[1] if entry else None
        rec["dialogue"] = {
            "message_id": msg_id,
            "string_offset": entry[0] if entry else None,
            "speaker_unit_byte": unit & 0xFF,
            "raw_text": raw,
            "tokens": tokenize(raw) if raw is not None else [],
        }


def main() -> None:
    ap = argparse.ArgumentParser(description="Disassemble FFT event-script bytecode")
    ap.add_argument("file", type=Path, help="byte stream to disassemble")
    ap.add_argument("--catalog", "--xml", dest="catalog", type=Path,
                    default=EVENT_CATALOG,
                    help="opcode catalog path (default: %(default)s)")
    ap.add_argument("--chunk-base", type=lambda s: int(s, 0), default=None,
                    help="RAM base address. Default: parsed from filename "
                         "(e.g. event_chunk_0x8004A6BC.bin → 0x8004A6BC); else 0.")
    ap.add_argument("--start", type=lambda s: int(s, 0), default=0,
                    help="start byte offset within the file (default: 0)")
    ap.add_argument("--end", type=lambda s: int(s, 0), default=None,
                    help="end byte offset within the file (default: EOF)")
    ap.add_argument("--json", action="store_true",
                    help="emit JSON records instead of human-readable lines")
    ap.add_argument("--with-text", action="store_true",
                    help="(JSON mode only) walk the post-Event-End string "
                         "table and bake the resolved text + structured "
                         "tokens into every 0x10 Display Message record.")
    args = ap.parse_args()

    table = load_opcodes(args.catalog)
    data = args.file.read_bytes()
    base = args.chunk_base
    if base is None:
        base = detect_chunk_base(args.file) or 0
    insts = disasm(data, table, chunk_base=base, start=args.start, end=args.end)

    if args.json:
        records = [format_json(i) for i in insts]
        payload: dict = {
            "_source": str(args.file),
            "_chunk_base": base,
            "_catalog": catalog_label(args.catalog),
            "_opcode_width": table.opcode_width,
            "instructions": records,
        }
        if args.with_text:
            str_base = find_string_table_base(data, table)
            strings = StringTable(
                base=str_base, entries=walk_strings(data, str_base),
            )
            _attach_dialogue(records, strings)
            payload["_string_table"] = {
                "base": strings.base,
                "count": len(strings.entries),
            }
        print(json.dumps(payload, indent="\t"))
        return

    print(f"# {args.file}  ({len(data)} bytes)  chunk_base=0x{base:08X}")
    print(f"# disasm range: 0x{args.start:X} .. 0x{(args.end or len(data)):X}")
    print(f"# {len(table.by_hex)} opcodes loaded from {args.catalog}")
    for inst in insts:
        print(format_human(inst, table.opcode_width))


if __name__ == "__main__":
    main()
