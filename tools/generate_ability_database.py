#!/usr/bin/env python3
"""
Generate AbilityDatabase.gd from effects.json

This tool reads the parsed ability data and generates a GDScript file
containing a const Dictionary for fast lookup without runtime JSON parsing.

Usage:
    python tools/generate_ability_database.py            # write the files
    python tools/generate_ability_database.py --check    # fail if committed files are stale

Output:
    addons/exmateria_almanac/abilities/AbilityDatabase.gd   (const store + lookups)
    addons/exmateria_almanac/abilities/AbilityView.gd       (typed façade over a record)

Both files are MEMBERS of the `exmateria_almanac` addon (ADR-0251 dec. 1), so
neither declares a `class_name` and both reach their siblings by `preload`
path. A generator that emitted a bare global would re-open the arm-7 hole the
extraction closed, silently, on the next regenerate.
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime

# Paths relative to project root
PROJECT_ROOT = Path(__file__).parent.parent
EFFECTS_JSON = PROJECT_ROOT / "assets" / "abilities" / "effects.json"
SKILL_SETS_JSON = PROJECT_ROOT / "assets" / "abilities" / "skill_sets.json"
ABILITY_ATTRS_JSON = PROJECT_ROOT / "assets" / "abilities" / "ability_attributes.json"
ADDON_DIR = PROJECT_ROOT / "addons" / "exmateria_almanac" / "abilities"
OUTPUT_FILE = ADDON_DIR / "AbilityDatabase.gd"
VIEW_OUTPUT_FILE = ADDON_DIR / "AbilityView.gd"

# Every intra-addon reference the two generated files make. Kept here rather
# than spelled inline in each template so the paths move together.
ADDON_RES = "res://addons/exmateria_almanac"
PRELOAD_BANNER = """# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did."""

# Fields to include in the generated database
# These are the most useful fields for gameplay
# NOTE: ability_id is the lookup key, effect_id is which E###.BIN to use (they can differ!)
INCLUDED_FIELDS = [
    "ability_id",
    "effect_id",
    "name",
    "ability_type",
    "ability_type_id",
    "mp_cost",
    "ct",
    "cooldown_ticks",
    "range",
    "vertical",
    "effect_area",
    "formula_x",
    "formula_y",
    "elements",
    "formula",
    "charging_pose",
    "charging_pose_id",
    "target_reaction_type",
    "target_reaction_category",
    "has_effect_file",
    "effect_file",
    "reflectable",
    "evadeable",
    "linear_attack",
    "three_directions",
    "jp_cost",
    # ADR-0013: decoded name array + mode enum, not the raw set_id FK
    "inflict_statuses",
    "inflict_mode",
    "blocked_by_golem",
    "math_skill",
    "weapon_range",
    # Vertical targeting fields (from ability_attributes.json)
    "vertical_tolerance",
    "vertical_fixed",
    # Hit policy flags (ADR-0049): which units in the AOE radius the
    # ability's effect actually lands on. ROM-canonical; never inferred.
    "dont_hit_enemies",
    "dont_hit_allies",
    "dont_hit_caster",
    # Aim policy (ADR-0291): a DIFFERENT axis from the hit-policy triple above.
    # `dont_target_self` is enforced by the ROM at CURSOR time, not splash time:
    # `FUN_8017A290` @ 0x8017A290 builds the selectable-tile table at 0x80192DD8,
    # marks the caster's own tile selectable (0x8017A410-0x8017A418), and then at
    # 0x8017A444 tests flags1 & 0x01 and ZEROES that entry (0x8017A450). So the
    # flag removes a tile from what the cursor may land on, where `dont_hit_caster`
    # removes a unit from what the splash lands on.
    "dont_target_self",
    # The AI's ally/foe POLARITY (issue #1227) — the ROM's own answer to the
    # axis `AbilityFamily.is_ally_side` computes. Read by BATTLE.BIN as a
    # two-bit field: `lbu 0x4(v1); andi 0x3` at 0x8018b5f8-0x8018b604, with the
    # other six bits of that byte discarded at the same site. Corroboration for
    # `AbilityFamily` (265/265 over the 278 reachable, 0 disagreements), NOT a
    # replacement for it — the ROM is SILENT on 13 of those 278, nine of them
    # usable Faith/Brave/talk skills, so a family derived from these alone would
    # leave them with no side. `AbilityFamily` stays the answer (ADR-0278 dec. 9).
    #
    # 🔴 `ai_only_allies`/`ai_only_enemies` are absent on purpose: nothing reads
    # them, and they contradict this pair on three abilities. ADR-0291 dec. 5.
    "ai_target_allies",
    "ai_target_enemies",
    # Learning fields (for progression system)
    "learn_with_jp",
    "learn_on_hit",
    "learn_rate",
    # Animation fields (for ability-specific casting animations)
    "start_seq_slot",       # Brief wind-up animation before sustain (nullable)
    "sustain_seq_slot",     # Held charging pose (nullable)
    "effect_anim_id",       # Execution animation ID (multiply by 2 for SEQ slot)
    "throw_item_id",        # Item type ID for throw abilities (Ninja)
]


