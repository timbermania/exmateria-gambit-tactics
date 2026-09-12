#!/usr/bin/env python3
"""
Disassemble FFT BattleConditionals bytecode (2-byte little-endian opcodes).

BattleConditionals are the scripted condition language scenarios use to
chain to the next scenario, set variables, check unit HP, etc. The file
lives at `BTLEVT.BIN`; the canonical RAM mirror for set 1 is `0x80049A18`.
Opcode `0x0019 Run Scenario N` is the chain primitive that drives
scenario-to-scenario flow (see SCENARIO_LOADING.md §3.2.5).

Opcode catalog: the OWNED `assets/scenarios/battle_conditional_opcodes.json`
(seeded from FFTPatcher's `BattleConditionalCommands.xml`, now reference-only
under `tools/data/vendor/`; regenerated/checked by `gen_opcode_catalog.py`).
Shared loader/walker lives in `tools/_fft_bytecode.py` (see also
`disasm_event.py` for the 1-byte event-script dialect).

Usage:
    uv run python tools/disasm_bc.py CHUNK.bin
    uv run python tools/disasm_bc.py --chunk-base 0x80049A18 CHUNK.bin
    uv run python tools/disasm_bc.py --json CHUNK.bin
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from _fft_bytecode import (
    BC_CATALOG, catalog_label, detect_chunk_base, disasm, format_human,
    format_json, load_opcodes,
)


def main() -> None:
    ap = argparse.ArgumentParser(description="Disassemble FFT BattleConditionals bytecode")
    ap.add_argument("file", type=Path, help="byte stream to disassemble")
    ap.add_argument("--catalog", "--xml", dest="catalog", type=Path,
                    default=BC_CATALOG,
                    help="opcode catalog path (default: %(default)s)")
    ap.add_argument("--chunk-base", type=lambda s: int(s, 0), default=None,
                    help="RAM base address. Default: parsed from filename; else 0.")
    ap.add_argument("--start", type=lambda s: int(s, 0), default=0,
                    help="start byte offset within the file (default: 0)")
    ap.add_argument("--end", type=lambda s: int(s, 0), default=None,
                    help="end byte offset within the file (default: EOF)")
    ap.add_argument("--json", action="store_true",
                    help="emit JSON records instead of human-readable lines")
    args = ap.parse_args()

    table = load_opcodes(args.catalog)
    data = args.file.read_bytes()
    base = args.chunk_base
    if base is None:
        base = detect_chunk_base(args.file) or 0
    insts = disasm(data, table, chunk_base=base, start=args.start, end=args.end)

    if args.json:
        print(json.dumps({
            "_source": str(args.file),
            "_chunk_base": base,
            "_catalog": catalog_label(args.catalog),
            "_opcode_width": table.opcode_width,
            "instructions": [format_json(i) for i in insts],
        }, indent="\t"))
        return

    print(f"# {args.file}  ({len(data)} bytes)  chunk_base=0x{base:08X}")
    print(f"# disasm range: 0x{args.start:X} .. 0x{(args.end or len(data)):X}")
    print(f"# {len(table.by_hex)} opcodes loaded from {args.catalog}")
    for inst in insts:
        print(format_human(inst, table.opcode_width))


if __name__ == "__main__":
    main()
