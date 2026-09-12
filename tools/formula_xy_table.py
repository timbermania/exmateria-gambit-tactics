#!/usr/bin/env python3
"""
Formula X/Y Semantic Table Generator for FFT Abilities

Shows what the X and Y parameter bytes actually mean for each ability,
based on the formula ID. The meaning of X and Y changes per formula.

Data source: assets/abilities/ability_attributes.json (368 Normal abilities)
Formula semantics: Derived from PSX disassembly at 0x8018f614 (101 formula function pointers)

Notable corrections from wiki:
  - Formula 0x25 (Break): Wiki says Hit_(PA+WP+X)%, PSX code uses Hit_(SP+X)%
    (shares FUN_80185e30 with Steal formulas 0x26-0x28)

Usage:
  python3 formula_xy_table.py                    # Full table
  python3 formula_xy_table.py --formula 0x25     # Filter by formula
  python3 formula_xy_table.py --unexpected-only  # Show data anomalies
  python3 formula_xy_table.py --format json      # JSON output
"""

import argparse
import csv
import io
import json
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Formula semantics: formula_id -> (formula_name, x_label, y_label)
#
# Sources: PSX dispatch table at 0x8018f614, FFHacktics wiki, disassembly
# Labels: "unused" means the formula function never reads that byte
# Suffixes: NS = Not affected by Sign (Faith), NE = Not affected by Element
# F = affected by Faith, CasF = caster Faith, TarF = target Faith
# --------------------------------------------------------------------------

