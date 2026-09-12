#!/usr/bin/env python3
"""
Unified FFT Ability Parser

Extracts all ability data from SCUS_942.21 and BATTLE.BIN:
- Ability names (from BATTLE.BIN text section)
- Ability data and attributes (from SCUS_942.21)
- Ability animations (from BATTLE.BIN)
- Ability→Effect mapping (from BATTLE.BIN)

Outputs:
- effects.json: Unified ability database (512 entries)
- fft_names.json: All extracted names (abilities, jobs, items, etc.)

Usage:
    python tools/parse_abilities.py

Then regenerate SpellDatabase.gd:
    python tools/generate_spell_database.py
"""

import json
import struct
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Optional

# =============================================================================
# Configuration
# =============================================================================

# Default input paths — resolve to project-assets/fft-extract via shared helper.
from _repo_paths import scus as _scus, battle_bin as _battle_bin, effect_dir as _effect_dir
from _fft_decode import extract_inflict_status_sets
DEFAULT_SCUS_PATH = _scus()
DEFAULT_BATTLE_PATH = _battle_bin()
DEFAULT_EFFECT_DIR = _effect_dir()

# Default output path
DEFAULT_OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "abilities"

# =============================================================================
# Memory Layout Constants
# =============================================================================

# RAM to file offset conversion for SCUS_942.21
# SCUS loads at RAM 0x80010000, file has 0x800 byte header
RAM_BASE = 0x80010000
FILE_HEADER = 0x800

def ram_to_file_offset(ram_addr: int) -> int:
    """Convert RAM address to file offset in SCUS_942.21"""
    return (ram_addr - RAM_BASE) + FILE_HEADER

# SCUS_942.21 table addresses
ABILITY_DATA_RAM = 0x8005EBF0
ABILITY_ATTRS_RAM = 0x8005FBF0
ABILITY_DATA_OFFSET = ram_to_file_offset(ABILITY_DATA_RAM)
ABILITY_ATTRS_OFFSET = ram_to_file_offset(ABILITY_ATTRS_RAM)

# Secondary data tables for non-Normal abilities
ITEM_DATA_OFFSET = ram_to_file_offset(0x80061010)
THROW_DATA_OFFSET = ram_to_file_offset(0x80061020)
JUMP_DATA_OFFSET = ram_to_file_offset(0x8006102C)
CHARGE_DATA_OFFSET = ram_to_file_offset(0x80061044)
MATH_DATA_OFFSET = ram_to_file_offset(0x80061054)
RSM_DATA_OFFSET = ram_to_file_offset(0x8006105C)

# BATTLE.BIN addresses. BATTLE.BIN is an overlay: its file offsets map to RAM
# via +0x67000 (FFTPatcher PsxIso.FileToRamOffsets[BATTLE_BIN]), so the overlay
# loads at RAM 0x80067000 — NOT 0x80010000 (that is SCUS_942.21's base).
ABILITY_ANIMS_OFFSET = 0x2CE10  # 3 bytes each, 512 abilities
# AbilityEffects table (FFTPatcher: PsxIso.AbilityEffects, KnownPosition
# BATTLE_BIN @ 0x14F3F0, length 0x38C). File 0x14F3F0 + 0x67000 = RAM
# 0x801B63F0 — the exact GameShark base FFTPatcher cites as "0x1B63F0"
# (KSeg0-masked). Each ability of offset <= 0x1C5 (Normal..Reaction) carries a
# little-endian u16 graphic Effect index here; 0xFFFF = no effect. Support
# (>= 0x1C6) / Movement have none — the table is 0x1C6 (454) entries, not 512.
EFFECT_TABLE_OFFSET = 0x14F3F0  # u16 each, 454 entries (ids 0x000..0x1C5)
EFFECT_TABLE_COUNT = 0x1C6      # 454: FFTPatcher gate `i <= 0x1C5`
# Item/Throw abilities (ids 0x170..0x189) store their effect index with the
# 0x0800 "item effect" prefix bit set; FFTPatcher (Ability.ItemEffectPrefixValue)
# masks it off on read. e.g. Potion raw 0x0904 -> E260, not E2308.
ITEM_EFFECT_PREFIX = 0x0800
ITEM_EFFECT_ID_START = 0x170
ITEM_EFFECT_ID_END = 0x189

# Text table in BATTLE.BIN
TEXT_OFFSETS_START = 0xfa2dc
TEXT_NUM_SECTIONS = 32
TEXT_END = 0xfee64

# Counts
TOTAL_ABILITIES = 512
NORMAL_ABILITIES = 0x170  # 368 - abilities with full attributes

# Ability ID ranges by type
ITEM_START = 368
THROW_START = 382
JUMP_START = 394
CHARGE_START = 406
MATH_START = 414
REACTION_START = 422
SUPPORT_START = 454
MOVEMENT_START = 486

# =============================================================================
# Lookup Tables
# =============================================================================

