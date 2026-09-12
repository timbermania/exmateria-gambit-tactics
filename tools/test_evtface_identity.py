#!/usr/bin/env python3
"""Guard for the EVTFACE `(row,col) -> identity` derivation (dialogue-name method).

Replays a miniature event corpus and asserts each portrait cell is bound to the
speaker named in its message header, that the speaker's-own-portrait path
(`Portrait=0`) is NOT attributed to a grid cell, and that scene-local speaker
bytes do not fracture a cell's stable text-derived identity.

Run:  uv run python -m unittest test_evtface_identity
"""

from __future__ import annotations

import unittest

import evtface_identity as ei


def _msg(dialog, portrait, unit, text, speaker_byte=None):
    return {
        "opcode": ei.OP_DISPLAY_MESSAGE,
        "params": [{"name": "Dialog", "value": dialog},
                   {"name": "Portrait", "value": portrait},
                   {"name": "Unit", "value": unit}],
        "dialogue": {"raw_text": text,
                     "speaker_unit_byte": speaker_byte if speaker_byte is not None else unit},
    }


def _row(r):
    return {"opcode": ei.OP_PORTRAIT_ROW, "params": [{"name": "Row", "value": r}]}


def _chunk(*insts):
    return {"instructions": list(insts)}


class ExtractNameTest(unittest.TestCase):
    def test_header_name(self):
        self.assertEqual(
            ei.extract_speaker_name("{Color 08}Balbanes{Newline}{Color 00}How goes?"),
            "Balbanes")

    def test_name_variable_stripped(self):
        self.assertEqual(
            ei.extract_speaker_name("{Color 08}{Ramza}{Newline}{Color 00}Father!"),
            "Ramza")

    def test_multiword_name(self):
        self.assertEqual(
            ei.extract_speaker_name("{Color 08}Flower Girl{Newline}{Color 00}..."),
            "Flower Girl")

    def test_no_header_is_none(self):
        self.assertIsNone(ei.extract_speaker_name("{Delay 05}plain narration"))
        self.assertIsNone(ei.extract_speaker_name(""))


