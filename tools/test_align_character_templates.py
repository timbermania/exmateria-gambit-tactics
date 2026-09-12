#!/usr/bin/env python3
"""Guard for the character-alignment transform (wayfinder #201, ADR-0072).

Given the flat-store extract (assets/sprites/textures/<id>.tga + .palette.tga),
the identity residue (template_residue.json) and the asset residue
(template_assets.json), assert that `align_character_templates` emits, per
unique, a folder-per-key packet matching the LOCKED schema
(docs/TEMPLATE_JSON_SCHEMA.md):

  - body.tga / body.palette.tga  -- byte-identical slices of the flat sheet
  - portrait.tga / portrait.palette.tga  -- the 48x32 portrait crop + own palette
  - template.json  -- body + portrait + animation{seq,shp} + flying + height,
    with NO `formation` (RE gap) and NO `events` (owned by #204)

Run:  uv run python -m unittest test_align_character_templates
"""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

import align_character_templates as act
import event_asset_derivation as ead
from extract_spr import write_tga

TOOLS = Path(__file__).resolve().parent
GODOT = TOOLS.parent
TEXTURES = GODOT / "assets" / "sprites" / "textures"
RESIDUE = GODOT / "assets" / "scenarios" / "template_residue.json"
ASSETS = GODOT / "assets" / "scenarios" / "template_assets.json"


def _load_tga(path: Path):
    """Return (width, height, bytes) for one of our 32-bit BGRA top-left TGAs."""
    data = path.read_bytes()
    w, h = struct.unpack("<HH", data[12:16])
    bpp = data[16]
    assert bpp == 32, f"{path}: expected 32bpp, got {bpp}"
    return w, h, data[18:]


def _require(*paths: Path) -> None:
    for p in paths:
        if not p.exists():
            raise unittest.SkipTest(f"flat-store input missing (gitignored): {p}")