# Text section numbers
class TextSection:
    ABILITY_NAMES = 14
    JOB_NAMES = 6
    ITEM_NAMES = 7
    SKILLSET_NAMES = 22
    STATUS_NAMES = 17

# Caster charging pose names
CHARGING_POSES = {
    0x00: "Crouch", 0x01: "Spell Cast", 0x02: "Summon (bubble)",
    0x03: "Spell Cast", 0x04: "Crouch", 0x05: "Spell Cast",
    0x06: "Crouch", 0x07: "Crouch", 0x08: "Crouch",
    0x09: "Spell Cast", 0x0A: "Crouch", 0x0B: "Spell Cast",
    0x0C: "Crouch", 0x0D: "Sing", 0x0E: "Dance",
    0x0F: "Spell Cast", 0x10: "Spell Cast", 0x11: "Kneeling",
    0x12: "Crouch",
}

# Ability type names
ABILITY_TYPES = {
    0x0: "None", 0x1: "Normal", 0x2: "Item", 0x3: "Throwing",
    0x4: "Jumping", 0x5: "Charging", 0x6: "Arithmetick",
    0x7: "Reaction", 0x8: "Support", 0x9: "Movement",
}

# Target reaction types - maps category → reaction animation key in reaction_animations.json
REACTION_TYPES = {
    0: "taking_damage",    # Default damage (Fire, Holy, etc.) → SEQ 0x19
    1: "evade",            # Physical evade → SEQ 0x18
    2: "receive_heal",     # Healing spells (Cure, etc.) → SEQ 0x1b
    3: "shield_block",     # Throwing items → SEQ 0x58-0x5a
    4: "evade",            # Jumping
    5: "evade",            # Charging/Aim
    6: "evade",            # Arithmetick
    7: "evade",            # Reaction
    8: "none",             # Support - no reaction
    9: "none",             # Movement - no reaction
    10: "none",            # Buffs (Protect, Shell, etc.) - no reaction
    11: "taking_damage",   # Magic damage category → SEQ 0x19
    13: "receive_heal",    # Raise/special → SEQ 0x1b
}

# Element flags
ELEMENTS = {
    0x80: "Fire", 0x40: "Lightning", 0x20: "Ice", 0x10: "Wind",
    0x08: "Earth", 0x04: "Water", 0x02: "Holy", 0x01: "Dark",
}

# ---------------------------------------------------------------------------
# The full 32 attribute flag bits (bytes 3..6 of each 14-byte record).
#
# `parse_ability_attributes` below decodes only the 7 bits the runtime ability
# record needs; ADR-0013 keeps raw bitmasks out of what the game loads. But
# `assets/abilities/ability_attributes.json` — the tool-side raw view that
# `generate_ability_database.py` merges its vertical/hit-policy/aim-policy
# fields from (ADR-0049, ADR-0291) — needs all of them, and had NO generator
# at all until this table existed.
#
# Bit assignment is MSB->LSB within each byte, in the order below. 29 of the
# 32 were solved uniquely against the 368 committed rows (no other bit in any
# of the 4 bytes predicts them). The remaining three — force_self_target_80,
# force_self_target_40, top_down_targeting — are false on all 368 vanilla
# abilities, so the DATA cannot discriminate them; they are assigned by
# position, taking exactly the three bits the other 29 left unclaimed
# (flags1 0x80, flags1 0x40, flags2 0x20), and the first two name their own
# mask. Treat those three as unverified by this corpus.
#
# Positive control: the 7 bits parse_ability_attributes hardcodes
# independently (weapon_range, reflectable, math_skill, blocked_by_golem,
# evadeable, linear_attack, three_directions) all agree with the solve.
ABILITY_ATTR_FLAGS = (
    ("force_self_target_80",    3, 0x80), ("force_self_target_40",   3, 0x40),
    ("weapon_range",            3, 0x20), ("vertical_fixed",         3, 0x10),
    ("vertical_tolerance",      3, 0x08), ("weapon_strike",          3, 0x04),
    ("auto_target",             3, 0x02), ("dont_target_self",       3, 0x01),
    ("dont_hit_enemies",        4, 0x80), ("dont_hit_allies",        4, 0x40),
    ("top_down_targeting",      4, 0x20), ("dont_follow_target",     4, 0x10),
    ("random_fire",             4, 0x08), ("linear_attack",          4, 0x04),
    ("three_directions",        4, 0x02), ("dont_hit_caster",        4, 0x01),
    ("reflectable",             5, 0x80), ("math_skill",             5, 0x40),
    ("not_silence",             5, 0x20), ("not_mimicable",          5, 0x10),
    ("blocked_by_golem",        5, 0x08), ("persevere",              5, 0x04),
    ("show_quote",              5, 0x02), ("animate_on_miss",        5, 0x01),
    ("counter_flood",           6, 0x80), ("counter_magic",          6, 0x40),
    ("direct",                  6, 0x20), ("blade_grasp",            6, 0x10),
    ("requires_sword",          6, 0x08), ("requires_materia_blade", 6, 0x04),
    ("evadeable",               6, 0x02), ("targeting_ai_only",      6, 0x01),
)

