#!/usr/bin/env python3
"""
Ability Semantics Annotation Generator for FFT

Auto-generates human-readable descriptions of what each ability DOES in gameplay
terms ("Breaks target's helmet equipment slot") from ability_attributes.json +
formula semantics. ~85% of abilities are auto-derivable; the rest are marked for
manual annotation.

Separate from formula_xy_table.py (which answers "what do X/Y mean?").

Data sources:
  - assets/abilities/ability_attributes.json (368 Normal abilities), the third
    output of tools/parse_abilities.py
  - Formula dispatch table at PTR_FUN_8018f614 in BATTLE.BIN (101 x 4-byte pointers)
  - FORMULA_SEMANTICS from formula_xy_table.py

Usage:
  python3 seed_ability_semantics.py                    # Generate ability_semantics.json
  python3 seed_ability_semantics.py --stats            # Show derivation statistics
  python3 seed_ability_semantics.py --manual-only      # Show abilities needing manual work
  python3 seed_ability_semantics.py --format table     # Table format to stdout
"""

import argparse
import json
import sys
from pathlib import Path

# Import FORMULA_SEMANTICS from sibling script
sys.path.insert(0, str(Path(__file__).parent))
from formula_xy_table import FORMULA_SEMANTICS

# ---------------------------------------------------------------------------
# Formula dispatch table: formula_id -> function address
# Parsed from disassembly of PTR_FUN_8018f614 in BATTLE.BIN
# (101 entries at 0x8018f614..0x8018f7a0)
# ---------------------------------------------------------------------------

FORMULA_DISPATCH = {
    0x00: 0x80188B64, 0x01: 0x80188BA4, 0x02: 0x80188BE4, 0x03: 0x80188C24,
    0x04: 0x80188C9C, 0x05: 0x80188CF4, 0x06: 0x80188D3C, 0x07: 0x80188D84,
    0x08: 0x80188DF4, 0x09: 0x80188E78, 0x0A: 0x80188EB8, 0x0B: 0x80188EF8,
    0x0C: 0x80188F38, 0x0D: 0x80188F90, 0x0E: 0x80189084, 0x0F: 0x801890DC,
    0x10: 0x80189124, 0x11: 0x8018912C, 0x12: 0x80189164, 0x13: 0x8018916C,
    0x14: 0x801891AC, 0x15: 0x80189204, 0x16: 0x8018925C, 0x17: 0x8018929C,
    0x18: 0x801892A4, 0x19: 0x801892AC, 0x1A: 0x8018933C, 0x1B: 0x8018937C,
    0x1C: 0x801893D8, 0x1D: 0x80189434, 0x1E: 0x80189464, 0x1F: 0x801895C4,
    0x20: 0x801895F4, 0x21: 0x80189654, 0x22: 0x8018967C, 0x23: 0x801896B4,
    0x24: 0x801896EC, 0x25: 0x80189794, 0x26: 0x80189828, 0x27: 0x80189870,
    0x28: 0x80189910, 0x29: 0x801899A4, 0x2A: 0x80189A90, 0x2B: 0x80189AD8,
    0x2C: 0x80189B20, 0x2D: 0x80189B94, 0x2E: 0x80189C50, 0x2F: 0x80189C90,
    0x30: 0x80189CD0, 0x31: 0x80189D74, 0x32: 0x80189E28, 0x33: 0x80189E94,
    0x34: 0x80189F08, 0x35: 0x801868F0, 0x36: 0x80189F84, 0x37: 0x80187F24,
    0x38: 0x80186D2C, 0x39: 0x80186D00, 0x3A: 0x80186D58, 0x3B: 0x80186DBC,
    0x3C: 0x80189FCC, 0x3D: 0x8018A00C, 0x3E: 0x8018A02C, 0x3F: 0x8018A088,
    0x40: 0x8018A114, 0x41: 0x8018A17C, 0x42: 0x80186E28, 0x43: 0x80186E54,
    0x44: 0x80186E78, 0x45: 0x8018A218, 0x46: 0x8018A220, 0x47: 0x8018A250,
    0x48: 0x80188288, 0x49: 0x8018A2C4, 0x4A: 0x8018A2EC, 0x4B: 0x8018A3A0,
    0x4C: 0x8018A3D0, 0x4D: 0x8018A420, 0x4E: 0x8018A458, 0x4F: 0x8018A4A0,
    0x50: 0x8018A4E8, 0x51: 0x8018A554, 0x52: 0x8018A5E4, 0x53: 0x8018A668,
    0x54: 0x8018A698, 0x55: 0x8018A6F8, 0x56: 0x8018A758, 0x57: 0x8018A824,
    0x58: 0x8018A908, 0x59: 0x8018A980, 0x5A: 0x8018A9C4, 0x5B: 0x8018AA10,
    0x5C: 0x8018AA54, 0x5D: 0x8018AA98, 0x5E: 0x8018AAC8, 0x5F: 0x8018AAF8,
    0x60: 0x8018AB18, 0x61: 0x8018AB58, 0x62: 0x8018AB98, 0x63: 0x8018AC44,
    0x64: 0x8018AC44,  # Jump shares handler with 0x63
}

