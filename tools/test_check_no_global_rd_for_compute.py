"""Tests for the #430 global-device guard (check_no_global_rd_for_compute.py).

The rule is a per-file CO-OCCURRENCE — hold the renderer's global RenderingDevice AND drive it by
hand — so the guard has two independent halves and three ways to misfire, all covered here:

  1. Either half ALONE must stay clean. `EffectMultiMeshPool` / `FoldSurface` legitimately hold the
     global device and never submit; `GPUBatchSimulator` (fixed) legitimately submits a LOCAL one.
     A guard that fired on either half alone would be unusable and would get exempted away.
  2. The prose EXPLAINING the rule must not satisfy or trip it. The fix deliberately leaves a long
     comment naming `get_rendering_device()` and `submit()/sync()` in the very file that must not
     call them — if comments were scanned, the fixed file would still read as violating. This is the
     failure mode from `a-source-assertion-can-match-its-own-comment`, and here it would fire in the
     FALSE-POSITIVE direction, which is worse: it makes the guard look armed while the only way to
     quiet it is to delete the explanation.
  3. Killing ONE of `submit`/`sync` must not disarm it. #430's errors came from both calls; a
     one-branch seed would leave the guard green on a still-broken file.

Run from tools/:
    uv run python -m unittest test_check_no_global_rd_for_compute
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import check_no_global_rd_for_compute as guard

PROJECT_DIR = TOOLS_DIR.parent

VIOLATING = """\
extends Node
var _rd: RenderingDevice = null
func initialize() -> bool:
\t_rd = RenderingServer.create_local_rendering_device()
\tif not _rd:
\t\t_rd = RenderingServer.get_rendering_device()
\treturn true
func _run_tick() -> void:
\t_rd.submit()
\t_rd.sync()
"""


def _violates(text: str) -> bool:
    g, d = guard.scan_source(text)
    return bool(g and d)


class CoOccurrenceTests(unittest.TestCase):
    def test_the_430_shape_is_caught(self):
        """The exact pre-fix GPUBatchSimulator shape: local-with-global-fallback, then submit/sync."""
        self.assertTrue(_violates(VIOLATING))

    def test_global_device_without_driving_is_clean(self):
        """EffectMultiMeshPool / FoldSurface: hold the global device, never submit. Legitimate."""
        text = (
            "extends Node\n"
            "func _resize() -> void:\n"
            "\tvar rd := RenderingServer.get_rendering_device()\n"
            "\tif rd == null:\n"
            "\t\treturn\n"
            "\trd.buffer_update(_buf, 0, _n, _bytes)\n"
        )
        self.assertFalse(_violates(text), "holding the global device alone is not a violation")

    def test_driving_a_local_device_is_clean(self):
        """The FIXED GPUBatchSimulator shape: local only, no fallback, submit/sync freely."""
        text = (
            "extends Node\n"
            "func initialize() -> bool:\n"
            "\t_rd = RenderingServer.create_local_rendering_device()\n"
            "\tif not _rd:\n"
            "\t\tpush_error(\"no local device\")\n"
            "\t\treturn false\n"
            "\treturn true\n"
            "func _run_tick() -> void:\n"
            "\t_rd.submit()\n"
            "\t_rd.sync()\n"
        )
        self.assertFalse(_violates(text), "driving a LOCAL device is the correct pattern")


class SeedArmTests(unittest.TestCase):
    """Each half killed independently — a partial seed must still leave the guard armed."""

    def test_removing_only_submit_still_violates(self):
        text = VIOLATING.replace("\t_rd.submit()\n", "")
        self.assertTrue(_violates(text), "sync() alone still drives the global device")

    def test_removing_only_sync_still_violates(self):
        text = VIOLATING.replace("\t_rd.sync()\n", "")
        self.assertTrue(_violates(text), "submit() alone still drives the global device")

    def test_removing_the_whole_drive_mechanism_clears_it(self):
        text = VIOLATING.replace("\t_rd.submit()\n", "").replace("\t_rd.sync()\n", "")
        self.assertFalse(_violates(text), "with neither call the file only holds the device")

    def test_removing_the_global_getter_clears_it(self):
        text = VIOLATING.replace("\t\t_rd = RenderingServer.get_rendering_device()\n", "\t\treturn false\n")
        self.assertFalse(_violates(text), "no global getter, no violation")


class ProseTests(unittest.TestCase):
    """The words describing the rule must not participate in it — in EITHER direction."""

    def test_comment_naming_the_getter_does_not_trip_the_guard(self):
        text = (
            "extends Node\n"
            "func initialize() -> bool:\n"
            "\t# LOCAL ONLY - deliberately no fallback to RenderingServer.get_rendering_device(),\n"
            "\t# which returns a device that cannot submit()/sync(). See #430.\n"
            "\t_rd = RenderingServer.create_local_rendering_device()\n"
            "\treturn _rd != null\n"
            "func _run_tick() -> void:\n"
            "\t_rd.submit()\n"
            "\t_rd.sync()\n"
        )
        self.assertFalse(
            _violates(text),
            "a comment explaining why the fallback is absent must not read as the fallback",
        )

    def test_docstring_naming_the_getter_does_not_trip_the_guard(self):
        text = (
            "extends Node\n"
            "func initialize() -> bool:\n"
            '\t"""No get_rendering_device() fallback: the global device cannot submit()/sync()."""\n'
            "\t_rd = RenderingServer.create_local_rendering_device()\n"
            "\treturn _rd != null\n"
            "func _run_tick() -> void:\n"
            "\t_rd.submit()\n"
        )
        self.assertFalse(_violates(text), "a docstring is not code")

    def test_a_commented_out_getter_does_not_satisfy_the_drive_half_either(self):
        """Negative arm on the other side: commenting out submit/sync must not hide a real getter."""
        text = (
            "extends Node\n"
            "func initialize() -> void:\n"
            "\t_rd = RenderingServer.get_rendering_device()\n"
            "func _run_tick() -> void:\n"
            "\t# _rd.submit()\n"
            "\t# _rd.sync()\n"
        )
        self.assertFalse(_violates(text), "commented-out calls do not drive anything")


class ExemptionTests(unittest.TestCase):
    def test_exempt_marker_clears_the_line(self):
        text = VIOLATING.replace(
            "\t\t_rd = RenderingServer.get_rendering_device()\n",
            "\t\t_rd = RenderingServer.get_rendering_device()  # global-rd-exempt: test double\n",
        )
        self.assertFalse(_violates(text), "an exempted line must not count")


class LiveTreeTests(unittest.TestCase):
    """The guard must be about THIS tree, not only about fixtures."""

    def test_the_live_tree_is_clean(self):
        self.assertEqual(guard.main(), 0, "the shipped tree must satisfy the guard")

    def test_the_scan_actually_reaches_files(self):
        """A guard that scans nothing passes. Pin a floor and pin the known device-driving file."""
        files = list(guard.iter_gd_files(PROJECT_DIR))
        self.assertGreater(len(files), 100, "scan floor: a linked worktree must not silently see ~8")
        names = {p.name for p in files}
        self.assertIn("GPUBatchSimulator.gd", names, "the file the rule exists for must be scanned")
        self.assertIn("EffectMultiMeshPool.gd", names, "the legitimate global-device user too")

    def test_gpubatchsimulator_has_no_global_fallback(self):
        """The #430 fix itself, asserted on a distinctive composite rather than a bare token."""
        text = (PROJECT_DIR / "src/gpu/GPUBatchSimulator.gd").read_text(encoding="utf-8")
        _, code_only = zip(*[(raw, code) for _, raw, code in guard.strip_code_lines(text)])
        joined = "\n".join(code_only)
        self.assertIn("RenderingServer.create_local_rendering_device()", joined)
        self.assertNotIn("RenderingServer.get_rendering_device()", joined)
        self.assertIn(".submit()", joined, "this file is only interesting because it drives a device")


if __name__ == "__main__":
    unittest.main()
