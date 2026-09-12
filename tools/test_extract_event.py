"""Tests for tools/extract_event.py.

TEST.EVT (= Events.bin) holds 500 events x 8,192 bytes each. Each event:
    +0  u32 text_offset (or sentinel 0xF2F2F2F2 = no text)
    +4  command bytes (event-script bytecode)
    +text_offset  optional text section

Event indices come from ScenarioNames.xml:
    0x0001 = Orbonne Prayer (Setup)        -- cinematic prep, NO text
    0x0002 = Orbonne Prayer                -- the cinematic itself
    ...

The Setup chunk's text_offset is 0xF2F2F2F2 (no text). The cinematic chunk
has text_offset = 0x8F9.

For parity with the existing RAM-captured `scenario_1_chunk.json` shape,
we replace the 4-byte text_offset header with 4 x 0xF2 (No-op padding) and
truncate command bytes at text_offset (when present). The result is a
chunk ready to feed to disasm_event.disasm().

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_extract_event
"""

from __future__ import annotations

import unittest
from pathlib import Path

import extract_event as ee
from _repo_paths import event_dir


TEST_EVT = event_dir() / "TEST.EVT"
CAPTURED_CINEMATIC = (
    Path(__file__).resolve().parent.parent.parent
    / "research" / "working_documents" / "scenario_1_captures"
    / "cinematic_event_chunk_0x8004A6BC.bin"
)

EVENT_SIZE = 8192


@unittest.skipUnless(TEST_EVT.exists(), f"TEST.EVT not present at {TEST_EVT}")
class ExtractEventTracerTest(unittest.TestCase):

    def test_event_count_is_500(self) -> None:
        events = ee.list_events(TEST_EVT)
        self.assertEqual(len(events), 500)

    def test_event_1_is_setup_with_blank_text_offset(self) -> None:
        ev = ee.read_event(TEST_EVT, 1)
        self.assertEqual(ev.index, 1)
        self.assertEqual(ev.raw_bytes_len, EVENT_SIZE)
        # 0xF2F2F2F2 sentinel per DataHelper.cs:43 BlankTextOffsetValue
        self.assertEqual(ev.text_offset, 0xF2F2F2F2)
        # First real cmd bytes are 4d 02 f1 1e 00 db ... (Reveal, Wait, Event End)
        self.assertEqual(ev.command_bytes[:6].hex(), "4d02f11e00db")

    def test_event_2_command_bytes_match_ram_capture(self) -> None:
        """Cinematic chunk extracted from TEST.EVT must match the
        RAM-captured chunk byte-for-byte after we paint over the
        text_offset header with the 4 No-op pad bytes the engine uses
        when loading the chunk into RAM at 0x8004A6BC."""
        if not CAPTURED_CINEMATIC.exists():
            self.skipTest(f"capture missing: {CAPTURED_CINEMATIC}")
        ev = ee.read_event(TEST_EVT, 2)
        ram_layout = ee.to_ram_chunk(ev)
        self.assertEqual(len(ram_layout), EVENT_SIZE)
        cap = CAPTURED_CINEMATIC.read_bytes()
        # Compare command region (skip the 4 pad bytes and stop at text_offset
        # since the RAM capture truncates text section out anyway).
        # The capture starts with f2f2f2f2 then real cmds; ours should too.
        self.assertEqual(ram_layout[:4].hex(), "f2f2f2f2")
        # First 256 bytes including the 4 F2 pad must match the capture.
        self.assertEqual(ram_layout[:256], cap[:256])

    def test_event_2_preserve_text_matches_capture_exactly(self) -> None:
        """preserve_text reproduces the full 0x8004A6BC RAM image -- commands
        AND the text/string-table region -- byte-for-byte (not just the
        command prefix). This is the ISO source for scenario_1_chunk.json."""
        if not CAPTURED_CINEMATIC.exists():
            self.skipTest(f"capture missing: {CAPTURED_CINEMATIC}")
        ev = ee.read_event(TEST_EVT, 2)
        ram_layout = ee.to_ram_chunk(ev, preserve_text=True)
        self.assertEqual(ram_layout, CAPTURED_CINEMATIC.read_bytes())

    def test_chunk_json_stops_at_text_boundary(self) -> None:
        """The disassembly must stop at the command/text boundary (text_offset)
        instead of walking dialogue text bytes as spurious opcodes past the
        real Event End. Regression for the ~1750 phantom rows (and the ghost
        'Event End' markers at text bytes) the old unbounded walk emitted."""
        ev = ee.read_event(TEST_EVT, 2)
        doc = ee.to_chunk_json(ev, with_text=True)
        insts = doc["instructions"]
        # Every emitted instruction is inside the command region [0, text_offset).
        self.assertTrue(insts, "expected a non-empty command region")
        self.assertLess(insts[-1]["offset"], ev.text_offset,
                        "last instruction leaked into the text/string table")
        # The command region ends with the sole 0x13 Event End; no phantom
        # Event Ends past it (those were text bytes that happened to be 0x13).
        event_ends = [i for i in insts if i["name"] == "Event End"]
        self.assertEqual(len(event_ends), 1,
                         "exactly one real Event End should survive the bound")
        self.assertEqual(insts[-1]["name"], "Event End",
                         "the command region should terminate at Event End")


