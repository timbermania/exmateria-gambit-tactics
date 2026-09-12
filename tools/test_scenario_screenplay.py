"""Tests for tools/scenario_screenplay.py.

Two layers:
  - Pure-function: synthetic chunks exercise the string-table walker, the
    Event-End detection, and the ENTD speaker resolver.
  - Real-data sanity: against the scenario 1 capture (cinematic_event_chunk_
    0x8004A6BC.bin) — locks down the first few dialogue lines / speakers /
    string-table offsets that align with the legacy
    `dialogue_pages_decoded.txt` golden.

Run from tools/:
    uv run python -m unittest test_scenario_screenplay
"""

from __future__ import annotations

import unittest
from pathlib import Path

import _fft_bytecode as fb
import scenario_screenplay as ss


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CAPTURES = REPO_ROOT / "research" / "working_documents" / "scenario_1_captures"
EVENT_CHUNK = CAPTURES / "cinematic_event_chunk_0x8004A6BC.bin"


class FindStringTableBaseTest(unittest.TestCase):

    def test_no_event_end_falls_back_to_eof(self) -> None:
        table = fb.load_opcodes(fb.EVENT_CATALOG)
        # 0xF2 No-op × 3, no Event End.
        buf = bytes([0xF2, 0xF2, 0xF2])
        self.assertEqual(ss.find_string_table_base(buf, table), 3)

    def test_event_end_at_offset_zero(self) -> None:
        table = fb.load_opcodes(fb.EVENT_CATALOG)
        # 0xDB Event End is a 1-byte opcode with no params.
        buf = bytes([0xDB, 0xAA, 0xBB])
        self.assertEqual(ss.find_string_table_base(buf, table), 1)


class WalkStringsTest(unittest.TestCase):

    def test_two_terminated_strings(self) -> None:
        # Charmap: 0x0A = 'A', 0x0B = 'B', 0xFE = soft-end, 0xFF = close.
        # → strings: "A", "BB"
        buf = bytes([0x0A, 0xFE, 0x0B, 0x0B, 0xFF, 0x00])
        out = ss.walk_strings(buf, 0)
        self.assertEqual([(0, "A"), (2, "BB")], out)

    def test_unterminated_string_stops_walk(self) -> None:
        buf = bytes([0x0A, 0xFE, 0x0B, 0x0B])    # second string has no terminator
        out = ss.walk_strings(buf, 0)
        self.assertEqual([(0, "A")], out)


class StringTableLookupTest(unittest.TestCase):

    def test_one_based_lookup(self) -> None:
        st = ss.StringTable(base=0x100, entries=[(0x100, "a"), (0x102, "b")])
        self.assertEqual(st.get(1), (0x100, "a"))
        self.assertEqual(st.get(2), (0x102, "b"))
        self.assertIsNone(st.get(0))           # 0 = "no message"
        self.assertIsNone(st.get(3))           # past end


class LoadNameMapTest(unittest.TestCase):

    def test_unit_names_have_ovelia(self) -> None:
        m = ss.load_name_map(ss.DEFAULT_UNIT_NAMES)
        self.assertEqual(m.get(0x0C), "Ovelia")
        self.assertEqual(m.get(0x13), "Simon")

    def test_sprite_names_have_priest(self) -> None:
        # Per the screenplay golden, sprite 0x80 → "Priest".
        m = ss.load_name_map(ss.DEFAULT_SPRITE_NAMES)
        self.assertIn(0x80, m)


class ResolveSpeakerTest(unittest.TestCase):

    def _slots(self) -> list[dict]:
        # Two used slots + one 0xFF padding slot.
        return [
            {"sprite_set": 0x0C, "unit_id": 0x0C, "special_name": 0x0C},
            {"sprite_set": 0x13, "unit_id": 0x13, "special_name": 0x13},
            {"sprite_set": 0x00, "unit_id": 0xFF, "special_name": 0xFF},
        ]

    def test_low_byte_matches_unit_id(self) -> None:
        sprite = {0x0C: "Ovelia"}
        unit = {0x0C: "Ovelia"}
        # u16 0x010C — low byte 0x0C → slot 0.
        info = ss.resolve_speaker(0x010C, self._slots(), sprite, unit)
        self.assertEqual(info.slot_index, 0)
        self.assertEqual(info.sprite_name, "Ovelia")
        self.assertEqual(info.display, "Ovelia")

    def test_no_match_falls_back_to_unit_names(self) -> None:
        sprite: dict = {}
        unit = {0x83: "Knight"}
        info = ss.resolve_speaker(0x0083, self._slots(), sprite, unit)
        self.assertIsNone(info.slot_index)
        self.assertEqual(info.unit_name, "Knight")
        self.assertEqual(info.display, "Knight")