def escape_gdscript_string(s: str) -> str:
    """Escape a string for GDScript."""
    if s is None:
        return '""'
    # Escape backslashes first, then quotes
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    return f'"{s}"'


def format_value(value) -> str:
    """Format a Python value as GDScript literal."""
    if value is None:
        return "null"
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, str):
        return escape_gdscript_string(value)
    elif isinstance(value, list):
        if len(value) == 0:
            return "[]"
        items = [escape_gdscript_string(v) if isinstance(v, str) else str(v) for v in value]
        return "[" + ", ".join(items) + "]"
    elif isinstance(value, (int, float)):
        return str(value)
    else:
        return str(value)


def generate_entry(effect_id: int, data: dict) -> str:
    """Generate a single ability dictionary entry."""
    lines = []
    lines.append(f"\t{effect_id}: {{")

    fields = []
    for field in INCLUDED_FIELDS:
        if field in data:
            value = data[field]
            fields.append(f'\t\t"{field}": {format_value(value)}')

    lines.append(",\n".join(fields))
    lines.append("\t}")

    return "\n".join(lines)


# ----------------------------------------------------------------------------
# AbilityView field-type inference + generation
#
# The view is a flat, typed façade over the ability record. Its field list is
# INCLUDED_FIELDS and its per-field type/default/nullability are INFERRED by
# sampling every record. The 512 ROM abilities are the fixed, complete universe
# of ability data — no record can appear at runtime that this sampling did not
# see — so the inference is exact, not heuristic. See ADR-0008.
# ----------------------------------------------------------------------------

GD_DEFAULTS = {
    "int": "0",
    "float": "0.0",
    "String": '""',
    "bool": "false",
    "Array": "[]",
}

# Coercion call wrapped around the raw dict read for non-nullable typed fields,
# so a stored value of an unexpected-but-compatible kind still types correctly.
GD_COERCE = {"int": "int", "float": "float", "String": "str", "bool": "bool"}


def _py_kind(value) -> str | None:
    """Map a JSON value to a GDScript type name. bool must precede int."""
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "String"
    if isinstance(value, list):
        return "Array"
    return None


def infer_field_specs(effects: dict) -> list[dict]:
    """Infer a {name, gd_type, nullable, default, present} spec per field.

    A field is nullable (untyped Variant, null preserved) when any record has it
    present-but-null, when it mixes incompatible types, or when no record carries
    it at all (the sparse case). Otherwise it is typed with a zero-value default.
    """
    specs = []
    total = len(effects)
    for field in INCLUDED_FIELDS:
        kinds: set[str] = set()
        present = 0
        null_present = False
        for data in effects.values():
            if field not in data:
                continue
            present += 1
            value = data[field]
            if value is None:
                null_present = True
                continue
            kind = _py_kind(value)
            if kind:
                kinds.add(kind)

        # int values can satisfy a float field; collapse the pair.
        if "float" in kinds and "int" in kinds:
            kinds.discard("int")

        if present == 0:
            specs.append({"name": field, "gd_type": None, "nullable": True,
                          "default": "null", "present": 0, "total": total})
            continue

        if len(kinds) == 1:
            gd_type = next(iter(kinds))
        else:
            # zero kinds (present but all null) or mixed incompatible kinds
            gd_type = None

        nullable = null_present or gd_type is None
        default = "null" if gd_type is None else GD_DEFAULTS[gd_type]
        specs.append({"name": field, "gd_type": gd_type, "nullable": nullable,
                      "default": default, "present": present, "total": total})
    return specs


