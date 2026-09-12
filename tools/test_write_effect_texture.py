"""Unit tests for the texture-replacement writer (#280, ADR-0199).

`write_effect_texture` turns an imported RGBA image back into an indexed pixel
plane against a FIXED CLUT, then splices that plane into an E###.BIN.

The load-bearing rule is ADR-0199 decision 2: quantization is an **index delta**
against the original plane, not a blind re-quantize. A colour does not identify
an index — 265 of 401 corpus effects hold the same BGR555 word at two or more
indices — so an unchanged texel must keep the index it already had.

Expected values here come from hand-built palettes with deliberate duplicates,
not from the implementation's own arithmetic.

Run from tools/:
    python3 -m unittest test_write_effect_texture
"""

from __future__ import annotations

import glob
import os
import unittest

import parse_effect as pe

import effect_writer_registry as ewr
import write_effect_texture as wet


# A 4-entry CLUT with a DELIBERATE duplicate: entries 1 and 3 are both the same
# red word, so the colour red maps to two legal indices.
#   0: 0x0000  transparent black -> RGBA(0,0,0,255)   (STP=0, per ADR-0096)
#   1: 0x001F  red               -> RGBA(248,0,0,255)
#   2: 0x8000  black with STP    -> RGBA(0,0,0,128)
#   3: 0x001F  red AGAIN         -> RGBA(248,0,0,255)
_CLUT = [0x0000, 0x001F, 0x8000, 0x001F]

_BLACK = (0, 0, 0, 255)
_RED = (248, 0, 0, 255)
_STP_BLACK = (0, 0, 0, 128)


class QuantizeIndexDelta(unittest.TestCase):
    def test_unchanged_image_keeps_every_original_index_including_duplicates(self):
        """Re-importing an unmodified export reproduces the ORIGINAL indices.

        Pixel 2 was drawn with index 3 — the duplicate red. A blind
        nearest-colour match would collapse it to index 1 and silently rewrite
        the byte; the delta rule must keep 3.
        """
        original = [0, 1, 3, 2]
        rgba = [_BLACK, _RED, _RED, _STP_BLACK]

        result = wet.quantize_to_clut(rgba, _CLUT, original)

        self.assertEqual(result["indices"], [0, 1, 3, 2])
        self.assertEqual(result["off_palette"], 0)


    def test_repainted_texel_takes_the_matching_entry(self):
        """A texel the artist actually changed re-quantizes; unchanged neighbours
        still keep their original index."""
        original = [0, 1, 3, 2]
        rgba = [_RED, _RED, _RED, _STP_BLACK]   # pixel 0 repainted black -> red

        result = wet.quantize_to_clut(rgba, _CLUT, original)

        self.assertEqual(result["indices"][0], 1, "repainted texel takes the red entry")
        self.assertEqual(result["indices"][2], 3, "untouched duplicate-red texel is preserved")
        self.assertEqual(result["off_palette"], 0)

    def test_off_palette_colour_is_approximated_and_counted(self):
        """The artist cannot introduce a colour (the CLUT is fixed), so a
        near-miss is snapped to the closest entry and REPORTED, not failed."""
        original = [0, 1, 3, 2]
        rgba = [_BLACK, (200, 10, 10, 255), _RED, _STP_BLACK]

        result = wet.quantize_to_clut(rgba, _CLUT, original)

        self.assertEqual(result["indices"][1], 1, "snapped to the red entry")
        self.assertEqual(result["off_palette"], 1)

    def test_flat_texel_does_not_silently_become_semi_transparent(self):
        """Alpha is the STP bit (ADR-0096). Where two entries share an RGB but
        differ in STP, a flat (alpha=255) import must not pick the STP one."""
        original = [-1, -1]
        rgba = [_BLACK, _STP_BLACK]

        result = wet.quantize_to_clut(rgba, _CLUT, original)

        self.assertEqual(result["indices"], [0, 2])


class AuthorableScope(unittest.TestCase):
    """ADR-0199 decision 3: v1 authors 8bpp single-sub-palette sheets only.
    Everything else is refused WITH A REASON, never silently mis-imported."""

    def test_plain_8bpp_sheet_is_authorable(self):
        verdict = wet.authorable(is_8bpp=True, sub_palettes=[0])
        self.assertTrue(verdict["ok"])
        self.assertEqual(verdict["reason"], "")

    def test_4bpp_is_refused_even_when_it_uses_one_sub_palette(self):
        """One rule, no special cases — the 2 single-sub-palette 4bpp sheets are
        refused with the other 58 (ADR-0199 consequences)."""
        verdict = wet.authorable(is_8bpp=False, sub_palettes=[0])
        self.assertFalse(verdict["ok"])
        self.assertIn("4bpp", verdict["reason"])

    def test_multi_sub_palette_sheet_is_refused_naming_the_sub_palettes(self):
        """E040: 8bpp but drawn through sub-palettes 0/4/5, so one flat RGBA
        export cannot show it truthfully."""
        verdict = wet.authorable(is_8bpp=True, sub_palettes=[0, 4, 5])
        self.assertFalse(verdict["ok"])
        self.assertIn("sub-palette", verdict["reason"])

    def test_unknown_depth_is_refused_rather_than_assumed(self):
        """E509/E510 have a texture but no frames referencing it, and E040's
        frames disagree on depth; none has an established depth, so refuse
        instead of guessing 8bpp and corrupting them."""
        verdict = wet.authorable(is_8bpp=None, sub_palettes=[])
        self.assertFalse(verdict["ok"])
        self.assertNotEqual(verdict["reason"], "")