# Per-ability real-time cooldown floor in GPU ticks (60 ticks = 1 second).
#
# NOT a copy of CT, and not the same quantity. FFT spells two different things
# "CT" and this kernel already spends that word on the second one: an ability's
# CHARGE PERIOD, the delay between committing and the effect landing
# (`AB_CHARGE_TIME` / `get_ability_charge_time`, and see the warning at
# combat_common.glslinc's turn-meter block). A cooldown is the floor between two
# COMMITS of the same ability. `ct` is read here as EVIDENCE of what FFT
# considered an ability to cost, never as the cooldown itself.
#
# WHY THIS IS DERIVED AND NO LONGER A SINGLE NUMBER (#1108, map #1101).
# The old value was 300 for all 512 abilities, and ADR-0047 dec. 2 justified
# that as harmless: "cooldown counts from commit, so a CT-bearing ability spends
# most of its action in SPELL_CHARGING and the floor has long expired ... only
# CT=0 abilities actually feel it."
#
# MEASURED, THAT JUSTIFICATION IS FALSE. The charge period is `ct * 30` ticks
# (GPUAbilityLoader.gd), so it only exceeds a 300-tick floor at ct > 10 — which
# is SIX abilities. The flat floor therefore BINDS 123 of the 144 CT-bearing
# abilities (72 of the 87 that sit below the old 128 ceiling and are actually
# gated), adding between +30 and +240 ticks on top of FFT's own cadence. It did
# not merely fail to differentiate; it OVERRODE the differentiation the ROM
# already had, flattening a 2..20 spread onto one number.
#
# THE DERIVATION, in one sentence per population:
#
#   ct > 0        -> the floor IS the charge period (`ct * 30`). FFT already
#                    priced this ability with time, so the cooldown is made
#                    exactly non-binding rather than deleted: the kernel's
#                    effective period is max(charge, cooldown), so at factor
#                    1.0 the ability paces exactly as the ROM paced it, and the
#                    lever layer still has a real, non-zero base to scale.
#                    A base of 0 would be unleverable (0 * anything is 0) and
#                    would read as a hollow lever under ADR-0277 dec. 9.
#
#   ct == 0       -> free and instant in the ROM, so the floor is the WHOLE
#                    price and has to come from somewhere else. MP cannot carry
#                    it (209 of these 224 abilities cost 0 MP). JP can: it is
#                    what FFT charges to learn the ability, the only ROM number
#                    that separates Wave Fist from Holy Explosion. The JP price
#                    is mapped onto FFT's OWN ct scale at JP_PER_CT_UNIT and
#                    then through the same `* 30`, so one derivation and one
#                    unit system covers both populations.
#
#   jp_cost == 0  -> the ROM prices this ability NOT AT ALL: 127 of the ct == 0
#                    records are unlearnable monster/enemy skills at 0 JP and
#                    0 MP. They keep the bare floor. Only 3 of the 127 sit below
#                    the old ceiling, so this tail is nearly all newly-gated.
#
#   no `ct` field -> 144 records (ids 368-511: Reaction, Support, Movement,
#                    Item, Throwing, Jumping, Charging) carry a 20-field record
#                    with no `ct` at all. Absent is NOT zero: handing them the
#                    full floor would price the abilities ADR-0277 already calls
#                    unreachable. They keep the bare floor too, which is what
#                    they had before, so nothing regresses.
#
# THE FLOOR ITSELF IS UNCHANGED AT 300 and that is deliberate (#92 / #93): the
# original 60 left no fall-through window for a CT=0 ability like Secret Fist
# whose cast animation is itself ~60 ticks of ACTING, so the slot-1 ATTACK
# fallback never had room to commit. 300 is the measured-safe window. It is a
# floor and not a default — the derivation may only raise a value above it.
#
# This is a DEFAULT, not a balance verdict: per-record overrides ride the lever
# layer on top (ADR-0277), and #1101 rules the final numbers out of scope.

# Ticks per unit of FFT's CT scale. Mirrors GPUAbilityLoader.gd's
# `charge_time = ability.ct * 30`; the two must not drift.
TICKS_PER_CT_UNIT = 30

# The #92 / #93 fall-through window. A derived cooldown may exceed this, never
# undercut it.
COOLDOWN_FLOOR_TICKS = 300

# How much JP buys one unit on FFT's own ct scale. Chosen so the JP prices of
# the learnable CT=0 abilities (10..900) land on the range the ROM's own ct
# already occupies (2..20) rather than on an invented scale of their own.
JP_PER_CT_UNIT = 50