def generate_view_property(spec: dict) -> str:
    """One typed accessor over the wrapped record dict."""
    name = spec["name"]
    if spec["nullable"]:
        # Untyped (Variant) so null is preserved for absent OR present-null keys.
        kind = spec["gd_type"] or "?"
        return (f'## {name} ({kind}, nullable — null preserved)\n'
                f'var {name}:\n'
                f'\tget:\n'
                f'\t\treturn _d.get("{name}", null)')
    gd_type = spec["gd_type"]
    if gd_type == "Array":
        return (f'## {name} (Array)\n'
                f'var {name}: Array:\n'
                f'\tget:\n'
                f'\t\treturn _d.get("{name}", [])')
    coerce = GD_COERCE[gd_type]
    default = spec["default"]
    return (f'## {name} ({gd_type})\n'
            f'var {name}: {gd_type}:\n'
            f'\tget:\n'
            f'\t\treturn {coerce}(_d.get("{name}", {default}))')


def generate_ability_view(specs: list[dict]) -> str:
    """Generate AbilityView.gd — a typed façade over one ability record dict."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    props = "\n\n".join(generate_view_property(s) for s in specs)
    return f'''# AUTO-GENERATED FILE - Do not edit manually
# Generated: {timestamp}
# Source: assets/abilities/effects.json (field types inferred over all records)
# Regenerate: python tools/generate_ability_database.py

extends RefCounted

## Typed, flat mirror of one ability record (the denormalized per-ability data).
##
## A façade: it wraps the AbilityDatabase.ABILITIES[id] dict BY REFERENCE and
## exposes one typed accessor per record field, so callers read `view.formula_y`
## instead of `dict.get("formula_y", default)` and never type a field key. The
## dict stays the single stored representation; this is a transient view built
## on demand via AbilityDatabase.get_ability_view(id). See ADR-0008.
##
## 1:1 MIRROR, not a projection — `ct` is in ticks, not seconds. For the lossy
## cast-path projection (charge_time, base_damage, effect_path) see AbilityData.

{PRELOAD_BANNER}
const _Self = preload("{ADDON_RES}/abilities/AbilityView.gd")

var _d: Dictionary


func _init(record: Dictionary = {{}}) -> void:
	_d = record


## Build a view over a raw record dict (used by AbilityDatabase and by tests —
## no database, scene, or RenderingDevice required).
static func from_record(record: Dictionary) -> _Self:
	return _Self.new(record)


## True when this view wraps an empty record (id not found).
func is_empty() -> bool:
	return _d.is_empty()


## True when the record actually carries `field` (vs. the accessor's typed
## default). For the rare caller that must distinguish absent from a genuine
## zero/empty value — e.g. applying a non-zero policy default for a field some
## records omit. Prefer the typed accessors; reach for this only when a default
## of 0/""/[] would change behavior.
func has(field: String) -> bool:
	return _d.has(field)


## Escape hatch to the underlying record (e.g. for the dict-returning legacy
## methods not yet migrated). Prefer the typed accessors below.
func to_dict() -> Dictionary:
	return _d


{props}
'''


def generate_skill_set_entry(ss_id: int, data: dict) -> str:
    """Generate a single skill set dictionary entry."""
    lines = []
    lines.append(f"\t{ss_id}: {{")

    fields = []
    fields.append(f'\t\t"id": {ss_id}')
    fields.append(f'\t\t"name": {escape_gdscript_string(data.get("name", f"SkillSet_{ss_id:02X}"))}')

    # Actions array
    actions = data.get("actions", [])
    action_ids = [a.get("id", 0) for a in actions]
    fields.append(f'\t\t"actions": {action_ids}')

    # RSM (Reaction/Support/Movement) array
    rsm = data.get("rsm", [])
    rsm_ids = [r.get("id", 0) for r in rsm]
    fields.append(f'\t\t"rsm": {rsm_ids}')

    lines.append(",\n".join(fields))
    lines.append("\t}")

    return "\n".join(lines)


def generate_database(effects: dict, skill_sets: dict) -> str:
    """Generate the full GDScript file content."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    header = f'''# AUTO-GENERATED FILE - Do not edit manually
# Generated: {timestamp}
# Source: assets/abilities/effects.json, assets/abilities/skill_sets.json
# Regenerate: python tools/generate_ability_database.py

