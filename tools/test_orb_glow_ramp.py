"""Parse-and-validate guard for the Formation-screen orb glow ramp.

The selected-unit orb on the party-roster screen glows up/down through a fixed
set of DISCRETE gouraud-brightness levels (not a continuous fade). The exact
levels + timing were measured frame-exact from the running ROM and recorded in
`research/working_documents/roster_catalogue_captures/orb_glow_ramp.json`.

This test proves the data file (a) parses and (b) its compact "rule"
(21 levels 88..168 step 4, ping-pong with endpoints held 2 frames) reconstructs
the raw 64-frame measurement byte-for-byte. That is the machine-checkable form of
"the discrete glow levels are captured and parseable".
"""
import json
import os
import unittest

RAMP_JSON = os.path.normpath(
    os.path.join(
        os.path.dirname(__file__),
        "..", "..", "research", "working_documents",
        "roster_catalogue_captures", "orb_glow_ramp.json",
    )
)


def build_ping_pong(levels, endpoint_hold, interior_hold):
    """Reconstruct one full period from the discrete-level rule.

    Up-ramp then down-ramp; the two extreme levels are held `endpoint_hold`
    frames, interior levels `interior_hold` frames each. Returns the frame
    sequence for exactly one period (length == period_frames).
    """
    up = list(levels)
    down = list(reversed(levels))[1:-1]  # interior only, on the way down
    seq = []
    n = len(levels)
    for i, v in enumerate(up):
        hold = endpoint_hold if (i == 0 or i == n - 1) else interior_hold
        seq.extend([v] * hold)
    for v in down:
        seq.extend([v] * interior_hold)
    return seq


class TestOrbGlowRamp(unittest.TestCase):
    def setUp(self):
        with open(RAMP_JSON) as f:
            self.data = json.load(f)
        self.ramp = self.data["ramp"]

    def test_parses_and_has_expected_shape(self):
        self.assertTrue(self.ramp["discrete"])
        self.assertEqual(self.ramp["type"], "ping_pong_triangle")
        self.assertEqual(self.ramp["level_count"], 21)
        self.assertEqual(self.ramp["period_frames"], 42)

    def test_levels_are_88_to_168_step_4(self):
        levels = self.ramp["levels"]
        self.assertEqual(levels, list(range(88, 168 + 1, 4)))
        self.assertEqual(min(levels), self.ramp["min"])
        self.assertEqual(max(levels), self.ramp["max"])
        self.assertEqual(len(levels), self.ramp["level_count"])

    def test_rule_reconstructs_raw_measurement(self):
        period = build_ping_pong(
            self.ramp["levels"],
            self.ramp["endpoint_hold_frames"],
            self.ramp["interior_hold_frames"],
        )
        self.assertEqual(len(period), self.ramp["period_frames"])
        # The raw 64-frame capture must be the periodic repetition of `period`,
        # phase-aligned to some starting offset within the period.
        measured = self.data["measured_sequence_64_frames"]
        start = period.index(measured[0])
        # find a phase that matches the whole measurement
        matched = False
        for phase in range(len(period)):
            if all(measured[i] == period[(phase + i) % len(period)]
                   for i in range(len(measured))):
                matched = True
                break
        self.assertTrue(
            matched,
            "measured sequence is not a rotation of the reconstructed period",
        )
        self.assertIsInstance(start, int)

    def test_sprite_metadata_present(self):
        sp = self.data["sprite"]
        self.assertEqual(sp["uv_rect"], [243, 73, 254, 84])
        self.assertEqual(sp["size_px"], [12, 12])
        self.assertTrue(sp["semi_transparent"])
        self.assertEqual(len(sp["clut"]["bgr555"]), 16)


if __name__ == "__main__":
    unittest.main()
