"""Tests for the ADR-0067 colour-seam preflight net (check_color_shaders.py).

The net enforces two things: no shader re-declares a deleted legacy tint uniform,
and any shader that CALLS color_apply reaches the shared include. Two ways the
text net can misfire — both guarded here:

  1. A `#include` that appears only inside a `//` comment must NOT count as reaching
     the seam (else a doc example silently satisfies the rule).
  2. The seam file itself (color_stack.gdshaderinc) DEFINES color_apply, so it
     trips `calls_apply`; it must not be reported as failing to include itself.

Run from tools/:
    uv run python -m unittest test_check_color_shaders
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import check_color_shaders as ccs

INCLUDE = ccs.INCLUDE  # "color_stack.gdshaderinc"
# The seam's LIVE res:// path. `includes_seam` resolves an include against the
# project and requires the file to exist, so a fixture must name where the seam
# actually is — addons/exmateria_schema/ since prologue pass 6 (ADR-0146).
SEAM_RES = ccs.SEAM_RES


def _write(dir_path: Path, name: str, text: str) -> Path:
    p = dir_path / name
    p.write_text(text, encoding="utf-8")
    return p


class SeamDetectionTests(unittest.TestCase):
    def test_commented_include_does_not_reach_seam(self):
        """An #include that lives only in a // comment must not satisfy the seam."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(
                Path(d),
                "fake.gdshader",
                '// example usage:\n'
                f'//   #include "res://{SEAM_RES}"\n'
                "void fragment() { ALBEDO = color_apply(base, 0); }\n",
            )
            self.assertFalse(
                ccs.includes_seam(path),
                "a commented-out #include should not count as reaching the seam",
            )

    def test_real_include_reaches_seam(self):
        """A genuine (uncommented) #include of the seam still counts (regression guard)."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(
                Path(d),
                "fake.gdshader",
                f'#include "res://{SEAM_RES}"\n'
                "void fragment() { ALBEDO = color_apply(base, 0); }\n",
            )
            self.assertTrue(ccs.includes_seam(path))

    def test_dangling_include_does_not_reach_seam(self):
        """A path that no longer exists must NOT satisfy the seam, even though its
        basename is still the seam's (ADR-0146 dec. 8). Prologue pass 6 moved the
        seam into addons/exmateria_schema/, so a stale `assets/shaders/` include
        compiles to nothing while reading, to a basename match, as compliant."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(
                Path(d),
                "fake.gdshader",
                f'#include "res://assets/shaders/{INCLUDE}"\n'
                "void fragment() { ALBEDO = color_apply(base, 0); }\n",
            )
            self.assertFalse(
                ccs.includes_seam(path),
                "an #include naming a path that does not exist must not count",
            )

    def test_seam_file_itself_is_not_a_violation(self):
        """The seam file DEFINES color_apply; scanning it must report no problem
        even with no self-include comment present."""
        with tempfile.TemporaryDirectory() as d:
            seam = _write(
                Path(d),
                INCLUDE,
                "// Unified PSX colour-mode stack (no self-include example here).\n"
                "vec3 color_apply(vec3 base, int surface_id) { return base; }\n",
            )
            self.assertEqual(
                ccs.check_shader(seam), [],
                "the seam file that defines color_apply must not flag itself",
            )


if __name__ == "__main__":
    unittest.main()