class AlignCharacterTemplatesTest(unittest.TestCase):
    def setUp(self) -> None:
        _require(RESIDUE, ASSETS, TEXTURES / "03.tga", TEXTURES / "03.palette.tga")
        self._tmp = tempfile.TemporaryDirectory()
        self.out_root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    # --- the two authored manifests must agree on the unique set ---

    def test_residue_and_assets_cover_the_same_special_names(self) -> None:
        residue = json.loads(RESIDUE.read_text())["residue"]
        assets = json.loads(ASSETS.read_text())["assets"]
        self.assertEqual(
            set(residue.keys()), set(assets.keys()),
            "template_residue.json (identity) and template_assets.json (asset) "
            "must list the same special_names",
        )

    # --- one unique end-to-end: Ramza Ch4 (special_name 3 -> sprite 0x03) ---

    def test_emit_unique_folder_layout(self) -> None:
        folder = act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        self.assertTrue(folder.is_dir())
        for name in ("body.tga", "body.palette.tga",
                     "portrait.tga", "portrait.palette.tga", "template.json"):
            self.assertTrue((folder / name).exists(), f"missing {name}")

    def test_body_slice_is_byte_identical_to_flat_store(self) -> None:
        folder = act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        self.assertEqual((folder / "body.tga").read_bytes(),
                         (TEXTURES / "03.tga").read_bytes(),
                         "body.tga must be a byte-identical copy of the flat sheet")
        self.assertEqual((folder / "body.palette.tga").read_bytes(),
                         (TEXTURES / "03.palette.tga").read_bytes(),
                         "body.palette.tga must be a byte-identical copy")

    def test_portrait_is_the_48x32_bottom_crop(self) -> None:
        folder = act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        pw, ph, ppx = _load_tga(folder / "portrait.tga")
        self.assertEqual((pw, ph), (48, 32))

        # Recompute the expected crop independently from the source sheet:
        # x in [80,128), y in [456,488) for a compressed sprite.
        sw, sh, spx = _load_tga(TEXTURES / "03.tga")
        expected = bytearray()
        for y in range(456, 488):
            for x in range(80, 128):
                i = (y * sw + x) * 4
                expected += spx[i:i + 4]
        self.assertEqual(ppx, bytes(expected),
                         "portrait crop pixels must match the source band")

    def test_portrait_crop_is_non_empty(self) -> None:
        folder = act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        _, _, ppx = _load_tga(folder / "portrait.tga")
        nonzero = sum(1 for i in range(0, len(ppx), 4) if ppx[i] != 0)
        self.assertGreater(nonzero, len(ppx) // 4 // 4,
                           "portrait region should be a filled face, not blank")

    def test_template_json_shape_generic_of_a_unique(self) -> None:
        folder = act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        tj = json.loads((folder / "template.json").read_text())
        self.assertEqual(tj["template_key"], "3")
        self.assertEqual(tj["category"], "unique")
        self.assertEqual(tj["body"], {"sprite": "body.tga", "palette": "body.palette.tga"})
        self.assertEqual(tj["portrait"],
                         {"sprite": "portrait.tga", "palette": "portrait.palette.tga"})
        self.assertEqual(tj["animation"], {"seq": "type1", "shp": "type1"})
        self.assertFalse(tj["flying"])
        self.assertEqual(tj["height"], 36)
        # #201 carve-outs: formation contents = RE gap; events owned by #204.
        self.assertNotIn("formation", tj)
        self.assertNotIn("events", tj)

    def test_regen_with_event_context_removes_stale_event_assets(self) -> None:
        # A token that derived event frames once but derives NONE now (all its
        # cinematic anims turned out to be false positives -- delita_6) must not
        # keep the old slices on disk. Regenerating with an event context wipes
        # events/ even when there are no token_events for this unique.
        class _NoEventsCtx:
            def atlas(self, s): return None
            def segment_palette(self, s): return Path("/nonexistent")
            def face_png(self, row, col): return Path("/nonexistent")

        folder = self.out_root / "ramza_3"
        stale = folder / "events" / "chr"
        stale.mkdir(parents=True)
        (stale / "99.tga").write_bytes(b"stale")

        act.emit_unique(
            special_name=3, token="ramza_3", body_sprite_id="03",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
            token_events=None, event_ctx=_NoEventsCtx(),
        )
        self.assertFalse((folder / "events").exists(),
                         "stale events/ must be removed on regen with an event context")

    def test_ovelia_animation_seq_shp_diverge(self) -> None:
        # Ovelia (0x0C) is TYPE2.SHP / TYPE3.SEQ -- the schema's headline case
        # that seq and shp families are independent and must be named separately.
        _require(TEXTURES / "0C.tga", TEXTURES / "0C.palette.tga")
        folder = act.emit_unique(
            special_name=12, token="ovelia_12", body_sprite_id="0C",
            textures_dir=TEXTURES, out_root=self.out_root, compressed=True,
        )
        tj = json.loads((folder / "template.json").read_text())
        self.assertEqual(tj["animation"], {"seq": "type3", "shp": "type2"})


class _FakeGenericCtx:
    """Minimal EventAssetContext: one 2x2 all-index-1 atlas, a real 16x16 CLUT on
    disk, and a frames table with a single 2x2 block for (seg 5, frame 210)."""

    def __init__(self, tmp: Path):
        self._atlas = (2, 2, bytes([0, 0, 17, 255] * 4))  # BGRA, r=17 -> index 1
        pal = [(0, 0, 0, 0)] * 256
        for c in range(16):
            pal[3 * 16 + c] = (c * 15, 0, 0, 255)          # row 3 = a red ramp
        self._pal = tmp / "seg.palette.tga"
        write_tga(str(self._pal), 16, 16, pal)
        self.frames = {"5": {"210": [{"location_x": 0, "location_y": 0,
                                      "rectangle_x": 0, "rectangle_y": 0,
                                      "rectangle_width": 2, "rectangle_height": 2,
                                      "invert": False, "revert": False}]}}

    def atlas(self, segment): return self._atlas
    def segment_palette(self, segment): return self._pal
    def face_png(self, row, col): return Path("/nonexistent")


