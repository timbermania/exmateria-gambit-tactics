#!/usr/bin/env python3
"""Guard for the residue auto-derivation (ADR-0072 pilot -> full-cast expansion).

Two layers:
  * pure-logic tests over a synthetic ENTD/names fixture -- token naming,
    dominant-sprite selection (generics ignored), and each flag class;
  * a real-data invariant -- once the full resolvable cast is promoted, the tool
    derives NO further candidates, and the two authored JSONs agree on the unique
    set with valid hex bodies (skips if the authored inputs are absent).

Run:  uv run python -m unittest test_derive_template_residue
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest import mock

import derive_template_residue as dtr

TOOLS = Path(__file__).resolve().parent
GODOT = TOOLS.parent
SCEN = GODOT / "assets" / "scenarios"
RESIDUE = SCEN / "template_residue.json"
ASSETS = SCEN / "template_assets.json"
UNIT_NAMES = SCEN / "unit_names.json"
ENTD = SCEN / "entd.json"


def _entd(*slot_lists) -> dict:
    """Wrap raw slot lists as an entd.json-shaped doc."""
    return {"records": [{"slots": slots} for slots in slot_lists]}


def _slot(sn: int, ss: int) -> dict:
    return {"special_name": sn, "sprite_set": ss, "unit_id": sn}


class DominantSpriteTest(unittest.TestCase):
    def test_ignores_generic_and_null_sheets(self) -> None:
        dist = {0x07: 5, 0x00: 3, 0x82: 2}  # ARU real; null + GIN_M generic noise
        self.assertEqual(dtr.dominant_char_sprite(dist), (0x07, 5))

    def test_none_when_only_generic(self) -> None:
        self.assertEqual(dtr.dominant_char_sprite({0x00: 4, 0x80: 1}), (None, 0))

    def test_picks_highest_count(self) -> None:
        self.assertEqual(dtr.dominant_char_sprite({0x11: 2, 0x22: 9}), (0x22, 9))


class DeriveCandidatesTest(unittest.TestCase):
    """Drive derive_candidates over a synthetic corpus by patching the loaders."""

    def _run(self, names, residue, entd, sprite_files):
        reads = {
            dtr.UNIT_NAMES_PATH: {"names": names},
            dtr.RESIDUE_PATH: {"residue": residue},
            dtr.ENTD_PATH: entd,
            dtr.SPRITE_FILES_PATH: sprite_files,
        }

        def fake_read(self):
            return json.dumps(reads[self])

        with mock.patch.object(Path, "read_text", fake_read):
            return dtr.derive_candidates()

    def test_token_and_body_from_dominant(self) -> None:
        cands = self._run(
            names={"7": "Algus"}, residue={},
            entd=_entd([_slot(7, 0x07), _slot(7, 0x07), _slot(7, 0x07)],
                       [_slot(7, 0x00)]),  # a null extra, ignored
            sprite_files={"07": {"filename": "ARU.SPR"}})
        self.assertEqual(len(cands), 1)
        c = cands[0]
        self.assertEqual(c["token"], "algus_7")
        self.assertEqual(c["body_sprite_id"], "07")
        self.assertEqual(c["flags"], [])

    def test_already_promoted_is_skipped(self) -> None:
        cands = self._run(
            names={"7": "Algus"}, residue={"7": "algus_7"},
            entd=_entd([_slot(7, 0x07)]),
            sprite_files={"07": {"filename": "ARU.SPR"}})
        self.assertEqual(cands, [])

    def test_lowconf_flag(self) -> None:
        cands = self._run(
            names={"29": "Barinten"}, residue={},
            entd=_entd([_slot(29, 0x1D), _slot(29, 0x1D)]),  # only 2 appearances
            sprite_files={"1D": {"filename": "BARITEN.SPR"}})
        self.assertIn("LOWCONF(2)", cands[0]["flags"])

    def test_no_char_sheet_flag_and_null_body(self) -> None:
        cands = self._run(
            names={"99": "Ghost"}, residue={},
            entd=_entd([_slot(99, 0x00), _slot(99, 0x80)]),  # only generic/null
            sprite_files={})
        self.assertIsNone(cands[0]["body_sprite_id"])
        self.assertIn("NO_CHAR_SHEET", cands[0]["flags"])

    def test_shared_sheet_flag(self) -> None:
        cands = self._run(
            names={"1": "Foo", "2": "Bar"}, residue={},
            entd=_entd([_slot(1, 0x10)], [_slot(2, 0x10)]),  # both dominate 0x10
            sprite_files={"10": {"filename": "SHARE.SPR"}})
        by = {c["special_name"]: c for c in cands}
        self.assertIn("SHARED:Bar", by[1]["flags"])
        self.assertIn("SHARED:Foo", by[2]["flags"])

    def test_verify_flag_for_known_decoy(self) -> None:
        # sn 22 is in VERIFY_BODY: surprising sheet kept faithful, flagged.
        cands = self._run(
            names={"22": "Mustadio"}, residue={},
            entd=_entd([_slot(22, 0x16), _slot(22, 0x16), _slot(22, 0x16)]),
            sprite_files={"16": {"filename": "GARU.SPR"}})
        self.assertEqual(cands[0]["body_sprite_id"], "16")  # faithful, not overridden
        self.assertIn("VERIFY", cands[0]["flags"])


class ShippedResidueInvariantTest(unittest.TestCase):
    """The real authored JSONs, post-expansion."""

    def setUp(self) -> None:
        for p in (RESIDUE, ASSETS, UNIT_NAMES, ENTD):
            if not p.exists():
                raise unittest.SkipTest(f"authored input missing: {p}")

    def test_full_resolvable_cast_is_promoted(self) -> None:
        # Every story character with a derivable body should already be a
        # template; the tool must find nothing new (drift guard).
        leftover = [c for c in dtr.derive_candidates()
                    if c["body_sprite_id"] is not None]
        self.assertEqual(
            leftover, [],
            f"unpromoted resolvable cast: {[c['token'] for c in leftover]}")

    def test_residue_and_assets_agree(self) -> None:
        residue = json.loads(RESIDUE.read_text())["residue"]
        assets = json.loads(ASSETS.read_text())["assets"]
        self.assertEqual(set(residue), set(assets),
                         "identity and asset residues must cover the same set")
        for sn, entry in assets.items():
            body = entry["body_sprite_id"]
            self.assertEqual(len(body), 2)
            int(body, 16)  # raises if not valid hex


if __name__ == "__main__":
    unittest.main()