# ---------------------------------------------------------------------------
# Inflict status sets: loaded from the decoded BATTLE.BIN `InflictStatusList`
# table (SCUS RAM 0x80063FC4 — see godot-learning/tools/_fft_decode.py
# `extract_inflict_status_sets`). Ghidra-authoritative; the previous hand-coded
# dict (32:"Raise", 41:"Death+Stop+DontMove+DontAct", etc.) had bugs — set 41
# is just `All + Dead`, the compound was a guess.
# ---------------------------------------------------------------------------

INFLICT_SETS_ARTIFACT = (
    Path(__file__).resolve().parent / "extracted" / "inflict_status_sets.json"
)


def _load_inflict_sets() -> dict[int, dict]:
    """Read the decoded inflict-set artifact emitted by godot-learning's
    `extract_inflict_status_sets.py`. Returns {set_id: {mode, statuses, ...}}.
    """
    with open(INFLICT_SETS_ARTIFACT) as f:
        artifact = json.load(f)
    return {int(k): v for k, v in artifact["sets"].items()}


INFLICT_SETS = _load_inflict_sets()

# FFTPatcher status names considered buffs (positive statuses).
# Used to recategorise a set as buff-application when all listed statuses are
# in this set AND the set's mode != "cancel".
_BUFF_STATUS_NAMES = {
    "Regen", "Protect", "Shell", "Haste", "Float", "Reraise",
    "Transparent", "Reflect", "Faith",
}


def is_buff_status(set_id: int) -> bool:
    """Return True if `set_id` applies only buff statuses (mode != cancel)."""
    s = INFLICT_SETS.get(set_id)
    if not s or not s["statuses"] or s["mode"] == "cancel":
        return False
    return all(name in _BUFF_STATUS_NAMES for name in s["statuses"])

# ---------------------------------------------------------------------------
# Break/Steal slot derivation from ability name
# Matches assembly hardcoding in FUN_801879c8
# ---------------------------------------------------------------------------

EQUIP_SLOT_KEYWORDS = {
    "Head": "helmet", "Helm": "helmet",
    "Armor": "armor",
    "Shield": "shield",
    "Weapon": "weapon",
    "Accessry": "accessory", "Access": "accessory",
}

# ---------------------------------------------------------------------------
# Stat keywords for stat-reduce/stat-boost formulas
# ---------------------------------------------------------------------------

STAT_FROM_NAME = {
    "Speed": "Speed", "Magic": "MA", "Power": "PA", "Mind": "MA",
}

# Stat by formula_id for specific stat formulas
STAT_BY_FORMULA = {
    0x36: "PA",
    0x39: "Speed",
    0x55: "PA",
    0x56: "MA",
}

# ---------------------------------------------------------------------------
# Element names
# ---------------------------------------------------------------------------

ELEMENT_NAMES = {
    1: "Dark", 2: "Holy", 4: "Water", 8: "Wind",
    16: "Earth", 32: "Lightning", 64: "Ice", 128: "Fire",
}

# ---------------------------------------------------------------------------
# Special formula hardcoded descriptions
# ---------------------------------------------------------------------------