class TextureSplice(unittest.TestCase):
    """ADR-0199 decision 4: the write is a wholesale section SPLICE of
    [texture_ptr + 0x404, EOF), mirroring serialize_sound_def — not a field
    patch. Palette bytes and the 4-byte VRAM header are never written here.

    Layout is hand-built independently of the writer's own arithmetic:
      0x0000 .. 0x003F   filler (stands in for the earlier sections)
      0x0040             texture_ptr: palette 1 (512 B)
      0x0240             palette 2 (512 B)
      0x0440             VRAM header (4 B)
      0x0444 .. 0x0453   pixel plane (16 B), running to EOF
    """

    TEX_PTR = 0x40
    PLANE_AT = 0x40 + 0x404
    PLANE_LEN = 16
    TOTAL = 0x40 + 0x404 + 16

    def _buffer(self) -> bytearray:
        return bytearray((i * 7 + 3) & 0xFF for i in range(self.TOTAL))

    def _header(self):
        return {"texture_ptr": self.TEX_PTR}

    def test_splice_replaces_only_the_pixel_plane(self):
        buf = self._buffer()
        before = bytes(buf)
        plane = bytes(range(self.PLANE_LEN))

        ewr.serializer_for("texture")(buf, self._header(), plane)

        self.assertEqual(bytes(buf[self.PLANE_AT:]), plane, "plane replaced")
        self.assertEqual(bytes(buf[:self.PLANE_AT]), before[:self.PLANE_AT],
                         "palettes and the VRAM header are untouched")

    def test_a_resized_plane_is_refused(self):
        """v1 forbids resize; a length mismatch can only mean wrong geometry or
        a dimension change, and must not shift the file."""
        buf = self._buffer()
        with self.assertRaises(ValueError) as ctx:
            ewr.serializer_for("texture")(buf, self._header(), bytes(self.PLANE_LEN + 1))
        self.assertIn("same-size", str(ctx.exception))

    def test_a_missing_texture_section_is_refused(self):
        buf = self._buffer()
        with self.assertRaises(ValueError):
            ewr.serializer_for("texture")(buf, {"texture_ptr": 0}, bytes(self.PLANE_LEN))


_CORPUS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "project-assets", "fft-extract", "EFFECT")


_sheet_facts = wet.sheet_facts


class TextureRoundTripCorpus(unittest.TestCase):
    """The #280 pre-build gate, kept as a permanent guard.

    ADR-0199's green bar: re-importing an UNMODIFIED export is byte-exact for
    every in-scope effect. Byte-exactness for an arbitrary image is unreachable
    (a colour does not identify an index), so this asserts the identity loop —
    section -> RGBA -> index delta -> splice -> the same file back.
    """

    def test_every_in_scope_effect_round_trips_byte_exact(self):
        files = sorted(glob.glob(os.path.join(_CORPUS, "E*.BIN")))
        self.assertGreater(len(files), 400, "corpus not populated — see SETUP.md")

        in_scope, refused, empty, failures = 0, 0, 0, []
        for path in files:
            with open(path, "rb") as fh:
                data = fh.read()
            if len(data) < 0x30:
                empty += 1
                continue
            header, is_8bpp, subs = _sheet_facts(data)
            if not wet.authorable(is_8bpp, subs)["ok"]:
                refused += 1
                continue
            in_scope += 1

            tex_ptr = header["texture_ptr"]
            plane = wet.read_plane(data, tex_ptr)
            clut = wet.read_clut(data, tex_ptr, is_8bpp)
            rgba = wet.decode_to_rgba(list(plane), clut)

            requantized = wet.quantize_to_clut(rgba, clut, list(plane))
            if requantized["off_palette"]:
                failures.append("%s: %d off-palette texels on an untouched sheet"
                                % (os.path.basename(path), requantized["off_palette"]))
                continue

            buf = bytearray(data)
            ewr.serializer_for("texture")(buf, header, bytes(requantized["indices"]))
            if bytes(buf) != data:
                differing = sum(1 for a, b in zip(buf, data) if a != b)
                failures.append("%s: %d bytes differ after an identity round trip"
                                % (os.path.basename(path), differing))

        self.assertEqual(failures, [], "\n".join(failures[:10]))
        self.assertGreaterEqual(in_scope, 338,
                                "ADR-0199 scopes 338 authorable effects; got %d" % in_scope)
        self.assertEqual(in_scope + refused + empty, len(files))

    def test_the_header_dimensions_agree_with_the_plane_that_reaches_eof(self):
        """The Lua extractor derives height from the +0x400 word; the plane also
        simply runs to EOF. All 401 effects have zero slack, so the two must
        agree — a disagreement would mean the exported TGA has the wrong shape."""
        mismatches = []
        for path in sorted(glob.glob(os.path.join(_CORPUS, "E*.BIN"))):
            with open(path, "rb") as fh:
                data = fh.read()
            if len(data) < 0x30:
                continue
            header, is_8bpp, subs = _sheet_facts(data)
            if not wet.authorable(is_8bpp, subs)["ok"]:
                continue
            w, h = wet.texture_dimensions(data, header["texture_ptr"])
            if w * h != len(wet.read_plane(data, header["texture_ptr"])):
                mismatches.append("%s: %dx%d vs %d plane bytes"
                                  % (os.path.basename(path), w, h,
                                     len(wet.read_plane(data, header["texture_ptr"]))))
        self.assertEqual(mismatches, [], "\n".join(mismatches[:10]))