FORMULA_SEMANTICS = {
    0x00: ("Dmg_(Weapon)",                          "unused",           "unused"),
    0x01: ("Dmg_(Weapon)",                          "unused",           "unused"),
    0x02: ("Dmg_(Weapon) NS",                       "unused",           "unused"),
    0x03: ("Dmg_(WP^2) NS",                         "unused",           "unused"),
    0x04: ("Magic Gun",                              "unused",           "unused"),
    0x05: ("Dmg_(Weapon)",                          "unused",           "unused"),
    0x06: ("AbsHP_(Weapon) NS",                     "unused",           "unused"),
    0x07: ("Heal_(Weapon) NS",                      "unused",           "unused"),
    0x08: ("Dmg_F(MA*Y)",                           "unused",           "damage_multiplier"),
    0x09: ("Dmg_(Y/100)% Hit_F(MA+X)%",            "hit_bonus",        "damage_pct"),
    0x0A: ("Hit_F(MA+X)%",                          "hit_bonus",        "unused"),
    0x0B: ("Hit_F(MA+X)%",                          "hit_bonus",        "unused"),
    0x0C: ("Heal_F(MA*Y) NS",                       "unused",           "heal_multiplier"),
    0x0D: ("Heal_(Y)% Hit_F(MA+X)%",               "hit_bonus",        "heal_pct"),
    0x0E: ("Dmg_(Y)% Hit_F(MA+X)%",                "hit_bonus",        "damage_pct"),
    0x0F: ("AbsMP_(Y)% Hit_F(MA+X)% NS",           "hit_bonus",        "absorb_pct"),
    0x10: ("AbsHP_(Y)% Hit_F(MA+X)% NS",           "hit_bonus",        "absorb_pct"),
    0x11: ("(no-op)",                                "unused",           "unused"),
    0x12: ("Set_Quick Hit_F(MA+X)% NS",             "hit_bonus",        "unused"),
    0x13: ("(no-op)",                                "unused",           "unused"),
    0x14: ("Set_Golem Hit_CasF/100*(MA+X)% NS",    "hit_bonus",        "unused"),
    0x15: ("Set_CT00 Hit_F(MA+X)% NS",             "hit_bonus",        "unused"),
    0x16: ("DmgMP_(TarCurMP) Hit_F(MA+X)% NS",     "hit_bonus",        "unused"),
    0x17: ("Dmg_(TarCurHP-1) Hit_F(MA+X)% NS",     "hit_bonus",        "unused"),
    0x18: ("(no-op)",                                "unused",           "unused"),
    0x19: ("(no-op)",                                "unused",           "unused"),
    0x1A: ("Hit_F(MA+Y)% -PA/MA/SP(X)",            "stat_amount",      "hit_bonus"),
    0x1B: ("DmgMP_(Y)% Hit_F(MA+X)% NS",           "hit_bonus",        "damage_pct"),
    0x1C: ("Hit_(X)% NS",                           "hit_pct",          "unused"),
    0x1D: ("Hit_(X)% NS",                           "hit_pct",          "unused"),
    0x1E: ("Dmg_((MA+Y)*MA/2) #Hit(Rdm(1,X))",    "max_hits",         "damage_bonus"),
    0x1F: ("Dmg_((100-CasF)*(100-TarF)*(MA+Y)*MA/2) #Hit(Rdm(1,X))", "max_hits", "damage_bonus"),
    0x20: ("Dmg_(MA*Y)",                            "unused",           "damage_multiplier"),
    0x21: ("DmgMP_(MA*Y)",                          "unused",           "damage_multiplier"),
    0x22: ("Hit_(100%) Status",                     "unused",           "unused"),
    0x23: ("Heal_(MA*Y) NS",                        "unused",           "heal_multiplier"),
    0x24: ("Dmg_((PA+Y)/2*MA)",                     "unused",           "damage_bonus"),
    0x25: ("Break Hit_(SP+X)% NS",                  "hit_bonus",        "unused"),  # Wiki says PA+WP+X, PSX code uses SP+X
    0x26: ("Steal Hit_(SP+X)%",                     "hit_bonus",        "unused"),
    0x27: ("StealGil_(CasLVL*SP) Hit_(SP+X)% NS",  "hit_bonus",        "unused"),
    0x28: ("StealExp_(min(TarExp,SP+Y)) Hit_(SP+X)%", "hit_bonus",     "steal_cap_bonus"),
    0x29: ("OppositeSex: Hit_(MA+X)%",              "hit_bonus",        "unused"),
    0x2A: ("Hit_(MA+X)% AffectBraveOrFaith(Y)",    "hit_bonus",        "brave_faith_change"),
    0x2B: ("Hit_(PA+Y)% -PA/MA/SP_(X)",            "stat_amount",      "hit_bonus"),
    0x2C: ("DmgMP_(Y)% Hit_(PA+Y)% NS",            "unused(Y_dual)",   "hit_bonus_and_pct"),
    0x2D: ("Dmg_(PA*(WP+Y)) 100% Status",          "unused",           "damage_bonus"),
    0x2E: ("Break Dmg_(PA*WP) NS",                 "unused",           "unused"),
    0x2F: ("AbsMP_(PA*WP) NS",                     "unused",           "unused"),
    0x30: ("AbsHP_(PA*WP) NS",                     "unused",           "unused"),
    0x31: ("Dmg_((PA+Y)/2*PA)",                     "unused",           "damage_bonus"),
    0x32: ("Dmg_(Rdm(1..X)*(PA*3+Y)) NS NE",      "random_max",       "damage_bonus"),
    0x33: ("Hit_(PA+X)%",                           "hit_bonus",        "unused"),
    0x34: ("Heal_(PA*Y) HealMP_(PA*Y/2) NS",       "unused",           "heal_multiplier"),
    0x35: ("Heal_(Y)% Hit_(PA+X)%",                "hit_bonus",        "heal_pct"),
    0x36: ("+PA_(Y) NS",                            "unused",           "stat_bonus"),
    0x37: ("Dmg_(Rdm(1..Y)*PA) NS NE",             "unused",           "random_max"),
    0x38: ("(100%) Status",                         "unused",           "unused"),
    0x39: ("+SP_(Y) NS",                            "unused",           "stat_bonus"),
    0x3A: ("+Brave_(Y) NS",                         "unused",           "stat_bonus"),
    0x3B: ("+Brave_(X) +PA/MA/SP_(Y) NS",          "brave_bonus",      "stat_bonus"),
    0x3C: ("Heal_(CasMaxHP*2/5) DmgCas_(CasMaxHP/5) NS", "unused",    "unused"),
    0x3D: ("Hit_(MA+X)%",                           "hit_bonus",        "unused"),
    0x3E: ("Dmg_(TarCurHP-1) NS",                  "unused",           "unused"),
    0x3F: ("Hit_(SP+X)%",                           "hit_bonus",        "unused"),
    0x40: ("Undead: Hit_(SP+X)%",                   "hit_bonus",        "unused"),
    0x41: ("Hit_(MA+X)%",                           "hit_bonus",        "unused"),
    0x42: ("Dmg_(PA*Y) DmgCas_(PA*Y/X) NS NE",    "self_dmg_divisor", "damage_multiplier"),
    0x43: ("Dmg_(CasMaxHP-CasCurHP) NS",           "unused",           "unused"),
    0x44: ("Dmg_(TarCurMP) NS",                    "unused",           "unused"),
    0x45: ("Dmg_(TarMaxHP-TarCurHP) NS",           "unused",           "unused"),
    0x46: ("(no-op)",                                "unused",           "unused"),
    0x47: ("AbsHP_(Y)% 100% Status",               "unused",           "absorb_pct"),
    0x48: ("Heal_(Z*10)",                           "unused",           "unused"),
    0x49: ("HealMP_(Z*10)",                         "unused",           "unused"),
    0x4A: ("Heal_(100%) HealMP_(100%)",             "unused",           "unused"),
    0x4B: ("Heal_(Rdm(1..9)) 100% Status",         "unused",           "unused"),
    0x4C: ("Heal_(MA*Y) NS",                        "unused",           "heal_multiplier"),
    0x4D: ("AbsHP_(Y)% Hit_(MA+X)% NS",            "hit_bonus",        "absorb_pct"),
    0x4E: ("Dmg_(MA*Y)",                            "unused",           "damage_multiplier"),
    0x4F: ("Dmg_(CasMaxHP-CasCurHP) Hit_(MA+X)% NS", "hit_bonus",     "unused"),
    0x50: ("Hit_(MA+X)% (reduced by Defense UP)",   "hit_bonus",        "unused"),
    0x51: ("Hit_(MA+X)% (Zodiac only)",             "hit_bonus",        "unused"),
    0x52: ("Dmg_(CasMaxHP-CasCurHP) 100% Status NS", "unused",        "unused"),
    0x53: ("Dmg_(Y)% Hit_(MA+X)%",                 "hit_bonus",        "damage_pct"),
    0x54: ("HealMP_(MA*Y) NS",                      "unused",           "heal_multiplier"),
    0x55: ("-PA_(Y) Hit_(MA+X)% NS",               "hit_bonus",        "stat_amount"),
    0x56: ("-MA_(Y) Hit_(MA+X)% NS",               "hit_bonus",        "stat_amount"),
    0x57: ("+Lvl(1) NS 100% Status on Caster",     "unused",           "unused"),
    0x58: ("Set_Morbol Hit_(MA+X)%",                "hit_bonus",        "unused"),
    0x59: ("-Lvl(1) Hit_(MA+X)% NS",               "hit_bonus",        "unused"),
    0x5A: ("Dragon: Hit(100)%",                     "unused",           "unused"),
    0x5B: ("Dragon: Heal_(Y)% 100% Status",        "unused",           "heal_pct"),
    0x5C: ("Dragon: +Brave_(X) +PA/MA/SP(Y) NS",   "brave_bonus",      "stat_bonus"),
    0x5D: ("Dragon: Set_Quick NS",                  "unused",           "unused"),
    0x5E: ("Dmg_((MA+Y)/2*MA) #Hit_(X+1) Status",  "hit_count",        "damage_bonus"),
    0x5F: ("Dmg_((MA+Y)/2*MA)",                     "unused",           "damage_bonus"),
    0x60: ("Dmg_((MA+Y)/2*MA) NE Status",          "unused",           "damage_bonus"),
    0x61: ("-Brave_(Y) Hit_F(MA+X)% NS",           "hit_bonus",        "brave_amount"),
    0x62: ("-Brave_(Y) Hit_(MA+X)% NS",            "hit_bonus",        "brave_amount"),
    0x63: ("Dmg_(SP*WP)",                           "unused",           "unused"),
    0x64: ("Jump Dmg_(PA*WP) NS",                  "unused",           "unused"),
}


