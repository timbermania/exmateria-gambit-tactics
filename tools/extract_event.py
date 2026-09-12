"""Extract a single event from TEST.EVT (= Events.bin) and prepare it
for ScenarioVM consumption.

TEST.EVT is 500 events x 8,192 bytes each. Each event:
    +0  u32 text_offset (or sentinel 0xF2F2F2F2 = no text)
    +4  command bytes (event-script bytecode)
    +text_offset  optional text section

The cinematic chunks at runtime get loaded into RAM at 0x8004A6BC. The
RAM image has the 4-byte text_offset header overwritten with 4 x 0xF2
(No-op padding) -- the event-load handler paints over it because
text-loading is keyed off a separate mechanism. `to_ram_chunk()` does
the same overwrite to reproduce the RAM-captured shape.

The text/string-table region IS preserved in RAM (the live capture at
0x8004A6BC retains it -- that's where Display Message resolves its
strings). `to_ram_chunk(preserve_text=True)` keeps it, reproducing the
capture `cinematic_event_chunk_0x8004A6BC.bin` byte-for-byte (verified:
event 2's command region + text == the capture, modulo the F2 header).
`--with-text` uses that path and bakes the resolved dialogue, and is what
`export_all_scenario_chunks.py` uses for every event. PREFER IT. The default
scrubs the text region to zeros, which leaves the walker disassembling the
padding past `Event End` — that is how the old command-only
`scenario_0001_setup_chunk.json` came to hold 2,737 instructions for a 7-
instruction script. That file has been deleted; nothing read it.

The event index is the canonical scenario id used by:
    - ScenarioNames.xml (`0x0001 = Orbonne Prayer (Setup)` etc.)
    - BC opcode 0x0019 Run Scenario
    - current_scenario_id at 0x8016A014 (see memory pin
      [[scenario-chunk-slot-bc-n-current-scenario-id-2026-06-20]])

Usage:
    # Dump event 1 (Orbonne Prayer Setup) as a chunk JSON. Pass --with-text
    # unless you specifically want the scrubbed-text shape:
    uv run python tools/extract_event.py --event 1 --with-text \\
        --output /tmp/event_0001.json

    # Or list every event by index + name:
    uv run python tools/extract_event.py --list
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from pathlib import Path

from _repo_paths import event_dir


EVENT_SIZE = 8192
NUM_EVENTS = 500
BLANK_TEXT_OFFSET = 0xF2F2F2F2  # DataHelper.cs:43
EVENT_END_OPCODE = 0xDB  # {DB} Event End — the script terminator the VM halts on


@dataclass(frozen=True)
class Event:
    """One raw event extracted from TEST.EVT."""

    index: int
    text_offset: int
    command_bytes: bytes  # cmd region only, trimmed at text_offset if any
    raw_bytes: bytes      # full 8192-byte slice

    @property
    def raw_bytes_len(self) -> int:
        return len(self.raw_bytes)


def list_events(path: str | Path) -> list[int]:
    """Cheap probe: how many EVENT_SIZE-aligned events does the file hold?"""
    size = Path(path).stat().st_size
    if size != NUM_EVENTS * EVENT_SIZE:
        raise ValueError(
            f"TEST.EVT size mismatch: got {size}, expected {NUM_EVENTS * EVENT_SIZE}"
        )
    return list(range(NUM_EVENTS))


def read_event(path: str | Path, index: int) -> Event:
    if not (0 <= index < NUM_EVENTS):
        raise IndexError(f"event index {index} out of range [0, {NUM_EVENTS})")
    data = Path(path).read_bytes()
    if len(data) != NUM_EVENTS * EVENT_SIZE:
        raise ValueError(f"TEST.EVT size {len(data)} != {NUM_EVENTS * EVENT_SIZE}")
    chunk = data[index * EVENT_SIZE : (index + 1) * EVENT_SIZE]
    text_offset = struct.unpack_from("<I", chunk, 0)[0]
    if text_offset == BLANK_TEXT_OFFSET:
        cmd_end = len(chunk)
    else:
        # text_offset is event-local; cmd region runs from 4 .. text_offset
        cmd_end = max(4, min(text_offset, len(chunk)))
    return Event(
        index=index,
        text_offset=text_offset,
        command_bytes=bytes(chunk[4:cmd_end]),
        raw_bytes=bytes(chunk),
    )


def to_ram_chunk(ev: Event, preserve_text: bool = False) -> bytes:
    """Produce the RAM-layout 8192-byte chunk: text_offset header painted
    over with 4 x 0xF2 No-op pad, command bytes intact.

    With ``preserve_text`` the text/string-table region is kept verbatim
    (the real RAM image -- reproduces the 0x8004A6BC capture byte-for-byte).
    Without it the text region is scrubbed to zeros (command-only shape)."""
    if preserve_text:
        # Real RAM image: only the 4-byte text_offset header is overwritten;
        # commands + text table stay intact (== the live capture).
        return b"\xf2\xf2\xf2\xf2" + ev.raw_bytes[4:]
    out = bytearray(EVENT_SIZE)
    out[0:4] = b"\xf2\xf2\xf2\xf2"
    out[4 : 4 + len(ev.command_bytes)] = ev.command_bytes
    # rest stays zeroed (text region scrubbed)
    return bytes(out)


# Placement opcodes whose absolute depth row (Event-Y) is an ADR-0052 Placement:
# it gets the 180°-about-X depth mirror. Sprite Move is deliberately absent — its
# +Y is a relative delta (a difference of absolutes), so it takes the linear part
# only (a sign flip, handled at decode), never the size_z mirror (ADR-0057).
_PLACEMENT_DEPTH_OPCODES = {"Warp Unit", "Walk To"}


def _flip_placement_rows(records: list[dict], size_z: int) -> None:
    """Bake the ADR-0052/0057 depth mirror onto every placement opcode's Event-Y
    row IN PLACE, turning a raw PSX chunk into the Godot-native consumed chunk.

    `godot_z = size_z - 1 - psx_z` (the same flip terrain/ENTD get at parse time;
    PsxNum.flip_depth_row). The record's `raw` hex is re-packed from opcode +
    params so the consumed chunk is fully Godot-native — no PSX bytes lurk in it
    (the raw byte-faithful form lives in the sidecar). X (lateral) and height are
    untouched: the rotation is about X."""
    for rec in records:
        if rec.get("name") not in _PLACEMENT_DEPTH_OPCODES:
            continue
        params = rec.get("params", [])
        y_param = next((p for p in params if p.get("name") == "Y"), None)
        if y_param is None:
            continue
        y = int(y_param["value"])
        # Only flip a VALID tile row (0 <= y < size_z). Rows outside the map are
        # disassembler over-walk garbage past Event End (the string table walked
        # as if it were opcodes) — never executed, so leave them byte-for-byte
        # raw rather than mirror them to a negative row.
        if not (0 <= y < size_z):
            continue
        y_param["value"] = size_z - 1 - y
        # Re-pack raw = opcode(1 byte, event opcode width) + LE params, so the
        # consumed chunk is fully Godot-native (no PSX bytes lurking).
        raw = bytes([int(rec["opcode"]) & 0xFF])
        for p in params:
            raw += int(p["value"]).to_bytes(int(p["bytes"]), "little")
        rec["raw"] = raw.hex()


def to_chunk_json(ev: Event, source_label: str | None = None,
                  with_text: bool = False,
                  placement_size_z: int | None = None) -> dict:
    """Disassemble + format as a chunk-JSON matching scenario_1_chunk.json.

    ``with_text`` preserves the text region and bakes the resolved Display
    Message string table + per-message dialogue (the ``--with-text`` shape).

    ``placement_size_z``: when set (the map's depth in tiles), bake the ADR-0052
    depth mirror onto every placement opcode's Event-Y row, emitting the
    **Godot-native consumed chunk** the runtime reads directly (no runtime flip).
    Left None → the raw, byte-faithful PSX chunk (the RE-diff sidecar). ADR-0057:
    the scenario chunk is the last transitional Placement; this brings it home to
    the parser like every other Placement."""
    # Local import to avoid making _fft_bytecode a hard dependency of
    # read_event() (which is the smallest useful API).
    from _fft_bytecode import (
        load_opcodes, disasm, format_json, EVENT_CATALOG, catalog_label,
    )

    ram = to_ram_chunk(ev, preserve_text=with_text)
    table = load_opcodes(EVENT_CATALOG)
    # ScenarioVM's RAM base for the scenario-chunk slot is 0x8004A6BC
    # per memory [[scenario-chunk-slot-bc-n-current-scenario-id-2026-06-20]].
    #
    # Terminate the instruction walk at the first {DB} Event End — exactly
    # where the runtime halts (parser.lua breaks on 0xDB; ScenarioVM sets the
    # context dead). This is what keeps a SETUP STUB event (Reveal+Wait+End,
    # and crucially NO text section) from over-walking: with no text_offset to
    # bound it, the walk would otherwise run the whole 8192-byte slot's zero
    # padding as thousands of unknown opcodes.
    #
    # Also bound the walk at `text_offset` for events that DO have text: the
    # command region ends where the string table begins (the 0xDB sits just
    # before it), so this stops the disassembler walking dialogue bytes as if
    # they were opcodes. The stop-at-Event-End is the primary terminator; the
    # text_offset bound is a belt-and-suspenders guard for a malformed event
    # whose 0xDB is absent. A blank text_offset (0xF2F2F2F2 = no text) leaves
    # only the Event-End stop. The text is walked separately below (--with-text).
    cmd_end = None
    if ev.text_offset != BLANK_TEXT_OFFSET:
        cmd_end = max(4, min(ev.text_offset, len(ram)))
    insts = disasm(ram, table, chunk_base=0x8004A6BC, end=cmd_end,
                   stop_opcode=EVENT_END_OPCODE)
    records = [format_json(i) for i in insts]
    if placement_size_z is not None:
        _flip_placement_rows(records, placement_size_z)
    doc = {
        "_source": source_label or f"TEST.EVT event index {ev.index}",
        "_chunk_base": 0x8004A6BC,
        "_catalog": catalog_label(EVENT_CATALOG),
        "_opcode_width": 1,
        "_event_index": ev.index,
        "_text_offset": ev.text_offset,
        # ADR-0057 Placement: True → placement Event-Y rows are pre-flipped
        # (Godot-native consumed chunk); False → raw byte-faithful PSX (sidecar).
        "_placement_flipped": placement_size_z is not None,
        "_map_size_z": placement_size_z,
        "instructions": records,
    }
    if with_text:
        # Mirror disasm_event.py --with-text: walk the post-Event-End string
        # table and attach the resolved text + tokens to every Display Message.
        from _fft_strings import (
            StringTable, find_string_table_base, walk_strings,
        )
        from disasm_event import _attach_dialogue

        str_base = find_string_table_base(ram, table)
        strings = StringTable(base=str_base, entries=walk_strings(ram, str_base))
        _attach_dialogue(records, strings)
        doc["_string_table"] = {"base": strings.base, "count": len(strings.entries)}
    return doc


def _main() -> int:
    import argparse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, default=None,
                   help="TEST.EVT path (default: project-assets)")
    p.add_argument("--event", type=int, default=None,
                   help="Event index (0..499) to extract")
    p.add_argument("--output", type=Path, default=None,
                   help="Write chunk-JSON to this path")
    p.add_argument("--list", action="store_true",
                   help="List event indices (no extraction)")
    p.add_argument("--with-text", action="store_true",
                   help="Preserve the text region and bake the resolved "
                        "Display Message string table + dialogue "
                        "(matches the RAM-sourced scenario_1_chunk.json shape)")
    p.add_argument("--placement-size-z", type=int, default=None,
                   help="Map depth in tiles (size_z). When set, emit the "
                        "Godot-native consumed chunk with placement Event-Y rows "
                        "pre-flipped (ADR-0057); omit for the raw PSX sidecar.")
    args = p.parse_args()

    in_path = args.input or (event_dir() / "TEST.EVT")

    if args.list:
        for i in list_events(in_path):
            print(i)
        return 0

    if args.event is None:
        p.error("--event INDEX is required (or use --list)")

    ev = read_event(in_path, args.event)
    print(f"event {ev.index}: text_offset=0x{ev.text_offset:08x} "
          f"cmd_bytes={len(ev.command_bytes)}")

    if args.output:
        doc = to_chunk_json(ev, source_label=f"TEST.EVT event {ev.index}",
                            with_text=args.with_text,
                            placement_size_z=args.placement_size_z)
        args.output.write_text(json.dumps(doc, indent=2))
        print(f"wrote {args.output} ({len(doc['instructions'])} instructions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