@unittest.skipUnless(EVENT_CHUNK.exists(), f"capture missing: {EVENT_CHUNK}")
class Scenario1RealCaptureTest(unittest.TestCase):
    """Lock down the screenplay's behaviour against scenario 1's capture."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.buf = EVENT_CHUNK.read_bytes()
        cls.table = fb.load_opcodes(fb.EVENT_CATALOG)
        cls.str_base = ss.find_string_table_base(cls.buf, cls.table)
        cls.strings = ss.StringTable(
            base=cls.str_base,
            entries=ss.walk_strings(cls.buf, cls.str_base),
        )

    def test_string_table_starts_after_event_end(self) -> None:
        # Per the SCENARIO_LOADING.md disasm (§3.2.2), 0xDB Event End sits
        # at chunk offset 0x8F8; strings start at 0x8F9.
        self.assertEqual(self.str_base, 0x8F9)

    def test_first_string_is_ovelia_prayer(self) -> None:
        off, text = self.strings.entries[0]
        self.assertEqual(off, 0x8F9)
        self.assertIn("please help us", text)
        self.assertIn("sinful children of Ivalice", text)

    def test_second_string_is_lets_go(self) -> None:
        # Display Message at offset 0x14F has message=2; the second entry
        # in the chunk's string table reads "Princess Ovelia, let's go."
        # (with the Female-Knight speaker label baked in via {Color 08}).
        _off, text = self.strings.entries[1]
        self.assertIn("Princess Ovelia, let's go.", text)

    def test_first_display_message_resolves_to_ovelia(self) -> None:
        scenario = ss.load_scenario_record(ss.DEFAULT_SCENARIOS, 1)
        entd = ss.load_entd_record(ss.DEFAULT_ENTD, scenario["entd_idx"])
        sprite_names = ss.load_name_map(ss.DEFAULT_SPRITE_NAMES)
        unit_names = ss.load_name_map(ss.DEFAULT_UNIT_NAMES)

        insts = fb.disasm(self.buf, self.table, chunk_base=0x8004A6BC)
        # First Display Message in scenario 1's chunk sits at offset 0x100;
        # has Message=1 (Ovelia's prayer) and Unit=0x0C (Ovelia).
        display = [i for i in insts if i.opcode == ss.DISPLAY_MESSAGE_OPCODE]
        first = display[0]
        self.assertEqual(first.offset, 0x100)
        msg_id = ss._inst_param(first, "Message")
        unit_param = ss._inst_param(first, "Unit")
        self.assertEqual(msg_id, 1)
        self.assertEqual(unit_param & 0xFF, 0x0C)
        speaker = ss.resolve_speaker(
            unit_param, entd["slots"], sprite_names, unit_names,
        )
        self.assertEqual(speaker.slot_index, 0)
        self.assertEqual(speaker.unit_id, 0x0C)
        self.assertEqual(speaker.unit_name, "Ovelia")
        # Strings #1 is the prayer line.
        line = self.strings.get(msg_id)[1]
        self.assertIn("please help us", line)

    def test_render_markdown_includes_dialogue_speakers(self) -> None:
        scenario = ss.load_scenario_record(ss.DEFAULT_SCENARIOS, 1)
        entd = ss.load_entd_record(ss.DEFAULT_ENTD, scenario["entd_idx"])
        sprite_names = ss.load_name_map(ss.DEFAULT_SPRITE_NAMES)
        unit_names = ss.load_name_map(ss.DEFAULT_UNIT_NAMES)
        insts = fb.disasm(self.buf, self.table, chunk_base=0x8004A6BC)
        md = ss.render_markdown(
            insts, self.table, self.strings, entd["slots"],
            sprite_names, unit_names, scenario,
        )
        # Smoke checks: scenario header + at least one speaker + Event End sentinel.
        self.assertIn("Orbonne Prayer", md)
        self.assertIn("Ovelia", md)
        self.assertIn("Event End", md)
        # The first message's text should make it into the rendered output.
        self.assertIn("please help us", md)


if __name__ == "__main__":
    unittest.main()