class DeriveTest(unittest.TestCase):
    def _derive(self, chunks):
        return ei.derive_evtface_identities(
            {sid: (lambda c=c: c) for sid, c in chunks.items()})

    def test_cell_bound_to_header_speaker(self):
        # {50} row 0, message with Portrait=1 -> cell (0,0), EVTFACE mode 0x10.
        t = self._derive({"014": _chunk(
            _row(0),
            _msg(0x10, 1, 128, "{Color 08}Balbanes{Newline}{Color 00}...", 128))})
        self.assertEqual(t["0_0"]["identity"], "Balbanes")
        self.assertEqual(t["0_0"]["row"], 0)
        self.assertEqual(t["0_0"]["col"], 0)

    def test_portrait_zero_is_not_a_grid_cell(self):
        # Portrait=0 -> speaker's own unit-sheet portrait, no EVTFACE cell.
        t = self._derive({"014": _chunk(
            _row(0),
            _msg(0x10, 0, 8, "{Color 08}Zalbag{Newline}{Color 00}...", 8))})
        self.assertEqual(t, {})

    def test_non_evtface_dialog_skipped(self):
        # bit-4 clear -> not an EVTFACE portrait message.
        t = self._derive({"099": _chunk(
            _row(2),
            _msg(0x03, 1, 5, "{Color 08}Ramza{Newline}{Color 00}...", 5))})
        self.assertEqual(t, {})

    def test_bit4_set_with_extra_mode_bits_still_captured(self):
        # Elidibs (scn112, cell (3,6)) carries Dialog=0x70 (bits 4/5/6). The gate
        # is bit 4, not the exact value 0x10, so the portrait IS attributed.
        t = self._derive({"112": _chunk(
            _row(3),
            _msg(0x70, 7, 128, "{Color 08}Elidibs{Newline}{Color 00}Who...", 128))})
        self.assertEqual(t["3_6"]["identity"], "Elidibs")

    def test_stable_identity_across_scene_local_speaker_bytes(self):
        # Same cell, same text name, DIFFERENT ENTD speaker bytes across scenes
        # (the reason the old ENTD-unit axis was wrong) -> one stable identity.
        t = self._derive({
            "052": _chunk(_row(1),
                          _msg(0x10, 3, 2, "{Color 08}Mustadio{Newline}{Color 00}a", 130)),
            "053": _chunk(_row(1),
                          _msg(0x10, 3, 4, "{Color 08}Mustadio{Newline}{Color 00}b", 129)),
        })
        self.assertEqual(t["1_2"]["identity"], "Mustadio")
        self.assertEqual(t["1_2"]["occurrences"], 2)
        self.assertEqual(t["1_2"]["speaker_bytes"], {"130": 1, "129": 1})

    def test_honorific_folds_to_most_frequent_canonical(self):
        t = self._derive({"010": _chunk(
            _row(2),
            _msg(0x10, 2, 9, "{Color 08}Gelwan{Newline}{Color 00}a", 131),
            _msg(0x10, 2, 9, "{Color 08}Gelwan{Newline}{Color 00}b", 131),
            _msg(0x10, 2, 9, "{Color 08}Minister Gelwan{Newline}{Color 00}c", 131))})
        self.assertEqual(t["2_1"]["identity"], "Gelwan")
        self.assertEqual(t["2_1"]["aliases"], ["Minister Gelwan"])

    def test_portrait_row_gates_col_range(self):
        # Portrait must be in [1,8]; a stray high byte is not a grid column.
        t = self._derive({"001": _chunk(
            _row(0),
            _msg(0x10, 9, 1, "{Color 08}Nobody{Newline}{Color 00}...", 1))})
        self.assertEqual(t, {})


class AttributionTest(unittest.TestCase):
    UNIT_NAMES = {"12": "Ovelia", "22": "Mustadio", "33": "Balbanes"}
    RESIDUE = {"12": "ovelia_12", "22": "mustadio_22"}  # note: no token for 33

    def test_name_to_token_only_tokened_identities(self):
        n2t = ei.build_name_to_token(self.UNIT_NAMES, self.RESIDUE)
        self.assertEqual(n2t, {"Ovelia": "ovelia_12", "Mustadio": "mustadio_22"})
        self.assertNotIn("Balbanes", n2t)  # SPR-less -> no token

    def test_attributions_split_tokened_vs_skipped(self):
        table = {
            "1_1": {"row": 1, "col": 1, "identity": "Ovelia"},
            "1_2": {"row": 1, "col": 2, "identity": "Mustadio"},
            "0_0": {"row": 0, "col": 0, "identity": "Balbanes"},   # SPR-less -> skip
            "6_2": {"row": 6, "col": 2, "identity": "Bar Patron"},  # generic -> skip
        }
        n2t = ei.build_name_to_token(self.UNIT_NAMES, self.RESIDUE)
        attributed, skipped = ei.face_attributions(table, n2t)
        self.assertEqual(attributed, {"ovelia_12": [(1, 1)],
                                      "mustadio_22": [(1, 2)]})
        self.assertEqual(skipped, {"Balbanes": [(0, 0)], "Bar Patron": [(6, 2)]})

    def test_same_identity_multiple_cells_grouped(self):
        table = {
            "4_1": {"row": 4, "col": 1, "identity": "Izlude"},
            "7_1": {"row": 7, "col": 1, "identity": "Izlude"},
            "4_2": {"row": 4, "col": 2, "identity": "Izlude"},
        }
        n2t = {"Izlude": "izlude_38"}
        attributed, _ = ei.face_attributions(table, n2t)
        self.assertEqual(attributed, {"izlude_38": [(4, 1), (4, 2), (7, 1)]})


if __name__ == "__main__":
    unittest.main()
