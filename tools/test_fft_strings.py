"""Tests for tools/_fft_strings.py — tokenizer + string-table walker."""

from __future__ import annotations

import unittest

import _fft_strings as fs


class TokenizeBasicTest(unittest.TestCase):

    def test_pure_text(self) -> None:
        self.assertEqual(
            fs.tokenize("hello world"),
            [{"type": "text", "value": "hello world"}],
        )

    def test_delay_then_text(self) -> None:
        self.assertEqual(
            fs.tokenize("{Delay 05}hi"),
            [
                {"type": "delay", "frames": 0x05},
                {"type": "text", "value": "hi"},
            ],
        )

    def test_text_then_delay_then_text(self) -> None:
        self.assertEqual(
            fs.tokenize("a{Delay 0F}b"),
            [
                {"type": "text", "value": "a"},
                {"type": "delay", "frames": 0x0F},
                {"type": "text", "value": "b"},
            ],
        )

    def test_color_and_newline(self) -> None:
        out = fs.tokenize("{Color 08}A{Newline}{Color 00}b")
        self.assertEqual(out, [
            {"type": "color", "palette": 0x08},
            {"type": "text", "value": "A"},
            {"type": "newline"},
            {"type": "color", "palette": 0x00},
            {"type": "text", "value": "b"},
        ])

    def test_macro_passes_through(self) -> None:
        out = fs.tokenize("Hello {Ramza}!")
        self.assertEqual(out, [
            {"type": "text", "value": "Hello "},
            {"type": "macro", "name": "Ramza"},
            {"type": "text", "value": "!"},
        ])

    def test_unknown_marker_kept_as_text(self) -> None:
        # Pure literal that doesn't match {Word [HH]} stays as-is so the
        # caller sees the raw decoder output.
        self.assertEqual(
            fs.tokenize("foo<E2>bar"),
            [{"type": "text", "value": "foo<E2>bar"}],
        )


class TokenizeOrbonnePrayerTest(unittest.TestCase):
    """Lock down the scenario-1 PC=42 prayer string's tokenization."""

    PRAYER = (
        '{Delay 05}"God,{Delay 0F} {Delay 05}please help us'
        "{Newline}sinful children of Ivalice{Delay 3C}.{Delay 01}"
    )

    def test_token_sequence(self) -> None:
        self.assertEqual(fs.tokenize(self.PRAYER), [
            {"type": "delay",   "frames": 0x05},
            {"type": "text",    "value": '"God,'},
            {"type": "delay",   "frames": 0x0F},
            {"type": "text",    "value": " "},
            {"type": "delay",   "frames": 0x05},
            {"type": "text",    "value": "please help us"},
            {"type": "newline"},
            {"type": "text",    "value": "sinful children of Ivalice"},
            {"type": "delay",   "frames": 0x3C},
            {"type": "text",    "value": "."},
            {"type": "delay",   "frames": 0x01},
        ])


if __name__ == "__main__":
    unittest.main()
