"""Guard for the generated feds_instrument_meta.json (ADR-0085 amendment: the
instrument-chip loop verdict). Two layers:

  * parse_waveset() logic — tested against a hand-built synthetic `dwds` blob with
    KNOWN ADPCM block flags (independent oracle, ROM-free).
  * the committed table — a pinned ROM-free oracle (id 67 sustains, id 1 silent),
    plus a full re-parse of WAVESET.WD when the ROM is present (skips otherwise).

Run from `tools/`:  uv run python -m unittest test_feds_instrument_meta_drift
"""
import json
import unittest

import generate_feds_instrument_meta as gen


def _block(flags: int) -> bytes:
    # One 16-byte ADPCM block: header byte, flags byte, 14 data bytes.
    return bytes([0x00, flags]) + bytes(14)


def _synthetic_waveset() -> bytes:
    # 4 entries → data_offset = 0x20 + 4*16 = 0x60. ADPCM follows.
    #   idx0 (opcode -1, dropped): null
    #   idx1 (opcode 0): 2 blocks, one-shot   (block1 = LOOP_END only)
    #   idx2 (opcode 1): 3 blocks, sustain     (block1 = LOOP_START @16, block2 = END|REPEAT)
    #   idx3 (opcode 2): null
    data_offset = 0x60
    header = bytearray(b"dwds") + bytes(0x0C)
    header += data_offset.to_bytes(4, "little")  # 0x10
    header += bytes(0x20 - len(header))           # pad to 0x20

    def entry(sample_offset: int, sample_size: int) -> bytes:
        return (sample_offset.to_bytes(4, "little")
                + sample_size.to_bytes(2, "little")
                + bytes(10))

    entries = (entry(0, 0)        # idx0 null
               + entry(0, 32)     # idx1 one-shot, adpcm at data_offset+0
               + entry(32, 48)    # idx2 sustain,   adpcm at data_offset+32
               + entry(0, 0))     # idx3 null

    adpcm = _block(0x00) + _block(gen.FLAG_LOOP_END)                      # idx1
    adpcm += _block(0x00) + _block(gen.FLAG_LOOP_START) + _block(0x03)    # idx2
    return bytes(header) + entries + adpcm


class TestParseWaveset(unittest.TestCase):
    def setUp(self):
        self.meta = gen.parse_waveset(_synthetic_waveset())

    def test_opcode_ids_are_waveset_index_minus_one(self):
        # 4 entries → opcode ids 0,1,2 (waveset[0] has no opcode and is dropped).
        self.assertEqual(sorted(self.meta.keys()), [0, 1, 2])
        self.assertNotIn(-1, self.meta)

    def test_one_shot_sample_reads_no_loop(self):
        m = self.meta[0]
        self.assertFalse(m["has_loop_repeat"])
        self.assertFalse(m["has_explicit_loop_start"])
        self.assertEqual(m["loop_offset_bytes"], -1)
        self.assertEqual(m["sample_size"], 32)
        self.assertFalse(m["is_null"])

    def test_sustaining_sample_reads_loop_with_explicit_start(self):
        m = self.meta[1]
        self.assertTrue(m["has_loop_repeat"])
        self.assertTrue(m["has_explicit_loop_start"])
        self.assertEqual(m["loop_offset_bytes"], 16)  # block 1 within the sample
        self.assertEqual(m["sample_size"], 48)

    def test_null_entry_is_flagged(self):
        self.assertTrue(self.meta[2]["is_null"])
        self.assertEqual(self.meta[2]["sample_size"], 0)

    def test_non_waveset_blob_is_empty(self):
        self.assertEqual(gen.parse_waveset(b"nope" + bytes(64)), {})


class TestCommittedTable(unittest.TestCase):
    def _committed(self) -> dict:
        if not gen.TARGET.exists():
            self.skipTest("feds_instrument_meta.json not generated yet")
        doc = json.loads(gen.TARGET.read_text())
        return doc["meta"]

    def test_tubular_bells_id_67_sustains(self):
        # Empirically verified: opcode 67 → waveset[68], 2288 B, loop-repeat.
        m = self._committed()["67"]
        self.assertTrue(m["has_loop_repeat"])
        self.assertEqual(m["sample_size"], 2288)
        self.assertFalse(m["is_null"])

    def test_empty_silent_id_1_is_tiny(self):
        m = self._committed()["1"]
        self.assertEqual(m["sample_size"], 32)
        self.assertFalse(m["is_null"])

    def test_committed_matches_live_waveset_when_present(self):
        if not gen.TARGET.exists():
            self.skipTest("feds_instrument_meta.json not generated yet")
        path = gen.waveset_path()
        if not path.exists():
            self.skipTest("WAVESET.WD absent (ROM-derived) — skipping live drift check")
        expected = gen.render(gen.parse_waveset(path.read_bytes()))
        actual = gen.TARGET.read_text()
        self.assertEqual(
            expected, actual,
            "feds_instrument_meta.json is stale — regenerate with "
            "`uv run python tools/generate_feds_instrument_meta.py`")


if __name__ == "__main__":
    unittest.main()
