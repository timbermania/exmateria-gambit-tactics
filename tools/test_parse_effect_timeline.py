"""Unit tests for parse_effect._derive_cinematic_timing.

Covers the three GPU-cinematic header fields (issue #53) the orchestrator
reads from timeline.json — first_hit_frame, for_each_delay, total_frames.
Uses stdlib unittest so there's no pytest dep on the tools venv.

Run from tools/:
    uv run python -m unittest test_parse_effect_timeline
"""

from __future__ import annotations

import unittest
from typing import Any, List

import parse_effect as pe


def _kf(time: int, action_flags: int = 0) -> dict[str, Any]:
    return {"time": time, "emitter_id": 0, "action_flags": action_flags}


def _ch(context: str, channel_index: int, keyframes: List[dict[str, Any]],
        max_keyframe: int | None = None) -> dict[str, Any]:
    if max_keyframe is None:
        max_keyframe = len(keyframes) - 1
    # Pad to 25 keyframes (matches parse_particle_channel's real shape).
    while len(keyframes) < 25:
        keyframes.append(_kf(0, 0))
    return {
        "context": context,
        "channel_index": channel_index,
        "keyframes": keyframes,
        "max_keyframe": max_keyframe,
    }


class DeriveCinematicTiming(unittest.TestCase):

    def test_first_hit_is_absolute_from_cinematic_start(self):
        # phase1_duration + spawn_delay = 60 base; HIT_REACT at relative time 58
        # → absolute first_hit_frame = 118 (matches real E001/Fire layout).
        header = {"phase1_duration": 12, "spawn_delay": 48, "phase2_delay": 77}
        channels = [_ch("for_each", 0, [_kf(58, 0x10)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["first_hit_frame"], 118)

    def test_first_hit_defaults_to_zero_when_no_hit_react(self):
        header = {"phase1_duration": 8, "spawn_delay": 16, "phase2_delay": 64}
        channels = [_ch("for_each", 0, [_kf(40, 0), _kf(80, 0)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["first_hit_frame"], 0)

    def test_for_each_delay_defaults_to_one_with_single_hit(self):
        header = {"phase1_duration": 12, "spawn_delay": 48, "phase2_delay": 77}
        channels = [_ch("for_each", 0, [_kf(58, 0x10)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["for_each_delay"], 1)

    def test_for_each_delay_defaults_to_one_with_no_hits(self):
        header = {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0}
        channels = [_ch("for_each", 0, [_kf(0, 0)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["for_each_delay"], 1)

    def test_for_each_delay_is_stride_between_consecutive_hits(self):
        # Two HIT_REACTs at relative times 40 and 70 → stride 30.
        header = {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0}
        channels = [_ch("for_each", 0, [_kf(40, 0x10), _kf(70, 0x10)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["for_each_delay"], 30)

    def test_for_each_delay_clamped_to_one_when_raw_is_zero(self):
        # Two HIT_REACTs at the same time → raw stride 0, clamped to 1.
        header = {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0}
        channels = [_ch("for_each", 0, [_kf(50, 0x10), _kf(50, 0x10)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["for_each_delay"], 1)

    def test_for_each_delay_merges_across_channels(self):
        # HIT_REACTs at 40 (ch0) and 60 (ch1) → sorted stride = 20.
        header = {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0}
        channels = [
            _ch("for_each", 0, [_kf(40, 0x10)]),
            _ch("for_each", 1, [_kf(60, 0x10)]),
        ]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["for_each_delay"], 20)

    def test_total_frames_is_base_plus_largest_for_each_time(self):
        # phase1=12, spawn_delay=48 → base=60. Largest for_each time = 600.
        header = {"phase1_duration": 12, "spawn_delay": 48, "phase2_delay": 77}
        channels = [_ch("for_each", 0, [_kf(58, 0x10), _kf(600, 0)])]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["total_frames"], 660)

    def test_max_keyframe_excludes_padding(self):
        # Padding slot at time=999 must not poison total_frames or first_hit.
        header = {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0}
        channels = [
            _ch(
                "for_each",
                0,
                [_kf(40, 0x10), _kf(100, 0), _kf(999, 0x10)],
                max_keyframe=1,
            )
        ]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["first_hit_frame"], 40)
        self.assertEqual(out["total_frames"], 100)

    def test_phase1_and_phase2_hit_reacts_are_ignored(self):
        # Empirical scan shows 0 HIT_REACTs in phase1/phase2; the derivation
        # must scan for_each only so a stray phase1 flag can't shift the value.
        header = {"phase1_duration": 8, "spawn_delay": 16, "phase2_delay": 64}
        channels = [
            _ch("phase1", 0, [_kf(20, 0x10)]),
            _ch("phase2", 0, [_kf(30, 0x10)]),
            _ch("for_each", 0, [_kf(0, 0)]),
        ]
        out = pe._derive_cinematic_timing(header, channels)
        self.assertEqual(out["first_hit_frame"], 0)


if __name__ == "__main__":
    unittest.main()