def format_value(label, value):
    """Format an X or Y value with its semantic label.

    - unused + 0  -> "-"
    - unused + nonzero -> "UNEXPECTED:N" (data anomaly)
    - meaningful label -> "label=N"
    """
    if label == "unused":
        if value == 0:
            return "-"
        return f"UNEXPECTED:{value}"
    return f"{label}={value}"


def is_unexpected(label, value):
    """Return True if this is an anomalous unused-but-nonzero field."""
    return label == "unused" and value != 0


def load_abilities(data_path):
    """Load ability_attributes.json."""
    with open(data_path, 'r') as f:
        return json.load(f)


def get_semantics(formula_id):
    """Look up formula semantics. Returns (name, x_label, y_label)."""
    if formula_id in FORMULA_SEMANTICS:
        return FORMULA_SEMANTICS[formula_id]
    return (f"Unknown_0x{formula_id:02X}", "unknown", "unknown")


def build_rows(abilities, args):
    """Build table rows from ability data, applying filters."""
    rows = []
    for ab in abilities:
        aid = ab["ability_id"]
        name = ab["name"]
        formula = ab["formula"]
        x = ab["x"]
        y = ab["y"]

        formula_name, x_label, y_label = get_semantics(formula)
        x_display = format_value(x_label, x)
        y_display = format_value(y_label, y)

        # Apply filters
        if args.formula is not None and formula != args.formula:
            continue
        if args.nonzero_only and x == 0 and y == 0:
            continue
        if args.unexpected_only:
            if not (is_unexpected(x_label, x) or is_unexpected(y_label, y)):
                continue

        rows.append({
            "ability_id": aid,
            "name": name,
            "formula_id": formula,
            "formula_name": formula_name,
            "x_value": x,
            "x_meaning": x_display,
            "y_value": y,
            "y_meaning": y_display,
        })

    return rows


