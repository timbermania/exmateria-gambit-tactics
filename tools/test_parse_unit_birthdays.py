"""Tests for tools/parse_unit_birthdays.py.

FFT stores no zodiac byte — the sign is derived from the birthday (ENTD slot bytes
4/5). This extractor lifts a special_name -> [month, day] table out of the committed
entd.json so the formation info panel can show a unique's REAL zodiac. The load-
bearing behaviours: first CONCRETE birthday wins, the Random/None/unset sentinels are
skipped, and the reserved special_names (0 generic, 255 empty) never key.

Run:  cd tools && uv run python -m unittest test_parse_unit_birthdays
"""
import json
import unittest
from pathlib import Path

import parse_unit_birthdays as b

HERE = Path(__file__).resolve().parent


def _slot(special_name, month, day):
    return {"special_name": special_name, "month": month, "day": day}


def _entd(*records):
    return {"records": {str(i): {"slots": list(r)} for i, r in enumerate(records)}}


class BuildTable(unittest.TestCase):
    def test_first_concrete_birthday_wins(self):
        # Same special_name twice: the first CONCRETE reading is kept.
        table = b.build_table(_entd([_slot(52, 6, 22)], [_slot(52, 1, 1)]))
        self.assertEqual(table["52"], [6, 22])

    def test_random_and_none_are_skipped(self):
        # A Random(254)/None(255)/unset(0) month carries no fixed sign — the first
        # CONCRETE reading that follows is the one that lands.
        table = b.build_table(_entd(
            [_slot(30, b._MONTH_RANDOM, 254)],
            [_slot(30, b._MONTH_NONE, 0)],
            [_slot(30, b._MONTH_UNSET, 0)],
            [_slot(30, 3, 18)],
        ))
        self.assertEqual(table["30"], [3, 18])

    def test_all_random_special_is_absent(self):
        # A special_name that is Random in every appearance never keys (the loader
        # then falls back to the unit's default zodiac).
        table = b.build_table(_entd([_slot(77, b._MONTH_RANDOM, 254)]))
        self.assertNotIn("77", table)

    def test_reserved_special_names_never_key(self):
        table = b.build_table(_entd([
            _slot(b._SPECIAL_GENERIC, 6, 22),
            _slot(b._SPECIAL_EMPTY, 6, 22),
        ]))
        self.assertEqual(table, {})

    def test_out_of_range_month_skipped(self):
        table = b.build_table(_entd([_slot(88, 13, 1)], [_slot(88, 0, 1)]))
        self.assertNotIn("88", table)


class RealAssetOracle(unittest.TestCase):
    """The committed table must carry the known ROM birthdays that anchor the
    zodiac derivation (the info-panel oracle values)."""

    @classmethod
    def setUpClass(cls):
        src = HERE.parent / "assets" / "scenarios" / "entd.json"
        cls.table = b.build_table(json.loads(src.read_text(encoding="utf-8")))

    def test_known_unique_birthdays(self):
        # Ramza2 12/30 (→ Capricorn, the FormationInfoPanelView oracle), Agrias
        # 6/22 (→ Cancer), Delita 3/18 (→ Pisces).
        self.assertEqual(self.table["2"], [12, 30])
        self.assertEqual(self.table["52"], [6, 22])
        self.assertEqual(self.table["19"], [3, 18])


class CommittedFileIsFresh(unittest.TestCase):
    def test_committed_matches_source(self):
        import subprocess
        import sys
        r = subprocess.run(
            [sys.executable, str(HERE / "parse_unit_birthdays.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
