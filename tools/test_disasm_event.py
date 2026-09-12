"""Tests for tools/disasm_event.py + tools/disasm_bc.py.

The two disassemblers share `_fft_bytecode.py`; the tests exercise the
shared engine in both opcode widths (1-byte event scripts, 2-byte
BattleConditionals) plus the per-CLI auto-detect logic.

Real-data sanity: the captured scenario-1 event chunk (1-byte opcodes)
starts with four `0xF2 No-op` slots before any meaningful instruction;
BattleConditionals[1] starts with `0x0001 Variable =`.

Uses stdlib unittest. Run from tools/:
    uv run python -m unittest test_disasm_event
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import _fft_bytecode as fb
import disasm_event
import disasm_bc
import extract_event


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CAPTURES = REPO_ROOT / "research" / "working_documents" / "scenario_1_captures"
EVENT_CHUNK = CAPTURES / "cinematic_event_chunk_0x8004A6BC.bin"
BC_CHUNK = CAPTURES / "battle_conditionals_1_ram_0x80049A18.bin"


class LoadOpcodesTest(unittest.TestCase):

    def test_event_catalog_loads(self) -> None:
        t = fb.load_opcodes(fb.EVENT_CATALOG)
        self.assertEqual(t.opcode_width, 1)
        # 0xF2 = No-op (no params) and 0x5F = Warp Unit (5 params).
        self.assertEqual(t.by_hex[0xF2].name, "No-op")
        self.assertEqual(t.by_hex[0xF2].params, [])
        warp = t.by_hex[0x5F]
        self.assertEqual(warp.name, "Warp Unit")
        self.assertEqual([p.name for p in warp.params],
                         ["Unit", "X", "Y", "Z", "Facing"])

    def test_bc_catalog_loads(self) -> None:
        t = fb.load_opcodes(fb.BC_CATALOG)
        self.assertEqual(t.opcode_width, 2)
        # 0x0019 Run Scenario takes one 2-byte parameter.
        run = t.by_hex[0x0019]
        self.assertEqual(run.name, "Run Scenario")
        self.assertEqual(run.body_bytes, 2)


class DetectChunkBaseTest(unittest.TestCase):

    def test_filename_with_ram_addr_suffix(self) -> None:
        self.assertEqual(
            fb.detect_chunk_base(Path("event_chunk_0x8004A6BC.bin")),
            0x8004A6BC,
        )
        self.assertEqual(
            fb.detect_chunk_base(Path("bc_1_ram_0x80049A18.bin")),
            0x80049A18,
        )

    def test_filename_without_suffix_returns_none(self) -> None:
        self.assertIsNone(fb.detect_chunk_base(Path("whatever.bin")))


class DisasmEngineTest(unittest.TestCase):
    """Synthetic byte-level coverage of the shared disasm engine."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.t_event = fb.load_opcodes(fb.EVENT_CATALOG)
        cls.t_bc = fb.load_opcodes(fb.BC_CATALOG)

    def test_one_byte_op_with_params(self) -> None:
        # 0x5F Warp Unit + 6 param bytes (Unit u16, X u8, Y u8, Z u8, Facing u8).
        buf = bytes([0x5F, 0x02, 0x00, 0x01, 0x03, 0x00, 0x03])
        out = fb.disasm(buf, self.t_event, chunk_base=0x80000000)
        self.assertEqual(len(out), 1)
        inst = out[0]
        self.assertEqual(inst.name, "Warp Unit")
        self.assertEqual(inst.ram_addr, 0x80000000)
        self.assertEqual([p["name"] for p in inst.params],
                         ["Unit", "X", "Y", "Z", "Facing"])
        self.assertEqual(inst.params[0]["value"], 0x0002)
        self.assertEqual(inst.params[4]["value"], 0x03)

    def test_unknown_opcode_marked(self) -> None:
        # 0xC2 is not in the event opcode catalog at the time of writing.
        if 0xC2 in self.t_event.by_hex:
            self.skipTest("opcode 0xC2 is mapped now; pick a different unknown")
        out = fb.disasm(bytes([0xC2]), self.t_event)
        self.assertEqual(len(out), 1)
        self.assertTrue(out[0].unknown)
        self.assertEqual(out[0].opcode, 0xC2)

    def test_truncated_at_end(self) -> None:
        # 0x5F Warp Unit needs 6 trailing bytes; supply only 2 → truncated.
        out = fb.disasm(bytes([0x5F, 0x01, 0x00]), self.t_event)
        self.assertEqual(len(out), 1)
        self.assertTrue(out[0].unknown)
        self.assertEqual(out[0].name, "Warp Unit")  # name still known
        self.assertEqual(out[0].params, [])

    def test_stop_at_event_end(self) -> None:
        # No-op, Event End (0xDB), then trailing bytes that WOULD keep walking
        # (0x00 is unmapped → unknown 1-byte stubs). `stop_opcode=0xDB` must
        # emit the Event End as the LAST instruction and walk no further —
        # matching the runtime (parser.lua / ScenarioVM both stop at 0xDB).
        buf = bytes([0xF2, 0xDB, 0x00, 0x00, 0x00, 0x00])
        out = fb.disasm(buf, self.t_event, stop_opcode=0xDB)
        self.assertEqual([i.name for i in out], ["No-op", "Event End"])

    def test_no_stop_opcode_walks_past_event_end(self) -> None:
        # Default (no stop_opcode): unchanged behaviour — the walk runs to EOF
        # and treats the trailing 0x00 bytes as unknown stubs.
        buf = bytes([0xF2, 0xDB, 0x00, 0x00, 0x00, 0x00])
        out = fb.disasm(buf, self.t_event)
        self.assertGreater(len(out), 2)
        self.assertEqual(out[1].name, "Event End")
        self.assertTrue(out[2].unknown)

    def test_two_byte_bc_op(self) -> None:
        # 0x0019 Run Scenario + 2 param bytes (Scenario u16).
        buf = bytes([0x19, 0x00, 0x04, 0x00])
        out = fb.disasm(buf, self.t_bc, chunk_base=0x80049A18)
        self.assertEqual(len(out), 1)
        inst = out[0]
        self.assertEqual(inst.opcode, 0x0019)
        self.assertEqual(inst.name, "Run Scenario")
        self.assertEqual(inst.params[0]["value"], 0x0004)
        self.assertEqual(inst.ram_addr, 0x80049A18)

    def test_format_human_includes_addr_and_params(self) -> None:
        buf = bytes([0x5F, 0x01, 0x00, 0x02, 0x03, 0x04, 0x01])
        out = fb.disasm(buf, self.t_event, chunk_base=0x8004A6BC)
        line = fb.format_human(out[0], self.t_event.opcode_width)
        self.assertIn("0x5F Warp Unit", line)
        self.assertIn("0x8004a6bc", line)
        self.assertIn("Unit=0x1", line)

    def test_format_json_round_trip(self) -> None:
        buf = bytes([0xF2, 0xF2, 0x5F, 0x01, 0x00, 0x02, 0x03, 0x04, 0x01])
        out = fb.disasm(buf, self.t_event)
        records = [fb.format_json(i) for i in out]
        # Round-trip through JSON to confirm all values are JSON-safe.
        as_json = json.loads(json.dumps(records))
        self.assertEqual(as_json[0]["name"], "No-op")
        self.assertEqual(as_json[2]["name"], "Warp Unit")
        self.assertEqual(as_json[2]["params"][0]["name"], "Unit")