def derive_cooldown_ticks(ct, jp_cost: int) -> int:
    """The per-ability cooldown floor in GPU ticks.

    `ct` is None for the 144 records that carry no `ct` field at all — absent,
    which is not the same as zero. See the block comment above for why each
    population lands where it does.
    """
    if ct:
        # Priced by time in the ROM. Match that period exactly so the floor is
        # non-binding at factor 1.0 but still leverable.
        return ct * TICKS_PER_CT_UNIT
    if ct is None or not jp_cost:
        # No ct field, or unlearnable at 0 JP: the ROM gives us nothing to
        # price with, so the bare fall-through window stands.
        return COOLDOWN_FLOOR_TICKS
    # Free and instant, but the ROM charged JP to learn it.
    virtual_ct = jp_cost // JP_PER_CT_UNIT
    return max(COOLDOWN_FLOOR_TICKS, virtual_ct * TICKS_PER_CT_UNIT)

# =============================================================================
# Text Decoding (from BATTLE.BIN)
# =============================================================================

def decode_fft_char(code: int) -> str:
    """Decode a single FFT character code to string."""
    if code == 0xfa or code == 0xda73:
        return ' '
    elif code == 0xe0:
        return '[Ramza]'
    elif code == 0xe1:
        return '[UnitName]'
    elif code in [0xe4, 0xe6]:
        return '[Number]'
    elif code in [0xe5, 0xe9, 0xea, 0xeb]:
        return '[TextVariable]'
    elif code == 0xf8:
        return ' '
    elif code < 10:
        return chr(code + 0x30)
    elif code < 36:
        return chr(code - 10 + 0x41)
    elif code < 62:
        return chr(code - 36 + 0x61)
    elif (code - 0xd000) >= 36 and (code - 0xd000) < 62:
        return chr((code - 0xd000) - 36 + 0x61)
    elif code == 62 or code == 0xd11a:
        return '!'
    elif code == 64 or code == 0xd9c9:
        return '?'
    elif code == 66 or code == 0xd11e:
        return '+'
    elif code == 68 or code == 0xd9c6:
        return '/'
    elif code == 70 or code == 0xd9bd:
        return ':'
    # Ligatures
    elif code == 0x56:
        return 'ni'
    elif code == 0x57:
        return 'ht'
    elif code == 0x58:
        return 'an'
    elif code == 0x59:
        return 'on'
    elif code == 0x5c:
        return 'th'
    elif code == 0x5d:
        return 'ea'
    elif code == 0x5e:
        return 'er'
    elif code == 0x60:
        return 'or'
    elif code == 95 or code == 0xd11c or code == 0xd9b6:
        return '.'
    elif code == 139 or code == 0xd9bc:
        return '·'
    elif code == 141 or code == 0xd9be:
        return '('
    elif code == 142 or code == 0xd9bf:
        return ')'
    elif code == 145 or code == 0xda77 or code == 0xd9c0:
        return '"'
    elif code == 147 or code == 0xda76 or code == 0xd9c1:
        return "'"
    elif code == 181 or code == 0xd111:
        return '*'
    elif code == 0xd117:
        return '-'
    elif code == 0xd11b:
        return '...'
    elif code == 0xd11d:
        return '-'
    elif code == 0xd11f:
        return '×'
    elif code == 0xd120:
        return '÷'
    elif code == 0xd123 or code == 0xda70:
        return '='
    elif code == 0xd125:
        return '>'
    elif code == 0xd126:
        return '<'
    elif code == 0xd9b7:
        return '&'
    elif code == 0xd9b8:
        return '%'
    elif code == 0xd9c5:
        return '~'
    elif code == 0xda71:
        return '$'
    elif code == 0xda74:
        return ','
    elif code == 0xda75:
        return ';'
    else:
        return f'[{code:04x}]'


def decode_fft_text(data: bytes, keep_empty: bool = False) -> list[str]:
    """Decode FFT text data into a list of strings."""
    strings = []
    current = ""
    i = 0

    while i < len(data):
        code = data[i]

        if code == 0xfe or code == 0xff:
            if keep_empty:
                strings.append(current.strip() if current.strip() else "")
            elif current.strip():
                strings.append(current.strip())
            current = ""
            i += 1
            continue

        if code >= 0xd0 and code <= 0xda:
            if i + 1 < len(data):
                code = (code << 8) | data[i + 1]
                i += 2
            else:
                i += 1
                continue
        elif code > 0xda:
            i += 1
            continue
        else:
            i += 1

        if code == 0xe3 or code == 0xe8 or code == 0xec:
            if i < len(data):
                i += 1
            continue
        if code == 0xfd:
            continue

        current += decode_fft_char(code)

    if keep_empty:
        strings.append(current.strip() if current.strip() else "")
    elif current.strip():
        strings.append(current.strip())

    return strings


def extract_text_section(battle_data: bytes, section_num: int, keep_empty: bool = False) -> list[str]:
    """Extract a text section from BATTLE.BIN."""
    offsets_end = TEXT_OFFSETS_START + (TEXT_NUM_SECTIONS * 4)
    offsets = []
    for i in range(TEXT_NUM_SECTIONS):
        offset = struct.unpack_from('<I', battle_data, TEXT_OFFSETS_START + i * 4)[0]
        offsets.append(offset + offsets_end)

    start = offsets[section_num]
    if section_num + 1 < len(offsets):
        end = offsets[section_num + 1]
        if end == offsets_end:
            end = TEXT_END
    else:
        end = TEXT_END

    section_data = battle_data[start:end]
    return decode_fft_text(section_data, keep_empty=keep_empty)


