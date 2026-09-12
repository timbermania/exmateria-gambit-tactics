"""Unit tests for the SCREEN section's authoritative `raw` block (#254 slice 4).

Per #254 decision 2, each on-disk screen keyframe entry (one screen **tween** /
lane event in Studio vocabulary) must carry a `raw` sub-block holding the
authoritative PSX-domain bytes from which the runtime-facing derived fields
(`duration_frames`, `mode`, `blend_mode`) are a cache. The byte-exact writer
(slice 5) serializes from this block, and the presence/absence of a valid raw
encoding is the mechanical Free/Faithful line.

Expected values come from the literal bytes placed into a synthetic buffer — an
independent source of truth, not the parser's own derivation.

Run from tools/:
    uv run python -m unittest test_parse_effect_screen_raw
"""

from __future__ import annotations

import struct
import unittest

import parse_effect as pe


# Screen keyframe field offsets, relative to the channel base (mirrors
# parse_screen_channel; asserted here as an independent copy of the ROM layout).
_OFF_TIME = 0x00     # + i*2, signed 16-bit
_OFF_START = 0x42    # + i*3, u8 R/G/B
_OFF_END = 0xA5      # + i*3, u8 R/G/B
_OFF_CTRL = 0x108    # + i,   u8
_CHANNEL_BYTES = 300  # 298 keyframe bytes + 2 max_keyframe


def _place_keyframe(buf: bytearray, base: int, i: int, *,
                    time_value: int, start_rgb, end_rgb, ctrl: int) -> None:
    """Write one keyframe's raw bytes into `buf` at the ROM offsets."""
    struct.pack_into("<h", buf, base + _OFF_TIME + i * 2, time_value)
    buf[base + _OFF_START + i * 3 + 0] = start_rgb[0]
    buf[base + _OFF_START + i * 3 + 1] = start_rgb[1]
    buf[base + _OFF_START + i * 3 + 2] = start_rgb[2]
    buf[base + _OFF_END + i * 3 + 0] = end_rgb[0]
    buf[base + _OFF_END + i * 3 + 1] = end_rgb[1]
    buf[base + _OFF_END + i * 3 + 2] = end_rgb[2]
    buf[base + _OFF_CTRL + i] = ctrl


class ScreenRawBlock(unittest.TestCase):

    def _parse_one(self, base: int = 0):
        buf = bytearray(base + _CHANNEL_BYTES)
        # Keyframe 0: a Gradient (FADE) tween — ctrl bit7 clear.
        _place_keyframe(buf, base, 0,
                        time_value=3, start_rgb=(255, 128, 0),
                        end_rgb=(64, 32, 16), ctrl=0x02)
        # Keyframe 2: a Blend (TINT) tween — ctrl bit7 set — proving the i-stride.
        _place_keyframe(buf, base, 2,
                        time_value=-5, start_rgb=(10, 20, 30),
                        end_rgb=(200, 210, 220), ctrl=0x85)
        ch = pe.parse_screen_channel(bytes(buf), base, "for_each")
        return ch

    def test_raw_block_carries_authoritative_bytes(self):
        ch = self._parse_one()
        raw0 = ch["keyframes"][0]["raw"]
        self.assertEqual(raw0, {
            "time_value": 3,
            "start_r": 255, "start_g": 128, "start_b": 0,
            "end_r": 64, "end_g": 32, "end_b": 16,
            "ctrl": 0x02,
        })

    def test_raw_block_indexes_by_keyframe_stride(self):
        ch = self._parse_one()
        raw2 = ch["keyframes"][2]["raw"]
        self.assertEqual(raw2, {
            "time_value": -5,
            "start_r": 10, "start_g": 20, "start_b": 30,
            "end_r": 200, "end_g": 210, "end_b": 220,
            "ctrl": 0x85,
        })

    def test_raw_is_present_on_every_keyframe(self):
        ch = self._parse_one()
        self.assertEqual(len(ch["keyframes"]), pe.MAX_SCREEN_KEYFRAMES)
        for kf in ch["keyframes"]:
            self.assertIn("raw", kf)
            self.assertEqual(set(kf["raw"].keys()), {
                "time_value", "start_r", "start_g", "start_b",
                "end_r", "end_g", "end_b", "ctrl",
            })

    def test_derived_fields_are_a_cache_of_raw(self):
        # The top-level derived fields stay (read-side unchanged) and remain
        # consistent with raw: duration = time_value*8, mode from ctrl bit7.
        ch = self._parse_one()
        kf0, kf2 = ch["keyframes"][0], ch["keyframes"][2]
        self.assertEqual(kf0["duration_frames"], kf0["raw"]["time_value"] * 8)
        self.assertEqual(kf0["mode"], "FADE")   # ctrl 0x02, bit7 clear
        self.assertEqual(kf2["mode"], "TINT")   # ctrl 0x85, bit7 set
        self.assertEqual(kf2["blend_mode"], 0x85 % 128)


if __name__ == "__main__":
    unittest.main()