class PlacementFlipTest(unittest.TestCase):
    """The parser-side ADR-0052/0057 depth mirror on placement Event-Y rows —
    the chirality guard that moved HOME from the runtime (#141). Pure: builds
    synthetic records, no ROM needed."""

    @staticmethod
    def _rec(name: str, y: int, opcode: int = 0x5F) -> dict:
        # Warp Unit layout: opcode + Unit(u16) + X + Y + Z + Facing.
        return {
            "opcode": opcode, "name": name,
            "params": [
                {"name": "Unit", "type": "Unit", "value": 2, "bytes": 2},
                {"name": "X", "type": None, "value": 1, "bytes": 1},
                {"name": "Y", "type": None, "value": y, "bytes": 1},
                {"name": "Z", "type": None, "value": 0, "bytes": 1},
                {"name": "Facing", "type": None, "value": 3, "bytes": 1},
            ],
            "raw": bytes([opcode, 2, 0, 1, y, 0, 3]).hex(),
        }

    def _y(self, rec: dict) -> int:
        return next(p["value"] for p in rec["params"] if p["name"] == "Y")

    def test_flip_mirrors_valid_rows_and_repacks_raw(self):
        recs = [self._rec("Warp Unit", 3), self._rec("Warp Unit", 0),
                self._rec("Warp Unit", 9)]
        ee._flip_placement_rows(recs, 10)
        self.assertEqual(self._y(recs[0]), 6)   # 10-1-3 (Ramza canary)
        self.assertEqual(self._y(recs[1]), 9)   # far edge
        self.assertEqual(self._y(recs[2]), 0)   # near edge
        # raw is re-packed consistently: byte 4 is the Y operand.
        self.assertEqual(bytes.fromhex(recs[0]["raw"])[4], 6)

    def test_flip_is_its_own_inverse(self):
        recs = [self._rec("Warp Unit", 8)]
        ee._flip_placement_rows(recs, 14)
        ee._flip_placement_rows(recs, 14)
        self.assertEqual(self._y(recs[0]), 8)

    def test_out_of_range_rows_left_raw(self):
        # Disassembler over-walk garbage (Y >= size_z) is NOT mirrored to a
        # negative row — it is left byte-for-byte raw (never executed anyway).
        recs = [self._rec("Warp Unit", 200)]
        ee._flip_placement_rows(recs, 10)
        self.assertEqual(self._y(recs[0]), 200)

    def test_non_placement_opcodes_untouched(self):
        recs = [self._rec("Camera", 5, opcode=0x19)]  # not a placement opcode
        ee._flip_placement_rows(recs, 10)
        self.assertEqual(self._y(recs[0]), 5)


@unittest.skipUnless(TEST_EVT.exists(), f"TEST.EVT not present at {TEST_EVT}")
class PlacementFlipRomParityTest(unittest.TestCase):
    """The consumed (flipped) chunk equals the raw chunk with only placement
    Event-Y rows mirrored + header flags set — nothing else drifts."""

    def test_consumed_vs_raw_differs_only_in_placement_rows(self):
        ev = ee.read_event(TEST_EVT, 4)  # scenario 4, MAP056 size_z 14
        raw = ee.to_chunk_json(ev, placement_size_z=None)
        flipped = ee.to_chunk_json(ev, placement_size_z=14)
        self.assertTrue(flipped["_placement_flipped"])
        self.assertFalse(raw["_placement_flipped"])
        for r, f in zip(raw["instructions"], flipped["instructions"]):
            ry = next((p["value"] for p in r["params"] if p["name"] == "Y"), None)
            fy = next((p["value"] for p in f["params"] if p["name"] == "Y"), None)
            if r["name"] in ee._PLACEMENT_DEPTH_OPCODES and ry is not None \
                    and 0 <= ry < 14:
                self.assertEqual(fy, 14 - 1 - ry)
            else:
                self.assertEqual(r, f)  # everything else byte-identical


if __name__ == "__main__":
    unittest.main()