def extract_all_names(battle_data: bytes) -> dict:
    """Extract all name tables from BATTLE.BIN."""
    return {
        "abilities": extract_text_section(battle_data, TextSection.ABILITY_NAMES, keep_empty=True),
        "jobs": extract_text_section(battle_data, TextSection.JOB_NAMES),
        "skillsets": extract_text_section(battle_data, TextSection.SKILLSET_NAMES),
        "items": extract_text_section(battle_data, TextSection.ITEM_NAMES),
        "statuses": extract_text_section(battle_data, TextSection.STATUS_NAMES),
    }

# =============================================================================
# Ability Data Parsing
# =============================================================================

def get_reaction_category(ability_type_id: int, formula: int) -> int:
    """Calculate target reaction category from ability type and formula."""
    if ability_type_id == 1:
        if formula == 12:
            return 2
        elif formula == 11:
            return 10
        elif formula == 13:
            return 13
        else:
            return 0
    elif ability_type_id in [2, 3, 4, 5, 6, 7, 8, 9]:
        return ability_type_id
    return 0


def parse_ability_data(data: bytes, ability_id: int, name: str) -> dict:
    """Parse 8 bytes of ability data."""
    jp_cost = struct.unpack_from("<H", data, 0)[0]
    learn_rate = data[2]
    flags_type = data[3]
    ai_flags_1 = data[4]
    ability_type_id = flags_type & 0x0F

    return {
        "ability_id": ability_id,
        "name": name,
        "jp_cost": jp_cost,
        "learn_rate": learn_rate,
        "learn_with_jp": not bool(flags_type & 0x80),  # Inverted: bit set = cannot learn
        "display_name": bool(flags_type & 0x40),
        "learn_on_hit": bool(flags_type & 0x20),
        "ability_type": ABILITY_TYPES.get(ability_type_id, f"Unknown_{ability_type_id}"),
        "ability_type_id": ability_type_id,
        # Placeholder, so the key keeps its position in the emitted record.
        # The real value needs `ct`, which is parsed in a later pass, and is
        # written by `derive_cooldown_ticks` once the entry is merged.
        "cooldown_ticks": COOLDOWN_FLOOR_TICKS,
        # --- the AI's ally/foe POLARITY (issue #1227) -------------------------
        # ADR-0278 dec. 9 argues `AbilityFamily` is a `rule` because "nothing in
        # the ROM stores a family". That stays true — a family is 4-valued. But
        # its ALLY/FOE PROJECTION *is* stored, and BATTLE.BIN reads it as a
        # TWO-BIT FIELD. Rooted by ADR-0291 dec. 1's closed enumeration, not by
        # the FFHacktics name:
        #
        #   0x8018b5e8  lui   v0,0x8006
        #   0x8018b5ec  addiu v0,v0,-0x1410   ; -> 0x8005EBF0, this table
        #   0x8018b5f0  sll   v1,v1,0x3       ; the 8-byte stride
        #   0x8018b5f8  lbu   v0,0x4(v1)      ; THIS byte
        #   0x8018b604  andi  v0,v0,0x3       ; BOTH bits; the other six DISCARDED
        #   0x8018b608  sb    v0,0x18(a0)     ; into the AI's working struct
        #
        # The discard is the positive control: `ai_hp` (0x80) .. `ai_unequip`
        # (0x04) do not survive that mask, and byte +7 is read at the SAME site
        # with a different mask (0x1), so this is a deliberate field extraction
        # rather than an incidental byte copy. Cross-checked 512/512 against live
        # RAM in three savestates, and 265/265 against `AbilityFamily` over the
        # 278 skillset-reachable abilities with ZERO disagreements.
        "ai_target_allies": bool(ai_flags_1 & 0x01),
        "ai_target_enemies": bool(ai_flags_1 & 0x02),
        #
        # 🔴 `ai_only_allies` (+7 & 0x40) and `ai_only_enemies` (+7 & 0x20) are
        # deliberately NOT emitted. Byte +7 is loaded exactly ONCE in the whole
        # enumeration and masked 0x01; those two masks appear nowhere against
        # this table, so nothing reads them. They also CONTRADICT the pair above
        # on `Silf`, `Fairy` and `StealExp`, and `GilTaking` sets both at once.
        # That is ADR-0291 dec. 5's `targeting_ai_only` again: a name that reads
        # like a targeting rule and is read by no code.
    }