extends RefCounted

## Ability Database - Contains all {len(effects)} ability definitions and {len(skill_sets)} skill sets
##
## Provides fast lookup of ability data without runtime JSON parsing.
## Data is sourced from FFT's SCUS_942.21, BATTLE.BIN, and Abilities.bin files.
##
## Includes:
## - Combat data (mp_cost, range, formula, effect_id, etc.)
## - Learning data (jp_cost, learn_with_jp, learn_rate)
## - Skill sets (job -> learnable abilities mapping)

{PRELOAD_BANNER}
const AbilityView = preload("{ADDON_RES}/abilities/AbilityView.gd")
const JobDatabase = preload("{ADDON_RES}/jobs/JobDatabase.gd")
const LearnableAbility = preload("{ADDON_RES}/abilities/LearnableAbility.gd")

'''

    # Generate the ABILITIES constant
    entries = []
    for effect_id in sorted(int(k) for k in effects.keys()):
        data = effects[str(effect_id)]
        entries.append(generate_entry(effect_id, data))

    abilities_dict = "const ABILITIES: Dictionary = {\n"
    abilities_dict += ",\n".join(entries)
    abilities_dict += "\n}\n\n"

    # Generate the SKILL_SETS constant
    skill_set_entries = []
    for ss_id in sorted(int(k) for k in skill_sets.keys()):
        ss_data = skill_sets[str(ss_id)]
        skill_set_entries.append(generate_skill_set_entry(ss_id, ss_data))

    skill_sets_dict = "const SKILL_SETS: Dictionary = {\n"
    skill_sets_dict += ",\n".join(skill_set_entries)
    skill_sets_dict += "\n}\n"

    # Generate helper functions
    functions = '''

## Get a typed view of an ability by ID (the read API — see ADR-0008)
## Wraps the record dict by reference; returns an empty view if not found
## (check with view.is_empty()).
static func get_ability_view(id: int) -> AbilityView:
	return AbilityView.from_record(ABILITIES.get(id, {}))


## All ability IDs, sorted ascending (for callers that enumerate every ability)
static func ability_ids() -> Array:
	var ids: Array = ABILITIES.keys()
	ids.sort()
	return ids


## A typed view for every ability, in ID order
static func get_all_views() -> Array[AbilityView]:
	var result: Array[AbilityView] = []
	for id in ability_ids():
		result.append(AbilityView.from_record(ABILITIES[id]))
	return result


## Get a typed view by ability name (case-sensitive)
## Returns an empty view if not found (check with view.is_empty()).
static func get_view_by_name(ability_name: String) -> AbilityView:
	for id in ABILITIES:
		if ABILITIES[id].get("name") == ability_name:
			return AbilityView.from_record(ABILITIES[id])
	return AbilityView.from_record({})


## All typed views of a specific ability_type
## type_name: "Normal", "Item", "Throwing", "Jumping", "Charging", "Arithmetick", "Reaction", "Support", "Movement"
static func get_views_by_type(type_name: String) -> Array[AbilityView]:
	var result: Array[AbilityView] = []
	for id in ABILITIES:
		if ABILITIES[id].get("ability_type") == type_name:
			result.append(AbilityView.from_record(ABILITIES[id]))
	return result


## True when the kernel calls this ability a heal — `target_reaction_type ==
## "receive_heal"`, which is the field `GPUAbilityLoader` encodes to
## `ABFLAG_HEALING` and `is_ability_healing` (`combat_common.glslinc`) reads.
##
## WAS `formula == 12`, and that DISAGREED WITH THE KERNEL on SIXTEEN records:
## `Raise` / `Raise2` are formula 13, and the twelve reachable `Item` records
## (`Potion` … `PhoenixDown`) plus `Antidote` / `EyeDrop` carry no `formula` key
## at all, so the old predicate read 0 and called every one of them not-a-heal
## while `ABFLAG_HEALING` called them heals (ADR-0276 "What is not decided";
## ADR-0278 dec. 7). The realignment changes no behaviour today, and that was
## MEASURED rather than assumed: the one caller, `CombatLoop.gd`'s AoE effect
## spray, is inside an `effect_area > 0` branch, and NONE of the sixteen has a
## non-zero `effect_area`. The disagreement was real in the predicate and
## unreachable at the call site.
##
## For what an ability is FOR rather than what it reacts as, see
## `AbilityFamily.of_id` — this predicate is the kernel's flag and not a
## taxonomy, and `healing` is one of that member's four families.
static func is_healing(id: int) -> bool:
	return str(ABILITIES.get(id, {}).get("target_reaction_type", "")) == "receive_heal"