SPECIAL_FORMULAS = {
    0x12: ("Grants Quick status (extra turn)", "special"),
    0x14: ("Summons Golem to absorb physical damage for allies", "special"),
    0x15: ("Resets target's CT to 0", "special"),
    0x16: ("Deals damage equal to target's current MP", "damage_magic"),
    0x17: ("Reduces target to 1 HP", "damage_magic"),
    0x22: ("Applies status with 100% hit rate", "status_inflict"),
    0x29: ("Charms opposite-sex target", "status_inflict"),
    0x2A: ("Modifies target's Brave or Faith", "special"),
    0x2D: ("Deals physical damage and inflicts status (100% hit)", "damage_physical"),
    0x2F: ("Absorbs MP equal to PA*WP", "absorb_mp"),
    0x30: ("Absorbs HP equal to PA*WP", "absorb_hp"),
    0x32: ("Deals random non-elemental physical damage", "damage_physical"),
    0x37: ("Deals random non-elemental physical damage (PA-based)", "damage_physical"),
    0x38: ("Applies status with 100% hit rate", "status_inflict"),
    0x3C: ("Heals allies for 40% of caster's max HP, costs caster 20% max HP", "heal_hp"),
    0x3E: ("Reduces target to 1 HP (100% hit)", "damage_magic"),
    0x43: ("Deals damage equal to caster's lost HP", "damage_physical"),
    0x44: ("Deals damage equal to target's current MP", "damage_magic"),
    0x45: ("Deals damage equal to target's missing HP", "damage_magic"),
    0x48: ("Heals HP based on crystal count", "heal_hp"),
    0x49: ("Heals MP based on crystal count", "heal_mp"),
    0x4A: ("Fully heals HP and MP", "heal_both"),
    0x4B: ("Heals random HP (1-9) and applies status", "heal_hp"),
    0x4F: ("Deals damage equal to caster's lost HP", "damage_magic"),
    0x50: ("Inflicts status (reduced by Defense UP)", "status_inflict"),
    0x51: ("Inflicts status (Zodiac compatibility only)", "status_inflict"),
    0x52: ("Deals damage equal to caster's lost HP and inflicts status", "damage_magic"),
    0x57: ("Gains 1 level and applies status to caster", "special"),
    0x58: ("Inflicts Morbol status set", "status_inflict"),
    0x59: ("Reduces target's level by 1", "special"),
    0x5A: ("Targets dragons with 100% hit rate", "special"),
    0x5B: ("Heals HP and applies status to dragons", "heal_hp"),
    0x5C: ("Increases Brave and stats (dragon target)", "stat_boost"),
    0x5D: ("Grants Quick status to dragon", "special"),
    0x63: ("Deals damage based on Speed*WP", "damage_physical"),
    0x64: ("Deals jump damage (PA*WP)", "damage_physical"),
}

# No-op formulas
NOOP_FORMULAS = {0x11, 0x13, 0x18, 0x19, 0x46}

# Weapon-based physical damage formulas
WEAPON_DAMAGE_FORMULAS = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05}
WEAPON_ABSORB_FORMULA = 0x06
WEAPON_HEAL_FORMULA = 0x07

# Heal formulas (MA-based)
HEAL_MA_FORMULAS = {0x0C, 0x23, 0x4C}
# Heal formulas (percentage)
HEAL_PCT_FORMULAS = {0x0D, 0x35}
# Heal HP+MP formula
HEAL_BOTH_FORMULA = 0x34
# Heal MP formula
HEAL_MP_FORMULA = 0x54

# Break formula
BREAK_FORMULA = 0x25
# Break + damage formula
BREAK_DAMAGE_FORMULA = 0x2E

# Steal formulas
STEAL_EQUIP_FORMULA = 0x26
STEAL_GIL_FORMULA = 0x27
STEAL_EXP_FORMULA = 0x28

# Absorb formulas
ABSORB_FORMULAS = {0x0F: "MP", 0x10: "HP", 0x47: "HP", 0x4D: "HP"}

# Stat boost formulas
STAT_BOOST_FORMULAS = {0x36, 0x39, 0x3A, 0x3B}

# Stat reduce formulas
STAT_REDUCE_FORMULAS = {0x1A, 0x2B, 0x55, 0x56}

# MP damage formula
DAMAGE_MP_FORMULA = 0x21

# Self-damage trade formula
SELF_DAMAGE_FORMULA = 0x42

# Damage formulas (MA-based)
DAMAGE_MA_FORMULAS = {0x08, 0x20, 0x4E, 0x24, 0x31, 0x1E, 0x1F, 0x5E, 0x5F, 0x60}

# Damage percentage formulas
DAMAGE_PCT_FORMULAS = {0x09, 0x0E, 0x1B, 0x2C, 0x53}

# Hit-only formulas (status application)
HIT_ONLY_FORMULAS = {0x0A, 0x0B, 0x1C, 0x1D, 0x33, 0x3D, 0x3F, 0x40, 0x41, 0x61, 0x62}