class GenericTemplateTokenTest(unittest.TestCase):
    """#222 legibility: a generic/monster folder is named by its ShiShi display
    name (slugified), not an opaque SPR hex. Filename/hex only as a fallback."""

    def test_job_and_npc_and_monster_names(self) -> None:
        self.assertEqual(act.generic_template_token("64", "KNIGHT_M.SPR"), "male_knight")
        self.assertEqual(act.generic_template_token("63", "ITEM_W.SPR"), "female_chemist")
        self.assertEqual(act.generic_template_token("4D", "20W.SPR"), "20_year_old_woman")
        self.assertEqual(act.generic_template_token("4F", "40W.SPR"), "40_year_old_woman")
        self.assertEqual(act.generic_template_token("56", "SOURYO.SPR"), "funeral_priest")
        self.assertEqual(act.generic_template_token("99", "DEMON.SPR"), "archaic_demon")
        self.assertEqual(act.generic_template_token("97", "HEBI.SPR"), "elidibs")

    def test_unknown_spr_falls_back_to_filename_then_hex(self) -> None:
        self.assertEqual(act.generic_template_token("EE", "WEIRD.SPR"), "weird")
        self.assertEqual(act.generic_template_token("EE", ""), "ee")


class EmitGenericStoreTest(unittest.TestCase):
    """#222: the generic/monster store is a self-contained template packet, not
    an events-only pool -- emitted into the SAME template tree as the uniques,
    named legibly (`male_knight`), owning a byte-identical body + palette, a 48x32
    portrait for generic-HUMAN sprites (a monster has none), its SPR-pooled
    cinematic frames, and a schema-shaped `template.json`. Empty composites still
    leave no folder."""

    def setUp(self) -> None:
        _require(TEXTURES / "64.tga", TEXTURES / "64.palette.tga",
                 TEXTURES / "99.tga", TEXTURES / "99.palette.tga",
                 act.SPRITE_TYPES_PATH, act.SPRITE_FILES_PATH)
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.ctx = _FakeGenericCtx(self.tmp)
        self.sprite_types = act.load_sprite_types()
        self.sprite_files = json.loads(act.SPRITE_FILES_PATH.read_text())
        self.out = self.tmp / "templates"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _run(self, result, taken=None):
        return act.emit_generic_store(
            result, self.ctx, self.out, self.sprite_files,
            textures_dir=TEXTURES, sprite_types=self.sprite_types,
            taken_tokens=taken)

    def test_generic_human_owns_body_portrait_and_events(self) -> None:
        result = ead.DerivationResult()
        result.generic_bucket(0x64).add_chr((5, 210, 3))   # KNIGHT_M -- human
        emitted = self._run(result)

        self.assertEqual([f.name for f in emitted], ["male_knight"])
        f = self.out / "male_knight"
        self.assertTrue((f / "events" / "chr" / "00.tga").exists())
        self.assertTrue((f / "events" / "chr" / "00.palette.tga").exists())
        # Owned body is a byte-identical copy of the flat sheet.
        self.assertTrue((f / "body.palette.tga").exists())
        self.assertEqual((f / "body.tga").read_bytes(),
                         (TEXTURES / "64.tga").read_bytes())
        self.assertTrue((f / "portrait.tga").exists())

        tj = json.loads((f / "template.json").read_text())
        self.assertEqual(tj["template_key"], "64")     # resolver key stays the SPR
        self.assertEqual(tj["name"], "Male Knight")
        self.assertEqual(tj["category"], "generic-human")
        self.assertEqual(tj["sprite"], "KNIGHT_M.SPR")
        self.assertEqual(tj["body"], {"sprite": "body.tga",
                                      "palette": "body.palette.tga"})
        self.assertIn("portrait", tj)
        self.assertIn("animation", tj)
        self.assertEqual(len(tj["events"]["chr"]), 1)

    def test_generic_monster_owns_body_but_no_portrait(self) -> None:
        result = ead.DerivationResult()
        result.generic_bucket(0x99).add_chr((5, 210, 3))   # DEMON -- MON family
        self._run(result)

        f = self.out / "archaic_demon"
        self.assertTrue((f / "body.tga").exists())
        self.assertFalse((f / "portrait.tga").exists())
        tj = json.loads((f / "template.json").read_text())
        self.assertEqual(tj["category"], "generic-monster")
        self.assertEqual(tj["name"], "Archaic Demon")
        self.assertNotIn("portrait", tj)

    def test_collision_with_a_unique_token_is_suffixed(self) -> None:
        result = ead.DerivationResult()
        result.generic_bucket(0x64).add_chr((5, 210, 3))
        emitted = self._run(result, taken={"male_knight"})   # pretend a unique took it
        self.assertEqual([f.name for f in emitted], ["male_knight_64"])

    def test_empty_composite_leaves_no_folder(self) -> None:
        result = ead.DerivationResult()
        result.generic_bucket(0x97).add_chr((5, 999, 3))   # no such frame -> empty
        emitted = self._run(result)
        self.assertEqual(emitted, [])
        self.assertFalse((self.out / "elidibs").exists())