class StubEventOverWalkTest(unittest.TestCase):
    """Regression for the "read past Event End" export bug: a SETUP STUB event
    has NO text section (text_offset == BLANK sentinel), so the command walk was
    unbounded to the end of the 8192-byte slot, emitting thousands of unknown
    stubs from the zero padding. to_chunk_json must stop at the first Event End
    (0xDB), matching parser.lua / ScenarioVM."""

    def _stub_event(self) -> extract_event.Event:
        # A minimal stub: four-No-op RAM header then an immediate Event End,
        # with the rest of the slot zero-padded (0x00 = unmapped opcode).
        raw = bytearray(extract_event.EVENT_SIZE)
        raw[0:4] = extract_event.BLANK_TEXT_OFFSET.to_bytes(4, "little")
        raw[4] = 0xDB  # Event End immediately after the painted-over header
        return extract_event.Event(
            index=7,
            text_offset=extract_event.BLANK_TEXT_OFFSET,
            command_bytes=bytes(raw[4:]),
            raw_bytes=bytes(raw),
        )

    def test_to_chunk_json_stops_at_event_end(self) -> None:
        doc = extract_event.to_chunk_json(self._stub_event())
        names = [i["name"] for i in doc["instructions"]]
        self.assertEqual(names, ["No-op"] * 4 + ["Event End"])


class RealCaptureTest(unittest.TestCase):

    def test_event_chunk_starts_with_four_noops(self) -> None:
        if not EVENT_CHUNK.exists():
            self.skipTest(f"capture missing: {EVENT_CHUNK}")
        table = fb.load_opcodes(fb.EVENT_CATALOG)
        insts = fb.disasm(EVENT_CHUNK.read_bytes(), table,
                          chunk_base=0x8004A6BC, end=4)
        self.assertEqual([i.name for i in insts], ["No-op"] * 4)
        self.assertEqual(insts[0].ram_addr, 0x8004A6BC)

    def test_bc_chunk_starts_with_variable_eq(self) -> None:
        if not BC_CHUNK.exists():
            self.skipTest(f"capture missing: {BC_CHUNK}")
        table = fb.load_opcodes(fb.BC_CATALOG)
        insts = fb.disasm(BC_CHUNK.read_bytes(), table,
                          chunk_base=0x80049A18, end=10)
        self.assertEqual(insts[0].name, "Variable =")
        self.assertEqual(insts[1].name, "Run Scenario")
        # Run Scenario's payload here selects scenario 4 (verified live).
        self.assertEqual(insts[1].params[0]["value"], 0x0004)


if __name__ == "__main__":
    unittest.main()