class TgaImportEndToEnd(unittest.TestCase):
    """The whole import path on real files: the studio hands the byte writer a
    .tga path and a base BIN, and gets a patched BIN back.

    `assets/effects/E019/texture.tga` was produced by the Lua extractor, so
    importing it UNMODIFIED must reproduce E019.BIN byte for byte — the identity
    leg of ADR-0199's green bar, end to end rather than in pieces.
    """

    E019_BIN = os.path.join(_CORPUS, "E019.BIN")
    E019_TGA = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "assets", "effects", "E019", "texture.tga")

    def test_importing_the_unmodified_export_reproduces_the_file(self):
        with open(self.E019_BIN, "rb") as fh:
            base = fh.read()

        out = wet.import_tga(base, self.E019_TGA)

        self.assertTrue(out["ok"], out.get("error", ""))
        self.assertEqual(out["bytes"], base, "identity import is byte-exact")
        self.assertEqual(out["off_palette"], 0)

    def test_a_repainted_texel_changes_exactly_one_byte(self):
        """A single-texel edit must not disturb anything else — the proof that
        the index delta really is a delta."""
        with open(self.E019_BIN, "rb") as fh:
            base = fh.read()
        with open(self.E019_TGA, "rb") as fh:
            tga = bytearray(fh.read())

        # Repaint texel 0 with the colour of a DIFFERENT palette entry, chosen
        # from the sheet's own CLUT so it is on-palette by construction.
        header, is_8bpp, _subs = _sheet_facts(base)
        clut = wet.read_clut(base, header["texture_ptr"], is_8bpp)
        plane = wet.read_plane(base, header["texture_ptr"])
        target = next(i for i, w in enumerate(clut)
                      if wet.bgr555_to_rgba(w) != wet.bgr555_to_rgba(clut[plane[0]]))
        r, g, b, a = wet.bgr555_to_rgba(clut[target])
        tga[18], tga[19], tga[20], tga[21] = b, g, r, a

        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".tga", delete=False) as fh:
            fh.write(bytes(tga))
            edited = fh.name
        try:
            out = wet.import_tga(base, edited)
        finally:
            os.unlink(edited)

        self.assertTrue(out["ok"], out.get("error", ""))
        differing = [i for i, (x, y) in enumerate(zip(out["bytes"], base)) if x != y]
        self.assertEqual(len(differing), 1, "exactly one byte moved")
        self.assertEqual(differing[0], header["texture_ptr"] + wet.PLANE_OFFSET,
                         "and it is texel 0 of the pixel plane")

    def test_a_sheet_outside_scope_is_refused_by_the_writer_too(self):
        """The GDScript surface refuses first, but the writer is the gate that
        matters — it must never splice a 4bpp sheet."""
        four_bpp = None
        for path in sorted(glob.glob(os.path.join(_CORPUS, "E*.BIN"))):
            with open(path, "rb") as fh:
                data = fh.read()
            if len(data) < 0x30:
                continue
            _h, is_8bpp, subs = _sheet_facts(data)
            if is_8bpp is False:
                four_bpp = data
                break
        self.assertIsNotNone(four_bpp, "corpus has 4bpp effects")

        out = wet.import_tga(four_bpp, self.E019_TGA)

        self.assertFalse(out["ok"])
        self.assertIn("4bpp", out["error"])


if __name__ == "__main__":
    unittest.main()