# Brave modify
BRAVE_MODIFY_FORMULAS = {0x61, 0x62}


def get_element_str(elements):
    """Get element string from list of element names."""
    if not elements:
        return ""
    return "/".join(elements)


def derive_equip_slot(name):
    """Derive equipment slot from ability name keywords."""
    for keyword, slot in EQUIP_SLOT_KEYWORDS.items():
        if keyword.lower() in name.lower():
            return slot
    return None


def derive_stat_from_name(name):
    """Derive stat from ability name keywords."""
    for keyword, stat in STAT_FROM_NAME.items():
        if keyword.lower() in name.lower():
            return stat
    return None


def get_status_desc(inflict_status: int) -> str | None:
    """Get a human-readable description from a decoded inflict-set entry.

    Returns formats like:
      - "Poison"                       (single status, mode=all)
      - "Shell+Protect"                (compound, mode=all)
      - "Dispel (cancel Reraise+...)"  (cancel mode)
      - "Random: Sleep/Slow/..."       (random mode)
    """
    s = INFLICT_SETS.get(inflict_status)
    if not s or not s["statuses"]:
        return None
    mode = s["mode"]
    names = s["statuses"]
    joined = "+".join(names)
    if mode == "all" or mode is None:
        return joined
    if mode == "cancel":
        return f"Cancel {joined}"
    if mode == "random":
        return f"Random({'/'.join(names)})"
    if mode == "separate":
        return f"Separate({'/'.join(names)})"
    return joined


def get_code_ref(formula_id):
    """Get code reference string for a formula."""
    if formula_id in FORMULA_DISPATCH:
        addr = FORMULA_DISPATCH[formula_id]
        return f"FUN_{addr:08X}:0x{addr:08X}"
    return ""


