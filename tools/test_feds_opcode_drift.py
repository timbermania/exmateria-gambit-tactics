"""Cross-language drift guard: `parse_effect._FEDS_OPCODE_INFO` must agree with
the runtime decoder's opcode tables in
`addons/exmateria_sound/runtime/sound_opcodes.gd` (OPCODE_INFO names + param
counts, plus the `_EXTRA_OPCODES` param-count-only entries).

The runtime table is the one decoder that PLAYS feds.bin (ADR-0085 amendment
2026-08-11): a param-count disagreement makes the Python extractor's feds.json
desync mid-track and decode garbage (proof: E004 track 2, a noise-sweep whoosh
that read as chromatic notes under the stale table). This guard regex-parses
the GDScript source, so the expected values come from the runtime file itself —
never from the Python table under test.

Run from tools/:
    python3 -m unittest test_feds_opcode_drift
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

import parse_effect as pe

_SMD_OPCODES_GD = (
    Path(__file__).resolve().parent.parent
    / "addons" / "exmateria_sound" / "runtime" / "sound_opcodes.gd"
)


def _extract_block(source: str, header: str) -> str:
    """Return the brace-delimited body of a `const NAME := {` block."""
    start = source.index(header)
    end = source.index("\n}", start)
    return source[start:end]


def _parse_runtime_tables() -> tuple[dict, dict]:
    """Parse sound_opcodes.gd into (opcode_info, extra_opcodes).

    opcode_info: {opcode: (name, param_count)}; extra_opcodes: {opcode: count}.
    """
    source = _SMD_OPCODES_GD.read_text()
    info_block = _extract_block(source, "const OPCODE_INFO := {")
    extra_block = _extract_block(source, "const _EXTRA_OPCODES := {")

    opcode_info = {}
    for m in re.finditer(r'0x([0-9A-Fa-f]{2}):\s*\["(\w+)",\s*(\d+)\]', info_block):
        opcode_info[int(m.group(1), 16)] = (m.group(2), int(m.group(3)))

    extra_opcodes = {}
    for m in re.finditer(r"0x([0-9A-Fa-f]{2}):\s*(\d+)", extra_block):
        extra_opcodes[int(m.group(1), 16)] = int(m.group(2))

    return opcode_info, extra_opcodes


class RuntimeTableParseSanity(unittest.TestCase):
    """Guard the regex itself against source-format rot: spot-check entries
    known independently from the GDScript source."""

    @classmethod
    def setUpClass(cls):
        cls.info, cls.extra = _parse_runtime_tables()

    def test_opcode_info_spot_checks(self):
        self.assertEqual(self.info[0x90], ("EndBar", 0))
        self.assertEqual(self.info[0xB4], ("Noise_EnableAndClock", 1))
        self.assertEqual(self.info[0xC4], ("ADSR_SustainRate", 1))
        self.assertEqual(self.info[0xF0], ("LFO_SubSlot_Select_Init", 3))

    def test_extra_opcodes_spot_checks(self):
        self.assertEqual(self.extra[0x8A], 0)
        self.assertEqual(self.extra[0xB8], 3)
        self.assertEqual(self.extra[0xFF], 0)

    def test_parse_found_full_tables(self):
        # sound_opcodes.gd currently defines 74 named + 29 extra opcodes; a
        # collapsed parse (regex rot) would show far fewer.
        self.assertGreaterEqual(len(self.info), 70)
        self.assertGreaterEqual(len(self.extra), 25)


class FedsOpcodeTableDrift(unittest.TestCase):
    """The actual drift guard: Python table == runtime table."""

    @classmethod
    def setUpClass(cls):
        cls.info, cls.extra = _parse_runtime_tables()

    def test_named_opcodes_match_runtime(self):
        """Every OPCODE_INFO entry appears in the Python table with the same
        name and param count."""
        mismatches = []
        for op, (name, count) in sorted(self.info.items()):
            got = pe._FEDS_OPCODE_INFO.get(op)
            if got != (name, count):
                mismatches.append("0x%02X: runtime (%s, %d) != python %s"
                                  % (op, name, count, got))
        self.assertEqual(mismatches, [])

    def test_extra_opcodes_match_runtime(self):
        """Every _EXTRA_OPCODES entry appears with the right param count and
        the Unknown_XX naming convention (the runtime has no names for them)."""
        mismatches = []
        for op, count in sorted(self.extra.items()):
            got = pe._FEDS_OPCODE_INFO.get(op)
            expected = ("Unknown_%02X" % op, count)
            if got != expected:
                mismatches.append("0x%02X: runtime %s != python %s"
                                  % (op, expected, got))
        self.assertEqual(mismatches, [])

    def test_no_python_only_opcodes(self):
        """The Python table carries nothing the runtime doesn't know —
        a python-only entry is drift in the other direction."""
        known = set(self.info) | set(self.extra)
        extras = sorted(set(pe._FEDS_OPCODE_INFO) - known)
        self.assertEqual(["0x%02X" % op for op in extras], [])


class E004NoiseSweepDecode(unittest.TestCase):
    """Regression for the concrete desync: E004 track 2 (offset 127) is a
    noise-sweep whoosh. Expected sequence hand-decoded from the raw bytes
    `b4 3f c2 32 e0 23 e2 78 00 60 0c 98 0e b5 3e 81 06 ba 99 b7 ac 0f
    94 04 c4 35 60 04 90` using the RUNTIME table (independent of the code
    under test). The stale table read 0xB4 as 0-param and fell into
    chromatic-note garbage from byte 1."""

    _FEDS_BIN = Path(__file__).resolve().parent.parent / "assets" / "effects" / "E004" / "feds.bin"

    def test_track2_event_sequence(self):
        if not self._FEDS_BIN.exists():
            self.skipTest("E004 assets not extracted (local-only ROM data)")
        feds = self._FEDS_BIN.read_bytes()
        events = pe._decode_feds_track(feds[127:156])
        got = [(e["type"], e.get("value", e.get("params"))) for e in events]
        self.assertEqual(got, [
            ("Noise_EnableAndClock", 0x3F),
            ("ADSR_Attack", 0x32),
            ("Dynamics", 0x23),
            ("Expression_VolBurst", [0x78, 0x00]),
            ("Note", None),               # vel 96, C, dur 12
            ("Repeat", 0x0E),
            ("Noise_ClockAdd", 0x3E),
            ("Fermata", 0x06),
            ("ReverbOn", None),
            ("Coda", None),
            ("Noise_Disable", None),
            ("Instrument", 0x0F),
            ("Octave", 0x04),
            ("ADSR_SustainRate", 0x35),
            ("Note", None),               # vel 96, C, dur 72
            ("EndBar", None),
        ])
        notes = [e for e in events if e["type"] == "Note"]
        self.assertEqual([(n["velocity"], n["note"], n["duration"]) for n in notes],
                         [(96, "C", 12), (96, "C", 72)])


if __name__ == "__main__":
    unittest.main()