def parse_ability_attributes(
    data: bytes,
    ability_id: int,
    name: str,
    inflict_sets: dict[int, dict],
) -> dict:
    """Parse 14 bytes of ability attributes.

    The `inflict_status` byte (data[11]) is decoded via `inflict_sets`
    (the SCUS InflictStatusList table) into a name array + mode enum per
    ADR-0013 — runtime never sees the set_id FK.
    """
    range_val = data[0]
    effect_area = data[1]
    vertical = data[2]
    flags1, flags2, flags3, flags4 = data[3], data[4], data[5], data[6]
    elements_byte = data[7]
    formula = data[8]
    x, y = data[9], data[10]
    inflict_set_id = data[11]
    ct = data[12]
    mp_cost = data[13]

    # Element affinity decodes here (set form, ADR-0013); the raw byte is
    # not emitted — runtime never sees the bitmask.
    elements = [name for bit, name in ELEMENTS.items() if elements_byte & bit]

    inflict_entry = inflict_sets[inflict_set_id]

    return {
        "range": range_val,
        "effect_area": effect_area,
        "vertical": vertical,
        "elements": elements,
        "formula": formula,
        "formula_x": x,
        "formula_y": y,
        # ADR-0013: decoded name array + mode enum; raw set_id stays in the
        # parser-side debug artifact (tools/extracted/inflict_status_sets.json)
        # — runtime never sees it.
        "inflict_statuses": list(inflict_entry["statuses"]),
        "inflict_mode": inflict_entry["mode"],
        "ct": ct,
        "mp_cost": mp_cost,
        "weapon_range": bool(flags1 & 0x20),
        "reflectable": bool(flags3 & 0x80),
        "math_skill": bool(flags3 & 0x40),
        "blocked_by_golem": bool(flags3 & 0x08),
        "evadeable": bool(flags4 & 0x02),
        "linear_attack": bool(flags2 & 0x04),
        "three_directions": bool(flags2 & 0x02),
    }


def build_ability_attributes(scus_data: bytes, effects: dict) -> list:
    """Build `ability_attributes.json` — the raw attribute view of ids 0..367.

    A deliberate sibling of `parse_ability_attributes`, not a duplicate of it:
    that one feeds the runtime record and obeys ADR-0013 (decoded sets, no raw
    bitmasks), this one is the tool-side raw view that
    `generate_ability_database.py` merges `vertical_*` / `dont_hit_*` /
    `dont_target_self` from. Those six fields are produced by nothing else in
    tools/, which is why this artifact sat in the tree with no generator.

    `effects` supplies `name` and `effect_file` so there is one source for each.
    """
    out = []
    for i in range(NORMAL_ABILITIES):
        rec = scus_data[ABILITY_ATTRS_OFFSET + i * 14:
                        ABILITY_ATTRS_OFFSET + i * 14 + 14]
        elements_byte = rec[7]
        entry = {
            "ability_id": i,
            "name": effects[i]["name"],
            "range": rec[0],
            "effect_area": rec[1],
            # The ROM-derived ability->effect mapping, same source as
            # effects.json. The hand-made file this replaced stored
            # f"E{ability_id:03d}.BIN", which is only right for 1 of 368 rows
            # (ability 37 is E039.BIN, not E037.BIN). No consumer read it —
            # generate_ability_database.py merges six named flags and nothing
            # else — so correcting it changes no behaviour.
            "effect_file": effects[i].get("effect_file") or "(none)",
            "vertical": rec[2],
        }
        for key, byte_index, mask in ABILITY_ATTR_FLAGS:
            entry[key] = bool(rec[byte_index] & mask)
        entry["elements"] = [n for bit, n in ELEMENTS.items() if elements_byte & bit]
        entry["elements_raw"] = elements_byte
        entry["formula"] = rec[8]
        entry["x"] = rec[9]
        entry["y"] = rec[10]
        entry["inflict_status"] = rec[11]
        entry["ct"] = rec[12]
        entry["mp_cost"] = rec[13]
        out.append(entry)
    return out


def parse_ability_animation(data: bytes, ability_id: int, ability_type_id: int, formula: int) -> dict:
    """Parse 3 bytes of ability animation data."""
    charging_id = data[0]
    effect_anim = data[1]
    flags = data[2]

    reaction_category = get_reaction_category(ability_type_id, formula)

    return {
        "charging_pose_id": charging_id,
        "charging_pose": CHARGING_POSES.get(charging_id, f"Unknown_{charging_id:02X}"),
        "effect_anim_id": effect_anim,
        "anim_flags": flags,
        "target_reaction_category": reaction_category,
        "target_reaction_type": REACTION_TYPES.get(reaction_category, "taking_damage"),
    }


