class_name GPUAbilityLoader
extends RefCounted

## Builds the GPU ability database buffer from AbilityDatabase.
##
## Extracted from GPUBatchSimulator._build_ability_database().
## Returns both the GPU buffer (PackedInt32Array) and a CPU-side cache (Dictionary).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityType = ExMateriaAlmanac.AbilityType
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const StatusEncoder = ExMateriaAlmanac.StatusEncoder



## Build ability database from AbilityDatabase.ABILITIES.
##
## Returns:
##     Dictionary with "buffer" (PackedInt32Array) and "cache" (Dictionary)
static func build() -> Dictionary:
	var data = PackedInt32Array()
	data.resize(GPUConstants.MAX_ABILITIES * GPUConstants.ABILITY_SIZE)
	var cache: Dictionary = {}

	# Element name to ID mapping
	const ELEMENT_MAP = {
		"Fire": 1, "Ice": 2, "Lightning": 3, "Wind": 4,
		"Earth": 5, "Water": 6, "Holy": 7, "Dark": 8
	}

	# Ability flag bits. ABFLAG_HEALING is the HP-write-direction predicate;
	# ABFLAG_HIT_NO_* are the hit-policy carve-outs (ADR-0049). Mirror of the
	# constants in combat_common.glslinc.
	const ABFLAG_REFLECTABLE = 1
	const ABFLAG_EVADEABLE = 2
	const ABFLAG_HEALING = 4
	const ABFLAG_WEAPON_RANGE = 16
	const ABFLAG_THROW_RANGE = 32
	const ABFLAG_VERTICAL_TOLERANCE = 64
	const ABFLAG_HIT_NO_ENEMIES = 128
	const ABFLAG_HIT_NO_ALLIES = 256
	const ABFLAG_HIT_NO_CASTER = 512

	# Initialize all abilities with defaults
	for i in range(GPUConstants.MAX_ABILITIES):
		var offset = i * GPUConstants.ABILITY_SIZE
		data[offset + GPUCombatPacker.AbilityField.MP_COST] = 0
		data[offset + GPUCombatPacker.AbilityField.CHARGE_TIME] = 0
		data[offset + GPUCombatPacker.AbilityField.RANGE] = 1
		data[offset + GPUCombatPacker.AbilityField.FORMULA_ID] = 0
		data[offset + GPUCombatPacker.AbilityField.FORMULA_Y] = 10
		data[offset + GPUCombatPacker.AbilityField.EFFECT_AREA] = 0
		data[offset + GPUCombatPacker.AbilityField.FORMULA_X] = 0
		data[offset + GPUCombatPacker.AbilityField.ELEMENT] = 0
		data[offset + GPUCombatPacker.AbilityField.FLAGS] = 0
		data[offset + GPUCombatPacker.AbilityField.VERTICAL] = 255
		data[offset + GPUCombatPacker.AbilityField.EFFECT_ID] = -1
		data[offset + GPUCombatPacker.AbilityField.COOLDOWN_TICKS] = 0
		data[offset + GPUCombatPacker.AbilityField.INFLICT_MASK] = 0
		data[offset + GPUCombatPacker.AbilityField.INFLICT_MODE] = StatusEncoder.MODE_NONE

	# Load all abilities from AbilityDatabase (typed view — see ADR-0008)
	var loaded_count = 0
	for ability_id in AbilityDatabase.ability_ids():
		if ability_id < 0 or ability_id >= GPUConstants.MAX_ABILITIES:
			continue

		var ability := AbilityDatabase.get_ability_view(ability_id)

		# Convert element array to single int (use first element)
		var element = 0
		var elements = ability.elements
		if elements.size() > 0:
			element = ELEMENT_MAP.get(elements[0], 0)

		# Build flags from boolean properties
		var flags = 0
		if ability.reflectable:
			flags |= ABFLAG_REFLECTABLE
		if ability.evadeable:
			flags |= ABFLAG_EVADEABLE
		if ability.target_reaction_type == "receive_heal":
			flags |= ABFLAG_HEALING
		if ability.weapon_range:
			flags |= ABFLAG_WEAPON_RANGE
		var ab_type: int = AbilityType.from_string(ability.ability_type)
		if ab_type == AbilityType.Type.THROWING:
			flags |= ABFLAG_THROW_RANGE
		if ability.vertical_tolerance or ability.vertical_fixed:
			flags |= ABFLAG_VERTICAL_TOLERANCE
		# Hit policy (ADR-0049). dont_hit_* default to false; merged from
		# ability_attributes.json by tools/generate_ability_database.py.
		if ability.dont_hit_enemies:
			flags |= ABFLAG_HIT_NO_ENEMIES
		if ability.dont_hit_allies:
			flags |= ABFLAG_HIT_NO_ALLIES
		if ability.dont_hit_caster:
			flags |= ABFLAG_HIT_NO_CASTER

		# Convert CT to ticks (CT * 30 = CT * 0.5 seconds at 60 ticks/sec)
		var charge_time = ability.ct * 30

		# Get formula and formula_y
		var formula = ability.formula
		var formula_y = ability.formula_y
		# range/vertical carry non-zero policy defaults for records that omit
		# them, and 0 is a genuine value, so distinguish absent via has().
		var range_val = ability.range if ability.has("range") else 1

		if ab_type == AbilityType.Type.THROWING:
			range_val = 4  # Nominal; GPU computes real range from speed

		if ab_type == AbilityType.Type.ITEM:
			var item_id = ability_id - 128  # Item abilities start at 368, items at 240
			var item = ItemDatabase.get_item(item_id)
			var chemist = item.get("chemist", {})
			if chemist:
				formula = chemist.get("formula", 72)
				formula_y = chemist.get("z_value", 3)
			range_val = 4
			charge_time = 0

		# Issue #98 -- translate FFTPatcher inflict_statuses + inflict_mode at
		# the encode boundary. Item abilities (>= ITEM_ABILITY_ID_OFFSET) carry
		# the chemist item's inflict info; everything else carries the
		# ability's own.
		var inflict_names: Array = ability.inflict_statuses
		var inflict_mode_str: Variant = ability.inflict_mode
		if ab_type == AbilityType.Type.ITEM:
			var item_id_2 = ability_id - 128
			var item_2 = ItemDatabase.get_item(item_id_2)
			var chemist_2 = item_2.get("chemist", {})
			if chemist_2:
				inflict_names = chemist_2.get("inflict_statuses", [])
				inflict_mode_str = chemist_2.get("inflict_mode", null)
		# Resolved as ONE record, not two calls (#1117): a mask with MODE_NONE
		# beside it inflicts nothing and only the pair can see that.
		var inflict: Dictionary = StatusEncoder.inflict_for_record(
			inflict_names, inflict_mode_str, "ability %d" % ability_id)
		var inflict_mask: int = inflict["mask"]
		var inflict_mode: int = inflict["mode"]

		# THE LEVER LAYER'S ABILITY BAKE SITE (ADR-0277 dec. 2). The three
		# ability quantities are levered HERE, at load, rather than reaching the
		# kernel through the config buffer: a per-category table is not a
		# 13-int uniform's shape, and a rollout forks this buffer, so baking
		# inherits into every candidate battle for nothing. What it gives up is
		# live scrub, which the reload affordance buys back between battles.
		# With an empty lever set every factor is 1.0 and `bake` is the identity.
		var levers := LeverSet.shared()
		var ab = {
			"mp_cost": levers.levered_ability("mp_cost", ability_id, ability.mp_cost),
			"charge_time": levers.levered_ability("charge_time", ability_id, charge_time),
			"range": range_val,
			"formula": formula,
			"formula_y": formula_y,
			"area_type": ability.effect_area,
			"formula_x": ability.formula_x,
			"element": element,
			"flags": flags,
			"effect_anim_id": ability.effect_anim_id,
			"vertical": ability.vertical if ability.has("vertical") else 255,
			# AbilityView.effect_id is nullable (some abilities have no E### file).
			# The orchestrator's get_ability_effect_id() returns sentinel and the
			# SSBO accessors degrade to neutral values when missing.
			"effect_id": int(ability.effect_id) if ability.effect_id != null else -1,
			"cooldown_ticks": levers.levered_ability("cooldown_ticks", ability_id, ability.cooldown_ticks),
			"inflict_mask": inflict_mask,
			"inflict_mode": inflict_mode,
		}
		_set_ability(data, ability_id, ab)
		cache[ability_id] = ab
		loaded_count += 1

	if DebugConfig.gpu_debug_enabled:
		print("[GPUAbilityLoader] Ability database loaded: %d abilities from AbilityDatabase" % loaded_count)

	return {"buffer": data, "cache": cache}