def build_summary(abilities):
    """Build formula summary: one row per formula with count and X/Y usage."""
    from collections import Counter, defaultdict

    formula_counts = Counter()
    formula_x_nonzero = Counter()
    formula_y_nonzero = Counter()
    formula_examples = defaultdict(list)

    for ab in abilities:
        fid = ab["formula"]
        formula_counts[fid] += 1
        if ab["x"] != 0:
            formula_x_nonzero[fid] += 1
        if ab["y"] != 0:
            formula_y_nonzero[fid] += 1
        if len(formula_examples[fid]) < 3:
            formula_examples[fid].append(ab["name"])

    rows = []
    for fid in sorted(formula_counts.keys()):
        fname, x_label, y_label = get_semantics(fid)
        rows.append({
            "formula_id": fid,
            "formula_name": fname,
            "count": formula_counts[fid],
            "x_label": x_label,
            "x_nonzero": formula_x_nonzero[fid],
            "y_label": y_label,
            "y_nonzero": formula_y_nonzero[fid],
            "examples": ", ".join(formula_examples[fid]),
        })
    return rows


def output_table(rows, args):
    """Print ASCII table to stdout."""
    if not rows:
        print("No matching abilities found.")
        return

    # Column widths
    id_w = 4
    name_w = max(len(r["name"]) for r in rows)
    name_w = max(name_w, 4)  # min width
    fid_w = 5
    fname_w = max(len(r["formula_name"]) for r in rows)
    fname_w = max(fname_w, 7)
    xm_w = max(len(r["x_meaning"]) for r in rows)
    xm_w = max(xm_w, 9)
    ym_w = max(len(r["y_meaning"]) for r in rows)
    ym_w = max(ym_w, 9)

    # Header
    hdr = (f"{'ID':>{id_w}}  {'Name':<{name_w}}  {'Form':>{fid_w}}  "
           f"{'Formula':<{fname_w}}  {'X Meaning':<{xm_w}}  {'Y Meaning':<{ym_w}}")
    print(hdr)
    print("-" * len(hdr))

    for r in rows:
        print(f"{r['ability_id']:>{id_w}}  {r['name']:<{name_w}}  "
              f"0x{r['formula_id']:02X}  "
              f"{r['formula_name']:<{fname_w}}  "
              f"{r['x_meaning']:<{xm_w}}  {r['y_meaning']:<{ym_w}}")

    print(f"\n{len(rows)} abilities shown")