class _FakeFaceCtx:
    """Minimal EventAssetContext for face-only slicing: `face_png` returns a real
    on-disk EVTFACE cell PNG; chr sourcing is never reached (face-only TokenEvents)."""

    def __init__(self, png: Path):
        self._png = png
        self.frames = {}

    def atlas(self, segment): return None
    def segment_palette(self, segment): return None
    def face_png(self, row, col): return self._png


class BuildCutsceneFaceTemplateJsonTest(unittest.TestCase):
    def test_portrait_only_shape_no_body(self) -> None:
        tj = act.build_cutscene_face_template_json(
            "balbanes", "Balbanes",
            {"face": [{"index": 0, "sprite": "events/face/00.tga",
                       "palette": "events/face/00.palette.tga"}]})
        self.assertEqual(tj["template_key"], "balbanes")
        self.assertEqual(tj["category"], "cutscene-face")
        self.assertEqual(tj["name"], "Balbanes")
        self.assertIn("face", tj["events"])
        self.assertNotIn("body", tj)      # SPR-less: no body sheet
        self.assertNotIn("portrait", tj)  # the face doubles as the portrait


class EmitCutsceneFacesTest(unittest.TestCase):
    """ADR-0072 addendum: a cutscene-face identity mints a portrait-only folder --
    events/face cells, NO body.tga, category `cutscene-face`, keyed by bare slug.
    A slug colliding with an already-taken folder (e.g. the `elidibs` monster SPR)
    is suffixed `_face`; an identity with no un-homed cells is skipped."""

    def setUp(self) -> None:
        face = act.FACES_DIR / "face_r0_c0.png"
        _require(face)
        self._tmp = tempfile.TemporaryDirectory()
        self.out = Path(self._tmp.name) / "templates"
        self.ctx = _FakeFaceCtx(face)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_mints_portrait_only_folder(self) -> None:
        emitted = act.emit_cutscene_faces(
            {"Balbanes": [(0, 0)]}, {"balbanes": "Balbanes"}, self.ctx, self.out)
        self.assertEqual([f.name for f in emitted], ["balbanes"])
        f = self.out / "balbanes"
        self.assertTrue((f / "events" / "face" / "00.tga").exists())
        self.assertFalse((f / "body.tga").exists())
        tj = json.loads((f / "template.json").read_text())
        self.assertEqual(tj["category"], "cutscene-face")
        self.assertEqual(tj["template_key"], "balbanes")

    def test_slug_collision_suffixed_face(self) -> None:
        emitted = act.emit_cutscene_faces(
            {"Elidibs": [(3, 6)]}, {"elidibs": "Elidibs"}, self.ctx, self.out,
            taken_tokens={"elidibs"})   # the HEBI.SPR monster folder already took it
        self.assertEqual([f.name for f in emitted], ["elidibs_face"])

    def test_identity_with_no_unhomed_cells_skipped(self) -> None:
        emitted = act.emit_cutscene_faces(
            {}, {"balbanes": "Balbanes"}, self.ctx, self.out)
        self.assertEqual(emitted, [])
        self.assertFalse((self.out / "balbanes").exists())


