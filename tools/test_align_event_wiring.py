#!/usr/bin/env python3
"""Guard for wiring the derived event assets into the transform (#204).

Exercises `emit_event_assets` -> the `events` block in template.json and the
dense first-seen re-indexing, using a real EVTFACE cell + a stub EVTCHR context
(so it runs without the gitignored 200 MiB chunk corpus).

Run:  uv run python -m unittest test_align_event_wiring
"""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

import align_character_templates as act
import event_asset_derivation as ead

TOOLS = Path(__file__).resolve().parent
GODOT = TOOLS.parent
FACES = GODOT / "assets" / "scenarios" / "faces"
EVTCHR = GODOT / "assets" / "sprites" / "textures" / "evtchr"


class EventWiringTest(unittest.TestCase):
    def _ctx(self):
        frames = json.loads((GODOT / "assets" / "sprites" / "animations"
                             / "evtchr_frames.json").read_text())
        return act.EventAssetContext(EVTCHR, frames, FACES)

    def test_events_block_indexes_face_and_chr_densely(self):
        if not (FACES / "face_r0_c0.png").exists() or not (EVTCHR / "segment_000.tga").exists():
            self.skipTest("evtchr/ or faces/ not generated (gitignored)")
        frames = json.loads((GODOT / "assets" / "sprites" / "animations"
                             / "evtchr_frames.json").read_text())
        seg0 = frames["0"]
        good_fid = int(next(k for k, v in seg0.items() if v))
        absent_fid = 999  # not a frame id in the segment -> no block list -> skipped

        te = ead.TokenEvents()
        # 3-tuples (segment, frame_id, palette_row); first unsourceable -> skipped.
        te.chr = [(0, absent_fid, None), (0, good_fid, None)]
        te.face = [(0, 0), (0, 1)]

        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            events = act.emit_event_assets(folder, te, self._ctx())

            # chr: the unsourceable frame is skipped; the good one lands at index 0.
            self.assertEqual(len(events["chr"]), 1)
            self.assertEqual(events["chr"][0]["index"], 0)
            self.assertEqual(events["chr"][0]["sprite"], "events/chr/00.tga")
            self.assertTrue((folder / "events" / "chr" / "00.tga").exists())
            self.assertTrue((folder / "events" / "chr" / "00.palette.tga").exists())

            # face: two cells, indices 0 and 1.
            self.assertEqual([e["index"] for e in events["face"]], [0, 1])
            self.assertTrue((folder / "events" / "face" / "01.tga").exists())

    def test_template_json_carries_events_when_supplied(self):
        te = ead.TokenEvents()
        te.face = [(0, 0)]

        class StubCtx:
            def atlas(self, s): return None
            def segment_palette(self, s): return Path("/nonexistent")
            def face_png(self, row, col): return FACES / f"face_r{row}_c{col}.png"

        if not (FACES / "face_r0_c0.png").exists():
            self.skipTest("faces/ not generated (gitignored)")
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            events = act.emit_event_assets(folder, te, StubCtx())
            tj = act.build_template_json(12, "0C", act.load_sprite_types(), events)
        self.assertIn("events", tj)
        self.assertIn("face", tj["events"])
        self.assertNotIn("chr", tj["events"])  # no atlas -> no chr entries


if __name__ == "__main__":
    unittest.main()