def output_summary_table(rows):
    """Print formula summary ASCII table."""
    if not rows:
        print("No formulas found.")
        return

    fid_w = 5
    fname_w = max(len(r["formula_name"]) for r in rows)
    fname_w = max(fname_w, 7)
    xl_w = max(len(r["x_label"]) for r in rows)
    xl_w = max(xl_w, 7)
    yl_w = max(len(r["y_label"]) for r in rows)
    yl_w = max(yl_w, 7)
    ex_w = max(len(r["examples"]) for r in rows)
    ex_w = max(ex_w, 8)

    hdr = (f"{'Form':>{fid_w}}  {'Formula':<{fname_w}}  {'Cnt':>3}  "
           f"{'X Label':<{xl_w}}  {'X#':>2}  {'Y Label':<{yl_w}}  {'Y#':>2}  "
           f"{'Examples':<{ex_w}}")
    print(hdr)
    print("-" * len(hdr))

    for r in rows:
        print(f"0x{r['formula_id']:02X}  {r['formula_name']:<{fname_w}}  "
              f"{r['count']:>3}  "
              f"{r['x_label']:<{xl_w}}  {r['x_nonzero']:>2}  "
              f"{r['y_label']:<{yl_w}}  {r['y_nonzero']:>2}  "
              f"{r['examples']:<{ex_w}}")

    total = sum(r["count"] for r in rows)
    print(f"\n{len(rows)} formulas, {total} abilities total")


def output_csv(rows):
    """Print CSV to stdout."""
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=[
        "ability_id", "name", "formula_id", "formula_name",
        "x_value", "x_meaning", "y_value", "y_meaning",
    ])
    writer.writeheader()
    writer.writerows(rows)
    print(buf.getvalue(), end="")


def output_json(rows, output_path):
    """Write JSON file."""
    with open(output_path, 'w') as f:
        json.dump(rows, f, indent=2)
    print(f"Wrote {len(rows)} entries to {output_path}", file=sys.stderr)


def parse_int(s):
    """Parse int from decimal or hex string."""
    s = s.strip()
    if s.startswith("0x") or s.startswith("0X"):
        return int(s, 16)
    return int(s)


def main():
    default_data = (Path(__file__).parent.parent / "assets" / "abilities"
                    / "ability_attributes.json")
    default_json_out = Path(__file__).parent / "extracted" / "formula_xy_table.json"

    parser = argparse.ArgumentParser(
        description="Show what X and Y parameters mean for each FFT ability formula")
    parser.add_argument("--data", type=Path, default=default_data,
                        help=f"Path to ability_attributes.json (default: {default_data})")
    parser.add_argument("--format", choices=["table", "csv", "json"], default="table",
                        help="Output format (default: table)")
    parser.add_argument("--output", type=Path, default=default_json_out,
                        help="JSON output path (only used with --format json)")
    parser.add_argument("--formula", type=parse_int, default=None,
                        help="Filter by formula ID (decimal or 0x hex)")
    parser.add_argument("--nonzero-only", action="store_true",
                        help="Only show abilities where X or Y is nonzero")
    parser.add_argument("--unexpected-only", action="store_true",
                        help="Only show abilities with nonzero values in 'unused' fields")
    parser.add_argument("--formula-summary", action="store_true",
                        help="Show one row per formula with counts instead of per-ability")

    args = parser.parse_args()

    if not args.data.exists():
        print(f"Error: Data file not found: {args.data}", file=sys.stderr)
        print("Run dump_ability_data.py first to generate ability_attributes.json",
              file=sys.stderr)
        return 1

    abilities = load_abilities(args.data)

    if args.formula_summary:
        summary = build_summary(abilities)
        output_summary_table(summary)
        return 0

    rows = build_rows(abilities, args)

    if args.format == "table":
        output_table(rows, args)
    elif args.format == "csv":
        output_csv(rows)
    elif args.format == "json":
        output_json(rows, args.output)

    return 0


if __name__ == "__main__":
    sys.exit(main())