# `is_damage` WAS HERE AND IS DELETED (ADR-0278 dec. 7). It listed formula 10 as
# damage while `NON_DAMAGE_FORMULAS` two lines below lists 10 as NOT damage — one
# file contradicting itself — and it had ZERO callers in the tree, so nothing was
# reading either answer. ADR-0276 named the pair as one of three partial family
# predicates that had to be RECONCILED rather than joined by a fourth; this is the
# half that reconciles by deletion. `AbilityFamily.of_id(id) == AbilityFamily.DAMAGE`
# is the live question, and it rules formula 10 through the status XOR rather than
# through a formula list.


# Formulas whose effect is not raw HP damage (status/break/special handling).
const NON_DAMAGE_FORMULAS: Array[int] = [37, 43, 44, 10, 11, 56, 42, 80]

# Formulas that play a "break" visual instead of a damage number.
const BREAK_VISUAL_FORMULAS: Array[int] = [37, 43, 44, 46]


## True for formulas that do not deal raw HP damage
static func is_non_damage_formula(formula: int) -> bool:
	return formula in NON_DAMAGE_FORMULAS


## True for formulas that play a break visual instead of a damage number
static func is_break_visual_formula(formula: int) -> bool:
	return formula in BREAK_VISUAL_FORMULAS


## Check if ability can be learned with JP (any ability with jp_cost > 0)
static func can_learn_with_jp(id: int) -> bool:
	return int(ABILITIES.get(id, {}).get("jp_cost", 0)) > 0


# ============== Skill Set Functions ==============

## Get skill set data by ID
## Returns empty Dictionary if not found
static func get_skill_set(id: int) -> Dictionary:
	return SKILL_SETS.get(id, {})


## Get skill set action ability IDs
## Returns array of ability IDs that are action abilities for this skill set
static func get_skill_set_actions(id: int) -> Array:
	var ss = get_skill_set(id)
	return ss.get("actions", [])


## Get skill set RSM (Reaction/Support/Movement) ability IDs
## Returns array of ability IDs
static func get_skill_set_rsm(id: int) -> Array:
	var ss = get_skill_set(id)
	return ss.get("rsm", [])


## Get all learnable abilities for a job as typed LearnableAbility rows
## Args:
##     job_id: Job ID as hex string (e.g., "4a" for Squire)
## Returns:
##     Array[LearnableAbility]
static func get_learnable_abilities_for_job(job_id: String) -> Array[LearnableAbility]:
	var result: Array[LearnableAbility] = []
	var job = JobDatabase.get_job(job_id)
	if job.is_empty():
		return result

	var skill_set_id = int(job.get("skill_set_id", 0))
	var ss = get_skill_set(skill_set_id)
	if ss.is_empty():
		return result

	# Action abilities (all skill set abilities are learnable via JP in FFT)
	for ability_id in ss.get("actions", []):
		var record: Dictionary = ABILITIES.get(ability_id, {})
		if not record.is_empty() and int(record.get("jp_cost", 0)) > 0:
			result.append(LearnableAbility.from_record(ability_id, record, "actions"))

	# RSM abilities
	for ability_id in ss.get("rsm", []):
		var record: Dictionary = ABILITIES.get(ability_id, {})
		if not record.is_empty() and int(record.get("jp_cost", 0)) > 0:
			result.append(LearnableAbility.from_record(ability_id, record, "rsm"))

	return result