def parse_secondary_data(scus_data: bytes, ability_id: int, ability_type: str) -> dict:
    """Parse type-specific secondary data for non-Normal abilities."""
    if ability_type == "Item" and ITEM_START <= ability_id < THROW_START:
        return {"item_id": scus_data[ITEM_DATA_OFFSET + ability_id - ITEM_START]}
    elif ability_type == "Throwing" and THROW_START <= ability_id < JUMP_START:
        return {"throw_item_id": scus_data[THROW_DATA_OFFSET + ability_id - THROW_START]}
    elif ability_type == "Jumping" and JUMP_START <= ability_id < CHARGE_START:
        idx = ability_id - JUMP_START
        return {"jump_multiplier": struct.unpack_from("<H", scus_data, JUMP_DATA_OFFSET + idx * 2)[0]}
    elif ability_type == "Charging" and CHARGE_START <= ability_id < MATH_START:
        idx = ability_id - CHARGE_START
        return {"charge_bonus": struct.unpack_from("<H", scus_data, CHARGE_DATA_OFFSET + idx * 2)[0]}
    elif ability_type == "Arithmetick" and MATH_START <= ability_id < REACTION_START:
        return {"math_ct": scus_data[MATH_DATA_OFFSET + ability_id - MATH_START]}
    # NOTE (ADR-0013, RE complete 2026-07-04): this byte is NOT flags — it is the
    # R/S/M ability's passive-effect *routine index* (FFTPatcher `OtherID`,
    # FFHacktics field `ID`). RSM_DATA_OFFSET (0x8006105C) is CORRECT: it is the
    # contiguous secondary-data table right after Math (0x80061054), verified
    # against the SCUS bytes, the hacktics disassembly, and FFTPatcher C#
    # (Ability.cs OtherID / AllAbilities.cs blob 0x246C = RAM 0x8006105C). Vanilla
    # assigns the indices sequentially (Reaction 0–31, Support 32–63, Movement
    # 64–87), so the value is redundant with the ability's own ordinal and carries
    # no bit-flag data — R/S/M passive behavior is hardcoded in BATTLE.BIN, keyed
    # by this index. Kept raw + out of INCLUDED_FIELDS: an int routine-id is the
    # faithful final representation, nothing to decode.
    elif ability_type == "Reaction" and REACTION_START <= ability_id < SUPPORT_START:
        return {"rsm_other_id": scus_data[RSM_DATA_OFFSET + ability_id - REACTION_START]}
    elif ability_type == "Support" and SUPPORT_START <= ability_id < MOVEMENT_START:
        return {"rsm_other_id": scus_data[RSM_DATA_OFFSET + ability_id - SUPPORT_START + 32]}
    elif ability_type == "Movement" and MOVEMENT_START <= ability_id < 510:
        return {"rsm_other_id": scus_data[RSM_DATA_OFFSET + ability_id - MOVEMENT_START + 64]}
    return {}


def load_effect_mapping(battle_data: bytes) -> dict[int, int]:
    """Load ability→effect mapping from BATTLE.BIN's AbilityEffects table.

    Only the first EFFECT_TABLE_COUNT (454) abilities — offsets 0x000..0x1C5,
    i.e. Normal through Reaction — have an entry; Support/Movement (>= 0x1C6)
    are past the table and get no effect (mirrors FFTPatcher's `i <= 0x1C5`
    gate). Item/Throw entries (0x170..0x189) carry the 0x0800 prefix bit, which
    is masked off here per FFTPatcher's Ability.ItemEffectPrefixValue.
    """
    mapping = {}
    for i in range(EFFECT_TABLE_COUNT):
        offset = EFFECT_TABLE_OFFSET + (i * 2)
        if offset + 2 <= len(battle_data):
            effect_id = struct.unpack_from('<H', battle_data, offset)[0]
            if (effect_id != 0xFFFF
                    and ITEM_EFFECT_ID_START <= i <= ITEM_EFFECT_ID_END):
                effect_id &= ~ITEM_EFFECT_PREFIX
            mapping[i] = effect_id
    return mapping

# =============================================================================
# Main Parser
# =============================================================================

