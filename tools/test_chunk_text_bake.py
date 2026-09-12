"""Regression test for ``disasm_event.py --with-text`` against the
committed ``assets/scenarios/scenario_1_chunk.json``.

Locks down the structure that ``ScenarioVM`` and ``DialogueOverlay``
consume so a future schema drift fails this test loudly instead of
silently breaking the prayer overlay."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


CHUNK_JSON = (
    Path(__file__).resolve().parent.parent
    / "assets" / "scenarios" / "scenario_1_chunk.json"
)
DISPLAY_MESSAGE_OPCODE = 0x10
PRAYER_FRAGMENT = "please help us"


@unittest.skipUnless(CHUNK_JSON.exists(), f"chunk JSON missing: {CHUNK_JSON}")
class ChunkTextBakeTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls) -> None:
        cls.chunk = json.loads(CHUNK_JSON.read_text())
        cls.insts = cls.chunk["instructions"]

    def test_string_table_metadata_present(self) -> None:
        st = self.chunk["_string_table"]
        # 0xDB Event End sits at chunk offset 0x8F8; strings start at 0x8F9.
        self.assertEqual(st["base"], 0x8F9)
        self.assertGreater(st["count"], 1)

    def test_pc_42_is_the_orbonne_prayer(self) -> None:
        # "Instruction index" 42 in the chunk → the chapel prayer
        # (Dialog=0x09, Message=0x01, Unit=0x0C, Y=0x3C, Open Type=0).
        inst = self.insts[42]
        self.assertEqual(inst["opcode"], DISPLAY_MESSAGE_OPCODE)
        self.assertEqual(inst["name"], "Display Message")
        self.assertFalse(inst["unknown"])

        dialogue = inst.get("dialogue")
        self.assertIsNotNone(dialogue, "--with-text should bake the prayer in")
        self.assertEqual(dialogue["message_id"], 1)
        self.assertEqual(dialogue["speaker_unit_byte"], 0x0C)        # Ovelia
        self.assertIn(PRAYER_FRAGMENT, dialogue["raw_text"])

    def test_pc_42_tokens_have_at_least_four_delays(self) -> None:
        tokens = self.insts[42]["dialogue"]["tokens"]
        delay_count = sum(1 for t in tokens if t["type"] == "delay")
        self.assertGreaterEqual(delay_count, 4,
                                f"expected ≥4 {{Delay}} tokens, got {delay_count}")

    def test_pc_42_tokens_have_a_newline(self) -> None:
        tokens = self.insts[42]["dialogue"]["tokens"]
        self.assertTrue(any(t["type"] == "newline" for t in tokens),
                        "prayer string has a {Newline} between body lines")

    def test_pc_42_text_token_content(self) -> None:
        # Concatenated text-token bodies must contain the load-bearing
        # phrases of the prayer.
        tokens = self.insts[42]["dialogue"]["tokens"]
        body = "".join(t["value"] for t in tokens if t["type"] == "text")
        self.assertIn("please help us", body)
        self.assertIn("sinful children of Ivalice", body)


if __name__ == "__main__":
    unittest.main()