'''

    return header + abilities_dict + skill_sets_dict + functions


def _strip_timestamp(text: str) -> str:
    """Drop the `# Generated:` line so --check ignores the only volatile line."""
    return "\n".join(
        line for line in text.splitlines() if not line.startswith("# Generated:")
    )


def load_sources(verbose: bool = True):
    """Load effects (+ merged vertical attrs) and skill sets. Returns (effects, skill_sets) or None on error."""
    if verbose:
        print(f"Reading {EFFECTS_JSON}...")
    if not EFFECTS_JSON.exists():
        print(f"Error: effects.json not found at {EFFECTS_JSON}")
        print("Run dump_ability_data.py first to generate it.")
        return None

    with open(EFFECTS_JSON, "r") as f:
        effects = json.load(f)
    if verbose:
        print(f"Loaded {len(effects)} abilities")

    # Merge vertical + hit-policy + aim-policy fields from
    # ability_attributes.json. Hit policy flags (dont_hit_*) drive the
    # per-ability AOE filter per ADR-0049 (CONTEXT.md §"Ability hit policy");
    # `dont_target_self` is the separate AIM-policy axis of ADR-0291.
    if ABILITY_ATTRS_JSON.exists():
        if verbose:
            print(f"Reading {ABILITY_ATTRS_JSON}...")
        with open(ABILITY_ATTRS_JSON, "r") as f:
            attrs = json.load(f)
        merged_count = 0
        merged_fields = (
            "vertical_tolerance",
            "vertical_fixed",
            "dont_hit_enemies",
            "dont_hit_allies",
            "dont_hit_caster",
            # ADR-0291: aim policy, not hit policy. See INCLUDED_FIELDS.
            "dont_target_self",
        )
        for entry in attrs:
            aid = str(entry.get("ability_id", -1))
            if aid in effects:
                for field in merged_fields:
                    if field in entry:
                        effects[aid][field] = entry[field]
                merged_count += 1
        if verbose:
            print(f"Merged attribute fields for {merged_count} abilities from ability_attributes.json")
    elif verbose:
        print(f"Warning: {ABILITY_ATTRS_JSON} not found, skipping attribute fields")

    if verbose:
        print(f"Reading {SKILL_SETS_JSON}...")
    if not SKILL_SETS_JSON.exists():
        print(f"Error: skill_sets.json not found at {SKILL_SETS_JSON}")
        print("Run extract_abilities.py first to generate it.")
        return None

    with open(SKILL_SETS_JSON, "r") as f:
        skill_sets_data = json.load(f)
        skill_sets = skill_sets_data.get("skill_sets", {})
    if verbose:
        print(f"Loaded {len(skill_sets)} skill sets")

    return effects, skill_sets


def main():
    parser = argparse.ArgumentParser(description="Generate AbilityDatabase.gd + AbilityView.gd")
    parser.add_argument(
        "--check", action="store_true",
        help="Verify the committed files match what regeneration would produce "
             "(ignoring the timestamp line); exit 1 if stale. Writes nothing.",
    )
    args = parser.parse_args()

    loaded = load_sources(verbose=not args.check)
    if loaded is None:
        return 1
    effects, skill_sets = loaded

    db_content = generate_database(effects, skill_sets)
    specs = infer_field_specs(effects)
    view_content = generate_ability_view(specs)

    if args.check:
        stale = []
        for path, fresh in ((OUTPUT_FILE, db_content), (VIEW_OUTPUT_FILE, view_content)):
            if not path.exists():
                stale.append(f"{path.name} (missing)")
                continue
            on_disk = path.read_text()
            if _strip_timestamp(on_disk) != _strip_timestamp(fresh):
                stale.append(path.name)
        if stale:
            print("STALE: " + ", ".join(stale))
            print("Run: uv run python tools/generate_ability_database.py")
            return 1
        print("AbilityDatabase.gd / AbilityView.gd are up to date.")
        return 0

    # Report any field with no sample to infer from (typed nullable Variant).
    for s in specs:
        if s["present"] == 0:
            print(f"  Note: field '{s['name']}' is in INCLUDED_FIELDS but present "
                  f"in 0/{s['total']} records — view types it as nullable Variant.")

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", newline="\n") as f:
        f.write(db_content)
    with open(VIEW_OUTPUT_FILE, "w", newline="\n") as f:
        f.write(view_content)

    print(f"Generated {OUTPUT_FILE}")
    print(f"Generated {VIEW_OUTPUT_FILE}  ({len(specs)} fields)")
    print(f"  Total abilities: {len(effects)}")
    print(f"  Total skill sets: {len(skill_sets)}")

    print("\nSample abilities:")
    for sample_id in [0, 1, 20, 100]:
        if str(sample_id) in effects:
            name = effects[str(sample_id)].get("name", "Unknown")
            print(f"  {sample_id}: {name}")

    return 0


if __name__ == "__main__":
    exit(main())