def parse_all_abilities(scus_path: Path, battle_path: Path, effect_dir: Optional[Path] = None) -> tuple[dict, dict]:
    """Parse all ability data and return (effects_dict, names_dict)."""

    print(f"Reading {scus_path}...")
    with open(scus_path, "rb") as f:
        scus_data = f.read()

    print(f"Reading {battle_path}...")
    with open(battle_path, "rb") as f:
        battle_data = f.read()

    # Decode the inflict-status set table once. Each Normal ability's byte 11
    # is a set_id into this table; we resolve to a name array + mode enum
    # per ADR-0013 at the parser boundary.
    inflict_sets = extract_inflict_status_sets(scus_data)

    # Extract names
    print("Extracting names from BATTLE.BIN...")
    all_names = extract_all_names(battle_data)
    ability_names = all_names["abilities"]
    print(f"  Found {len(ability_names)} ability names")

    # Load effect mapping
    print("Loading effect mapping from BATTLE.BIN...")
    effect_mapping = load_effect_mapping(battle_data)
    print(f"  Loaded {len(effect_mapping)} entries")

    # Parse all abilities
    print(f"Parsing {TOTAL_ABILITIES} abilities...")
    effects = {}
    effects_with_files = 0

    for i in range(TOTAL_ABILITIES):
        # Get name
        name = ability_names[i] if i < len(ability_names) else f"Ability_{i:03X}"
        if not name:
            name = "(Nothing)"

        # Parse ability data (8 bytes)
        offset = ABILITY_DATA_OFFSET + (i * 8)
        ability = parse_ability_data(scus_data[offset:offset+8], i, name)

        # Get effect_id from mapping. Abilities past the table (Support/Movement,
        # id >= EFFECT_TABLE_COUNT) are absent → no effect. 0xFFFF is the
        # in-table "no effect" sentinel.
        effect_id = effect_mapping.get(i)
        if effect_id == 0xFFFF:
            effect_id = None

        effect_file = f"E{effect_id:03d}.BIN" if effect_id is not None and effect_id > 0 else None

        # Check if effect file exists
        has_effect_file = False
        if effect_file and effect_dir:
            effect_path = effect_dir / effect_file
            has_effect_file = effect_path.exists() and effect_path.stat().st_size > 0
            if has_effect_file:
                effects_with_files += 1

        # Build entry
        entry = {
            "ability_id": i,
            "effect_id": effect_id,
            "effect_file": effect_file,
            "has_effect_file": has_effect_file,
            **ability,
        }

        # Parse attributes for Normal abilities (0-367)
        if i < NORMAL_ABILITIES:
            offset = ABILITY_ATTRS_OFFSET + (i * 14)
            attrs = parse_ability_attributes(
                scus_data[offset:offset+14], i, name, inflict_sets
            )
            entry.update(attrs)
            formula = attrs["formula"]
        else:
            # Add secondary data for non-Normal abilities
            secondary = parse_secondary_data(scus_data, i, ability["ability_type"])
            entry.update(secondary)
            formula = 0

        # Parse animation (3 bytes from BATTLE.BIN)
        offset = ABILITY_ANIMS_OFFSET + (i * 3)
        anim = parse_ability_animation(
            battle_data[offset:offset+3], i,
            ability["ability_type_id"], formula
        )
        entry.update(anim)

        # Cooldown floor (#1108). Written here rather than in
        # `parse_ability_data` because it needs `ct`, which only the Normal
        # attribute pass supplies — and its ABSENCE on ids 368-511 is itself
        # load-bearing, so read it with .get() and pass None through.
        entry["cooldown_ticks"] = derive_cooldown_ticks(
            entry.get("ct"), entry.get("jp_cost", 0)
        )

        effects[i] = entry

    print(f"  Parsed {len(effects)} abilities")
    if effect_dir:
        print(f"  Effects with files: {effects_with_files}")

    return effects, all_names


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Parse FFT ability data from SCUS_942.21 and BATTLE.BIN",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python tools/parse_abilities.py
  python tools/parse_abilities.py --output /custom/path

After running, regenerate SpellDatabase.gd:
  python tools/generate_spell_database.py
"""
    )
    parser.add_argument("--scus", type=Path, default=DEFAULT_SCUS_PATH,
                        help=f"Path to SCUS_942.21 (default: {DEFAULT_SCUS_PATH})")
    parser.add_argument("--battle", type=Path, default=DEFAULT_BATTLE_PATH,
                        help=f"Path to BATTLE.BIN (default: {DEFAULT_BATTLE_PATH})")
    parser.add_argument("--effects", type=Path, default=DEFAULT_EFFECT_DIR,
                        help=f"Path to EFFECT directory (default: {DEFAULT_EFFECT_DIR})")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_DIR,
                        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})")
    args = parser.parse_args()

    # Validate inputs
    if not args.scus.exists():
        print(f"Error: SCUS file not found: {args.scus}")
        return 1
    if not args.battle.exists():
        print(f"Error: BATTLE.BIN not found: {args.battle}")
        return 1

    effect_dir = args.effects if args.effects.exists() else None
    if not effect_dir:
        print(f"Warning: EFFECT directory not found, has_effect_file will be False")

    # Parse everything
    effects, all_names = parse_all_abilities(args.scus, args.battle, effect_dir)

    # Write outputs
    args.output.mkdir(parents=True, exist_ok=True)

    effects_path = args.output / "effects.json"
    with open(effects_path, "w") as f:
        json.dump(effects, f, indent=2)
    print(f"\nWrote {effects_path}")

    names_path = args.output / "fft_names.json"
    with open(names_path, "w") as f:
        json.dump(all_names, f, indent=2, ensure_ascii=False)
    print(f"Wrote {names_path}")

    attrs_path = args.output / "ability_attributes.json"
    with open(attrs_path, "w") as f:
        json.dump(build_ability_attributes(args.scus.read_bytes(), effects),
                  f, indent=2)
    print(f"Wrote {attrs_path}")

    # Print summary
    print(f"\nSummary:")
    print(f"  Total abilities: {len(effects)}")
    print(f"  Ability names: {len(all_names['abilities'])}")
    print(f"  Job names: {len(all_names['jobs'])}")
    print(f"  Item names: {len(all_names['items'])}")

    # Sample output
    print(f"\nSample abilities:")
    for sample_id in [1, 16, 20, 60]:
        if sample_id in effects:
            e = effects[sample_id]
            print(f"  {sample_id}: {e['name']} (effect={e['effect_id']}, mp={e.get('mp_cost', 'N/A')})")

    return 0


if __name__ == "__main__":
    exit(main())
