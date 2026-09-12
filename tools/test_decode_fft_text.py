"""Tests for tools/decode_fft_text.py.

Two layers:
  - Pure-function tests: hand-encoded byte sequences round-trip through
    the FFTPatcher PSX charmap into the expected ASCII text.
  - Real-data sanity test: a known dialogue line ("Princess Ovelia,
    let's go.") sits inside the captured scenario 1 chunk at a known
    offset; decoding from that offset must produce that exact line.

Uses stdlib unittest. Run from tools/:
    uv run python -m unittest test_decode_fft_text
"""

from __future__ import annotations

import unittest
from pathlib import Path

import decode_fft_text as d


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCENARIO_CHUNK = (
    REPO_ROOT / "research" / "working_documents" / "scenario_1_captures"
    / "cinematic_event_chunk_0x8004A6BC.bin"
)


class CharmapLoadTest(unittest.TestCase):
    """Lock the baked charmap to the FFTPatcher behaviour we depend on."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.cm = d.load_charmap()

    def test_ascii_letters_present(self) -> None:
        # V3 baseline: 0x0A..0x23 = A..Z, 0x24..0x3D = a..z, 0..9 = '0'..'9'.
        self.assertEqual(self.cm[0x18], "O")
        self.assertEqual(self.cm[0x24], "a")
        self.assertEqual(self.cm[0x32], "o")
        self.assertEqual(self.cm[0x00], "0")
        self.assertEqual(self.cm[0x09], "9")

    def test_common_punctuation_overrides(self) -> None:
        # V1 overrides that appear in dialogue.
        self.assertEqual(self.cm[0xFA], " ")
        self.assertEqual(self.cm[0xD9C1], "'")
        self.assertEqual(self.cm[0xDA74], ",")
        self.assertEqual(self.cm[0xD9B6], ".")
        self.assertEqual(self.cm[0xD11A], "!")

    def test_marker_strings(self) -> None:
        self.assertEqual(self.cm[0xF8], "{Newline}")
        self.assertEqual(self.cm[0xE0], "{Ramza}")
        self.assertEqual(self.cm[0xE300], "{Color 00}")
        self.assertEqual(self.cm[0xE308], "{Color 08}")
        self.assertEqual(self.cm[0xE205], "{Delay 05}")


class DecodeStringTest(unittest.TestCase):

    def test_simple_ascii(self) -> None:
        # 'a' 'b' 'c' (terminator 0xFE)
        s, new_pos, term = d.decode_string(bytes([0x24, 0x25, 0x26, 0xFE]))
        self.assertEqual(s, "abc")
        self.assertEqual(new_pos, 4)
        self.assertTrue(term)

    def test_two_byte_sequence(self) -> None:
        # 'l' 'e' 't' (D9C1='\'') 's' → "let's"
        s, _, _ = d.decode_string(bytes([0x2F, 0x28, 0x37, 0xD9, 0xC1, 0x36, 0xFE]))
        self.assertEqual(s, "let's")

    def test_unknown_falls_back_to_brackets(self) -> None:
        # 0xE1 is not in TWO_BYTE_PREFIXES and not in the charmap → <E1>.
        s, _, _ = d.decode_string(bytes([0xE1, 0xFE]))
        self.assertIn("<E1>", s)

    def test_terminator_ends_string(self) -> None:
        # Decode should stop at 0xFE and not consume the byte after.
        s, new_pos, term = d.decode_string(bytes([0x10, 0x11, 0xFE, 0x12]))
        self.assertEqual(s, "GH")
        self.assertEqual(new_pos, 3)
        self.assertTrue(term)

    def test_unterminated_returns_at_end(self) -> None:
        s, new_pos, term = d.decode_string(bytes([0x10, 0x11]))
        self.assertEqual(s, "GH")
        self.assertEqual(new_pos, 2)
        self.assertFalse(term)


class DecodeBytesTest(unittest.TestCase):

    def test_multiple_strings_joined_with_page_sep(self) -> None:
        # Two strings, terminator 0xFE between, terminator at end too.
        buf = bytes([0x10, 0xFE, 0x11, 0xFE])
        out = d.decode_bytes(buf)
        self.assertEqual(out, "G--page-end--\nH--page-end--\n")

    def test_newline_replaced_inline(self) -> None:
        # 'A' 0xF8 'B' 0xFE → A{NP}\nB
        out = d.decode_bytes(bytes([0x0A, 0xF8, 0x0B, 0xFE]))
        self.assertEqual(out, "A{NP}\nB--page-end--\n")


class RealCaptureTest(unittest.TestCase):
    """Decode a real captured scenario chunk: the first dialogue line at
    offset 0x944 in the scenario-1 cinematic chunk is "Princess Ovelia,
    let's go." (bytes verified live during the 2026-06-20 RE session)."""

    @classmethod
    def setUpClass(cls) -> None:
        if not SCENARIO_CHUNK.exists():
            raise unittest.SkipTest(f"capture missing: {SCENARIO_CHUNK}")
        cls.data = SCENARIO_CHUNK.read_bytes()

    def test_princess_ovelia_line(self) -> None:
        # The line "Princess Ovelia, let's go." starts after the speaker
        # marker `0xE3 0x00` at offset 0x949 (verified in the capture).
        text, _, _ = d.decode_string(self.data, pos=0x949)
        self.assertTrue(
            text.startswith("Princess Ovelia, let's go."),
            f"unexpected leading text: {text[:60]!r}",
        )

    def test_decode_bytes_yields_known_speaker(self) -> None:
        # Range that covers the first two dialogue strings. Both have
        # the `{Color 08}<speaker>{NP}\n{Color 00}<line>` pattern.
        text = d.decode_bytes(self.data, pos=0x946, end=0x9C0)
        # Body of line 1.
        self.assertIn("Princess Ovelia, let's go.", text)
        # Speaker tag for line 2.
        self.assertIn("{Color 08}Princess Ovelia{NP}", text)


if __name__ == "__main__":
    unittest.main()
