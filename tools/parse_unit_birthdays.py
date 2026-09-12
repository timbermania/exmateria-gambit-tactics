#!/usr/bin/env python3
"""Extract a special_name -> birthday (month, day) table the game loads to show a
unique's REAL zodiac in the formation info panel (UnitBirthdays.gd, §14.6).

FFT stores no zodiac byte: the sign is DERIVED from a unit's birthday. The birthday
lives per-ENTD-slot (bytes 4/5), so a unit built from a raw ENTD slot already has it
(Character.from_entd_slot reads it directly). But the formation "show all templates"
catalogue view mints its uniques from the TEMPLATE store, which carries no birthday —
so it needs a compact special_name -> (month, day) lookup. This is that table.

Source of truth: the committed assets/scenarios/entd.json (the extracted deployment
tables). We scan every slot and, per special_name, keep the FIRST concrete birthday
(month 1..12). Sentinels — month 0 (unset), 254 (Random, the game rolls it at
recruit), 255 (None) — carry no fixed sign and are skipped, so a special_name that is
Random in every appearance is intentionally absent (the loader falls back to the
unit's default zodiac). special_name 0 (generic) and 255 (empty slot) are never keyed.

Emits addons/exmateria_catalogue/identity/unit_birthdays.json keyed by DECIMAL special_name string, each
value a [month, day] pair, e.g. {"52": [6, 22], "2": [12, 30], ...}.

Run:  uv run python tools/parse_unit_birthdays.py           # write
      uv run python tools/parse_unit_birthdays.py --check    # verify committed file
"""
import json
import sys
from pathlib import Path

from _repo_paths import catalogue_dir

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "assets" / "scenarios" / "entd.json"
OUT = catalogue_dir("identity/unit_birthdays.json")   # ADR-0251 dec. 2, #1025 pass 3

# ENTD birthday sentinels (parse_entd.py / FFTPatcher Months.cs): no fixed sign.
_MONTH_UNSET = 0
_MONTH_RANDOM = 254
_MONTH_NONE = 255
# special_name reserved values: 0 = generic (no story identity), 255 = empty slot.
_SPECIAL_GENERIC = 0
_SPECIAL_EMPTY = 255


def build_table(entd: dict) -> dict[str, list[int]]:
    """special_name (decimal str) -> [month, day], first concrete birthday wins.

    Deterministic in ENTD record/slot order so re-running is byte-stable.
    """
    out: dict[str, list[int]] = {}
    for _rk, rec in sorted(entd["records"].items(), key=lambda kv: int(kv[0])):
        for slot in rec.get("slots", []):
            sn = slot.get("special_name")
            month = slot.get("month")
            day = slot.get("day")
            if sn is None or sn in (_SPECIAL_GENERIC, _SPECIAL_EMPTY):
                continue
            if not (isinstance(month, int) and 1 <= month <= 12):
                continue  # Unset / Random / None → no fixed sign
            key = str(sn)
            if key not in out:
                out[key] = [month, int(day)]
    return out


def build() -> dict:
    entd = json.loads(SRC.read_text(encoding="utf-8"))
    birthdays = build_table(entd)
    return {
        "_source": "assets/scenarios/entd.json (ENTD slot bytes 4/5)",
        "_comment": (
            "special_name (ENTD, decimal) -> [month, day] birthday. FFT derives "
            "the zodiac sign from the birthday (UnitProgression.zodiac_from_birthday); "
            "this feeds the formation info-panel glyph for uniques minted from the "
            "template store (which carries no birthday). First concrete (non-Random) "
            "birthday per special_name. Regenerate: uv run python "
            "tools/parse_unit_birthdays.py"
        ),
        "birthdays": birthdays,
    }


def main() -> int:
    data = build()
    text = json.dumps(data, indent=1, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            print(f"STALE: {OUT} differs from entd.json. "
                  f"Run: uv run python tools/parse_unit_birthdays.py")
            return 1
        print(f"OK: {OUT.name} up to date ({len(data['birthdays'])} birthdays)")
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT} ({len(data['birthdays'])} birthdays)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