class _FakeFaceAndChrCtx:
    """EventAssetContext that can slice BOTH a face cell (real EVTFACE PNG) AND a
    cinematic chr frame (2x2 atlas + CLUT + one block), so a cutscene-face with
    events/chr can be emitted end-to-end (Balbanes' deathbed frames)."""

    def __init__(self, tmp: Path, png: Path):
        self._png = png
        self._atlas = (2, 2, bytes([0, 0, 17, 255] * 4))     # BGRA, r=17 -> index 1
        pal = [(0, 0, 0, 0)] * 256
        for c in range(16):
            pal[0 * 16 + c] = (c * 15, 0, 0, 255)            # row 0 = a red ramp
        self._pal = tmp / "seg.palette.tga"
        write_tga(str(self._pal), 16, 16, pal)
        self.frames = {"3": {"210": [{"location_x": 0, "location_y": 0,
                                      "rectangle_x": 0, "rectangle_y": 0,
                                      "rectangle_width": 2, "rectangle_height": 2,
                                      "invert": False, "revert": False}]}}

    def atlas(self, segment): return self._atlas
    def segment_palette(self, segment): return self._pal
    def face_png(self, row, col): return self._png


class EmitCutsceneFacesChrTest(unittest.TestCase):
    """Balbanes' deathbed follow-up: a cutscene-face folder must also slice its
    SPR-less cinematic frames (result.cutscene[slug]) into events/chr, not just the
    portrait cell -- the chr analog of the face mint."""

    def setUp(self) -> None:
        face = act.FACES_DIR / "face_r0_c0.png"
        _require(face)
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.out = self.tmp / "templates"
        self.ctx = _FakeFaceAndChrCtx(self.tmp, face)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_folder_gains_events_chr_from_the_cutscene_bucket(self) -> None:
        chr_te = ead.TokenEvents()
        chr_te.add_chr((3, 210, 0))                          # seg 3, frame 210, row 0
        emitted = act.emit_cutscene_faces(
            {"Balbanes": [(0, 0)]}, {"balbanes": "Balbanes"}, self.ctx, self.out,
            cutscene_chr={"balbanes": chr_te})
        self.assertEqual([f.name for f in emitted], ["balbanes"])
        f = self.out / "balbanes"
        self.assertTrue((f / "events" / "chr" / "00.tga").exists())
        self.assertTrue((f / "events" / "face" / "00.tga").exists())
        tj = json.loads((f / "template.json").read_text())
        self.assertEqual(tj["category"], "cutscene-face")
        self.assertEqual(len(tj["events"]["chr"]), 1)
        self.assertEqual(len(tj["events"]["face"]), 1)

    def test_chr_only_identity_still_mints(self) -> None:
        # An identity with cinematic frames but no un-homed face cell still mints
        # (chr alone is enough to warrant a folder).
        chr_te = ead.TokenEvents()
        chr_te.add_chr((3, 210, 0))
        emitted = act.emit_cutscene_faces(
            {}, {"balbanes": "Balbanes"}, self.ctx, self.out,
            cutscene_chr={"balbanes": chr_te})
        self.assertEqual([f.name for f in emitted], ["balbanes"])
        f = self.out / "balbanes"
        self.assertTrue((f / "events" / "chr" / "00.tga").exists())
        self.assertFalse((f / "events" / "face").exists())


if __name__ == "__main__":
    unittest.main()
