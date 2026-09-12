"""Tests for the LINEAR-tonemap preflight net (check_tonemap.py).

The net is NEGATIVE by design: Linear is the class default, so a correct Environment
omits `tonemap_mode` entirely (Godot won't serialize a property equal to its default).
So the two load-bearing behaviours are:

  1. A non-zero tonemap_mode (Reinhard/Filmic/ACES/AgX) MUST be flagged.
  2. An OMITTED tonemap_mode (the default-Linear case — how every current scene looks)
     MUST pass. If this regressed to "require the line present", every scene would fail.

Run from tools/:
    uv run python -m unittest test_check_tonemap
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import check_tonemap as ct


def _write(dir_path: Path, name: str, text: str) -> Path:
    p = dir_path / name
    p.write_text(text, encoding="utf-8")
    return p


# A minimal inline-Environment .tscn body, parameterised by the tonemap line.
def _scene(tonemap_line: str = "") -> str:
    return (
        '[gd_scene load_steps=2 format=3]\n\n'
        '[sub_resource type="Environment" id="Environment_1"]\n'
        "background_mode = 1\n"
        f"{tonemap_line}"
        "\n[node name=\"World\" type=\"WorldEnvironment\"]\n"
        "environment = SubResource(\"Environment_1\")\n"
    )


class ToneMapNetTests(unittest.TestCase):
    def test_omitted_tonemap_passes(self):
        """The default-Linear case (no tonemap_mode line) must be clean — this is how
        every current scene is authored; a regression here would fail the whole build."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(Path(d), "ok.tscn", _scene())
            self.assertEqual(ct.check_file(path), [])

    def test_explicit_linear_passes(self):
        """tonemap_mode = 0 is Linear and must pass."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(Path(d), "ok.tscn", _scene("tonemap_mode = 0\n"))
            self.assertEqual(ct.check_file(path), [])

    def test_agx_is_flagged(self):
        """AgX (4) is the modern default many templates inject — the exact risk."""
        with tempfile.TemporaryDirectory() as d:
            path = _write(Path(d), "bad.tscn", _scene("tonemap_mode = 4\n"))
            problems = ct.check_file(path)
            self.assertEqual(len(problems), 1)
            self.assertIn("AgX", problems[0])
            self.assertIn("Environment_1", problems[0])

    def test_aces_is_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            path = _write(Path(d), "bad.tscn", _scene("tonemap_mode = 3\n"))
            problems = ct.check_file(path)
            self.assertEqual(len(problems), 1)
            self.assertIn("ACES", problems[0])

    def test_standalone_tres_environment_is_scanned(self):
        """A non-linear tonemap in a standalone .tres Environment must be caught too."""
        with tempfile.TemporaryDirectory() as d:
            body = (
                '[gd_resource type="Environment" format=3]\n\n'
                "[resource]\n"
                "background_mode = 1\n"
                "tonemap_mode = 2\n"  # Filmic
            )
            path = _write(Path(d), "env.tres", body)
            problems = ct.check_file(path)
            self.assertEqual(len(problems), 1)
            self.assertIn("Filmic", problems[0])
            self.assertIn("resource", problems[0])

    def test_section_attribution_across_multiple_environments(self):
        """With two Environments in one file, only the non-linear one is reported, and
        the offending section is named correctly."""
        with tempfile.TemporaryDirectory() as d:
            body = (
                "[gd_scene format=3]\n\n"
                '[sub_resource type="Environment" id="Env_good"]\n'
                "background_mode = 1\n\n"
                '[sub_resource type="Environment" id="Env_bad"]\n'
                "background_mode = 1\n"
                "tonemap_mode = 1\n"  # Reinhard
            )
            path = _write(Path(d), "two.tscn", body)
            problems = ct.check_file(path)
            self.assertEqual(len(problems), 1)
            self.assertIn("Env_bad", problems[0])
            self.assertIn("Reinhard", problems[0])

    def test_real_project_is_clean(self):
        """The live project must pass today (all scenes ride the Linear default). This
        pins the current-good state and turns a future AgX slip into a red test."""
        violations = []
        for path in ct._iter_project_files():
            violations.extend(ct.check_file(path))
        self.assertEqual(violations, [], f"project has non-linear tonemappers: {violations}")


if __name__ == "__main__":
    unittest.main()