def derive_semantics(ab):
    """Derive semantic_effect and semantic_category for an ability.

    Returns (semantic_effect, semantic_category, derivation).
    """
    fid = ab["formula"]
    name = ab["name"]
    x = ab["x"]
    y = ab["y"]
    inflict = ab["inflict_status"]
    elements = ab.get("elements", [])
    elem_str = get_element_str(elements)

    # Get formula name from FORMULA_SEMANTICS
    if fid in FORMULA_SEMANTICS:
        formula_name = FORMULA_SEMANTICS[fid][0]
    else:
        formula_name = f"Unknown_0x{fid:02X}"

    # Rule 1: No-op formulas
    if fid in NOOP_FORMULAS:
        return "No effect (unused formula)", "noop", "auto"

    # Rule 17: Special formulas with hardcoded descriptions
    if fid in SPECIAL_FORMULAS and inflict == 0:
        desc, cat = SPECIAL_FORMULAS[fid]
        return desc, cat, "auto"

    # Rule 2: Weapon-based physical damage
    if fid in WEAPON_DAMAGE_FORMULAS:
        base = "Deals weapon-based physical damage"
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"{base} and inflicts {status}", "damage_physical", "auto"
        if inflict:
            return f"{base} and inflicts status (set {inflict})", "damage_physical", "auto"
        return base, "damage_physical", "auto"

    # Weapon absorb
    if fid == WEAPON_ABSORB_FORMULA:
        return "Absorbs HP based on weapon damage", "absorb_hp", "auto"

    # Weapon heal
    if fid == WEAPON_HEAL_FORMULA:
        return "Heals HP based on weapon damage", "heal_hp", "auto"

    # Rule 3: MA-based heal
    if fid in HEAL_MA_FORMULAS:
        return f"Heals HP (MA*{y})", "heal_hp", "auto"

    # Rule 4: Heal HP+MP
    if fid == HEAL_BOTH_FORMULA:
        return f"Heals HP (PA*{y}) and MP (PA*{y}/2)", "heal_both", "auto"

    # Rule 5: Percentage heal
    if fid in HEAL_PCT_FORMULAS:
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"Heals {y}% HP and applies {status}", "heal_hp", "auto"
        return f"Heals {y}% HP", "heal_hp", "auto"

    # Heal MP
    if fid == HEAL_MP_FORMULA:
        return f"Heals MP (MA*{y})", "heal_mp", "auto"

    # Rule 6: Break formula + name parse
    if fid == BREAK_FORMULA:
        slot = derive_equip_slot(name)
        if slot:
            return f"Breaks target's {slot} equipment slot", "break", "auto"
        return "Breaks target's equipment", "break", "auto"

    # Rule 7: Break + damage
    if fid == BREAK_DAMAGE_FORMULA:
        return "Breaks equipment and deals physical damage (PA*WP)", "break", "auto"

    # Rule 8: Steal equipment
    if fid == STEAL_EQUIP_FORMULA:
        slot = derive_equip_slot(name)
        if slot:
            return f"Steals target's {slot}", "steal", "auto"
        return "Steals target's equipment", "steal", "auto"

    # Rule 9: Steal gil
    if fid == STEAL_GIL_FORMULA:
        return "Steals target's gil", "steal", "auto"

    # Rule 10: Steal experience
    if fid == STEAL_EXP_FORMULA:
        return "Steals target's experience", "steal", "auto"

    # Rule 11: Absorb formulas
    if fid in ABSORB_FORMULAS:
        resource = ABSORB_FORMULAS[fid]
        return f"Absorbs {y}% of target's {resource}", f"absorb_{resource.lower()}", "auto"

    # Rule 12: Stat boost formulas
    if fid in STAT_BOOST_FORMULAS:
        stat = STAT_BY_FORMULA.get(fid)
        if fid == 0x3A:
            return f"Increases Brave by {y}", "stat_boost", "auto"
        if fid == 0x3B:
            return f"Increases Brave by {x} and PA/MA/SP by {y}", "stat_boost", "auto"
        if stat:
            return f"Increases {stat} by {y}", "stat_boost", "auto"
        return f"Increases stat by {y}", "stat_boost", "auto"

    # Rule 13: Stat reduce formulas
    if fid in STAT_REDUCE_FORMULAS:
        stat = STAT_BY_FORMULA.get(fid)
        if not stat:
            stat = derive_stat_from_name(name) or "stat"
        if fid == 0x1A:
            return f"Reduces target's {stat} by {x}", "stat_reduce", "auto"
        if fid in (0x55, 0x56):
            return f"Reduces target's {stat} by {y}", "stat_reduce", "auto"
        # 0x2B
        return f"Reduces target's {stat} by {x}", "stat_reduce", "auto"

    # Rule for Brave modify formulas
    if fid in BRAVE_MODIFY_FORMULAS:
        return f"Reduces target's Brave by {y}", "stat_reduce", "auto"

    # Rule 17 with status: special formulas that also have inflict_status
    if fid in SPECIAL_FORMULAS:
        desc, cat = SPECIAL_FORMULAS[fid]
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"{desc} and inflicts {status}", cat, "auto"
        return desc, cat, "auto"

    # MP damage formula (0x21)
    if fid == DAMAGE_MP_FORMULA:
        return f"Deals non-elemental MP damage (MA*{y})", "damage_magic", "auto"

    # Self-damage trade formula (0x42)
    if fid == SELF_DAMAGE_FORMULA:
        base = f"Deals non-elemental physical damage (PA*{y}), costs caster PA*{y}/{x} HP"
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"{base} and inflicts {status}", "damage_physical", "auto"
        return base, "damage_physical", "auto"

    # Rule 14/15/18: Damage formulas
    if fid in DAMAGE_MA_FORMULAS:
        if elem_str:
            base = f"Deals {elem_str} magic damage (MA*{y})"
        else:
            base = f"Deals non-elemental magic damage (MA*{y})"
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"{base} and inflicts {status}", "damage_magic", "auto"
        if inflict:
            return f"{base} and inflicts status (set {inflict})", "damage_magic", "auto"
        return base, "damage_magic", "auto"

    if fid in DAMAGE_PCT_FORMULAS:
        if elem_str:
            base = f"Deals {elem_str} magic damage ({y}% HP)"
        else:
            base = f"Deals non-elemental magic damage ({y}% HP)"
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            return f"{base} and inflicts {status}", "damage_magic", "auto"
        if inflict:
            return f"{base} and inflicts status (set {inflict})", "damage_magic", "auto"
        return base, "damage_magic", "auto"

    # Rule 16: Hit-only formulas (primarily for status)
    if fid in HIT_ONLY_FORMULAS:
        if inflict and get_status_desc(inflict):
            status = get_status_desc(inflict)
            if is_buff_status(inflict):
                return f"Applies {status}", "status_buff", "auto"
            if inflict == 38:
                return "Cancels status effects", "status_cancel", "auto"
            if inflict == 55:
                return "Dispels positive status effects", "status_cancel", "auto"
            return f"Inflicts {status}", "status_inflict", "auto"
        if inflict:
            return f"Inflicts status (set {inflict})", "status_inflict", "auto"
        return f"Hit-only formula (no status)", "unknown", "auto"

    # Fallback: check if we can at least describe based on inflict_status
    if inflict and get_status_desc(inflict):
        status = get_status_desc(inflict)
        if is_buff_status(inflict):
            return f"Applies {status}", "status_buff", "auto"
        if inflict == 38:
            return "Cancels status effects", "status_cancel", "auto"
        if inflict == 55:
            return "Dispels positive status effects", "status_cancel", "auto"
        return f"Inflicts {status}", "status_inflict", "auto"

    # Fallback: empty, needs manual work
    return "", "unknown", "manual"