static func _set_ability(data: PackedInt32Array, id: int, ab: Dictionary) -> void:
	var offset = id * GPUConstants.ABILITY_SIZE
	data[offset + GPUCombatPacker.AbilityField.MP_COST] = ab["mp_cost"]
	data[offset + GPUCombatPacker.AbilityField.CHARGE_TIME] = ab["charge_time"]
	data[offset + GPUCombatPacker.AbilityField.RANGE] = ab["range"]
	data[offset + GPUCombatPacker.AbilityField.FORMULA_ID] = ab["formula"]
	data[offset + GPUCombatPacker.AbilityField.FORMULA_Y] = ab["formula_y"]
	data[offset + GPUCombatPacker.AbilityField.EFFECT_AREA] = ab["area_type"]
	data[offset + GPUCombatPacker.AbilityField.FORMULA_X] = ab["formula_x"]
	data[offset + GPUCombatPacker.AbilityField.ELEMENT] = ab["element"]
	data[offset + GPUCombatPacker.AbilityField.FLAGS] = ab["flags"]
	data[offset + GPUCombatPacker.AbilityField.EFFECT_ANIM_ID] = ab["effect_anim_id"]
	data[offset + GPUCombatPacker.AbilityField.VERTICAL] = ab["vertical"]
	data[offset + GPUCombatPacker.AbilityField.EFFECT_ID] = ab["effect_id"]
	data[offset + GPUCombatPacker.AbilityField.COOLDOWN_TICKS] = ab["cooldown_ticks"]
	data[offset + GPUCombatPacker.AbilityField.INFLICT_MASK] = ab["inflict_mask"]
	data[offset + GPUCombatPacker.AbilityField.INFLICT_MODE] = ab["inflict_mode"]