def build_semantics(abilities):
    """Build semantic annotations for all abilities."""
    results = []
    for ab in abilities:
        effect, category, derivation = derive_semantics(ab)
        entry = {
            "ability_id": ab["ability_id"],
            "name": ab["name"],
            "semantic_effect": effect,
            "semantic_category": category,
            "derivation": derivation,
            "code_ref": get_code_ref(ab["formula"]),
            "formula_id": f"0x{ab['formula']:02X}",
            "notes": "",
        }
        results.append(entry)
    return results


def print_stats(results):
    """Print derivation statistics."""
    total = len(results)
    auto = sum(1 for r in results if r["derivation"] == "auto")
    manual = sum(1 for r in results if r["derivation"] == "manual")

    from collections import Counter
    cats = Counter(r["semantic_category"] for r in results)

    print(f"Total abilities:  {total}")
    print(f"Auto-derived:     {auto} ({auto*100//total}%)")
    print(f"Needs manual:     {manual} ({manual*100//total}%)")
    print()
    print("By category:")
    for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {cat:<20s} {count:>3}")


def print_table(results, manual_only=False):
    """Print ASCII table of results."""
    if manual_only:
        results = [r for r in results if r["derivation"] == "manual"]

    if not results:
        print("No matching abilities.")
        return

    id_w = 4
    name_w = max(len(r["name"]) for r in results)
    name_w = max(name_w, 4)
    cat_w = max(len(r["semantic_category"]) for r in results)
    cat_w = max(cat_w, 8)
    eff_w = max(len(r["semantic_effect"]) for r in results)
    eff_w = min(max(eff_w, 6), 60)
    deriv_w = 6

    hdr = (f"{'ID':>{id_w}}  {'Name':<{name_w}}  {'Fml':>5}  "
           f"{'Category':<{cat_w}}  {'Deriv':<{deriv_w}}  {'Effect':<{eff_w}}")
    print(hdr)
    print("-" * len(hdr))

    for r in results:
        eff = r["semantic_effect"][:eff_w] if r["semantic_effect"] else "(needs manual)"
        print(f"{r['ability_id']:>{id_w}}  {r['name']:<{name_w}}  "
              f"{r['formula_id']:>5}  "
              f"{r['semantic_category']:<{cat_w}}  "
              f"{r['derivation']:<{deriv_w}}  {eff}")

    print(f"\n{len(results)} abilities shown")


def main():
    abilities_dir = Path(__file__).parent.parent / "assets" / "abilities"
    default_data = abilities_dir / "ability_attributes.json"
    default_output = abilities_dir / "ability_semantics.json"

    parser = argparse.ArgumentParser(
        description="Generate semantic annotations for FFT abilities")
    parser.add_argument("--data", type=Path, default=default_data,
                        help="Path to ability_attributes.json")
    parser.add_argument("--output", type=Path, default=default_output,
                        help="Output JSON path")
    parser.add_argument("--stats", action="store_true",
                        help="Show derivation statistics")
    parser.add_argument("--manual-only", action="store_true",
                        help="Show only abilities needing manual annotation")
    parser.add_argument("--format", choices=["json", "table"], default="json",
                        help="Output format (default: json)")

    args = parser.parse_args()

    if not args.data.exists():
        print(f"Error: {args.data} not found", file=sys.stderr)
        return 1

    with open(args.data) as f:
        abilities = json.load(f)

    results = build_semantics(abilities)

    if args.stats:
        print_stats(results)
        return 0

    if args.manual_only or args.format == "table":
        print_table(results, manual_only=args.manual_only)
        return 0

    # Default: write JSON
    with open(args.output, "w") as f:
        json.dump(results, f, indent=2)
    print(f"Wrote {len(results)} entries to {args.output}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
